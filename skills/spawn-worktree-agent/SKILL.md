---
name: spawn-worktree-agent
description: 'Delegate a problem or investigation to an autonomous coding-agent worker running in an isolated Herdr worktree, instead of solving it in the current session. The worker is Claude by default but can be any Herdr agent kind (opencode, codex, gemini, ...). Use when the user wants to "spin off", "delegate", "arrancá un worktree para", "resolvé esto en un worktree aparte", or hand a task to a fresh agent in its own branch. Requires running inside Herdr (HERDR_ENV=1), herdr >= 0.7.5, and the herdr-worktree skill installed.'
---

# Spawn Worktree Agent

This skill turns the current session into a **launcher**: it does NOT solve the
problem itself. It creates an isolated worktree, starts an autonomous worker
there with a specialized prompt, and reports. The real work happens in the worker.

## Prerequisites (check first; stop with a clear message if unmet)

1. Running inside Herdr: `HERDR_ENV` is `1`. If not, this skill does not apply —
   tell the user and stop.
2. herdr **>= 0.7.5** (`herdr --version`). Older versions lack `agent start --kind`.
3. `herdr`, `jq`, `lazygit` on `PATH`. For the default `claude` kind, `claude` too;
   for `--kind opencode`, `opencode`.
4. The `herdr-worktree` skill is installed. If not, tell the user to install it and stop.
5. For `--kind claude`: the one-time `--dangerously-skip-permissions` bypass warning
   must have been accepted once on this machine, or the worker will wait at that prompt.

## Step 1: Classify intent, agent kind, and branch

- Intent: **resolve** (implement/fix) or **investigate** (research, no code changes).
- Agent kind: default `claude`. If the user asks for another (e.g. "usá opencode"),
  use that as `--kind` (valid kinds: claude, opencode, codex, gemini, cursor, ...).
- **Autonomous flag:** spawn.sh applies a default autonomous flag for known kinds
  (no action needed):
  - `claude` → `--dangerously-skip-permissions`
  - `opencode` → `--auto` (auto-approves permissions not explicitly denied — opencode's
    equivalent of claude's `--dangerously-skip-permissions`)

  For any OTHER kind you MUST pass that agent's non-interactive/autonomous flag via
  `--agent-arg <flag>` — otherwise the worker stalls at its own permission prompt. If
  you do not know the agent's autonomous flag, ASK THE USER before launching; do not
  launch a worker of an unknown kind without one.
- Branch `<type>/<slug>`: type `feat`/`fix` (resolve) or `investigate`; slug = short
  kebab-case summary. Use an explicit name if the user gave one.

## Step 2: Compose the worker prompt

Write the prompt to a readably-named file in the spawn scratch dir (so it's easy to find, and `spawn.sh` auto-cleans it later):

```bash
spawn_dir="${TMPDIR:-/tmp}/herdr-spawn"; mkdir -p "$spawn_dir"
prompt_file=$(mktemp "$spawn_dir/<branch-slug>-XXXXXX.md")   # <branch-slug> = the branch with / turned into -
```

The path is absolute, so a cross-repo worker reads it regardless of its working directory. Include, in the user's language:

1. The task exactly as the user described it.
2. Context: repo name, the branch, and "You are in an isolated git worktree on branch
   `<branch>`; the full repo is checked out here."
3. Behavior by intent:
   - **resolve:** "Implement the change. Run the project's tests and make them pass.
     Commit your work on this branch with a conventional-commit message. Do NOT open
     a pull request — leave that to the user."
   - **investigate:** "Investigate and produce findings. Do NOT modify code or commit.
     Summarize what you found, where, and your recommendation."
4. "When you finish, print a short summary of what you did."

The prompt must be self-contained — the worker starts with zero conversation history.

## Step 3: Create the worktree (via the herdr-worktree skill)

Follow the `herdr-worktree` skill: read its SKILL.md and run its `scripts/create.sh <branch> [--base <ref>]` exactly as documented there. Capture the absolute worktree path it prints (its last output line).

Do NOT substitute a bare `git worktree add` — Herdr's sidebar cannot see worktrees created that way.

**Nested and cross-repo spawning are supported.** `herdr-worktree`'s `create.sh` always resolves the target repo's parent workspace by path, so it works whether you are inside a linked worktree (a worker spawning another worker) or targeting a **different repo** than the current session's. For a cross-repo spawn, run `create.sh` with the **target repo as the working directory** (e.g. `cd <other-repo> && bash <herdr-worktree>/scripts/create.sh <branch> --base origin/main`) so it resolves that repo, not the session's. Do not work around any of this by unsetting `HERDR_WORKSPACE_ID` or falling back to `git worktree add`.

## Step 4: Set up tabs and launch the worker

```bash
bash <skill-dir>/scripts/spawn.sh --worktree "<path-from-step-3>" --prompt-file "$prompt_file" [--kind <kind>]
bash <skill-dir>/scripts/spawn.sh --worktree "<path-from-step-3>" --prompt-file "$prompt_file" --kind <other-kind> --agent-arg <autonomous-flag>
```

It sets up two tabs in the worktree's workspace — `git` (running lazygit) and one named after the kind (hosting the worker, started with `agent start --kind`, with the task delivered as the worker's **launch argument** — a one-line instruction to read the prompt file — so it can't be lost the way text typed into the TUI after startup can). It then **verifies the worker actually begins the task** before reporting success; if the worker never starts, spawn.sh fails loudly instead of reporting a launched-but-dead worker. It moves Herdr focus to the worker tab and prints a one-line JSON result. When no `--agent-arg` is given it defaults the worker's autonomous flag by kind: `claude` → `--dangerously-skip-permissions`, `opencode` → `--auto`; for other kinds pass the agent's autonomous flag(s) via `--agent-arg` (repeatable). Add `--no-focus` if the user asked not to switch focus, or when spawning several workers in one turn so Herdr focus doesn't bounce between them.

## Step 5: Report

Parse the JSON and tell the user, e.g.:

    Worktree listo: <path>  (branch <branch>, workspace <workspace_id>, agente <kind>)
      tab git    → lazygit
      tab <kind> → <kind> (autónomo) — worker lanzado
    Foco movido al worktree.

If any step failed, report which step and the error. If the worktree was created but
tab setup failed, say so — it still exists in the sidebar; the user can retry or remove it.

Leave the prompt file in place — the worker reads it *after* launch (and may re-read it while working), so do NOT delete it when the launcher finishes. It lives in `${TMPDIR:-/tmp}/herdr-spawn/` with a readable name; `spawn.sh` auto-reaps files older than a day there on each run, and `rm -f "${TMPDIR:-/tmp}/herdr-spawn/"*.md` clears them all.

## Cleanup (when the worker's work is done and merged)

```bash
herdr worktree list --cwd <repo-root> --json   # find .open_workspace_id
herdr worktree remove --workspace <id>
```
