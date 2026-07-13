#!/usr/bin/env bash
# Create a git worktree through Herdr so it registers in the UI. If a
# `worktrees/` directory exists next to the repo, the checkout goes to
# <parent>/worktrees/<repo>/<branch-slug>; otherwise Herdr's default
# worktree directory is used.
set -euo pipefail

usage() {
  echo "usage: create.sh <branch> [--base <ref>] [--focus]" >&2
  exit 2
}

[ $# -ge 1 ] || usage
branch="$1"
shift

base=""
focus="--no-focus"
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:?--base requires a ref}"; shift 2 ;;
    --focus) focus="--focus"; shift ;;
    *) usage ;;
  esac
done

# Resolve the main repo root even when invoked from inside a linked worktree.
common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
repo_root=$(dirname "$common_dir")
repo=$(basename "$repo_root")
parent=$(dirname "$repo_root")

herdr_bin="${HERDR_BIN_PATH:-herdr}"

args=(worktree create --branch "$branch" "$focus" --json)
[ -n "$base" ] && args+=(--base "$base")

# Inside a Herdr pane the workspace id is injected; otherwise resolve by path.
if [ -n "${HERDR_WORKSPACE_ID:-}" ]; then
  args+=(--workspace "$HERDR_WORKSPACE_ID")
else
  args+=(--cwd "$repo_root")
fi

if [ -d "$parent/worktrees" ]; then
  slug="${branch//\//-}"
  args+=(--path "$parent/worktrees/$repo/$slug")
fi

out=$("$herdr_bin" "${args[@]}")

if ! path=$(printf '%s' "$out" | jq -er '.result.worktree.path'); then
  echo "herdr worktree create failed:" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi

echo "$path"
