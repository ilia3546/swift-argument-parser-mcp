# Contributing to ArgumentParserMCP

Thanks for your interest in contributing! This file is a quick orientation —
the **single source of truth** for code style, documentation policy, and
workflow lives in [`CLAUDE.md`](CLAUDE.md). Please read it before opening a
non-trivial PR.

## Quick start

```bash
git clone https://github.com/ilia3546/swift-argument-parser-mcp.git
cd swift-argument-parser-mcp
swift build
swift test
```

The repository ships with a sample `demo-cli` target that exercises the
library end-to-end. There are no custom scripts, Makefiles, or local lint
tools — `swift build` and `swift test` are the whole toolchain.

## Filing issues

Use the issue templates:

- **Bug report** — something is broken or behaves unexpectedly. Include a
  minimal reproduction, the package version, and your Swift toolchain.
- **Feature request** — a new capability or an improvement to an existing
  one. Lead with the user-facing problem, not the implementation sketch.

Open-ended questions and design discussions belong in
[GitHub Discussions](https://github.com/ilia3546/swift-argument-parser-mcp/discussions),
not the issue tracker.

## Pull requests

1. **Branch naming.** Use `<type>/<short-slug>`, where `<type>` is one of
   `feature`, `fix`, `chore`, `docs`, `refactor`, or `test`. Keep the slug
   short and kebab-case. Examples:
   - `feature/streaming-results`
   - `fix/argument-converter-overflow`
   - `docs/troubleshooting-stdio`
   - `refactor/schema-builder-split`
2. **Commits.** Imperative subject, ≤72 characters, no scope prefix
   ("Validate MCP arguments before spawning subprocess"). One logical change
   per commit. Never amend a commit that did not actually land — make a new
   one instead.
3. **PR description.** The repository's PR template walks you through the
   sections. The checklist mirrors the "Adding a new feature" checklist in
   [`CLAUDE.md`](CLAUDE.md) — tick what applies, strike out what does not.
4. **Tests.** Every new public function gets at least one happy-path test
   and one failure / edge-case test. End-to-end behaviour goes through
   `MCPProcessClient` in `MCPServerIntegrationTests.swift`.
5. **Documentation.** Public API changes update the `///` doc comment on the
   symbol and, where the user-facing scenario changes, the relevant DocC
   article under `Sources/ArgumentParserMCP/Documentation.docc/Articles/`.
   See the documentation policy in [`CLAUDE.md`](CLAUDE.md) for the full
   article-to-scope mapping.

## Code style

Airbnb Swift style, with **4-space indentation**. Notable house rules:

- No force operations in `Sources/` — no `try!`, no `as!`, no force-unwrap
  (`!`). In tests, prefer `try XCTUnwrap` and `XCTAssertNoThrow`.
- 120-column line limit. K&R braces. `let` over `var`. `final` on classes
  by default.
- Files longer than ~200 lines need `// MARK: -` sections in the canonical
  order documented in `CLAUDE.md`.
- Default to writing no comments. Add one only when the *why* is non-obvious
  — well-named identifiers cover the *what*.

## Things not to do

- Do not bypass commit hooks (`--no-verify`, `--no-gpg-sign`).
- Do not hand-edit `Package.resolved`.
- Do not commit `.build/`, `.swiftpm/`, or generated `docs/`.
- Do not bloat `README.md` with internal or cosmetic details — it is a sales
  pitch and a quickstart, nothing more.
- Do not add DocC articles about contribution process or code style — that
  content belongs in `CLAUDE.md`.

## Code of conduct

Be civil. Assume good faith. Critique code, not people. Reports of harassing
behaviour can go directly to the maintainers via the contact details on
their GitHub profile.
