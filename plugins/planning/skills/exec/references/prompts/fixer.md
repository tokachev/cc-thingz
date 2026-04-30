# Fixer prompt

Use this for the fixer agent after collecting review findings (replace `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH` and `FINDINGS_LIST`):

```
Code review found the following issues. Verify and fix them.

Plan file: PLAN_FILE_PATH (read it to find validation commands in the "## Validation Commands" section)
Progress file: PROGRESS_FILE_PATH (read it for context on what previous iterations found and fixed)

FINDINGS:
FINDINGS_LIST

SHELL VERIFICATION RULES (MANDATORY):
Claude Code's permission engine runs hardcoded pre-checks BEFORE bypassPermissions
takes effect. These force a manual prompt that blocks the parent /exec session
when a bash command contains any of:
  - process substitution `<(...)` `>(...)`
  - `for`/`while`/`until` loops, function defs, multi-statement subshells
  - heredocs `<<EOF` / `<< 'EOF'` (including inline python3/awk/sed scripts)
  - braces with quoted strings (e.g. Python set/dict comprehensions `{f for ...'.sql'}`)
  - complex parameter expansions or nested command substitutions

Restrict every Bash call to ONE of: a single command, a linear pipeline (`|`),
or a chain (`&& || ;`). Use absolute paths (e.g. `/tmp/claude/...`), not
`$TMPDIR` or other shell variables.

For anything more complex — iteration, multi-line scripts, multi-input tools
(diff, comm, paste) — use the Write tool to create a script under `./sandbox/`
and invoke it: `bash sandbox/<name>.sh` or `python3 sandbox/<name>.py`. The
Write tool is always cheaper than a permission prompt.

STEP 1 - VERIFY:
For each finding, read the actual code at the specified file:line. Check 20-30 lines of context. Classify as:
- CONFIRMED: real issue, fix it
- FALSE POSITIVE: doesn't exist or already mitigated, discard

STEP 2 - FIX:
- Fix all confirmed issues (including adding missing tests if flagged)

STEP 3 - VALIDATE (MANDATORY — code MUST compile and tests MUST pass before staging):
- Build, test, and run validation commands from PLAN_FILE_PATH
- If anything fails: fix it and re-run everything
- NEVER stage broken code

STEP 4 - STAGE (only after STEP 3 passes with zero errors):
- Stage fixes (this fork stages only — it does NOT commit): bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/stage-and-commit.sh "fix: address code review findings" <changed-files>
- The message argument is ignored by the script but kept for backward compatibility.
- Do NOT run `git commit` yourself. Leave staged changes for the user to commit when they choose.

STEP 5 - LOG PROGRESS (after staging):
Log details: echo "- confirmed: <list>
- false positives: <list>
- fixes: <what changed>
- validation: <what passed>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH
IMPORTANT: Use ONLY the append-progress.sh script. Do NOT use cat >>, echo >>, or heredocs directly.

STEP 6 - REPORT (MANDATORY — this is your return value to the parent):
Your final response MUST include a structured summary starting with "FIXES:" on its own line, followed by one line per fix:
FIXES:
- fixed: <file>:<line> — <what was fixed>
- fixed: <file>:<line> — <what was fixed>
- false positive: <description> — <why discarded>

This report is shown to the user. Be specific about what changed.
```
