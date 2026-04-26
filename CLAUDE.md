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
- Don't propose adding scripts, Makefiles, or lint tooling on your own —
  `swift build` / `swift test` are the whole local toolchain by design.
- Don't relax the "no force operations in `Sources/`" rule to make a tricky
  conversion compile. Surface the type problem instead.
