import Foundation

final class ProcessRunner: Sendable {

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

    /// Executes the binary at `executablePath` with `arguments`, capturing
    /// both standard output and standard error.
    ///
    /// - Parameter perStreamCapBytes: Maximum number of bytes captured per
    ///   stream. Output beyond the cap is dropped and the corresponding
    ///   `truncated` flag is set on the result. Defaults to no cap.
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
        try process.run()

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

    // MARK: - Private Helpers

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
