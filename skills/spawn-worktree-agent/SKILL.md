---
name: spawn-worktree-agent
description: 'Delegate a problem or investigation to an autonomous coding-agent worker running in an isolated Herdr worktree, instead of solving it in the current session. The worker is Claude by default but can be any Herdr agent kind (opencode, codex, gemini, ...). Use when the user wants to "spin off", "delegate", "arrancá un worktree para", "resolvé esto en un worktree aparte", or hand a task to a fresh agent in its own branch — including for a repo other than the current session''s ("spawn a worker for repo X", "delegá esto en el otro repo"). Not for ordinary same-session delegation (subagents/background tasks that need no new worktree). After launching, the launcher stays on duty: it arms watchers, opens the PR when the worker commits, and merges once CI is green and the PR is approved. Requires running inside Herdr (HERDR_ENV=1), herdr >= 0.7.5, and the herdr-worktree skill installed.'
---

# Spawn Worktree Agent

This skill turns the current session into a **launcher**: it does NOT solve the
problem itself. It creates an isolated worktree, starts an autonomous worker
there with a specialized prompt, and reports. The real work happens in the worker.

Launching is not the end of the launcher's job: after reporting, it **arms
watchers** (Step 6) and stays on duty to deliver — when the worker finishes it
opens the PR (resolve) or finds the worker's PR (resolve-full), watches it, and
merges it once CI is green **and** a reviewer approved. The launcher owns
delivery; the worker owns code.

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

- Intent: **resolve** (implement/fix; the WORKER stops at a local commit — the
  launcher then pushes, opens the PR, and merges it via the Step 6 watchers),
  **resolve-full** (the worker itself commits, pushes, opens PR(s), and watches CI —
  pick it only when the user or a calling skill explicitly asks for it; the launcher
  still watches and merges per Step 6), or **investigate** (research, no code changes).
  If the user asked to stop at the local commit ("solo commit local", "no PR"), use
  resolve but skip Step 6's PR stage — arm only the worker watcher and report.
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

Compose the report **in the user's language** from the JSON **plus what you already know**. The JSON carries `worktree`, `workspace_id`, `kind`, `agent`, `agent_pane`, `tabs`, `git_tab_ready`, `worker_launched` — it does **NOT** carry the branch; use the branch you chose in Step 1. E.g. (adapt the wording to the user's language):

    Worktree ready: <path>  (branch <branch-from-Step-1>, workspace <workspace_id>, agent <kind>)
      git tab    → lazygit
      <kind> tab → <kind> (autonomous) — worker launched and verified
    Focus moved to the worktree.
    Watching the worker — when it commits I'll open the PR and merge it once it's green + approved.

Adjust to reality: mention the focus move only if you did not pass `--no-focus`; if `git_tab_ready` is `false`, say the git tab setup failed but the worker is running fine (the user can open lazygit by hand).

If any step failed, report which step and the error. If the worktree was created but
tab setup failed, say so — it still exists in the sidebar; the user can retry or remove it.

Leave the prompt file in place — the worker reads it *after* launch (and may re-read it while working), so do NOT delete it when the launcher finishes. It lives in `${TMPDIR:-/tmp}/herdr-spawn/` with a readable name; `spawn.sh` auto-reaps files older than a day there on each run, and `rm -f "${TMPDIR:-/tmp}/herdr-spawn/"*.md` clears them all.

## Step 6: Arm the delivery watchers (default — skip only if the user opted out)

The launcher does not poll by hand and does not end its duty at the report: it
arms **event watchers** that wake the session when something decisive happens.
Run each watcher script under the session's non-blocking watch primitive — in
Claude Code that is the **Monitor tool with `persistent: true`** (each stdout
line becomes a notification; these waits can take hours, so never use a
foreground Bash call, and prefer Monitor over background Bash because background
tasks may be time-capped). The watchers live only as long as the launcher
session — if the session is about to end, hand off explicitly: tell the user
which stage remains and what event triggers it.

### 6a. Worker watcher (all intents)

Immediately after a successful Step 4 launch:

```bash
bash <skill-dir>/scripts/watch-worker.sh --agent <agent_pane-from-JSON> --worktree <worktree>
```

It blocks on `herdr agent wait` until the worker settles (with a settle window
that filters transient idle blips between worker turns), then emits ONE line and
exits. On wake, act by event and intent:

- `WORKER_SETTLED` + **investigate** → read the findings from the pane
  (`herdr agent read <agent>`), relay them to the user. Done.
- `WORKER_SETTLED` + **resolve** → in the worktree, verify `dirty=no` and
  `commits_ahead>=1` (both are on the event line). Push the branch
  (`git -C <worktree> push -u origin <branch>`), open the PR with `gh pr create`
  (use the calling skill's PR template if one governs the run, else the repo's
  convention), tell the user, then arm 6b.
- `WORKER_SETTLED` + **resolve-full** → the worker opened the PR itself: find it
  with `gh pr list --head <branch> --json number,url`, then arm 6b.
- `WORKER_SETTLED` but the tree is dirty or has no commits → the worker stopped
  short. Read its pane to see why; re-prompt it once
  (`herdr agent prompt <agent> "<what's missing>"`), then re-arm 6a. If it
  settles short again, surface to the user instead of looping.
- `WORKER_BLOCKED` → the worker is stuck on a prompt. Read the pane; if it's
  waiting on a trivial confirmation, answer via `herdr agent prompt` /
  `herdr agent send-keys`; otherwise surface to the user.
- `WORKER_GONE` / `WORKER_UNKNOWN` → inspect the workspace and report; do not
  silently re-arm.

### 6b. PR watcher (resolve / resolve-full)

```bash
bash <skill-dir>/scripts/watch-pr.sh --pr <number> --repo <owner/name> [--interval 30]
```

It polls `gh pr view` and emits one line per decisive event. On wake:

- `READY_TO_MERGE` (all checks green AND `reviewDecision: APPROVED`) → **merge it
  yourself**: `gh pr merge <n> --squash` (match the repo's allowed merge method —
  `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed`).
  The human gate is the review approval; never weaken it — no `--admin`, no
  merging on green-but-unapproved, no self-approving.
- `GREEN_AWAITING_REVIEW` (informative; the watcher keeps running) → tell the
  user their approval is the only thing missing, with the PR URL.
- `CHECKS_FAILED` → the worker's tab is still alive. Re-prompt it with the
  failing check names and the failure output
  (`herdr agent prompt <agent> "CI failed: <details>. Fix and push."`), then
  re-arm 6a (worker) and, once it settles, 6b again. If the failure is clearly
  environmental/flaky, say so to the user instead.
- `CHANGES_REQUESTED` → read the review comments (`gh pr view <n> --comments`,
  `gh api` for review threads), relay them to the worker via `herdr agent
  prompt`, re-arm 6a then 6b.
- `PR_CLOSED` → stop; report to the user.
- `PR_MERGED` (merged by someone else, or right after your own merge) → close out:
  run the Cleanup below, then report which PR merged and what was cleaned up.

### Close-out after merge

1. Confirm `mergedAt` is non-null (`gh pr view <n> --json mergedAt,state`).
2. Remove the worktree per **Cleanup** below — this also closes the worker's
   workspace and tabs, so only do it after the merge.
3. Delete the local branch from the main checkout
   (`git branch -d <branch>`; the remote branch is auto-deleted when the repo
   has `deleteBranchOnMerge`, otherwise `git push origin --delete <branch>`).
4. Report: PR URL, merged, worktree removed, branch deleted.

## Cleanup (when the worker's work is done and merged)

```bash
herdr worktree list --cwd <repo-root> --json   # find .open_workspace_id
herdr worktree remove --workspace <id> --force
```

Use `--force`: a worker that installed dependencies or ran builds leaves ignored
files (node_modules, artifacts) in the worktree, and without it the remove fails
with "Directory not empty" — worse, the failed attempt can leave a half-removed
state (git registration gone, orphan directory, workspace closed). Verify tracked
files are clean/merged before forcing. If a previous non-force attempt already
half-removed it, finish by hand: `rm -rf <worktree-path>` then
`git -C <repo-root> worktree prune`.
