# Troubleshooting

What every ``MCPServerError`` case means and the fastest way to fix it.

## Overview

``MCPServer/start()`` performs several blocking steps before it accepts the
first MCP request: it locates the running binary, spawns it with
`--experimental-dump-help`, decodes the JSON tree, and resolves every
registered command against that tree. A failure in any of those steps
surfaces as one of the four ``MCPServerError`` cases below.

For the underlying pipeline these errors map to, see <doc:Architecture>.

## ``MCPServerError/dumpHelpFailed(stderr:exitCode:)``

The introspection invocation
(`./my-cli --experimental-dump-help`) returned a non-zero exit code. The
attached `stderr` and `exitCode` are the ones the child process produced.

The error's `description` renders `stderr` as an indented block underneath
the exit-code line, and trims very long output to its trailing characters
(the actionable diagnostic is almost always at the tail). If you need the
unabridged stream — for logging or post-mortems — read the `stderr`
associated value directly instead of formatting `description`.

**Fix.** Run the same command yourself:

```
$ ./my-cli --experimental-dump-help
```

If it crashes interactively too, the cause is in the CLI, not in
`ArgumentParserMCP`. The most common culprit is a `validate()` on the root
command (or in an `init`) that runs unconditionally and rejects the
`--experimental-dump-help` invocation along with everything else. Either
gate that validation behind the actual `run()`, or special-case the
introspection flag.

## ``MCPServerError/invalidDumpHelpOutput``

`--experimental-dump-help` succeeded, but the JSON it produced couldn't be
decoded into the expected shape.

**Fix.** Bump `swift-argument-parser` to a recent 1.x — the JSON dump
format used here is the one shipped by current versions. If you've pinned an
older version, the schema may not match. After upgrading, re-run
`swift package resolve` and rebuild.

## ``MCPServerError/commandNotFound(_:)``

A type passed to
``MCPServer/init(name:version:commands:instructions:isStrict:globalArguments:outputCapBytes:)``
isn't reachable as a command in the dump-help tree. The associated value is
the command name the server tried to look up.

**Fix.** Two patterns hit this:

1. The command isn't registered with its parent's `subcommands:` array.
   Argument Parser doesn't know about types that aren't wired into the
   command tree, so they don't appear in `--experimental-dump-help` either.
2. You registered a parent group instead of its leaves. For nested commands
   like `math add` and `math multiply`, pass `MathAdd.self` and
   `MathMultiply.self` to the server — not `Math.self`. See
   <doc:NestedAndCustomCommands> for the full pattern.

## ``MCPServerError/unableToDetectCurrentExecutablePath``

Both platform-specific lookups failed: `_NSGetExecutablePath` on Darwin,
`readlink /proc/self/exe` on Linux. Without a binary path, the server can't
re-spawn itself for tool calls.

**Fix.** This usually only appears in unusual sandboxes (no `/proc` mounted,
restricted system calls, custom dynamic loaders). Verify the runtime
environment exposes one of those mechanisms — running outside the sandbox is
typically enough to confirm whether the sandbox itself is the cause.
