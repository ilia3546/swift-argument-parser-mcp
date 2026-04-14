import ArgumentParser

@main
struct ArgumentParserMCPDemo: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "CLI tool which demonstrates the use of ArgumentParserMCP",
        subcommands: [
            RepeatPhrase.self,
            MCP.self,
        ]
    )
}
