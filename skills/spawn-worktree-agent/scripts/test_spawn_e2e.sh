#!/usr/bin/env bash
# End-to-end test for spawn.sh. Requires running inside Herdr (>=0.7.5). Creates
# and removes a throwaway worktree; launches a REAL claude worker with a no-op
# prompt (torn down immediately). lazygit is stubbed to echo.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
spawn="$here/spawn.sh"
create="/Users/ricardo.quiroz/Developer/vland/skills/skills/herdr-worktree/scripts/create.sh"
branch="probe/spawn-e2e-$$"
ws="" ; repo="" ; pf=""
cleanup() {
  [ -n "$ws" ] && herdr worktree remove --workspace "$ws" --force >/dev/null 2>&1
  [ -n "$repo" ] && git -C "$repo" branch -D "$branch" >/dev/null 2>&1
  [ -n "$pf" ] && rm -f "$pf"
}
trap cleanup EXIT

[ "${HERDR_ENV:-}" = "1" ] || { echo "SKIP: not inside Herdr"; exit 0; }

wt=$(bash "$create" "$branch") || { echo "FAIL: create.sh"; exit 1; }
echo "worktree: $wt"
repo=$(dirname "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)")
ws=$(herdr worktree list --cwd "$wt" --json 2>/dev/null | jq -er --arg p "$wt" 'first(.result.worktrees[]|select(.path==$p)|.open_workspace_id)') || ws=""
pf=$(mktemp); printf 'Do nothing. Reply with exactly DONE and stop.\n' > "$pf"

out=$(HERDR_SPAWN_LAZYGIT=echo bash "$spawn" --worktree "$wt" --prompt-file "$pf" --no-focus) \
  || { echo "FAIL: spawn.sh exited non-zero"; exit 1; }
echo "spawn output: $out"

ws=$(printf '%s' "$out" | jq -er '.workspace_id') || { echo "FAIL: no workspace_id"; exit 1; }
printf '%s' "$out" | jq -e '.ok==true and .worker_launched==true and .kind=="claude"' >/dev/null \
  || { echo "FAIL: output flags"; exit 1; }

labels=$(herdr tab list --workspace "$ws" | jq -r '.result.tabs[].label' | sort | tr '\n' ',')
echo "tab labels: $labels"
case "$labels" in *git*) : ;; *) echo "FAIL: no git tab ($labels)"; exit 1 ;; esac
case "$labels" in *claude*) : ;; *) echo "FAIL: no claude tab ($labels)"; exit 1 ;; esac

agent_tab=$(printf '%s' "$out" | jq -r '.tabs.claude')
agent_pane=$(herdr pane list --workspace "$ws" \
  | jq -er --arg t "$agent_tab" 'first(.result.panes[]|select(.tab_id==$t)|.pane_id)') \
  || { echo "FAIL: no pane for claude tab"; exit 1; }
herdr agent get "$agent_pane" | jq -e '.result.agent.agent=="claude"' >/dev/null \
  || { echo "FAIL: claude agent not recognized on $agent_pane"; exit 1; }
echo "PASS"
