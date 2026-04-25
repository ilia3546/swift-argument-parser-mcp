import ArgumentParser
import ArgumentParserMCP

struct MCP: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "MCP Server for AI agents"
    )

    mutating func run() async throws {
        let server = MCPServer(
            name: "demo-cli",
            version: ArgumentParserMCPDemo.configuration.version,
            commands: [
                RepeatPhrase.self,
                Greet.self,
                Tag.self,
                MathAdd.self,
                MathMultiply.self,
                Echo.self,
                Deploy.self,
                Noisy.self,
                Flood.self,
                Sleep.self,
                Fail.self,
            ],
            instructions: """
                demo-cli exposes a curated set of subcommands as MCP tools. They are intended \
                for live verification of the ArgumentParserMCP plumbing by an AI agent.

                Coverage at a glance:
                  • repeat-phrase  — string positional + Int? option + enum option + flag.
                  • greet          — required positional, enum, optional String, Int default, short+long flag.
                  • tag            — repeating @Option, optional limit, positional message.
                  • math_add /
                    math_multiply  — nested subcommands with repeating positional Double.
                  • echo           — repeating positional String + custom mcpDescription override.
                  • deploy         — demonstrates `transformArguments` (always injects --non-interactive).
                  • noisy          — interleaved stdout/stderr to verify mergedLog ordering.
                  • flood          — emits a configurable byte payload to test the per-stream cap (8 KiB).
                  • sleep          — sleeps for a given duration to verify `durationMs`.
                  • fail           — exits with a custom code and stderr to verify `isError` / `exitCode`.

                Every tool result includes both a human-readable text block and a `structuredContent` \
                object with stdout, stderr, exitCode, terminationReason, *Truncated flags, and durationMs.
                """,
            outputCapBytes: 8 * 1024
        )
        try await server.start()
    }
}
