import Foundation

final class ProcessRunner: Sendable {

    // MARK: - Nested Types

    enum TerminationReason: String, Sendable {
        case exit
        case uncaughtSignal
    }

    /// Discriminator for the heterogeneous task group inside ``collectResult(process:pid:stdoutPipe:stderrPipe:perStreamCapBytes:startedAt:)``.
    /// Two cases carry the per-stream drain result; the third lets the
    /// cancellation watchdog return without confusing the result tally.
    private enum TaskOutcome: Sendable {
        case drain(StreamMerger.Stream, Bool)
        case watchdog
    }

    struct Result: Sendable {
        let stdout: String
        let stderr: String
        let mergedLog: String
        let exitCode: Int32
        let terminationReason: TerminationReason
        let stdoutTruncated: Bool
        let stderrTruncated: Bool
        let stdoutReadFailed: Bool
        let stderrReadFailed: Bool
        let durationMs: Int
    }

    // MARK: - Internal API

    /// Executes the binary at `executablePath` with `arguments`, capturing
    /// both standard output and standard error.
    ///
    /// If the calling Swift `Task` is cancelled while the child is still
    /// running, the child receives `SIGTERM` (via `Process.terminate()`) so
    /// the agent's `notifications/cancelled` for an in-flight `tools/call`
    /// actually kills the subprocess instead of letting it run to
    /// completion. The function then rethrows `CancellationError` so the
    /// MCP SDK suppresses the tool-call response per the MCP cancellation
    /// spec.
    ///
    /// - Parameter perStreamCapBytes: Maximum number of bytes captured per
    ///   stream. Output beyond the cap is dropped and the corresponding
    ///   `truncated` flag is set on the result. Defaults to no cap.
    /// - Throws: `CancellationError` if the surrounding `Task` was cancelled
    ///   before the child finished. Re-throws any error from `Process.run()`
    ///   if the binary could not be spawned.
    func run(
        executablePath: String,
        arguments: [String],
        perStreamCapBytes: Int = .max
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let (stdoutPipe, stderrPipe, startedAt) = try withProcessSpawnLock { () -> (Pipe, Pipe, Date) in
            let stdout = Pipe()
            let stderr = Pipe()
            markCloseOnExec(stdout.fileHandleForReading.fileDescriptor)
            markCloseOnExec(stdout.fileHandleForWriting.fileDescriptor)
            markCloseOnExec(stderr.fileHandleForReading.fileDescriptor)
            markCloseOnExec(stderr.fileHandleForWriting.fileDescriptor)
            process.standardOutput = stdout
            process.standardError = stderr

            let started = Date()
            try process.run()
            return (stdout, stderr, started)
        }

        // `withTaskCancellationHandler`'s `onCancel:` closure must be
        // `@Sendable`, but `Process` is not `Sendable`. We only need the
        // child's pid in the closure, and `pid_t` is `Sendable`, so
        // capture it directly instead of routing through `Process`.
        // Avoid `Process.terminate()` / `isRunning`: under load on macOS,
        // `isRunning` can briefly return false right after spawn, which
        // would silently skip the SIGTERM and leave the child running to
        // completion (observed on macos-15-arm64 CI as a 60s stall).
        let pid = process.processIdentifier

        let result = await withTaskCancellationHandler {
            await ProcessRunner.collectResult(
                process: process,
                pid: pid,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                perStreamCapBytes: perStreamCapBytes,
                startedAt: startedAt
            )
        } onCancel: {
            if pid > 0 {
                _ = kill(pid, SIGTERM)
            }
        }

        try Task.checkCancellation()
        return result
    }

    // MARK: - Private Helpers

    /// Drains both pipes, waits for the child to exit, and assembles the
    /// `Result`. Pulled out of `run(...)` so the body of
    /// `withTaskCancellationHandler` is a single `await` — keeps the
    /// non-`Sendable` `Pipe` references off the cancellation-handler
    /// boundary.
    ///
    /// A third "watchdog" task is added to the same task group: it polls
    /// `Task.isCancelled` every 100ms and sends `SIGTERM` to `pid` when it
    /// observes cancellation. This is a backstop for
    /// `withTaskCancellationHandler.onCancel`, which has been observed not
    /// to terminate the child reliably on swift-corelibs-foundation Linux
    /// and on macos-15-arm64 CI (a 60s stall on `sleep 60` despite a
    /// successful `task.cancel()`). The watchdog polls inside the task
    /// group's cancellation context — when the surrounding `Task` is
    /// cancelled, every group child is marked cancelled, and `Task.sleep`
    /// returns immediately.
    private static func collectResult(
        process: Process,
        pid: pid_t,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        perStreamCapBytes: Int,
        startedAt: Date
    ) async -> Result {
        let merger = StreamMerger(perStreamCapBytes: perStreamCapBytes)

        let readFailures = await withTaskGroup(
            of: TaskOutcome.self,
            returning: (stdout: Bool, stderr: Bool).self
        ) { group in
            group.addTask {
                let failed = await ProcessRunner.drain(
                    handle: stdoutPipe.fileHandleForReading,
                    stream: .stdout,
                    into: merger
                )
                return .drain(.stdout, failed)
            }
            group.addTask {
                let failed = await ProcessRunner.drain(
                    handle: stderrPipe.fileHandleForReading,
                    stream: .stderr,
                    into: merger
                )
                return .drain(.stderr, failed)
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if pid > 0 {
                    _ = kill(pid, SIGTERM)
                }
                return .watchdog
            }

            var stdoutFailed = false
            var stderrFailed = false
            var drainsDone = 0
            for await outcome in group {
                switch outcome {
                case .drain(.stdout, let failed):
                    stdoutFailed = failed
                    drainsDone += 1
                case .drain(.stderr, let failed):
                    stderrFailed = failed
                    drainsDone += 1
                case .watchdog:
                    break
                }
                if drainsDone == 2 {
                    // Both drains have EOFed; cancel the watchdog so the
                    // group can finish (the watchdog task will return
                    // immediately on its next loop iteration).
                    group.cancelAll()
                }
            }
            return (stdoutFailed, stderrFailed)
        }

        process.waitUntilExit()
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        let snapshot = await merger.finalize()
        let merged = mergedLog(from: snapshot)

        let reason: TerminationReason
        switch process.terminationReason {
        case .exit:
            reason = .exit
        case .uncaughtSignal:
            reason = .uncaughtSignal
        @unknown default:
            reason = .exit
        }

        return Result(
            stdout: String(decoding: snapshot.stdout, as: UTF8.self),
            stderr: String(decoding: snapshot.stderr, as: UTF8.self),
            mergedLog: merged,
            exitCode: process.terminationStatus,
            terminationReason: reason,
            stdoutTruncated: snapshot.stdoutTruncated,
            stderrTruncated: snapshot.stderrTruncated,
            stdoutReadFailed: readFailures.stdout,
            stderrReadFailed: readFailures.stderr,
            durationMs: durationMs
        )
    }

    /// Reads from `handle` until EOF, forwarding chunks to `merger`. Returns
    /// `true` if a non-EOF I/O error interrupted the drain. The error is
    /// logged to `stderr` so it isn't lost when the caller doesn't inspect
    /// the returned flag.
    private static func drain(
        handle: FileHandle,
        stream: StreamMerger.Stream,
        into merger: StreamMerger
    ) async -> Bool {
        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 4096)
            } catch {
                logReadFailure(stream: stream, error: error)
                return true
            }
            guard let chunk, !chunk.isEmpty else { return false }
            await merger.append(stream: stream, chunk: chunk)
        }
    }

    private static func logReadFailure(stream: StreamMerger.Stream, error: Error) {
        let label: String
        switch stream {
        case .stdout: label = "stdout"
        case .stderr: label = "stderr"
        }
        let message = "ArgumentParserMCP: failed to read child \(label): \(error)\n"
        if let data = message.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }
}

// MARK: - Spawn Serialization

/// Serializes `Pipe()` creation + `FD_CLOEXEC` tagging + `Process.run()`
/// across every spawn in the package.
///
/// `Foundation.Pipe` does not set `FD_CLOEXEC` on the file descriptors it
/// returns from `pipe(2)`, so a concurrent `posix_spawn` from another thread
/// can inherit the parent-side pipe ends of an unrelated child. The
/// inherited write-ends keep the unrelated pipe open even after its real
/// child exits, blocking the parent's `read` until the *other* (potentially
/// long-running) child exits — observed on `macos-15-arm64` CI as a 60s stall
/// in `cancellingTaskTerminatesLongRunningChild`. Holding this lock around
/// the pipe-creation + `Process.run()` block makes the otherwise interleaved
/// sequence atomic with respect to other spawn sites in this package,
/// including the `MCPProcessClient` test harness.
private let processSpawnLock = NSLock()

/// Runs `body` while holding ``processSpawnLock``. Synchronous so the lock
/// is never held across an `await` — `NSLock.lock()` is unavailable in
/// asynchronous contexts under Swift 6 strict concurrency.
internal func withProcessSpawnLock<T>(_ body: () throws -> T) rethrows -> T {
    processSpawnLock.lock()
    defer { processSpawnLock.unlock() }
    return try body()
}

/// Sets `FD_CLOEXEC` on `fd` so the descriptor is closed automatically on
/// the next `exec(2)` in *this* process.
///
/// `Process.run()` uses `posix_spawn_file_actions_adddup2` to map our pipe
/// write-end onto the child's stdout/stderr. `dup2` clears the close-on-exec
/// flag on the destination fd, so the child still inherits its three
/// redirected streams even though the original parent-side fd is now
/// `FD_CLOEXEC`.
internal func markCloseOnExec(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFD)
    if flags >= 0 {
        _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC)
    }
}
