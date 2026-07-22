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
  --agent-arg     extra arg passed to the agent after `--` (repeatable). Defaults when
                  none given: claude -> --dangerously-skip-permissions,
                  opencode -> --auto
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
case "$kind" in
  claude)   command -v claude   >/dev/null 2>&1 || { echo "error: claude not on PATH (needed for --kind claude)" >&2; exit 1; } ;;
  opencode) command -v opencode >/dev/null 2>&1 || { echo "error: opencode not on PATH (needed for --kind opencode)" >&2; exit 1; } ;;
esac

# Default autonomous flags per agent kind (only when no --agent-arg was given).
if [ "${#agent_args[@]}" -eq 0 ]; then
  case "$kind" in
    claude)   agent_args=(--dangerously-skip-permissions) ;;
    opencode) agent_args=(--auto) ;;
  esac
fi

fail() { echo "spawn.sh: $1" >&2; exit 1; }

# ---- resolve workspace id from worktree path --------------------------------
# Herdr reports each worktree's open workspace id as `open_workspace_id`.
ws=$(herdr worktree list --cwd "$worktree" --json 2>/dev/null \
      | jq -er --arg p "$worktree" 'first(.result.worktrees[] | select(.path==$p) | .open_workspace_id)') \
  || fail "could not resolve workspace id for worktree: $worktree (registered in Herdr?)"
[ -n "$ws" ] && [ "$ws" != "null" ] || fail "worktree has no open workspace: $worktree"

# ---- resolve the default (git) tab up front ---------------------------------
git_tab=$(herdr tab list --workspace "$ws" | jq -er '.result.tabs[0].tab_id') \
  || fail "could not resolve default tab of workspace $ws"

# ---- agent tab FIRST: create it, start the agent, submit the prompt ---------
# ORDER MATTERS: herdr 0.7.5 returns `agent_pane_busy` from `agent start` when a
# `pane run` was issued on a sibling pane just before it. So start the agent
# BEFORE running lazygit in the git pane. (Verified against the live server.)
create_out=$(herdr tab create --workspace "$ws" --cwd "$worktree" --label "$kind" --no-focus) \
  || fail "could not create agent tab"
agent_tab=$(printf '%s' "$create_out"  | jq -er '.result.tab.tab_id')        || fail "no tab_id in tab create output"
agent_pane=$(printf '%s' "$create_out" | jq -er '.result.root_pane.pane_id') || fail "no pane_id in tab create output"

# herdr agent names must match [a-z][a-z0-9_-]{0,31}; derive from the worktree slug.
agent_name=$(basename "$worktree" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^[^a-z]+//' | cut -c1-32)
[ -n "$agent_name" ] || agent_name="worker"

# Wait for the pane's shell to be ready; `agent start` rejects a not-yet-ready pane.
herdr pane wait-output "$agent_pane" --match '❯' --timeout 15000 >/dev/null \
  || fail "agent pane shell did not become ready"

herdr agent start "$agent_name" --kind "$kind" --pane "$agent_pane" --timeout 30000 -- ${agent_args[@]+"${agent_args[@]}"} >/dev/null \
  || fail "could not start '$kind' agent on pane $agent_pane"
herdr agent wait "$agent_pane" --until idle --timeout 30000 >/dev/null 2>&1 || true
herdr agent prompt "$agent_pane" "$(cat "$prompt_file")" >/dev/null \
  || fail "could not submit prompt to the '$kind' worker"

# ---- git tab AFTER: rename the default tab -> git, run lazygit --------------
herdr tab rename "$git_tab" git >/dev/null || fail "could not rename default tab to 'git'"
git_pane=$(herdr pane list --workspace "$ws" \
      | jq -er --arg t "$git_tab" 'first(.result.panes[] | select(.tab_id==$t) | .pane_id)') \
  || fail "could not resolve pane of git tab"
herdr pane wait-output "$git_pane" --match '❯' --timeout 10000 >/dev/null 2>&1 || true
herdr pane run "$git_pane" "$lazygit_bin" >/dev/null || fail "could not launch lazygit in git tab"

# ---- focus ------------------------------------------------------------------
if [ "$focus" -eq 1 ]; then
  herdr workspace focus "$ws" >/dev/null 2>&1 || true
  herdr tab focus "$agent_tab" >/dev/null 2>&1 || true
fi

# ---- structured result ------------------------------------------------------
jq -nc --arg worktree "$worktree" --arg ws "$ws" --arg git_tab "$git_tab" \
       --arg agent_tab "$agent_tab" --arg kind "$kind" --arg agent "$agent_name" \
  '{ok:true, worktree:$worktree, workspace_id:$ws, kind:$kind, agent:$agent,
    tabs:({git:$git_tab} + {($kind):$agent_tab}), worker_launched:true}'
