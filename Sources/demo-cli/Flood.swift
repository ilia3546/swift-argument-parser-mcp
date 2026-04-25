import Foundation
import ArgumentParser
import ArgumentParserMCP

struct Flood: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Emit a large blob of output on a chosen stream to exercise the per-stream byte cap."
    )

    @Option(name: .shortAndLong, help: "Number of bytes to emit per chosen stream.")
    var bytes: Int = 1024

    @Option(name: .shortAndLong, help: "Stream to emit to.")
    var stream: FloodStream = .stdout

    @Option(name: .shortAndLong, help: "Single character used as the payload byte.")
    var fill: String = "X"

    mutating func run() throws {
        let size = max(0, bytes)
        let unit = String(fill.first ?? "X")
        let payload = String(repeating: unit, count: size)
        switch stream {
        case .stdout:
            print(payload)
        case .stderr:
            FileHandle.standardError.write(Data((payload + "\n").utf8))
        case .both:
            print(payload)
            FileHandle.standardError.write(Data((payload + "\n").utf8))
        }
    }
}

enum FloodStream: String, ExpressibleByArgument, CaseIterable {

    case stdout
    case stderr
    case both
}
