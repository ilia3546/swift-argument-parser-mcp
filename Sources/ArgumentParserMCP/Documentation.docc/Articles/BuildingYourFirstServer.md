# Building Your First MCP Server

Take a single Argument Parser command and expose it to MCP clients in four
steps.

## Overview

You'll start with a regular `ParsableCommand`, conform it to ``MCPCommand``,
and add a small `mcp` subcommand that boots an ``MCPServer`` over stdio.
After this guide, an MCP client (Claude, Cursor, …) configured to launch
your binary with the `mcp` argument will be able to discover and call the
command as a tool.

## Add the package dependency

In `Package.swift`, add `swift-argument-parser-mcp` alongside
`swift-argument-parser` and depend on the `ArgumentParserMCP` product from
your executable target.

```swift
let package = Package(
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/ilia3546/swift-argument-parser-mcp", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "my-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ArgumentParserMCP", package: "swift-argument-parser-mcp"),
            ]
        ),
    ]
)
```

## Conform a command to `MCPCommand`

Take any existing `ParsableCommand` and conform it to ``MCPCommand``. No
other changes are required — your `run()` method, arguments, options, and
flags work exactly as they do on the command line.

```swift
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

The `abstract` becomes the tool's MCP description by default. The
`@Argument`, `@Option`, and `@Flag` `help:` strings become the JSON Schema
property descriptions an agent sees.

## Add the `mcp` subcommand

Add a second subcommand whose only job is to construct an ``MCPServer`` and
call ``MCPServer/start()``. The server transports MCP over stdio, which is
what every MCP client expects when it launches a local binary.

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

Wire both subcommands into your root command:

```swift
@main
struct MyCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [RepeatPhrase.self, MCP.self]
    )
}
```

## Try it out

Build and run the MCP server:

```
$ swift build
$ swift run my-cli mcp
```

The process will sit waiting for JSON-RPC on stdin. To verify it from a real
client, add an entry to your MCP client's config — for Claude Code:

```json
{
  "mcpServers": {
    "my-cli": {
      "command": "/absolute/path/to/.build/debug/my-cli",
      "args": ["mcp"]
    }
  }
}
```

The next time the client starts, it will see `repeat-phrase` listed as a
tool with `phrase` (required), `count`, and `include-counter` properties.

If startup fails — for example, the dump-help introspection step throws —
see <doc:Troubleshooting> for the matching ``MCPServerError`` case.

When you're ready to expose more than one command (and especially nested
ones), continue with <doc:NestedAndCustomCommands>.
