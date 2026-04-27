# Architecture

How `ArgumentParserMCP` turns one process invocation into a full MCP server.

## Overview

The library never reimplements your CLI's argument parsing. Instead it asks
the binary to describe itself, generates a JSON Schema from that
description, and re-invokes the binary as a subprocess for every tool call.
The whole pipeline runs in three stages:

```
┌──────────┐  stdio JSON-RPC   ┌──────────────────┐
│ MCP host │ ────────────────▶│  my-cli mcp      │
└──────────┘                   │  (MCPServer)     │
                               └────────┬─────────┘
   1. start()                           │
      └─ spawn: my-cli --experimental-dump-help
         └─ DumpHelpOutput → DumpCommandInfo tree
   2. for each registered MCPCommand:
      └─ SchemaBuilder → MCP Tool { name, description, inputSchema }
   3. tools/call:
      └─ ArgumentConverter (JSON args → ["--flag", "value", "pos"])
      └─ ProcessRunner.run(executablePath:arguments:)
      └─ StreamMerger → { stdout, stderr, mergedLog, exitCode, durationMs }
```

## Discovery

When ``MCPServer/start()`` is called it first resolves the path of the
running binary — `_NSGetExecutablePath` on Darwin, `readlink /proc/self/exe`
on Linux — and spawns it with `--experimental-dump-help`. Argument Parser
emits a JSON description of the entire command tree (root, subcommands,
arguments, options, flags) which the library decodes into the
`DumpHelpOutput` / `DumpCommandInfo` model. If the dump-help invocation
fails, ``MCPServerError/dumpHelpFailed(stderr:exitCode:)`` is thrown; if the
output can't be decoded, ``MCPServerError/invalidDumpHelpOutput`` is thrown
instead.

Nested commands are walked recursively. Every type passed to
``MCPServer/init(name:version:commands:instructions:isStrict:globalArguments:outputCapBytes:)``
must be reachable as a leaf in this tree — otherwise the server fails
startup with ``MCPServerError/commandNotFound(_:)``.

## Schema generation

For each registered ``MCPCommand`` type, `SchemaBuilder` walks the matching
`DumpCommandInfo` and produces an MCP `Tool` with:

- a `name` derived from the full command path (`math add` becomes
  `math_add`),
- a `description` taken from ``MCPCommand/mcpDescription`` (or the command's
  `abstract` + `discussion` by default),
- an `inputSchema` JSON Schema with one property per argument/option/flag.

Auto-generated `--help` and `--version` flags are filtered out. Types are
inferred from `defaultValue` and `allValues`: enums become `enum` schemas,
arrays become `array` schemas with `items`, optional arguments are excluded
from `required`.

## Dispatch

When a client calls a tool, `ArgumentConverter` rebuilds a CLI argv from the
JSON arguments — flags are emitted only when `true`, options become
`--name value`, repeating arguments are emitted multiple times, positional
arguments are appended at the end. The reconstructed argv is then passed
through ``MCPCommand/transformArguments(_:)`` (see
<doc:NestedAndCustomCommands> for a real example) and any `globalArguments`
from
``MCPServer/init(name:version:commands:instructions:isStrict:globalArguments:outputCapBytes:)``
are appended.

`ProcessRunner` re-executes the same binary with the assembled arguments and
captures stdout / stderr concurrently.

## Output capture

`StreamMerger` records both streams as they arrive and produces three
artefacts that ride back in the tool-call response:

- **`stdout`** and **`stderr`** as separate raw strings (use these for
  programmatic parsing),
- a **`mergedLog`** that interleaves both streams in arrival order, with
  `[stderr] ` prepended to lines that came from stderr — included as a
  human-readable `text` content block,
- a **`structuredContent`** object with `exitCode`, `terminationReason`
  (`"exit"` or `"uncaughtSignal"`), `stdoutTruncated`, `stderrTruncated`,
  `stdoutReadFailed`, `stderrReadFailed`, and `durationMs`.

Each stream is capped at the `outputCapBytes` argument of the server
initializer (default 256 KiB). When the cap is reached, capture stops and
the corresponding `*Truncated` flag is set so the agent can detect the
truncation rather than silently receive a partial result.

If reading a pipe fails with an I/O error before EOF, the corresponding
`*ReadFailed` flag is set and a one-line diagnostic is written to the
host process's stderr — the captured output is still returned, just
potentially incomplete.

## Cancellation

When the agent sends `notifications/cancelled` for an in-flight `tools/call`,
the MCP SDK cancels the Swift `Task` running the tool's handler. The library
surfaces that cancellation to the spawned child:

1. A cancellation handler installed inside `ProcessRunner.run(...)` sends
   `SIGTERM` to the child as soon as the task is cancelled. If the child
   blocks or ignores `SIGTERM`, `ProcessRunner` sends `SIGKILL` after a short
   grace period. Once the child exits, the stdout/stderr pipes hit EOF and the
   stream-drain tasks return naturally.
2. After the drain completes, `ProcessRunner` rethrows `CancellationError`
   so the SDK suppresses the tool-call response — the MCP cancellation
   spec requires that no response is sent for a cancelled request.

Long-running tools therefore stop consuming CPU and file descriptors shortly
after the agent loses interest, instead of running to completion in the
background.

For failures at any stage of the pipeline, see <doc:Troubleshooting>.
