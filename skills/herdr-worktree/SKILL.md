---
name: herdr-worktree
description: 'Create a git worktree registered in the Herdr UI, at the right path for the repo. Use whenever you are running inside Herdr (the HERDR_ENV environment variable is set) and need an isolated worktree to work on a branch — e.g. before implementing a Linear issue. If a worktrees/ directory exists next to the repo, the checkout goes to <parent>/worktrees/<repo>/<branch-slug>; otherwise Herdr''s default worktree directory is used. Prefer this over a bare `git worktree add`, which Herdr''s sidebar cannot see.'
---

# Herdr Worktree

## When to use

- You are inside a Herdr pane (`HERDR_ENV=1` is present in the environment) **and** you need a worktree to work on a branch in isolation.
- If `HERDR_ENV` is not set or the `herdr` binary is not on `PATH`, this skill does not apply — create the worktree however the task requires (e.g. `git worktree add`) and say so.

## Usage

From anywhere inside the repo (main checkout or an existing worktree):

```bash
bash <skill-dir>/scripts/create.sh <branch> [--base <ref>] [--focus]
```

- `<branch>` — the branch to check out; created from `HEAD` (or `--base <ref>`) if it doesn't exist locally. Slashes are fine (e.g. a Linear `gitBranchName`).
- `--base <ref>` — base ref for a new branch, e.g. `origin/main`.
- `--focus` — switch the Herdr UI to the new worktree workspace (default: don't steal focus).

On success the script prints exactly one line: **the absolute path of the new worktree**. `cd` there and continue working. On failure it prints Herdr's error to stderr and exits non-zero.

## What it does

1. Resolves the main repo root (correct even when invoked from inside another worktree).
2. Picks the checkout path by convention:
   - A `worktrees/` directory exists next to the repo → `<parent>/worktrees/<repo>/<branch-slug>` (slashes in the branch become dashes). Creating that directory is how a group of sibling repos opts into this layout.
   - Otherwise → Herdr's configured default (`[worktrees].directory`, usually `~/.herdr/worktrees`).
3. Creates the worktree through `herdr worktree create`, so it appears in the Herdr sidebar as a workspace linked to the repo. It **always targets the worktree's parent workspace by repo path** (`--cwd`), never by the injected `HERDR_WORKSPACE_ID`. That injected id is only correct in the plain main-checkout case; path resolution additionally handles two scenarios it would break: **from inside a linked worktree** (a worker spawning another worker) the injected id is that linked worktree's own workspace, and **cross-repo** (creating a worktree for a repo other than the current session's) it belongs to a different repo — both are rejected by `herdr worktree create` as `linked_worktree_source`. Because the script resolves by the target repo's path, nested and cross-repo worktree creation work with no caller workaround. For a cross-repo create, invoke the script with the target repo as the working directory.

Note: git identity is not this skill's concern — conditional gitconfig includes key off the repo location, and linked worktrees inherit the main repo's identity automatically.

## Cleanup

When the branch is merged and the worktree is no longer needed, remove it through Herdr (not `git worktree remove`), so the UI stays in sync:

```bash
herdr worktree list --cwd <repo-root> --json   # find the workspace id
herdr worktree remove --workspace <id>
```
