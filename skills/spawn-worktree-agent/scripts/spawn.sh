#!/usr/bin/env bash
# spawn.sh — given an EXISTING Herdr-registered worktree, set up a `git` tab
# (lazygit) and an agent tab (an AI coding agent, claude by default) inside its
# workspace, submit a specialized prompt to the agent, then focus it. This
# script never references paths outside its own skill directory; the worktree is
# created upstream by the `herdr-worktree` skill and passed in via --worktree.
# Requires herdr >= 0.7.5 (agent start --kind / agent prompt / pane wait-output).
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: spawn.sh --worktree <path> --prompt-file <path> [--kind <kind>] [--agent-arg <arg>]... [--no-focus]
  --worktree      absolute path of an existing Herdr-registered worktree
  --prompt-file   file with the specialized task prompt for the agent
  --kind          herdr agent kind (default: claude); e.g. claude, opencode, codex, gemini
  --agent-arg     extra arg passed to the agent after `--` (repeatable). Default when
                  --kind claude and none given: --dangerously-skip-permissions
  --no-focus      do not move Herdr focus to the new workspace
EOF
  exit 2
}

worktree="" ; prompt_file="" ; kind="claude" ; focus=1
agent_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree)    [ $# -ge 2 ] || { echo "error: --worktree needs a value" >&2; usage; }; worktree="$2"; shift 2 ;;
    --prompt-file) [ $# -ge 2 ] || { echo "error: --prompt-file needs a value" >&2; usage; }; prompt_file="$2"; shift 2 ;;
    --kind)        [ $# -ge 2 ] || { echo "error: --kind needs a value" >&2; usage; }; kind="$2"; shift 2 ;;
    --agent-arg)   [ $# -ge 2 ] || { echo "error: --agent-arg needs a value" >&2; usage; }; agent_args+=("$2"); shift 2 ;;
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
command -v "$lazygit_bin" >/dev/null 2>&1 || { echo "error: '$lazygit_bin' not on PATH" >&2; exit 1; }
if [ "$kind" = "claude" ]; then
  command -v claude >/dev/null 2>&1 || { echo "error: claude not on PATH (needed for --kind claude)" >&2; exit 1; }
fi

# Default agent args for the claude kind.
if [ "${#agent_args[@]}" -eq 0 ] && [ "$kind" = "claude" ]; then
  agent_args=(--dangerously-skip-permissions)
fi

fail() { echo "spawn.sh: $1" >&2; exit 1; }

# (worktree/tab orchestration added in Task 2)
