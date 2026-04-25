import Foundation
import ArgumentParser
import ArgumentParserMCP

struct Sleep: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        commandName: "sleep",
        abstract: "Sleep for a given duration. Useful to verify the MCP `durationMs` field."
    )

    @Option(name: .shortAndLong, help: "Duration to sleep, in milliseconds.")
    var milliseconds: Int = 100

    mutating func run() throws {
        let clamped = max(0, milliseconds)
        Thread.sleep(forTimeInterval: Double(clamped) / 1000.0)
        print("slept \(clamped)ms")
    }
}
