#!/usr/bin/env bash
# watch-worker.sh — block until a spawned worker agent settles, then emit ONE
# machine-readable line on stdout and exit. Designed to run under a session's
# non-blocking watch primitive (Claude Code: Monitor persistent, or background
# Bash): the emitted line is the wake-up event for the launcher.
#
# Events (single line, key=value):
#   WORKER_SETTLED status=<idle|done> agent=<t> [commits_ahead=<n> dirty=<yes|no> last=<subject>]
#   WORKER_BLOCKED agent=<t>            worker waiting on something (permission prompt?)
#   WORKER_UNKNOWN agent=<t>            agent detection lost; inspect the pane
#   WORKER_GONE agent=<t>               agent no longer exists in herdr
#   WATCH_TIMEOUT agent=<t>             only with --timeout; the wait gave up
set -uo pipefail

usage() {
  cat >&2 <<'EOF'
usage: watch-worker.sh --agent <name-or-pane> [--worktree <path>] [--settle <sec>] [--timeout <ms>]
  --agent     herdr agent target (name or pane id) to watch
  --worktree  if given, append a git summary of this checkout to the event line
  --settle    seconds the agent must stay settled before firing (default 15) —
              filters transient idle blips between worker turns
  --timeout   fail with WATCH_TIMEOUT after this many ms (default: wait forever)
EOF
  exit 2
}

target="" ; worktree="" ; settle=15 ; timeout=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agent)    [ $# -ge 2 ] || usage; target="$2";   shift 2 ;;
    --worktree) [ $# -ge 2 ] || usage; worktree="$2"; shift 2 ;;
    --settle)   [ $# -ge 2 ] || usage; settle="$2";   shift 2 ;;
    --timeout)  [ $# -ge 2 ] || usage; timeout="$2";  shift 2 ;;
    -h|--help)  usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done
[ -n "$target" ] || usage
command -v herdr >/dev/null 2>&1 || { echo "error: herdr not on PATH" >&2; exit 1; }
command -v jq    >/dev/null 2>&1 || { echo "error: jq not on PATH" >&2; exit 1; }

agent_status() { herdr agent get "$target" 2>/dev/null | jq -er '.result.agent.agent_status'; }

git_summary() {
  [ -n "$worktree" ] && [ -d "$worktree" ] || return 0
  local ahead dirty subject
  ahead=$(git -C "$worktree" rev-list --count '@{upstream}..HEAD' 2>/dev/null) \
    || ahead=$(git -C "$worktree" rev-list --count 'origin/main..HEAD' 2>/dev/null) || ahead="?"
  dirty=yes; [ -z "$(git -C "$worktree" status --porcelain 2>/dev/null)" ] && dirty=no
  subject=$(git -C "$worktree" log -1 --format=%s 2>/dev/null | tr -d '\n' | cut -c1-80)
  printf ' commits_ahead=%s dirty=%s last="%s"' "$ahead" "$dirty" "$subject"
}

wait_args=(--until idle --until done --until blocked --until unknown)
[ -n "$timeout" ] && wait_args+=(--timeout "$timeout")

while :; do
  if ! herdr agent wait "$target" "${wait_args[@]}" >/dev/null 2>&1; then
    # Distinguish "agent gone" from "wait timed out / transient error".
    if ! herdr agent get "$target" >/dev/null 2>&1; then
      echo "WORKER_GONE agent=$target"; exit 1
    fi
    if [ -n "$timeout" ]; then echo "WATCH_TIMEOUT agent=$target"; exit 1; fi
    sleep 5; continue
  fi

  status=$(agent_status) || { echo "WORKER_GONE agent=$target"; exit 1; }
  case "$status" in
    blocked) echo "WORKER_BLOCKED agent=$target"; exit 0 ;;
    working) continue ;;
  esac

  # idle/done/unknown: require the state to hold for the settle window, so a
  # blip between worker turns doesn't fire a premature "finished" event.
  sleep "$settle"
  status2=$(agent_status) || { echo "WORKER_GONE agent=$target"; exit 1; }
  case "$status2" in
    idle|done)  printf 'WORKER_SETTLED status=%s agent=%s' "$status2" "$target"; git_summary; echo; exit 0 ;;
    blocked)    echo "WORKER_BLOCKED agent=$target"; exit 0 ;;
    unknown)    [ "$status" = "unknown" ] && { echo "WORKER_UNKNOWN agent=$target"; exit 0; } ;;
  esac
  # state moved on (back to working, or first unknown was transient) — keep waiting
done
