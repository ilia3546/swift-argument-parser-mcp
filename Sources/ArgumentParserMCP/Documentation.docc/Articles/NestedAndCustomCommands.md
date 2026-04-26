# Nested and Custom Commands

Group commands into hierarchies, override the description an agent sees, and
intercept arguments before they reach `run()`.

## Overview

Once your CLI grows past one command, three patterns come up repeatedly:
nesting commands under a parent (`my-cli math add`), tailoring the
description an agent reads, and reshaping the arguments the MCP server
forwards to your binary. ``MCPCommand`` covers all three with the same
mechanism it uses for the basic case in <doc:BuildingYourFirstServer>.

## Nested commands

`ParsableCommand` already supports nesting through `subcommands:`.
`ArgumentParserMCP` walks that tree when introspecting `--experimental-dump-help`,
so nested commands work without any extra wiring — *as long as you register
the leaves, not the parent group*, with the server.

```swift
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
```

Wire the parent into the root command's `subcommands:` as usual, then
register only the leaves with the server:

```swift
let server = MCPServer(
    name: "my-cli",
    version: "1.0.0",
    commands: [MathAdd.self, MathMultiply.self]
)
```

The full command path becomes the MCP tool name (`/` separators replaced
with `_`): `MathAdd` is exposed as `math_add`, `MathMultiply` as
`math_multiply`. If you accidentally pass `Math.self` instead, startup
fails with ``MCPServerError/commandNotFound(_:)`` — see the entry in
<doc:Troubleshooting>.

## Custom tool descriptions

By default the tool description is built from `CommandConfiguration.abstract`
(joined with `discussion` if present). Override
``MCPCommand/mcpDescription`` when you want to write a description aimed
specifically at an LLM — usually one that names the inputs, the expected
output, and a worked example.

```swift
extension Echo: MCPCommand {

    static var mcpDescription: String {
        """
        Joins the provided words with a separator and prints the result. \
        Use this as a sanity check that the MCP plumbing is wired up: \
        pass `words: ["hello", "world"]` and expect `hello world`.
        """
    }
}
```

The override only changes what an MCP client sees — the human-readable
`--help` output continues to use `abstract` and `discussion`.

## Intercepting arguments

Sometimes an MCP-driven invocation needs different arguments than a
human-driven one. The canonical example is a deploy command that prompts
for confirmation when run by a human but must run non-interactively when
called by an agent (no TTY is attached to the subprocess, so an interactive
prompt would simply hang).

Override ``MCPCommand/transformArguments(_:)`` to add, remove, or rewrite
arguments after the JSON tool-call payload has been converted to argv but
before the binary is re-spawned.

```swift
import ArgumentParser
import ArgumentParserMCP

struct Deploy: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Pretend deploy command. Demonstrates `transformArguments` by always running non-interactively when invoked from the MCP server."
    )

    @Option(name: .shortAndLong, help: "Environment to deploy to.")
    var environment: DeployEnvironment = .staging

    @Flag(help: "Run without prompting. Always set when called via MCP.")
    var nonInteractive: Bool = false

    mutating func run() throws {
        if !nonInteractive {
            print("Would prompt for confirmation here. Use --non-interactive to skip.")
            return
        }
        print("Deploying to \(environment.rawValue)…")
        print("non-interactive=true")
        print("Done.")
    }

    static func transformArguments(_ arguments: [String]) -> [String] {
        if arguments.contains("--non-interactive") {
            return arguments
        }
        return arguments + ["--non-interactive"]
    }
}

enum DeployEnvironment: String, ExpressibleByArgument, CaseIterable {
    case staging
    case production
    case preview
}
```

Two details worth highlighting:

- The override is **idempotent**: it checks for `--non-interactive` before
  appending. ``MCPCommand/transformArguments(_:)`` is called exactly once
  per tool call, but writing it idempotently means the same code is safe to
  call from a test or a higher-level wrapper without doubling up flags.
- The `arguments` array contains only the command's own arguments —
  *without* the subcommand path. You don't need to preserve `["math",
  "add", …]` prefixes; the server reattaches the path before spawning the
  process.

For a global version of the same idea, use the `globalArguments:` parameter
on
``MCPServer/init(name:version:commands:instructions:isStrict:globalArguments:outputCapBytes:)``
— those arguments are appended to *every* tool call, regardless of which
``MCPCommand`` is being dispatched.
