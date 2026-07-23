---
name: spawn-worktree-agent
description: 'Delegate a problem or investigation to an autonomous coding-agent worker running in an isolated Herdr worktree, instead of solving it in the current session. The worker is Claude by default but can be any Herdr agent kind (opencode, codex, gemini, ...). Use when the user wants to "spin off", "delegate", "arrancá un worktree para", "resolvé esto en un worktree aparte", or hand a task to a fresh agent in its own branch — including for a repo other than the current session''s ("spawn a worker for repo X", "delegá esto en el otro repo"). Not for ordinary same-session delegation (subagents/background tasks that need no new worktree). Requires running inside Herdr (HERDR_ENV=1), herdr >= 0.7.5, and the herdr-worktree skill installed.'
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

- Intent: **resolve** (implement/fix; stops at a local commit — no PR), **resolve-full**
  (end-to-end: commit, push, open PR(s), watch CI — pick it only when the user or a
  calling skill explicitly asks for full delivery), or **investigate** (research, no
  code changes).
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
- Branch `<type>/<slug>`: type `feat`/`fix` (resolve / resolve-full) or `investigate`;
  slug = short kebab-case summary. Use an explicit name if the user gave one.

## Step 2: Compose the worker prompt

Write the prompt to a readably-named file in the spawn scratch dir (so it's easy to find, and `spawn.sh` auto-cleans it later):

```bash
spawn_dir="${TMPDIR:-/tmp}/herdr-spawn"; mkdir -p "$spawn_dir"
prompt_file="$spawn_dir/<branch-slug>-$(date +%s).md"   # <branch-slug> = the branch with / turned into -
```

Do NOT reach for `mktemp` here: BSD/macOS `mktemp` requires the `X`s to be the template's
trailing characters, so a template ending in `.md` gets created *literally* (no unique
suffix) — and pre-creating an empty file also forces overwrite-guarded write tools into a
pointless read-before-write step. Compose the content and write it to `$prompt_file` in
one go; the timestamp keeps re-spawns of the same branch from colliding.

The path is absolute, so a cross-repo worker reads it regardless of its working directory. Include, in the user's language:

1. The task exactly as the user described it.
2. Context: repo name, the branch, and "You are in an isolated git worktree on branch
   `<branch>`; the full repo is checked out here."
3. Behavior by intent:
   - **resolve:** "Implement the change. Run the project's tests and make them pass.
     Commit your work on this branch with a conventional-commit message. Do NOT open
     a pull request — leave that to the user."
   - **resolve-full:** "Implement the change. Run the project's checks and tests until
     everything is green. Commit on this branch with a conventional-commit message,
     push the branch, and open the PR(s) with `gh`. Watch CI and fix failures until
     the PR is green. Do NOT merge, and do NOT update any issue tracker — the launcher
     session owns those — unless this prompt explicitly says otherwise."
   - **investigate:** "Investigate and produce findings. Do NOT modify code or commit.
     Summarize what you found, where, and your recommendation."
4. "When you finish, print a short summary of what you did."

The prompt must be self-contained — the worker starts with zero conversation history.

If a plan or spec file governs the task and lives somewhere gitignored (e.g. `.plans/`),
do not paste its contents into the prompt: reference it as a path relative to the
worker's working directory, and copy the file into the worktree after Step 3 creates it
(see there). One pointer beats an inline copy that can drift.

## Step 3: Create the worktree (via the herdr-worktree skill)

Follow the `herdr-worktree` skill: read its SKILL.md and run its `scripts/create.sh <branch> [--base <ref>]` exactly as documented there. Capture the absolute worktree path it prints (its last output line).

If the prompt references gitignored plan/spec files (see Step 2), copy them into the same relative location inside the worktree now (e.g. `mkdir -p <worktree>/.plans && cp .plans/<issue>.md <worktree>/.plans/`) — gitignored files are not part of the checkout, and once copied they remain ignored, so the worker cannot accidentally commit them.

Do NOT substitute a bare `git worktree add` — Herdr's sidebar cannot see worktrees created that way.

**Nested and cross-repo spawning are supported.** `herdr-worktree`'s `create.sh` always resolves the target repo's parent workspace by path, so it works whether you are inside a linked worktree (a worker spawning another worker) or targeting a **different repo** than the current session's. For a cross-repo spawn, run `create.sh` with the **target repo as the working directory**, in a **subshell** so your own working directory doesn't stay changed for the rest of the session: `(cd <other-repo> && bash <herdr-worktree-skill-dir>/scripts/create.sh <branch> --base origin/main)`. Do not work around any of this by unsetting `HERDR_WORKSPACE_ID` or falling back to `git worktree add`.

## Step 4: Set up tabs and launch the worker

```bash
bash <skill-dir>/scripts/spawn.sh --worktree "<path-from-step-3>" --prompt-file "$prompt_file" [--kind <kind>]
bash <skill-dir>/scripts/spawn.sh --worktree "<path-from-step-3>" --prompt-file "$prompt_file" --kind <other-kind> --agent-arg <autonomous-flag>
```

It sets up two tabs in the worktree's workspace — `git` (running lazygit) and one named after the kind (hosting the worker, started with `agent start --kind`, with the task delivered as the worker's **launch argument** — a one-line instruction to read the prompt file — so it can't be lost the way text typed into the TUI after startup can). It then **verifies the worker actually begins the task** before reporting success (if the worker stays idle it re-delivers the instruction once via `agent prompt`; if it still won't start, spawn.sh fails loudly — and tears the agent tab down — instead of reporting a launched-but-dead worker). The `git` tab is best-effort: a lazygit hiccup never fails a successful delegation, it just sets `git_tab_ready:false` in the JSON. It moves Herdr focus to the worker tab and prints a one-line JSON result. When no `--agent-arg` is given it defaults the worker's autonomous flag by kind: `claude` → `--dangerously-skip-permissions`, `opencode` → `--auto`; for other kinds pass the agent's autonomous flag(s) via `--agent-arg` (repeatable). Add `--no-focus` if the user asked not to switch focus, or when spawning several workers in one turn so Herdr focus doesn't bounce between them.

## Step 5: Report

Compose the report **in the user's language** from the JSON **plus what you already know**. The JSON carries `worktree`, `workspace_id`, `kind`, `agent`, `tabs`, `git_tab_ready`, `worker_launched` — it does **NOT** carry the branch; use the branch you chose in Step 1. E.g. (adapt the wording to the user's language):

    Worktree ready: <path>  (branch <branch-from-Step-1>, workspace <workspace_id>, agent <kind>)
      git tab    → lazygit
      <kind> tab → <kind> (autonomous) — worker launched and verified
    Focus moved to the worktree.

Adjust to reality: mention the focus move only if you did not pass `--no-focus`; if `git_tab_ready` is `false`, say the git tab setup failed but the worker is running fine (the user can open lazygit by hand).

If any step failed, report which step and the error. If the worktree was created but
tab setup failed, say so — it still exists in the sidebar; the user can retry or remove it.

Leave the prompt file in place — the worker reads it *after* launch (and may re-read it while working), so do NOT delete it when the launcher finishes. It lives in `${TMPDIR:-/tmp}/herdr-spawn/` with a readable name; `spawn.sh` auto-reaps files older than a day there on each run, and `rm -f "${TMPDIR:-/tmp}/herdr-spawn/"*.md` clears them all.

## Cleanup (when the worker's work is done and merged)

```bash
herdr worktree list --cwd <repo-root> --json   # find .open_workspace_id
herdr worktree remove --workspace <id>
```
