import Foundation
import ArgumentParser
import ArgumentParserMCP

struct RepeatPhrase: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Repeat a phrase multiple times.",
        usage: "Use this tool to repeat a phrase multiple times."
    )

    @Flag(help: "Include a counter with each repetition.")
    var includeCounter = false

    @Option(name: .shortAndLong, help: "How many times to repeat 'phrase'.")
    var count: Int? = nil

    @Option(help: "How to repeat phrase")
    var repeatMode: RepeatPhraseMode = .default

    @Argument(help: "The phrase to repeat.")
    var phrase: String

    mutating func run() throws {
        let repeatCount = count ?? 2

        for i in 1...repeatCount {
            var result: String
            if includeCounter {
                result = "\(i): \(phrase)"
            } else {
                result = phrase
            }
            if case .withPrefix = repeatMode {
                result = "prefix_\(result)"
            }
            print(result)
        }
    }
}

enum RepeatPhraseMode: String, ExpressibleByArgument {

    case `default`
    case withPrefix
}
