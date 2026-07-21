#!/usr/bin/env bash
# spawn.sh — given an EXISTING Herdr-registered worktree, set up a `git` tab
# (lazygit) and a `claude` tab (autonomous worker) inside its workspace, then
# focus it. This script never references paths outside its own skill directory;
# the worktree is created upstream by the `herdr-worktree` skill and passed in.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: spawn.sh --worktree <path> --prompt-file <path> [--no-focus]
  --worktree      absolute path of an existing Herdr-registered worktree
  --prompt-file   file containing the specialized task prompt for the worker
  --no-focus      do not move Herdr focus to the new workspace
EOF
  exit 2
}

worktree="" ; prompt_file="" ; focus=1
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree)    worktree="${2:?--worktree needs a value}"; shift 2 ;;
    --prompt-file) prompt_file="${2:?--prompt-file needs a value}"; shift 2 ;;
    --no-focus)    focus=0; shift ;;
    -h|--help)     usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[ -n "$worktree" ] || { echo "error: --worktree is required" >&2; usage; }
[ -n "$prompt_file" ] || { echo "error: --prompt-file is required" >&2; usage; }

# ---- guards -----------------------------------------------------------------
[ "${HERDR_ENV:-}" = "1" ] || { echo "error: not running inside Herdr (HERDR_ENV unset)" >&2; exit 1; }
command -v herdr >/dev/null 2>&1 || { echo "error: herdr not on PATH" >&2; exit 1; }
command -v jq    >/dev/null 2>&1 || { echo "error: jq not on PATH" >&2; exit 1; }
[ -d "$worktree" ]    || { echo "error: worktree path does not exist: $worktree" >&2; exit 1; }
[ -f "$prompt_file" ] || { echo "error: prompt file does not exist: $prompt_file" >&2; exit 1; }

lazygit_bin="${HERDR_SPAWN_LAZYGIT:-lazygit}"
claude_bin="${HERDR_SPAWN_CLAUDE:-claude}"
command -v "$lazygit_bin" >/dev/null 2>&1 || { echo "error: '$lazygit_bin' not on PATH" >&2; exit 1; }
command -v "$claude_bin"  >/dev/null 2>&1 || { echo "error: '$claude_bin' not on PATH" >&2; exit 1; }

fail() { echo "spawn.sh: $1" >&2; exit 1; }

# (worktree/tab orchestration added in Task 2)
