import Foundation
import Testing

@testable import ArgumentParserMCP

@Suite("MCPServerError")
struct MCPServerErrorTests {

    @Test func dumpHelpFailedRendersStderrAsIndentedBlock() {
        let error = MCPServerError.dumpHelpFailed(
            stderr: "first line\nsecond line",
            exitCode: 2
        )

        #expect(error.description == """
        Failed to dump help (exit code 2)
        stderr (22 chars):
            first line
            second line
        """)
    }

    @Test func dumpHelpFailedTrimsSurroundingWhitespace() {
        let error = MCPServerError.dumpHelpFailed(
            stderr: "\n\n  warn: deprecated option\n\n",
            exitCode: 1
        )

        let description = error.description
        #expect(description.contains("    warn: deprecated option"))
        #expect(description.hasSuffix("    warn: deprecated option"))
    }

    @Test func dumpHelpFailedReportsEmptyStderr() {
        let error = MCPServerError.dumpHelpFailed(stderr: "   \n", exitCode: 5)

        #expect(error.description == "Failed to dump help (exit code 5) — stderr was empty")
    }

    @Test func dumpHelpFailedTruncatesLongStderr() {
        let cap = MCPServerError.maxStderrCharactersInDescription
        let totalChars = cap + 1_000
        let stderr = String(repeating: "x", count: totalChars)

        let description = MCPServerError.dumpHelpFailed(stderr: stderr, exitCode: 1).description

        #expect(description.contains("stderr (\(totalChars) chars total, last \(cap) shown):"))
        #expect(description.contains("[… 1000 earlier characters truncated]"))
        #expect(!description.contains(stderr))
        #expect(description.hasSuffix(String(repeating: "x", count: cap)))
    }

    @Test func dumpHelpFailedKeepsFullStderrOnAssociatedValue() {
        let stderr = String(repeating: "y", count: MCPServerError.maxStderrCharactersInDescription * 2)
        let error = MCPServerError.dumpHelpFailed(stderr: stderr, exitCode: 7)

        guard case .dumpHelpFailed(let captured, let exitCode) = error else {
            Issue.record("expected .dumpHelpFailed")
            return
        }
        #expect(captured == stderr)
        #expect(exitCode == 7)
    }

    @Test func nonDumpHelpCasesUseSimpleDescription() {
        #expect(
            MCPServerError.invalidDumpHelpOutput.description
                == "Could not decode --experimental-dump-help output"
        )
        #expect(
            MCPServerError.commandNotFound("foo").description
                == "Command 'foo' not found in CLI tool structure"
        )
        #expect(
            MCPServerError.unableToDetectCurrentExecutablePath.description
                == "Unable to detect current executable path"
        )
    }
}
