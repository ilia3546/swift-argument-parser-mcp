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
                RepeatPhrase.self
            ]
        )
        try await server.start()
    }
}
