# ``ArgumentParserMCP``

Turn any Swift Argument Parser CLI into a Model Context Protocol server that
AI agents can call as tools.

## Overview

`ArgumentParserMCP` lets you expose existing
[`swift-argument-parser`](https://github.com/apple/swift-argument-parser)
commands to MCP clients (Claude, Cursor, …) with one protocol conformance and
one extra subcommand. It introspects the CLI through
`--experimental-dump-help`, generates a JSON Schema for every registered
command, and dispatches incoming tool calls back to the same binary as
subprocesses — so the behaviour an agent sees through MCP is the exact
behaviour a human sees on the command line.

```swift
struct RepeatPhrase: ParsableCommand, MCPCommand {
    @Argument var phrase: String
    mutating func run() throws { print(phrase) }
}

struct MCP: AsyncParsableCommand {
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

## Topics

### Essentials

- ``MCPCommand``
- ``MCPServer``

### Errors

- ``MCPServerError``

### Guides

- <doc:BuildingYourFirstServer>
- <doc:NestedAndCustomCommands>

### Reference

- <doc:Architecture>
- <doc:Troubleshooting>
