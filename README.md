# Swift Argument Parser MCP

**Turn any Swift CLI into an MCP server in minutes.**

ArgumentParserMCP lets AI agents call your [Swift Argument Parser][sap] commands
as tools via the [Model Context Protocol][mcp].
Add one conformance, register your commands, and your CLI is ready for Claude, Cursor, and other MCP clients.

[sap]: https://github.com/apple/swift-argument-parser
[mcp]: https://modelcontextprotocol.io

## Usage

Start with a regular Argument Parser command and conform it to `MCPCommand`:

```swift
import ArgumentParser
import ArgumentParserMCP

struct RepeatPhrase: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Repeat a phrase multiple times."
    )

    @Flag(help: "Include a counter with each repetition.")
    var includeCounter = false

    @Option(name: .shortAndLong, help: "How many times to repeat 'phrase'.")
    var count: Int? = nil

    @Argument(help: "The phrase to repeat.")
    var phrase: String

    mutating func run() throws {
        let repeatCount = count ?? 2
        for i in 1...repeatCount {
            if includeCounter {
                print("\(i): \(phrase)")
            } else {
                print(phrase)
            }
        }
    }
}
```

Then add a subcommand that starts the MCP server:

```swift
import ArgumentParser
import ArgumentParserMCP

struct MCP: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "MCP Server for AI agents"
    )

    mutating func run() async throws {
        let server = MCPServer(
            name: "my-cli",
            version: "1.0.0",
            commands: [RepeatPhrase.self]
        )
        try await server.start()
    }
}
```

Register both subcommands in your root command:

```swift
@main
struct MyCLI: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        subcommands: [
            RepeatPhrase.self,
            MCP.self,
        ]
    )
}
```

That's it. Your CLI now speaks MCP over stdio when invoked with the `mcp` subcommand:

```
$ my-cli mcp
```

The library automatically introspects your CLI via `--experimental-dump-help`,
generates JSON Schema for every registered command,
and dispatches tool calls back to the same binary as subprocesses.

## How It Works

```
AI Agent ──stdio──> my-cli mcp (MCPServer)
                       |
                       |── tools/list  -> tool definitions from --experimental-dump-help
                       |
                       └── tools/call  -> my-cli repeat-phrase --count 3 "hello"
                                          captures stdout, returns as text
```

1. On startup, `MCPServer` runs the current executable with `--experimental-dump-help`
   to discover the full command tree and argument metadata.
2. For each registered `MCPCommand`, it builds an MCP tool with a JSON Schema `inputSchema`
   derived from the command's arguments, options, and flags.
3. When an agent calls a tool, the server converts JSON arguments back to CLI arguments
   and invokes the appropriate subcommand as a child process.

## Customization

### Custom Tool Descriptions

By default, the MCP tool description is built from `CommandConfiguration.abstract` and `.discussion`.
Override `mcpDescription` for a custom one:

```swift
extension RepeatPhrase: MCPCommand {

    static var mcpDescription: String {
        "Repeats a given phrase N times. Useful for testing and demonstrations."
    }
}
```

### Argument Interceptor

Use `transformArguments` to add, remove, or modify CLI arguments before execution on a per-command basis:

```swift
extension Deploy: MCPCommand {

    static func transformArguments(_ arguments: [String]) -> [String] {
        arguments + ["--non-interactive"]
    }
}
```

### Global Arguments

Pass arguments that should be appended to every command invocation:

```swift
let server = MCPServer(
    name: "my-cli",
    version: "1.0.0",
    commands: [Deploy.self, Status.self],
    globalArguments: ["--verbose"]
)
```

## Adding `ArgumentParserMCP` as a Dependency

To use the `ArgumentParserMCP` library in a SwiftPM project,
add it to the dependencies for your package and your CLI target:

```swift
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/ilia3546/swift-argument-parser-mcp", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(name: "<command-line-tool>", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "ArgumentParserMCP", package: "swift-argument-parser-mcp"),
        ]),
    ]
)
```

### Connecting to an MCP Client

Add your CLI to the client's MCP configuration. For example, in Claude Code (`settings.json`):

```json
{
  "mcpServers": {
    "my-cli": {
      "command": "/path/to/my-cli",
      "args": ["mcp"]
    }
  }
}
```

## Documentation

API documentation is generated automatically from source and hosted by Swift Package Index:

- [ArgumentParserMCP documentation][docs]

[docs]: https://swiftpackageindex.com/ilia3546/swift-argument-parser-mcp/documentation/argumentparsermcp

## Requirements

- Swift 6.0+
- macOS 13+

## License

This library is released under the Apache 2.0 license. See [LICENSE](LICENSE) for details.
