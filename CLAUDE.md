# CLAUDE.md

Pointer file for Claude Code and other AI agents working on this repository.

**The single source of truth for code style, documentation policy, and
contribution workflow is [`CONTRIBUTING.md`](CONTRIBUTING.md).** Read it in
full before making non-trivial changes — repository structure, code style,
MARK policy, documentation policy, testing expectations, commit/PR rules,
the "adding a new feature" checklist, and the "things not to do" list all
live there.

## AI-specific notes

A few items that apply to agents but are not interesting to human contributors:

- The session-trailer line that Claude Code appends to commits
  (`https://claude.ai/code/session_…`) is fine to keep.
- When asked to implement a feature, work the
  [Checklist: adding a new feature](CONTRIBUTING.md#checklist-adding-a-new-feature)
  in `CONTRIBUTING.md` end-to-end before reporting the task as done.
- **Branch names**: follow the `<type>/<short-slug>` rule from
  [Commit & PR conventions](CONTRIBUTING.md#branch-names). `<type>` must be
  one of `feature`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`,
  `ci`, `build`. Don't invent new prefixes (no `claude/`, `agent/`, `wip/`)
  — pick the type that actually describes the change.
- **PR titles**: open every PR with the title `<type>: <imperative subject>`
  using the same type set, and apply the matching label so the change
  lands in the right section of the auto-generated release notes (see
  [PR titles and labels](CONTRIBUTING.md#pr-titles-and-labels-drives-the-release-changelog)
  and [`.github/release.yml`](.github/release.yml)). For PRs that
  shouldn't appear in the changelog at all, add the `skip-changelog`
  label.
- Don't propose adding scripts, Makefiles, or lint tooling on your own —
  `swift build` / `swift test` are the whole local toolchain by design.
- Don't relax the "no force operations in `Sources/`" rule to make a tricky
  conversion compile. Surface the type problem instead.
