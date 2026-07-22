#!/usr/bin/env bash
# Smoke test for spawn.sh guards. Does not touch Herdr.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
spawn="$here/spawn.sh"
fail=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (expected $2, got $3)"; fail=1; else echo "ok: $1"; fi; }

# usage errors -> exit 2
HERDR_ENV=1 bash "$spawn" >/dev/null 2>&1; check "no args" 2 $?
HERDR_ENV=1 bash "$spawn" --worktree /tmp >/dev/null 2>&1; check "missing --prompt-file" 2 $?
HERDR_ENV=1 bash "$spawn" --worktree >/dev/null 2>&1; check "--worktree no value" 2 $?
HERDR_ENV=1 bash "$spawn" --worktree /tmp --prompt-file >/dev/null 2>&1; check "--prompt-file no value" 2 $?
HERDR_ENV=1 bash "$spawn" --worktree /tmp --prompt-file /tmp/x --kind >/dev/null 2>&1; check "--kind no value" 2 $?
HERDR_ENV=1 bash "$spawn" --worktree /tmp --prompt-file /tmp/x --agent-arg >/dev/null 2>&1; check "--agent-arg no value" 2 $?
HERDR_ENV=1 bash "$spawn" --bogus >/dev/null 2>&1; check "unknown flag" 2 $?

# guard failures -> exit 1
# The path checks run AFTER the binary checks, so stub the binaries onto PATH:
# without this, a host missing herdr/jq/lazygit would still exit 1 — the test
# would pass for the wrong reason.
pf=$(mktemp); wt=$(mktemp -d); stub=$(mktemp -d)
for b in herdr jq lazygit claude; do printf '#!/bin/sh\nexit 0\n' > "$stub/$b"; chmod +x "$stub/$b"; done
env -u HERDR_ENV bash "$spawn" --worktree "$wt" --prompt-file "$pf" >/dev/null 2>&1; check "no HERDR_ENV" 1 $?
HERDR_ENV=1 PATH="$stub:$PATH" bash "$spawn" --worktree /nope/nope --prompt-file "$pf" >/dev/null 2>&1; check "bad worktree" 1 $?
HERDR_ENV=1 PATH="$stub:$PATH" bash "$spawn" --worktree "$wt" --prompt-file /nope/nope >/dev/null 2>&1; check "bad prompt file" 1 $?

rm -f "$pf"; rm -rf "$stub"; rmdir "$wt" 2>/dev/null || true
exit $fail
