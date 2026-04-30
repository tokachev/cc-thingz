# Review orchestration prompt

Use this prompt when spawning the review agent (replace `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `REVIEW_PHASE`, `RESOLVE_SCRIPT`, and `PLUGIN_DATA_DIR`).

The review agent launches individual review agents, collects findings, and reports back. It does NOT fix anything — the orchestrator passes findings to the fixer.

## Phase 1 — comprehensive (5 agents)

Used when `REVIEW_PHASE` is `comprehensive`.

For each agent, resolve its prompt file using the resolve script:
```
bash RESOLVE_SCRIPT agents/quality.txt PLUGIN_DATA_DIR
bash RESOLVE_SCRIPT agents/implementation.txt PLUGIN_DATA_DIR
bash RESOLVE_SCRIPT agents/testing.txt PLUGIN_DATA_DIR
bash RESOLVE_SCRIPT agents/simplification.txt PLUGIN_DATA_DIR
bash RESOLVE_SCRIPT agents/documentation.txt PLUGIN_DATA_DIR
```

Read the resolved content for each agent. Replace `DEFAULT_BRANCH` with the actual value in each prompt. Prepend each agent prompt with:

"CRITICAL: You are a READ-ONLY reviewer. Do NOT run git stash, git checkout, git reset, or any command that modifies the working tree. Other agents run in parallel. Only use git diff, git log, git show, and read files.

Run `git diff DEFAULT_BRANCH...HEAD` to see all changes. Read the actual source files for full context — do not review from diff alone.

The plan file at PLAN_FILE_PATH describes the goal and requirements — use it to understand what the code is supposed to do.

Read the progress file at PROGRESS_FILE_PATH for context on previous review iterations and fixes. Re-evaluate all findings independently — previous fixes may be incomplete or wrong, and previously dismissed issues may be real.

SHELL VERIFICATION RULES (MANDATORY):
Claude Code's permission engine runs hardcoded pre-checks BEFORE bypassPermissions takes effect. These force a manual prompt that blocks the parent /exec session when a bash command contains any of: process substitution `<(...)` `>(...)`; `for`/`while`/`until` loops, function defs, multi-statement subshells; heredocs `<<EOF` / `<< 'EOF'` (including inline python3/awk/sed); braces with quoted strings (e.g. Python set/dict comprehensions `{f for ...'.sql'}`); complex parameter expansions or nested command substitutions.

Restrict every Bash call to ONE of: a single command, a linear pipeline (`|`), or a chain (`&& || ;`). Use absolute paths (e.g. `/tmp/claude/...`), not `$TMPDIR` or other shell variables. For iteration over files, prefer multiple parallel Bash tool calls in one message over `for`-loops. For anything more complex — multi-line scripts, multi-input tools (diff, comm, paste) — use the Write tool to create a script under `./sandbox/` and invoke it: `bash sandbox/<name>.sh` or `python3 sandbox/<name>.py`."

Launch all 5 in parallel — send ALL 5 Agent tool calls in a SINGLE message. Use `mode: "bypassPermissions"`, `subagent_type: "general-purpose"` for each.

After ALL 5 agents return:
- Collect and deduplicate findings from all agents
- Same file:line + same issue — merge
- Report ALL findings — do NOT verify, fix, or dismiss any
- ONLY include agents that reported actual issues — omit agents that found nothing
- List each finding as: agent-name: file:line — description

## Phase 2 — critical only (2 agents)

Used when `REVIEW_PHASE` is `critical`.

Resolve only `quality.txt` and `implementation.txt` using the resolve script. Prepend each agent prompt with: "Report ONLY critical and major issues — bugs, security vulnerabilities, data loss risks, broken functionality, incorrect logic, missing critical error handling. Ignore style, minor improvements, suggestions.

SHELL VERIFICATION RULES (MANDATORY): Claude Code's permission engine runs hardcoded pre-checks BEFORE bypassPermissions takes effect, forcing a manual prompt that blocks the parent /exec session when a bash command contains: process substitution `<(...)` `>(...)`; `for`/`while`/`until` loops, function defs, multi-statement subshells; heredocs `<<EOF` (including inline python3/awk/sed); braces with quoted strings (e.g. `{f for ...'.sql'}`); complex parameter expansions or nested command substitutions. Restrict every Bash call to ONE of: a single command, a linear pipeline (`|`), or a chain (`&& || ;`). For iteration prefer multiple parallel Bash tool calls; for multi-line logic use the Write tool to create a script in `./sandbox/` and invoke it."

Launch both in parallel. Same format as Phase 1.

After BOTH agents return:
- Same collection/deduplication as Phase 1
- Only keep critical/major severity findings
