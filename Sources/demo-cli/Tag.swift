import ArgumentParser
import ArgumentParserMCP

struct Tag: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Annotate a message with one or more tags."
    )

    @Option(name: .shortAndLong, help: "A tag value. Repeat the option to add multiple tags.")
    var tag: [String] = []

    @Option(name: .shortAndLong, help: "Maximum number of tags to display.")
    var limit: Int? = nil

    @Argument(help: "Message to annotate.")
    var message: String

    mutating func run() throws {
        let kept = limit.map { Array(tag.prefix(max(0, $0))) } ?? tag
        if kept.isEmpty {
            print(message)
        } else {
            let prefix = kept.map { "[\($0)]" }.joined(separator: " ")
            print("\(prefix) \(message)")
        }
    }
}
