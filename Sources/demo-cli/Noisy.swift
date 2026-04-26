import Foundation
import ArgumentParser
import ArgumentParserMCP

struct Noisy: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Print interleaved lines on stdout and stderr."
    )

    @Option(name: .shortAndLong, help: "Number of line pairs to print.")
    var lines: Int = 3

    @Option(name: .shortAndLong, help: "Prefix prepended to every printed line.")
    var prefix: String = "line"

    mutating func run() throws {
        let count = max(0, lines)
        guard count > 0 else { return }
        for i in 1...count {
            print("\(prefix) \(i) on stdout")
            FileHandle.standardError.write(Data("\(prefix) \(i) on stderr\n".utf8))
        }
    }
}
