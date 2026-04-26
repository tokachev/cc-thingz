# Finalize prompt

Finalize is permanently disabled in this fork because it requires `git rebase`
and commit squashing — operations that have no commits to operate on. This
fork stages changes via `git add` and never creates commits, so the rebase /
squash step is a no-op.

`SKILL.md` step 11 already short-circuits before reaching this prompt, but the
file is kept (rather than deleted) so the override-resolution chain in
`exec/scripts/resolve-file.sh` continues to find a bundled default if anything
ever calls it. The body below is intentionally inert.

```
Finalize is disabled in the no-autocommit fork of the planning plugin. Do
nothing and exit immediately. Report a single line back to the orchestrator:

FINALIZE: skipped (disabled in fork — no commits to rebase or squash).
```
