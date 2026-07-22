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
common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || { echo "error: not inside a git repository — run from the target repo" >&2; exit 1; }
repo_root=$(dirname "$common_dir")
repo=$(basename "$repo_root")
parent=$(dirname "$repo_root")

herdr_bin="${HERDR_BIN_PATH:-herdr}"

# Always target the worktree's parent workspace by repo path (--cwd), never by
# the injected HERDR_WORKSPACE_ID. Path resolution is correct in every case:
#   - main checkout: resolves the repo's own workspace;
#   - inside a linked worktree (a worker spawning another worker): the injected
#     id is the linked worktree's own workspace, which `herdr worktree create`
#     rejects (linked_worktree_source) — --cwd resolves the parent instead;
#   - cross-repo (creating a worktree for a repo other than the session's): the
#     injected id belongs to a different repo — --cwd targets the right one.
args=(worktree create --branch "$branch" "$focus" --json --cwd "$repo_root")
[ -n "$base" ] && args+=(--base "$base")
if [ -d "$parent/worktrees" ]; then
  slug="${branch//\//-}"
  args+=(--path "$parent/worktrees/$repo/$slug")
fi

# herdr writes its result JSON to stdout on success and its error JSON to stderr
# on failure — capture them separately so a failure surfaces the real error.
err=$(mktemp)
trap 'rm -f "$err"' EXIT
out=$("$herdr_bin" "${args[@]}" 2>"$err") || true
if ! path=$(printf '%s' "$out" | jq -er '.result.worktree.path' 2>/dev/null); then
  echo "herdr worktree create failed:" >&2
  cat "$err" >&2
  [ -n "$out" ] && printf '%s\n' "$out" >&2
  exit 1
fi

echo "$path"
