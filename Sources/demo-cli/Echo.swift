import ArgumentParser
import ArgumentParserMCP

struct Echo: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Echo input back. Demonstrates a repeating positional argument and a custom `mcpDescription`."
    )

    @Option(name: .shortAndLong, help: "Separator placed between echoed words.")
    var separator: String = " "

    @Argument(help: "Words to echo back.")
    var words: [String] = []

    mutating func run() throws {
        print(words.joined(separator: separator))
    }

    static var mcpDescription: String {
        "Joins the provided words with a separator and prints the result. Use this as a sanity check that the MCP plumbing is wired up: pass `words: [\"hello\", \"world\"]` and expect `hello world`."
    }
}
