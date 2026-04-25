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
                demo-cli is a sample CLI built with ArgumentParserMCP. It exposes a variety of \
                subcommands so MCP clients can verify the plumbing end-to-end. Use `tools/list` \
                to discover what is available; every tool description is generated from its \
                CommandConfiguration.

                Each tool result includes a human-readable text block plus a `structuredContent` \
                object with `stdout`, `stderr`, `exitCode`, `terminationReason`, \
                `stdoutTruncated`, `stderrTruncated`, and `durationMs`. `isError` is set when \
                the child exits non-zero or is killed.
                """,
            outputCapBytes: 8 * 1024
        )
        try await server.start()
    }
}
