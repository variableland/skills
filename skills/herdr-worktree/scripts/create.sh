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

# Build the `herdr worktree create` args. $1 selects how to target the Herdr
# workspace: "workspace" (pass the injected id) or "cwd" (resolve by repo path).
build_args() {
  args=(worktree create --branch "$branch" "$focus" --json)
  [ -n "$base" ] && args+=(--base "$base")
  if [ "$1" = "workspace" ]; then
    args+=(--workspace "$HERDR_WORKSPACE_ID")
  else
    args+=(--cwd "$repo_root")
  fi
  if [ -d "$parent/worktrees" ]; then
    slug="${branch//\//-}"
    args+=(--path "$parent/worktrees/$repo/$slug")
  fi
}

# Inside a Herdr pane the workspace id is injected. But when the pane lives in a
# LINKED worktree, that id is the linked worktree's own workspace, which
# `herdr worktree create` rejects (linked_worktree_source) — new worktrees must
# originate from the repo's parent workspace. So only pass --workspace from the
# main checkout; from a linked worktree, resolve the parent workspace by the main
# repo path. Detect a linked worktree: its toplevel differs from the repo root.
toplevel=$(git rev-parse --show-toplevel)
if [ -n "${HERDR_WORKSPACE_ID:-}" ] && [ "$toplevel" = "$repo_root" ]; then
  mode=workspace
else
  mode=cwd
fi

build_args "$mode"
out=$("$herdr_bin" "${args[@]}") || true

# Defense in depth: if Herdr still rejects because the target resolved to a
# linked-worktree workspace, retry once resolving the parent workspace by path.
if [ "$mode" = "workspace" ] && printf '%s' "$out" | jq -e '.error.code=="linked_worktree_source"' >/dev/null 2>&1; then
  build_args cwd
  out=$("$herdr_bin" "${args[@]}") || true
fi

if ! path=$(printf '%s' "$out" | jq -er '.result.worktree.path'); then
  echo "herdr worktree create failed:" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi

echo "$path"
