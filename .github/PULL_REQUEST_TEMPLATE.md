<!--
Thanks for contributing to ArgumentParserMCP!

Before opening this PR, please skim CLAUDE.md — it is the single source of
truth for code style, documentation policy, and contribution workflow. The
checklist below mirrors the "Adding a new feature" checklist from that file.
-->

## Summary

<!-- One short paragraph: what changed and why. Focus on motivation, not the
diff. The reviewer can read the code; explain what they cannot infer from it. -->

## Changes

<!-- Bullet list of behavioural changes. Skip cosmetic noise. -->

-

## Testing

<!-- How did you verify this works? Mention `swift test` results, manual
runs against the demo CLI, or any new tests you added. If you could not
exercise something, say so explicitly. -->

- [ ] `swift test` passes locally

## Checklist

<!-- Mirrors the "Adding a new feature" checklist in CLAUDE.md. Tick the
items that apply; cross out (`~~item~~`) the ones that don't. -->

- [ ] Implementation lives in `Sources/ArgumentParserMCP/`
- [ ] Tests added in `Tests/ArgumentParserMCPTests/` (happy path + failure / edge case)
- [ ] `///` doc comment on every new `public` / `internal` symbol
- [ ] `Documentation.docc/ArgumentParserMCP.md` `## Topics` updated, if a new public symbol was introduced
- [ ] Article in `Documentation.docc/Articles/` extended or added, if the user-facing scenario changed
- [ ] `README.md` touched **only** if existing info became inaccurate or the change is pitch-worthy
- [ ] Files >200 lines have `// MARK: -` sections in the canonical order
- [ ] No `try!`, `as!`, or force-unwrap (`!`) in `Sources/`
- [ ] Commit subjects are imperative, ≤72 characters, no scope prefix
- [ ] One logical change per commit

## Related issues

<!-- Use "Closes #123" / "Fixes #456" to auto-link, or "Refs #789" for
context-only references. Delete this section if there is nothing to link. -->
