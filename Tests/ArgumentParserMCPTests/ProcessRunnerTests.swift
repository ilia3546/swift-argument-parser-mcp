import Foundation
import Testing

@testable import ArgumentParserMCP

@Suite("ProcessRunner")
struct ProcessRunnerTests {

    // MARK: - Cancellation

    /// Cancelling the surrounding `Task` while the child is still alive must
    /// terminate the subprocess and rethrow `CancellationError` — otherwise
    /// the MCP server would keep a runaway child alive after an agent's
    /// `notifications/cancelled` for the in-flight `tools/call`.
    @Test func cancellingTaskTerminatesLongRunningChild() async throws {
        let runner = ProcessRunner()
        let sleepBinary = sleepBinaryPath()
        let startedAt = Date()

        let task = Task {
            return try await runner.run(executablePath: sleepBinary, arguments: ["60"])
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        #expect(elapsed < 5.0, "cancellation should kill the child long before 60s")
    }

    /// A run that completes naturally (no cancellation) still produces a
    /// normal `Result` — the cancellation plumbing must not perturb the
    /// happy path.
    @Test func completesNormallyWhenNotCancelled() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executablePath: sleepBinaryPath(),
            arguments: ["0"]
        )

        #expect(result.exitCode == 0)
        #expect(result.terminationReason == .exit)
    }

    // MARK: - Test Helpers

    private func sleepBinaryPath() -> String {
        let candidates = ["/bin/sleep", "/usr/bin/sleep"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            ?? candidates[0]
    }
}
