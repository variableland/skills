#!/usr/bin/env bash
# watch-pr.sh — poll a GitHub PR until it reaches a decisive state, emitting one
# machine-readable stdout line per event. Designed to run under a session's
# non-blocking watch primitive (Claude Code: Monitor persistent, or background
# Bash): each emitted line is a wake-up event for the launcher.
#
# Terminal events (script exits):
#   READY_TO_MERGE pr=<n> url=<u>          all checks green AND review approved
#   CHECKS_FAILED pr=<n> failing=<a,b>     at least one check failed
#   CHANGES_REQUESTED pr=<n> url=<u>       a reviewer requested changes
#   PR_MERGED pr=<n> url=<u>               merged (by someone else, or already)
#   PR_CLOSED pr=<n> url=<u>               closed without merging
#   WATCH_ERROR pr=<n> reason=<r>          repeated gh failures; exit 1
# Informative events (script keeps polling):
#   GREEN_AWAITING_REVIEW pr=<n> url=<u>   emitted once: green but not approved
set -uo pipefail

usage() {
  cat >&2 <<'EOF'
usage: watch-pr.sh --pr <number> [--repo <owner/name>] [--interval <sec>] [--no-require-approval]
  --pr                   PR number to watch
  --repo                 owner/name (default: repo of the current directory)
  --interval             poll interval in seconds (default 60; keep >=30 for API limits)
  --no-require-approval  fire READY_TO_MERGE on green checks alone (default requires APPROVED)
EOF
  exit 2
}

pr="" ; repo="" ; interval=60 ; require_approval=1
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)       [ $# -ge 2 ] || usage; pr="$2";       shift 2 ;;
    --repo)     [ $# -ge 2 ] || usage; repo="$2";     shift 2 ;;
    --interval) [ $# -ge 2 ] || usage; interval="$2"; shift 2 ;;
    --no-require-approval) require_approval=0; shift ;;
    -h|--help)  usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done
[ -n "$pr" ] || usage
command -v gh >/dev/null 2>&1 || { echo "error: gh not on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not on PATH" >&2; exit 1; }

repo_args=() ; [ -n "$repo" ] && repo_args=(--repo "$repo")

announced_green=0 ; consecutive_failures=0
while :; do
  if ! json=$(gh pr view "$pr" "${repo_args[@]}" \
        --json state,mergedAt,reviewDecision,statusCheckRollup,url 2>/dev/null); then
    consecutive_failures=$((consecutive_failures + 1))
    if [ "$consecutive_failures" -ge 10 ]; then
      echo "WATCH_ERROR pr=$pr reason=gh_pr_view_failed_${consecutive_failures}_times"; exit 1
    fi
    sleep "$interval"; continue
  fi
  consecutive_failures=0

  url=$(jq -r '.url' <<<"$json")
  state=$(jq -r '.state' <<<"$json")
  review=$(jq -r '.reviewDecision // ""' <<<"$json")

  case "$state" in
    MERGED) echo "PR_MERGED pr=$pr url=$url"; exit 0 ;;
    CLOSED) echo "PR_CLOSED pr=$pr url=$url"; exit 0 ;;
  esac
  if [ "$review" = "CHANGES_REQUESTED" ]; then
    echo "CHANGES_REQUESTED pr=$pr url=$url"; exit 0
  fi

  # statusCheckRollup mixes CheckRun {status,conclusion,name} and
  # StatusContext {state,context}; classify both shapes.
  failing=$(jq -r '[.statusCheckRollup[]?
      | select(((.conclusion // "") | IN("FAILURE","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE"))
            or ((.state // "") | IN("FAILURE","ERROR")))
      | (.name // .context)] | join(",")' <<<"$json")
  pending=$(jq -r '[.statusCheckRollup[]?
      | select((((.status // "COMPLETED") != "COMPLETED"))
            or ((.state // "") | IN("PENDING","EXPECTED")))
      | (.name // .context)] | length' <<<"$json")

  if [ -n "$failing" ]; then
    echo "CHECKS_FAILED pr=$pr failing=$failing"; exit 0
  fi
  if [ "$pending" -eq 0 ]; then
    if [ "$require_approval" -eq 0 ] || [ "$review" = "APPROVED" ]; then
      echo "READY_TO_MERGE pr=$pr url=$url"; exit 0
    fi
    if [ "$announced_green" -eq 0 ]; then
      echo "GREEN_AWAITING_REVIEW pr=$pr url=$url"
      announced_green=1
    fi
  fi

  sleep "$interval"
done
