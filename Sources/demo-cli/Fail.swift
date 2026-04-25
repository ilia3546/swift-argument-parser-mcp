import Foundation
import ArgumentParser
import ArgumentParserMCP

struct Fail: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Exit with a configurable code, writing a message to stderr.",
        discussion: "Use this command to verify the MCP server's error path: structured `exitCode` and `isError`."
    )

    @Option(name: .shortAndLong, help: "Exit code to terminate with.")
    var exitCode: Int = 1

    @Option(name: .shortAndLong, help: "Message written to stderr before exiting.")
    var message: String = "demo-cli failure"

    @Flag(help: "Also write the message to stdout before exiting.")
    var alsoStdout: Bool = false

    mutating func run() throws {
        if alsoStdout {
            print(message)
        }
        FileHandle.standardError.write(Data((message + "\n").utf8))
        throw ExitCode(Int32(truncatingIfNeeded: exitCode))
    }
}
