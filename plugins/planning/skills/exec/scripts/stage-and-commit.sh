#!/bin/bash
# stage files only — DO NOT commit
#
# This is a fork-modified version of the upstream planning plugin script.
# Upstream auto-commits after each task; this fork only stages changes via
# `git add` and leaves all commit decisions to the user. Stage accumulates
# across tasks within /planning:exec — the user can split or squash later
# (e.g. `git reset HEAD <file>` then manual commits).
#
# The first argument (commit message) is accepted for backward compatibility
# with callers that still pass one, but it is ignored — no commit is created.
#
# usage: stage-and-commit.sh <ignored-message> <file1> [file2 ...]
# VCS-aware: dispatches to git or hg based on detect-vcs.sh

set -e

if [ $# -lt 2 ]; then
    echo "error: usage: stage-and-commit.sh <message> <file1> [file2 ...]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
vcs=$(bash "$SCRIPT_DIR/detect-vcs.sh")

do_git() {
    shift # drop ignored message
    git add -- "$@"
}

do_hg() {
    # hg has no staging area; `hg add` only registers untracked files.
    # Tracked files are picked up by the next commit automatically. Best-effort:
    # swallow "already tracked" warnings so the script stays idempotent.
    shift # drop ignored message
    hg add -- "$@" 2>/dev/null || true
}

case "$vcs" in
git) do_git "$@" ;;
hg) do_hg "$@" ;;
*)
    echo "error: unsupported VCS: $vcs" >&2
    exit 1
    ;;
esac
