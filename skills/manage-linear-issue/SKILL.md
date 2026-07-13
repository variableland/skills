---
name: manage-linear-issue
description: Create or edit well-structured Linear issues for this workspace. Use whenever the user wants to report a bug, request a feature, record technical debt, document something, track infrastructure work, or update an existing issue. Reads .linear.json from the workspace root to know which Linear project and team to use. Automatically picks the right labels, maps issue type to a conventional commit prefix (fix/feat/refactor/docs/ci), and proposes a parent + sub-issue breakdown for large features. Always previews the full issue draft and waits for explicit user approval before writing anything to Linear. Always load this skill instead of creating or editing Linear issues ad hoc.
---

# Linear Issue Creator

## Step 0: Verify the Linear MCP is available

Before doing anything else, call `list_teams` as a connectivity check.

- If it succeeds, continue to Step 1.
- If it fails or returns an error, stop and tell the user: "The Linear MCP doesn't seem to be reachable. Check that the MCP server is configured and running, then try again."

Do not proceed if this check fails.

---

## Step 1: Read workspace state

Look for `.linear.json` at the workspace root (e.g., `cat .linear.json`). This file links the repo to a specific Linear project.

If the file **exists**, extract `teamId`, `teamName`, `projectId`, `projectName` and use them throughout. You can reuse the `list_teams` result from Step 0 — no need to call it again.

If the file **does not exist**, run the setup flow:

1. Show the teams returned by the Step 0 check and ask the user to confirm the team.
2. Call `list_projects` for the chosen team and ask the user to confirm the project.
3. Write `.linear.json` to the workspace root:

```json
{
  "teamId": "...",
  "teamName": "...",
  "projectId": "...",
  "projectName": "..."
}
```

4. Tell the user the file was created and continue.

---

## Language

**Always write issue titles and descriptions in English**, regardless of the language the user is speaking. If the user writes in another language, translate their intent into clear English before creating or updating the issue.

---

## Mode: create vs. edit

Determine what the user wants before proceeding:

- **Create**: the user describes something new (bug, feature, task). Follow the full workflow below.
- **Edit**: the user refers to an existing issue by ID or description (e.g., "update PROJ-12", "change the priority of the auth issue"). Follow the edit workflow below.

---

## Issue types

Every issue belongs to exactly one type. Use the user's description to infer it — only ask if genuinely ambiguous.

| Type | Label | PR prefix | When |
|------|-------|-----------|------|
| **Bug** | Bug | `fix(scope)` | Something is broken or behaves incorrectly |
| **Feature** | Feature | `feat(scope)` | New capability or user-facing behaviour |
| **Improvement** | Improvement | `feat(scope)` | Enhancement to an existing feature |
| **Technical Debt** | Technical Debt | `refactor(scope)` | Internal cleanup with no user-visible change |
| **Documentation** | Documentation | `docs` | Docs, READMEs, conventions, ADRs |
| **Infra** | Infrastructure | see sub-types | CI, IaC, containers, deployment |

### Infra sub-types

| Sub-type | Keywords | PR prefix |
|----------|----------|-----------|
| CI/CD | GitHub Actions, workflows, pipeline, lint | `ci` |
| Terraform | tf, IaC, cloud resources | `chore(tf)` |
| Docker | Dockerfile, compose, containers | `chore(docker)` |
| Kubernetes | k8s, Helm, manifests | `chore(k8s)` |
| General | anything else | `chore(infra)` |

---

## Scope (conventional commit scope)

Infer the scope from the workspace structure and the user's description. Do not assume any fixed list.

- In a monorepo, look at the top-level directories (e.g., `apps/`, `packages/`, `services/`) and use the relevant package or app name as the scope.
- In a single-app repo, use a logical layer name (e.g., `auth`, `db`, `api`, `ui`).
- Omit scope only for cross-cutting changes or pure infra issues that touch no specific module.

The scope should map naturally to what a developer would write in `fix(<scope>): ...`. Keep it short and lowercase.

---

## Labels

Before assigning a label, call `list_issue_labels` to check which ones exist. Create any missing labels with `create_issue_label` using these colors:

| Label | Color |
|-------|-------|
| Bug | `#EB5757` |
| Feature | `#BB87FC` |
| Improvement | `#4EA7FC` |
| Technical Debt | `#F2C94C` |
| Documentation | `#5E6AD2` |
| Infrastructure | `#26B5CE` |

---

## Issue title

Use a plain, human-readable title in English. Do **not** include the conventional commit prefix — that belongs on the PR.

**Good:** `OAuth sessions expire too early when refreshing token`
**Bad:** `fix(auth): OAuth sessions expire too early`

---

## Issue description

Always use this template. Fill every section — even a single sentence is better than leaving it blank.

```markdown
## Context
<!-- What problem does this solve? What's the current broken/missing behaviour? -->

## Acceptance criteria
- [ ] ...

---
> **PR prefix:** `fix(auth)`
```

The `PR prefix` line is the contract between the issue and the pull request that will close it. It tells the developer how to title their branch and commit.

---

## Code references

When an issue points to a specific place in the codebase (a bug in a function, a class that needs refactoring, a missing test, etc.), enrich the description with a short code snippet and a GitHub permalink to the exact lines.

**Only include a snippet if you can produce a valid permalink.** To build one:

1. Get the GitHub remote URL: `git remote get-url origin`
2. Get the current commit SHA: `git rev-parse HEAD`
3. Identify the file path and the relevant line range (read the file to confirm)
4. Construct the permalink:
   `https://github.com/<owner>/<repo>/blob/<sha>/<path/to/file>#L<start>-L<end>`

The snippet itself must be **short** — 3 to 8 lines maximum, enough to show the relevant context at a glance. It is a preview only; the permalink is the source of truth. Do not paste large blocks of code.

Add it to the description under a `## Code reference` heading, using a fenced code block with the language identifier, followed by the permalink on its own line:

```markdown
## Code reference

```ts
// src/auth/session.ts · lines 42–48
export function refreshSession(token: string) {
  const expiry = Date.now() + SESSION_TTL
  return db.sessions.update({ token, expiry })
}
```

[`src/auth/session.ts#L42-L48`](https://github.com/org/repo/blob/abc1234/src/auth/session.ts#L42-L48)
```

If multiple locations are relevant, repeat the block for each one — but keep each snippet equally brief.

---

## Priority

Default to **No priority** (value `0`) unless the user signals urgency. Map like this:

| User says | Priority |
|-----------|----------|
| urgent, blocker, production down | Urgent (1) |
| important, high priority | High (2) |
| when we get to it, low | Low (4) |

---

## Large features: parent + sub-issues

A feature is **large** (needs breakdown) if any of these apply:
- Touches more than one scope / area
- More than 3–4 distinct acceptance criteria
- Would likely span more than one PR
- User uses words like "epic", "initiative", "module", "system"

When a feature is large, **do not just ask** — propose a concrete breakdown first, then confirm:

1. Identify 3–6 logical sub-tasks from the user's description.
2. Assign each sub-task its own type (a feature might break into `feat` + `refactor` + `ci` sub-issues).
3. The breakdown goes through the same *Preview & confirmation* gate as everything else: preview the parent and every sub-issue in full, and let the user adjust before creating anything.

**Creation order:**
- Create the parent issue first (type: Feature, no `parentId`).
- Create each sub-issue with `parentId` set to the parent's ID.

Sub-issue title convention: `[Area] description`, where Area is the relevant module, layer, or app derived from the workspace structure.

Examples:
- `[API] Add webhook endpoint`
- `[UI] Confirmation modal`
- `[DB] Migration for new table`
- `[CI] Add integration test job`

---

## Default status

Set all new issues to **Backlog** status.

---

## Preview & confirmation (mandatory)

**Never write to Linear without showing a preview and getting explicit approval first.** This gates every write call — `save_issue` (create and edit) and `create_issue_label` alike. Drafting is free; writing is not.

For **creation**, render each issue exactly as it will be created, with the full description markdown visible (not summarized):

```
## Preview

**PROJ — <title>**
Type: Feature · Label: Feature · Priority: No priority · Status: Backlog

---
<the complete description markdown, rendered as it will appear in Linear,
including Context, Acceptance criteria, Code reference, and PR prefix>
---
```

For a parent + sub-issues, preview the parent first, then every sub-issue in creation order — each with its own full description. Never create a parent "to get started" while sub-issues are still being discussed.

The preview must be emitted as normal visible text in the conversation **before** asking for approval. Drafting it in your internal reasoning does not count — the user cannot see that. Never call `AskUserQuestion` unless the full preview markdown is already printed in the transcript above it; putting the preview inside the question text or option descriptions does not count either.

Then ask the user to approve. If the `AskUserQuestion` tool is available, use it with options like **Create as shown** / **Adjust first**; otherwise ask in plain text and wait. If the user requests changes, apply them, re-show the affected parts, and ask again. Only proceed after an explicit approval **of the latest version** in this conversation — approval of an earlier draft does not carry over, and neither does a general "create an issue for X" request.

For **edits**, show a field-by-field `before → after` diff of everything that will change (for description changes, show the resulting markdown of the changed sections) and confirm the same way before calling `save_issue`.

---

## Create workflow

1. **Gather info** from the user's message:
   - Title (in English)
   - Type (infer; ask only if ambiguous)
   - Scope (infer from affected area)
   - Priority (default: No priority)
   - One or two sentences of context
2. **Size check for features** — if large, draft the sub-issue breakdown so it lands in the preview.
3. **Preview & confirm** — show every issue as described in *Preview & confirmation* and wait for explicit approval. No Linear writes before this point.
4. **Ensure labels exist** — create missing ones.
5. **Create issues** — parent first, then children in order.
6. **Report results:**

```
Created:
  PROJ-42  OAuth sessions expire too early  →  fix(auth)
  https://linear.app/.../issue/PROJ-42/...

Expected PR: fix(auth): resolve OAuth session expiry on token refresh
```

If sub-issues were created, list them indented under their parent.

---

## Edit workflow

When the user wants to modify an existing issue:

1. **Identify the issue** — use the ID if provided, otherwise call `list_issues` with a search query to find it. Confirm with the user if there's any ambiguity.
2. **Determine what to change** — title, description, type/label, priority, status, assignee, parent, or any combination.
3. **Preview & confirm** — show the `before → after` diff as described in *Preview & confirmation* and wait for explicit approval.
4. **Apply changes** with `save_issue` passing the issue `id` and only the fields that change.
5. **Report what changed:**

```
Updated PROJ-42:
  priority: No priority → High
  label: Bug → Improvement
```

For description edits, preserve the existing template structure (Context / Acceptance criteria / PR prefix). Only replace the sections the user asked to change.
