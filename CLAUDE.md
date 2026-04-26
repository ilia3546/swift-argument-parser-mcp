# CLAUDE.md

Pointer file for Claude Code and other AI agents working on this repository.

> **Stop.** [`CONTRIBUTING.md`](CONTRIBUTING.md) is the single source of truth
> for code style, MARK policy, documentation policy, testing expectations,
> branch/commit/PR conventions, the "adding a new feature" checklist, and the
> "things not to do" list. Past sessions have shipped work that violated it
> because the agent skipped this step — **don't be that session**.

## Mandatory pre-flight (every task, before any edit)

1. **Read [`CONTRIBUTING.md`](CONTRIBUTING.md) in full.** Every section
   applies to AI agents. Memory of a previous session is not a substitute —
   the file changes.
2. If the task touches a `public` symbol, also open
   `Sources/ArgumentParserMCP/Documentation.docc/ArgumentParserMCP.md` and
   decide upfront whether `## Topics` and an article under
   `Documentation.docc/Articles/` need to change.
3. For anything non-trivial, work the
   [Checklist: adding a new feature](CONTRIBUTING.md#checklist-adding-a-new-feature)
   end-to-end and tick every box before reporting the task as done.

## Rules that get missed most often

Restated here because past sessions have ignored them. The authoritative
wording still lives in `CONTRIBUTING.md` — when in doubt, that file wins.

- **Branch names** — `<type>/<short-slug>` where `<type>` is one of
  `feature`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`, `ci`,
  `build`. **Don't invent new prefixes** (no `claude/`, `agent/`, `wip/`).
  If the harness created a branch with a non-conforming prefix, flag it to
  the user before pushing instead of silently using it.
- **PR titles** — `<type>: <imperative subject>` using the same type set,
  with the matching label applied so the change lands in the right section
  of the auto-generated release notes (see
  [`.github/release.yml`](.github/release.yml)). Append `!` after the type
  for breaking changes. Use `skip-changelog` for PRs that shouldn't appear
  in the changelog at all.
- **Commit subjects** — imperative, ≤72 chars, **no** Conventional-Commits
  prefix on the commit itself (`feat:` / `fix:` lives on the PR title, not
  on commits). One logical change per commit. If a hook fails, make a new
  commit — never amend a commit that didn't land.
- **Code style** — 4-space indent, K&R braces, 120-col line limit, `///`
  docs on every new `public` / `internal` symbol, imports sorted with
  `Foundation` first, trailing commas in multi-line collections, `let` over
  `var`, `final` on classes. **No force operations** in `Sources/` (`!`,
  `try!`, `as!`) — don't relax this to make a tricky conversion compile,
  surface the type problem instead.
- **Comments** — by default, write none. Only add a comment when the *why*
  is non-obvious (workaround, hidden invariant, external constraint). Don't
  narrate *what* the code does.
- **MARK policy** — files longer than ~200 lines must use the canonical
  section order from `CONTRIBUTING.md`. Don't introduce a new long file
  without sectioning it.
- **Doc surface split** — DocC is user-facing only; process, style, and
  internal architecture stays in `CONTRIBUTING.md`. The README is a pitch +
  quickstart and only changes when existing info became inaccurate or the
  new capability is pitch-worthy.
- **Testing** — every new public function needs at least one happy-path and
  one failure / edge-case test. End-to-end behaviour goes through
  `MCPProcessClient` in `MCPServerIntegrationTests.swift`.
- **Tooling** — `swift build` / `swift test` is the entire local toolchain
  by design. Don't propose Makefiles, helper scripts, or lint configuration
  on your own.

## Self-audit before reporting "done"

Before you tell the user the task is finished, walk this list. If any item
fails, fix it first — don't hand back work with known violations.

- [ ] Re-read the `CONTRIBUTING.md` sections that apply to the kind of
      change you made.
- [ ] Branch name matches the type taxonomy (or you flagged the mismatch).
- [ ] PR title (if a PR is being opened) matches `<type>: <subject>` and
      has the matching label.
- [ ] No force operations introduced in `Sources/`.
- [ ] `///` docs on every new `public` / `internal` symbol.
- [ ] DocC `## Topics` and articles updated if the public surface changed.
- [ ] README touched only if existing info became inaccurate or the change
      is pitch-worthy.
- [ ] Files longer than ~200 lines are MARK-sectioned in canonical order.
- [ ] `swift test` is green.
- [ ] Nothing on the
      [Things not to do](CONTRIBUTING.md#things-not-to-do) list was done.

## AI-specific notes

- The session-trailer line that Claude Code appends to commits
  (`https://claude.ai/code/session_…`) is fine to keep.
- Treat `CONTRIBUTING.md` as load-bearing: if a user instruction conflicts
  with it (e.g. an unusual branch prefix imposed by the harness), call out
  the conflict explicitly so the user can decide, rather than silently
  overriding the contributor rules.
