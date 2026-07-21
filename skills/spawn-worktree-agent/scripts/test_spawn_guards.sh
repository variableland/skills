#!/usr/bin/env bash
# Smoke test for spawn.sh guards. Does not touch Herdr.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
spawn="$here/spawn.sh"
fail=0
check() { # desc, expected_code, actual_code
  if [ "$2" != "$3" ]; then echo "FAIL: $1 (expected exit $2, got $3)"; fail=1; else echo "ok: $1"; fi
}

# missing args -> usage (exit 2)
HERDR_ENV=1 bash "$spawn" >/dev/null 2>&1; check "no args" 2 $?
HERDR_ENV=1 bash "$spawn" --worktree /tmp >/dev/null 2>&1; check "missing --prompt-file" 2 $?

# not inside herdr -> exit 1
pf=$(mktemp); wt=$(mktemp -d)
env -u HERDR_ENV bash "$spawn" --worktree "$wt" --prompt-file "$pf" >/dev/null 2>&1; check "no HERDR_ENV" 1 $?

# nonexistent worktree -> exit 1
HERDR_ENV=1 bash "$spawn" --worktree /nope/nope --prompt-file "$pf" >/dev/null 2>&1; check "bad worktree" 1 $?

# nonexistent prompt file -> exit 1
HERDR_ENV=1 bash "$spawn" --worktree "$wt" --prompt-file /nope/nope >/dev/null 2>&1; check "bad prompt file" 1 $?

rm -f "$pf"; rmdir "$wt" 2>/dev/null || true
exit $fail
