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
            outputCapBytes: 8 * 1024
        )
        try await server.start()
    }
}
