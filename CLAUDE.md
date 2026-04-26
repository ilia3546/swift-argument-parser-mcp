# CLAUDE.md

Guidance for Claude Code (and any other AI agent or human contributor) working
on this repository. This file is the **single source of truth** for code style,
documentation policy, and contribution workflow. The user-facing `README.md`
and the DocC catalogue stay focused on consumers of the library — process and
style rules live here.

## Project mental model

`ArgumentParserMCP` turns a regular [`swift-argument-parser`][sap]-based CLI
into a [Model Context Protocol][mcp] server. At startup, `MCPServer`
introspects the current executable via `--experimental-dump-help`, builds a
JSON Schema for every registered `MCPCommand`, and dispatches incoming
`tools/call` invocations as **child processes of the same binary**. Whatever a
human sees on the command line is exactly what the agent sees through MCP.

For the deeper architectural picture see
[`Sources/ArgumentParserMCP/Documentation.docc/Articles/Architecture.md`](Sources/ArgumentParserMCP/Documentation.docc/Articles/Architecture.md).

[sap]: https://github.com/apple/swift-argument-parser
[mcp]: https://modelcontextprotocol.io

## Repository map

```
Sources/
  ArgumentParserMCP/          # The library
    Documentation.docc/       # User-facing DocC catalogue (articles + topics)
    ToolInfoModels/           # Decodable models for --experimental-dump-help
  demo-cli/                   # Sample CLI that exercises the library
Tests/
  ArgumentParserMCPTests/     # Unit + integration tests
.github/workflows/            # CI (macOS + Linux build & test)
Package.swift                 # SPM manifest
README.md                     # User-facing pitch and usage
CLAUDE.md                     # ← you are here
```

Largest source files (relevant for the MARK policy below):

- `Sources/ArgumentParserMCP/MCPServer.swift` (~260 lines) — already MARKed.
- `Tests/ArgumentParserMCPTests/SchemaBuilderTests.swift` (~560 lines).
- `Tests/ArgumentParserMCPTests/ArgumentConverterTests.swift` (~545 lines).
- `Tests/ArgumentParserMCPTests/MCPProcessClient.swift` (~390 lines) — already MARKed.
- `Tests/ArgumentParserMCPTests/MCPServerIntegrationTests.swift` (~235 lines).

## Build & test

```bash
swift build                 # build the library + demo-cli
swift test                  # run all tests
swift test --parallel       # run tests in parallel (faster locally)
```

DocC can be previewed in Xcode via **Product → Build Documentation**, or from
the command line if [`swift-docc-plugin`][docc-plugin] is installed globally:

```bash
swift package --allow-writing-to-directory ./docs \
    generate-documentation --target ArgumentParserMCP \
    --output-path ./docs --transform-for-static-hosting
```

There are no custom scripts, Makefiles, or local lint tools — keep it that way
unless we add tooling deliberately.

[docc-plugin]: https://github.com/apple/swift-docc-plugin

## Code style

Base: [Airbnb Swift Style Guide][airbnb], with one **explicit deviation**:

- **Indentation: 4 spaces** (not Airbnb's 2). Matches the existing codebase.

Beyond that, follow Airbnb. The rules that come up most often in this repo:

- K&R braces — opening brace on the same line: `func foo() {`.
- **Max line length: 120**.
- `///` doc comments on every `public` and `internal` symbol — minimum a
  one-line summary; document `Parameters` / `Throws` / `Returns` where they
  apply.
- **No force operations in `Sources/`**: no `try!`, no `as!`, no force-unwrap
  (`!`). In tests, prefer `try XCTUnwrap` and `XCTAssertNoThrow` over `!`.
- `let` over `var` by default. `final` on classes by default.
- Imports sorted alphabetically, no duplicates, `Foundation` first.
- Trailing commas in multi-line collections and parameter lists.
- No redundant `self.` — drop it where the compiler doesn't require it.
- Naming: types `UpperCamelCase`; functions, properties, cases `lowerCamelCase`;
  no leading underscore on private members.
- **Comments**: by default, write none. Add a comment only when the *why* is
  non-obvious (a workaround, a hidden invariant, a constraint that isn't
  visible from the code). Don't narrate *what* the code does — well-named
  identifiers cover that.

[airbnb]: https://github.com/airbnb/swift

## MARK section policy

**Required** for any file longer than ~200 lines. **Recommended** for any type
with more than three logical groupings, regardless of file size.

Canonical order (skip sections that don't apply):

```swift
// MARK: - Nested Types
// MARK: - Static Properties
// MARK: - Properties              // or split: Public / Internal / Private Properties
// MARK: - Initializers
// MARK: - Lifecycle               // start() / stop() / deinit, where applicable
// MARK: - Public API              // or "Public Methods"
// MARK: - Internal API
// MARK: - Private Helpers
```

Extensions get their own top-level mark — `// MARK: - <ProtocolName>` — as
already done in `MCPServer.swift`.

Known debt: `SchemaBuilderTests.swift`, `ArgumentConverterTests.swift`, and
`MCPServerIntegrationTests.swift` exceed 200 lines and are not MARKed yet.
Section them in a dedicated follow-up PR — don't fold that refactor into
unrelated work.

## Documentation policy

The library has two parallel doc surfaces. Treat them differently.

### DocC (`Sources/ArgumentParserMCP/Documentation.docc/`) — user-facing only

Any change to **public API** must:

- Update or add the `///` doc comment on the symbol (summary plus
  `Parameters` / `Throws` / `Returns` where relevant).
- Update `Documentation.docc/ArgumentParserMCP.md`'s `## Topics` section if a
  new public type, protocol, or major extension is introduced.
- Extend or add an article under `Documentation.docc/Articles/` **only when
  the change alters a user-facing scenario** (a new customisation point, a new
  parameter on `MCPServer.init`, a new requirement on `MCPCommand`, a new
  failure mode users may hit, …).

Article mapping:

| Article                        | Scope                                                                  |
| ------------------------------ | ---------------------------------------------------------------------- |
| `BuildingYourFirstServer.md`   | Onboarding / ergonomic walkthrough.                                    |
| `NestedAndCustomCommands.md`   | Advanced patterns, customisation points, routing.                      |
| `Architecture.md`              | Externally visible runtime behaviour (output ordering, result shape).  |
| `Troubleshooting.md`           | Failure modes, FAQ, debugging tips.                                    |

**Do not** add DocC articles about code style, contribution workflow, or
internal architecture — that content belongs in this `CLAUDE.md` file.

### Internal API and non-obvious code

`///` doc comments on internal symbols are **not required**. Where the *why*
behind a piece of internal code is non-obvious (subprocess timing, signal
handling, MCP framing quirks, …), drop a regular `//` comment that explains
the reasoning rather than the mechanics.

### `README.md` — keep it small

The README is a sales pitch and a quickstart. Touch it **only** when:

- Existing information becomes inaccurate (a changed `MCPServer.init`
  signature, a different `structuredContent` shape, a changed `MCPCommand`
  example), **or**
- A new capability is significant enough to belong in the pitch (something
  along the lines of "now supports streaming results" — not "added a new
  internal validator").

Process notes, contribution rules, and stylistic guidance do **not** go into
the README.

## Testing expectations

- Tests mirror the `Sources/` layout: `Foo.swift` → `FooTests.swift`.
- Test names use the pattern `func test_<scenario>_<expectation>()`.
- End-to-end behaviour goes through `MCPProcessClient` in
  `MCPServerIntegrationTests.swift` — that's the harness for spawning the
  demo CLI as a child process and speaking MCP to it over stdio.
- Every new public function needs at least one happy-path test and one
  failure / edge-case test.

## Commit & PR conventions

- **Branch name**: `<type>/<short-slug>`, where `<type>` is one of
  `feature`, `fix`, `chore`, `docs`, `refactor`, or `test`
  (e.g. `feature/streaming-results`, `fix/argument-converter-overflow`,
  `docs/troubleshooting-stdio`). Keep the slug short and kebab-case.
- **Subject**: imperative, no scope prefix, ≤72 characters
  ("Validate MCP arguments before spawning subprocess").
- **Body**: one paragraph explaining the motivation; bullet list for
  multi-step behavioural changes.
- Trailer `https://claude.ai/code/session_…` — Claude Code adds this
  automatically; keep it.
- One logical change per commit.
- If a pre-commit hook fails, **make a new commit** with the fix — never
  amend a commit that didn't actually land.

## Checklist: adding a new feature

- [ ] Implementation in `Sources/ArgumentParserMCP/`
- [ ] Tests in `Tests/ArgumentParserMCPTests/` (happy + failure)
- [ ] `///` doc comment on every new `public` / `internal` symbol
- [ ] `Documentation.docc/ArgumentParserMCP.md` `## Topics` updated, if a new
      public symbol was introduced
- [ ] Article in `Documentation.docc/Articles/` extended or added, if the
      user-facing scenario changed
- [ ] `README.md` touched **only** if existing info became inaccurate or the
      change is pitch-worthy
- [ ] Files >200 lines have `// MARK: -` sections in the canonical order
- [ ] `swift test` is green

## Things not to do

- No `try!`, `as!`, or force-unwrap (`!`) in `Sources/`.
- Don't commit `.build/`, `.swiftpm/`, or generated `docs/`.
- Don't use `--no-verify` or `--no-gpg-sign` on commits.
- Don't hand-edit `Package.resolved`.
- New SPM dependencies go into `Package.swift` **and** the README's
  "Adding `ArgumentParserMCP` as a Dependency" section if they affect how a
  consumer integrates the library.
- Don't add DocC articles about process, style, or contribution — they belong
  here.
- Don't bloat the README with cosmetic or internal details.
