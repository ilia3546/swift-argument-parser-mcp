import ArgumentParser

@main
struct ArgumentParserMCPDemo: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "CLI tool which demonstrates the use of ArgumentParserMCP",
        subcommands: [
            RepeatPhrase.self,
            Greet.self,
            Tag.self,
            Math.self,
            Echo.self,
            Deploy.self,
            Noisy.self,
            Flood.self,
            Sleep.self,
            Fail.self,
            MCP.self,
        ]
    )
}
