import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class ProcessRunner: Sendable {

    private static let forcedKillGraceNanoseconds: Int = 500_000_000

    // MARK: - Nested Types

    enum TerminationReason: String, Sendable {
        case exit
        case uncaughtSignal
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
    /// running, the child receives `SIGTERM`; if it does not exit promptly,
    /// it receives `SIGKILL`. The function then rethrows `CancellationError`
    /// so the MCP SDK suppresses the tool-call response per the MCP
    /// cancellation spec.
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

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let startedAt = Date()
        try ProcessRunner.spawn(process)

        // `withTaskCancellationHandler`'s `onCancel:` closure must be
        // `@Sendable`, but `Process` is not `Sendable`. We only use the
        // reference to inspect whether the specific child is still running
        // before a delayed SIGKILL fallback, so we shuttle it across in an
        // unchecked wrapper.
        let processHandle = ProcessHandle(process: process)

        let result = await withTaskCancellationHandler {
            return await ProcessRunner.collectResult(
                process: process,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                perStreamCapBytes: perStreamCapBytes,
                startedAt: startedAt
            )
        } onCancel: {
            let pid = processHandle.process.processIdentifier
            _ = kill(pid, SIGTERM)
            ProcessRunner.scheduleForcedKillIfNeeded(processHandle, pid: pid)
        }

        try Task.checkCancellation()
        return result
    }

    // MARK: - Private Helpers

    /// Spawns `process` without letting Linux children inherit a blocked
    /// SIGTERM from the Swift runtime's worker thread.
    ///
    /// POSIX children inherit the spawning thread's signal mask. On Linux CI
    /// the Swift worker that reaches `Process.run()` can have SIGTERM blocked,
    /// which makes a later cancellation SIGTERM stay pending while `/bin/sleep`
    /// continues until its natural timeout. Temporarily unblocking SIGTERM
    /// around `Process.run()` keeps cancellation graceful; the mask is restored
    /// immediately after spawn in the parent.
    private static func spawn(_ process: Process) throws {
        #if canImport(Glibc)
        var unblockSet = sigset_t()
        guard sigemptyset(&unblockSet) == 0, sigaddset(&unblockSet, SIGTERM) == 0 else {
            try process.run()
            return
        }

        var previousMask = sigset_t()
        let unblockResult = pthread_sigmask(SIG_UNBLOCK, &unblockSet, &previousMask)
        guard unblockResult == 0 else {
            try process.run()
            return
        }

        defer {
            _ = pthread_sigmask(SIG_SETMASK, &previousMask, nil)
        }

        try process.run()
        #else
        try process.run()
        #endif
    }

    /// Sends SIGKILL after a short grace period if SIGTERM did not stop the
    /// child. SIGKILL is intentionally delayed so well-behaved commands still
    /// get a chance to clean up, but cancellation is not held hostage by a
    /// process that blocks or ignores SIGTERM.
    private static func scheduleForcedKillIfNeeded(_ handle: ProcessHandle, pid: Int32) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .nanoseconds(forcedKillGraceNanoseconds)
        ) {
            guard handle.process.isRunning else { return }
            _ = kill(pid, SIGKILL)
        }
    }

    /// Drains both pipes, waits for the child to exit, and assembles the
    /// `Result`. Pulled out of `run(...)` so the body of
    /// `withTaskCancellationHandler` is a single `await` — keeps the
    /// non-`Sendable` `Pipe` references off the cancellation-handler
    /// boundary.
    private static func collectResult(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        perStreamCapBytes: Int,
        startedAt: Date
    ) async -> Result {
        let merger = StreamMerger(perStreamCapBytes: perStreamCapBytes)

        let readFailures = await withTaskGroup(
            of: (StreamMerger.Stream, Bool).self,
            returning: (stdout: Bool, stderr: Bool).self
        ) { group in
            group.addTask {
                let failed = await ProcessRunner.drain(
                    handle: stdoutPipe.fileHandleForReading,
                    stream: .stdout,
                    into: merger
                )
                return (.stdout, failed)
            }
            group.addTask {
                let failed = await ProcessRunner.drain(
                    handle: stderrPipe.fileHandleForReading,
                    stream: .stderr,
                    into: merger
                )
                return (.stderr, failed)
            }

            var stdoutFailed = false
            var stderrFailed = false
            for await (stream, failed) in group {
                switch stream {
                case .stdout: stdoutFailed = failed
                case .stderr: stderrFailed = failed
                }
            }
            return (stdoutFailed, stderrFailed)
        }

        await ProcessRunner.waitForExit(process: process)
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
    ///
    /// `FileHandle.read(upToCount:)` is a synchronous syscall; calling it
    /// directly from a `withTaskGroup` child blocks a cooperative-executor
    /// thread until the child writes or closes the pipe. With multiple
    /// concurrent invocations the cooperative pool can be fully blocked,
    /// starving unrelated `Task.sleep` / cancellation work — which is
    /// exactly what made cancellation appear broken on CI. Hop onto a
    /// global Dispatch queue for the blocking read, then resume on the
    /// cooperative pool to talk to the actor.
    private static func drain(
        handle: FileHandle,
        stream: StreamMerger.Stream,
        into merger: StreamMerger
    ) async -> Bool {
        while true {
            let chunk: Data?
            do {
                chunk = try await readChunk(from: handle, upToCount: 4096)
            } catch {
                logReadFailure(stream: stream, error: error)
                return true
            }
            guard let chunk, !chunk.isEmpty else {
                return false
            }
            await merger.append(stream: stream, chunk: chunk)
        }
    }

    /// Performs a single blocking `read(upToCount:)` on a global Dispatch
    /// queue so it doesn't tie up a cooperative-executor thread.
    private static func readChunk(from handle: FileHandle, upToCount: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let chunk = try handle.read(upToCount: upToCount)
                    continuation.resume(returning: chunk)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Awaits child termination off the cooperative pool. `waitUntilExit()`
    /// is a blocking syscall; running it inline would re-introduce the same
    /// pool-starvation that motivated the off-pool reads above.
    private static func waitForExit(process: Process) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume()
            }
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

// MARK: - ProcessHandle

/// `@Sendable`-bridge for a `Foundation.Process` so a reference can be
/// captured by a `withTaskCancellationHandler` `onCancel:` closure.
/// `Process.isRunning` is safe to invoke from any thread, so the unchecked
/// conformance is sound for the narrow use here.
private struct ProcessHandle: @unchecked Sendable {
    let process: Process
}
