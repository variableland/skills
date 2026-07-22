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
3. `herdr`, `jq`, `lazygit` on `PATH`. For the default `claude` kind, `claude` too.
4. The `herdr-worktree` skill is installed. If not, tell the user to install it and stop.
5. For `--kind claude`: the one-time `--dangerously-skip-permissions` bypass warning
   must have been accepted once on this machine, or the worker will wait at that prompt.

## Step 1: Classify intent, agent kind, and branch

- Intent: **resolve** (implement/fix) or **investigate** (research, no code changes).
- Agent kind: default `claude`. If the user asks for another (e.g. "usá opencode"),
  use that as `--kind` (valid kinds: claude, opencode, codex, gemini, cursor, ...).
- **Autonomous flag:** for `--kind claude`, spawn.sh defaults to `--dangerously-skip-permissions` (no action needed). For any OTHER kind you MUST pass that agent's non-interactive/autonomous flag via `--agent-arg <flag>` — otherwise the worker stalls at its own permission prompt. If you do not know the agent's autonomous flag, ASK THE USER before launching; do not launch a non-claude worker without one.
- Branch `<type>/<slug>`: type `feat`/`fix` (resolve) or `investigate`; slug = short
  kebab-case summary. Use an explicit name if the user gave one.

## Step 2: Compose the worker prompt

Write the prompt to a temp file: `prompt_file=$(mktemp)`. Include, in the user's language:

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

**Nested spawning is supported.** If you are already inside a linked worktree (a spawned worker spawning another worker), `herdr-worktree`'s `create.sh` targets the repo's parent workspace automatically — worktree creation just works. Do not work around it by unsetting `HERDR_WORKSPACE_ID` or falling back to `git worktree add`.

## Step 4: Set up tabs and launch the worker

```bash
bash <skill-dir>/scripts/spawn.sh --worktree "<path-from-step-3>" --prompt-file "$prompt_file" [--kind <kind>]
bash <skill-dir>/scripts/spawn.sh --worktree "<path-from-step-3>" --prompt-file "$prompt_file" --kind <other-kind> --agent-arg <autonomous-flag>
```

It sets up two tabs in the worktree's workspace — `git` (running lazygit) and one named after the kind (hosting the worker, started with `agent start --kind` and given the task via `agent prompt`) — moves Herdr focus to the worker tab, and prints a one-line JSON result. For `--kind claude` it defaults the worker to `--dangerously-skip-permissions`; for other kinds pass the agent's autonomous flag(s) via `--agent-arg` (repeatable). Add `--no-focus` if the user asked not to switch focus, or when spawning several workers in one turn so Herdr focus doesn't bounce between them.

## Step 5: Report

Parse the JSON and tell the user, e.g.:

    Worktree listo: <path>  (branch <branch>, workspace <workspace_id>, agente <kind>)
      tab git    → lazygit
      tab <kind> → <kind> (autónomo) — worker lanzado
    Foco movido al worktree.

If any step failed, report which step and the error. If the worktree was created but
tab setup failed, say so — it still exists in the sidebar; the user can retry or remove it.

After reporting, remove the temp prompt file: `rm -f "$prompt_file"`.

## Cleanup (when the worker's work is done and merged)

```bash
herdr worktree list --cwd <repo-root> --json   # find .open_workspace_id
herdr worktree remove --workspace <id>
```
