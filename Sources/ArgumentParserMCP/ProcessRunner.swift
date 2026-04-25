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

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let handle = stdoutPipe.fileHandleForReading
                while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
                    await merger.append(stream: .stdout, chunk: chunk)
                }
            }
            group.addTask {
                let handle = stderrPipe.fileHandleForReading
                while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
                    await merger.append(stream: .stderr, chunk: chunk)
                }
            }
            await group.waitForAll()
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
            durationMs: durationMs
        )
    }
}
