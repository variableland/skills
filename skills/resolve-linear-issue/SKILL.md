---
name: resolve-linear-issue
description: 'Implement a Linear issue end-to-end: read or generate the plan, move the issue to In Progress, write the code, verify tests pass, open PR(s), wait for CI to go green, and close the issue once merged. Use when the user says "resolve", "implement", "work on", or "fix" a Linear issue. If no plan file exists it generates one automatically before implementing. Always use this skill instead of implementing Linear issues ad hoc.'
---

# Issue Resolver

## Step 0: Verify the Linear MCP is available

Call `list_teams` as a connectivity check before doing anything else.

- If it succeeds, continue.
- If it fails, stop and tell the user: "The Linear MCP doesn't seem to be reachable. Check that the MCP server is configured and running, then try again."

---

## Step 1: Read workspace state

Look for `.linear.json` at the workspace root. Extract `teamId`, `teamName`, `projectId`, `projectName`. You can reuse the result from Step 0.

If `.linear.json` is missing, tell the user to run the `manage-linear-issue` skill first to set up the workspace state, then stop.

---

## Step 2: Read or generate the plan

Accept either:
- A Linear identifier: `VLAND-5`, `PROJ-12`
- A Linear URL: `https://linear.app/.../issue/VLAND-5/...`

Call `get_issue` to get the current issue state and confirm it hasn't already been closed.

Then look for `.plans/<ISSUE-ID>.md` at the workspace root.

**If the plan file exists**, read it and extract:
- Issue title
- Type and PR prefix (e.g., `refactor(db)`)
- Suggested branch name
- Affected files
- Steps (numbered list)
- Testing requirements
- Sub-issues (if any were created)

**If the plan file does not exist**, generate the plan inline before continuing — do not stop and do not ask the user. Follow the full planning flow from the `plan-linear-issue` skill:

1. Read project conventions (`AGENTS.md`, `docs/conventions/`, etc.)
2. Follow any GitHub permalinks in the issue description
3. Search the codebase for files related to the issue's scope
4. Write the plan to `.plans/<ISSUE-ID>.md` (creating the directory and updating `.gitignore` if needed)
5. Tell the user: "No plan found — generated one at `.plans/<ISSUE-ID>.md`. Continuing with implementation."

Then continue with Step 3 using the plan just generated.

---

## Step 3: Prepare the branch

**If running inside Herdr** (`HERDR_ENV` is set in the environment) and the `herdr-worktree` skill is available, prefer an isolated worktree over switching branches in place: invoke that skill's `create.sh` with the suggested branch name, `cd` into the printed worktree path, and run every following step from there.

Otherwise, check the current git branch. If not already on the issue branch:

1. Ensure the working tree is clean (`git status`). If there are uncommitted changes, warn the user and stop.
2. Checkout or create the branch using the suggested branch name from the plan:
   ```
   git checkout -b <branch>
   ```
   If the branch already exists locally, checkout without `-b`.

---

## Step 4: Move the issue to In Progress

Call `save_issue` with `state: "In Progress"` on the main issue. If sub-issues exist, move them to In Progress as well.

---

## Step 5: Implement the plan

Work through each step in the plan's `## Steps` section sequentially. For each step:

1. Read the relevant files identified in `## Affected files` before making changes.
2. Implement the change following the project's conventions (read `AGENTS.md` or `docs/conventions/` if needed for guidance).
3. After each step, do a quick sanity check — the code should be syntactically valid and imports should resolve.

Do not move to Step 6 until all plan steps are complete.

---

## Step 6: Verify — conventions and tests

Before opening any PR, the implementation must pass local checks. Read the project's `AGENTS.md` or `DEVELOPMENT.md` to find the correct commands. Common patterns:

- Lint / format: `pnpm check`, `rr jscheck`, `biome check`
- Type check: `pnpm typecheck`, `rr tscheck`, `turbo run tscheck`
- Tests: `pnpm test`, `rr test`, `vitest run`

Run them in this order: **lint → typecheck → tests**. If any step fails:

1. Fix the issue.
2. Re-run the failing check.
3. Do not proceed until all pass.

Never open a PR with a failing local check.

---

## Step 7: Commit

Stage only the files changed as part of this issue. Do not include unrelated changes.

Commit message format follows the PR prefix from the plan:

```
<pr-prefix>: <concise description>
```

Example: `refactor(db): extract seeder helpers into shared module`

If the plan has sub-issues with separate scopes, you may make one commit per logical chunk — but a single commit is preferred if all changes are cohesive.

---

## Step 8: Open PR(s)

Use the `gh` CLI to open the PR:

```bash
gh pr create \
  --title "<pr-prefix>: <description>" \
  --body "<pr body>" \
  --base main
```

### PR body template

```markdown
## What

[One paragraph describing what this PR does.]

## Why

[Reference to the Linear issue and why this change is needed.]

## How

[Brief description of the approach taken.]

Closes <Linear issue URL>
```

If the issue has sub-issues, open one PR per sub-issue branch (each on its own branch), and include `Closes <sub-issue URL>` in the respective PR body.

After creating the PR, move the issue (or sub-issue) to **In Review** via `save_issue` with `state: "In Review"`.

---

## Step 9: Wait for CI

After opening the PR, poll its status using:

```bash
gh pr checks <pr-number> --watch
```

Or check periodically with:

```bash
gh pr view <pr-number> --json statusCheckRollup
```

- If all checks pass → tell the user the PR is green and ready to merge.
- If a check fails → read the failure output, attempt to fix it, push a new commit, and re-check. If the failure is outside your control (e.g., a flaky test or external service), surface it clearly to the user.

Do not mark the issue as Done until the PR is actually merged.

---

## Step 10: Close the issue once merged

Poll the PR merge status:

```bash
gh pr view <pr-number> --json mergedAt,state
```

Once `mergedAt` is non-null (PR merged to main):

1. Call `save_issue` with `state: "Done"` on the main issue.
2. If sub-issues exist and had their own PRs merged, mark each sub-issue as `Done` as well.
3. Delete the local branch if it was created by this skill:
   ```bash
   git checkout main && git pull && git branch -d <branch>
   ```

---

## Step 11: Report

Tell the user:

```
Done. VLAND-5 is closed.

  PR: https://github.com/org/repo/pull/42 (merged)
  Branch: deleted locally

[If sub-issues:]
  VLAND-6 — Done  (PR #43 merged)
  VLAND-7 — Done  (PR #44 merged)
```
