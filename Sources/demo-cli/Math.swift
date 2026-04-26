import ArgumentParser
import ArgumentParserMCP

struct Math: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "math",
        abstract: "Numeric helpers grouped under a parent command.",
        subcommands: [MathAdd.self, MathMultiply.self]
    )
}

struct MathAdd: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a list of numbers together."
    )

    @Argument(help: "Numbers to add together.")
    var numbers: [Double] = []

    @Flag(name: .shortAndLong, help: "Print intermediate sums to stdout.")
    var verbose: Bool = false

    mutating func run() throws {
        var total = 0.0
        for (idx, value) in numbers.enumerated() {
            total += value
            if verbose {
                print("step \(idx + 1): +\(value) -> \(total)")
            }
        }
        print(total)
    }
}

struct MathMultiply: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        commandName: "multiply",
        abstract: "Multiply a list of numbers together."
    )

    @Argument(help: "Numbers to multiply.")
    var numbers: [Double] = []

    mutating func run() throws {
        let product = numbers.reduce(1.0, *)
        print(product)
    }
}
