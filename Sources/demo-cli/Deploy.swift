import ArgumentParser
import ArgumentParserMCP

struct Deploy: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Pretend deploy command. Demonstrates `transformArguments` by always running non-interactively when invoked from the MCP server."
    )

    @Option(name: .shortAndLong, help: "Environment to deploy to.")
    var environment: DeployEnvironment = .staging

    @Flag(help: "Run without prompting. Always set when called via MCP.")
    var nonInteractive: Bool = false

    mutating func run() throws {
        if !nonInteractive {
            print("Would prompt for confirmation here. Use --non-interactive to skip.")
            return
        }
        print("Deploying to \(environment.rawValue)…")
        print("non-interactive=true")
        print("Done.")
    }

    static func transformArguments(_ arguments: [String]) -> [String] {
        if arguments.contains("--non-interactive") {
            return arguments
        }
        return arguments + ["--non-interactive"]
    }
}

enum DeployEnvironment: String, ExpressibleByArgument, CaseIterable {

    case staging
    case production
    case preview
}
