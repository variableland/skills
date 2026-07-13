---
name: plan-linear-issue
description: Read a Linear issue and generate a structured implementation plan as a local markdown file. Use when the user wants to plan how to solve an issue, mentions a Linear issue ID or URL, says "plan" or "tackle" an issue. Explores the codebase to understand the affected area, reads project conventions, follows GitHub permalinks from the issue description, and creates sub-issues in Linear when the plan is complex. Always use this skill instead of planning ad hoc. To implement the plan afterwards, use the resolve-linear-issue skill.
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

## Step 2: Fetch the issue

Accept either:
- A Linear identifier: `VLAND-5`, `PROJ-12`
- A Linear URL: `https://linear.app/.../issue/VLAND-5/...`

Call `get_issue` with the identifier. Extract:
- Title
- Type (from labels)
- Status
- Description — parse it to find:
  - Context section
  - Acceptance criteria
  - `PR prefix` line (e.g., `refactor(db)`)
  - Any GitHub permalinks in `## Code reference` sections

---

## Step 3: Explore the codebase

Do this in order, in parallel where possible:

1. **Read project conventions** — look for `AGENTS.md`, `CLAUDE.md`, or `docs/conventions/` at the workspace root. Skim for testing conventions, naming rules, and architecture patterns relevant to the issue's scope.

2. **Follow code references** — if the issue description contains GitHub permalinks, read those files at the referenced line ranges using the local filesystem (the permalink gives you the file path and lines).

3. **Search for related files** — based on the issue's scope (from the PR prefix) and keywords in the title/description, search the codebase for files that are likely to be touched. Look for:
   - The implementation file(s)
   - Their corresponding test files
   - Any shared utilities or types they depend on

Keep this exploration focused. The goal is enough context to write a credible plan, not a full audit.

---

## Step 4: Generate the plan

Write a structured plan covering these sections:

```markdown
# <ISSUE-ID>: <Issue title>

**Type:** <label> → `<pr-prefix>`
**Branch:** `<type>/linear-<issue-id>`

---

## Understanding

[What the issue is asking for, explained in technical terms. What is currently wrong
or missing, and what the end state should look like.]

## Affected files

- `path/to/file.ts` — why it is relevant
- `path/to/file.test.ts` — tests to update

## Steps

### 1. [Action title]
[Concrete description of what to do and why.]

### 2. [Action title]
...

## Testing

[Which tests need to be added or modified. Reference the project's testing conventions.
Mention specific test file paths where possible.]

## Edge cases / risks

- [Thing to be careful about]
- [Potential regression]

## Sub-issues

[Only present if sub-issues were created. List them here after creation.]
- <ID> — <title>  →  <pr-prefix>
```

### Branch naming

Derive the branch from the PR prefix and the issue ID — never from Linear's auto-generated `gitBranchName` (`<username>/<issue-id>-<full-title>`), which is long and carries no semantic type:

- `<type>` — the conventional-commit type from the `PR prefix`, without the scope: `fix`, `feat`, `refactor`, `docs`, `ci`, `chore`.
- `<issue-id>` — the Linear identifier, lowercased. Keeping it in the branch name lets Linear autolink the branch and its PR to the issue.

Examples: `fix/linear-vland-11`, `feat/linear-vland-12`, `ci/linear-vland-9`.

---

## Step 5: Complexity check and sub-issues

After generating the plan, evaluate whether the issue is complex:

An issue is complex if the plan has **4 or more steps that touch clearly distinct areas** (different scopes, layers, or concerns that could be worked on independently).

If complex:
1. Derive sub-issues directly from the plan steps — group related steps into 3–6 logical chunks.
2. For each sub-issue, determine its own type, label, and PR prefix (a refactor issue might break into `refactor` + `ci` + `docs` sub-issues).
3. Create each sub-issue using `save_issue` with:
   - `parentId` set to the original issue's ID
   - `project` from `.linear.json`
   - `state`: Backlog
   - Title in English following the `[Area] description` convention
   - Description using the standard template (Context / Acceptance criteria / PR prefix)
4. Add a `## Sub-issues` section to the plan listing what was created.

---

## Step 6: Write the plan file

1. Check whether `.plans/` appears in `.gitignore`. If not, append `.plans/` to `.gitignore`.
2. Create the `.plans/` directory if it does not exist.
3. Write the plan to `.plans/<ISSUE-ID>.md`.

---

## Step 7: Report

Tell the user:

```
Plan written to .plans/<ISSUE-ID>.md

Suggested branch: <type>/linear-<issue-id>
PR prefix: <pr-prefix>

[If sub-issues were created:]
Created N sub-issues:
  <ID> — <title>  →  <pr-prefix>
  ...
```
