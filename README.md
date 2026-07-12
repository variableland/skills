# Linear Agent Skills

A set of [Agent Skills](https://code.claude.com/docs/en/skills) for managing the full lifecycle of a Linear issue — from creation to a merged PR — without leaving your coding agent (Claude Code, opencode, etc.).

The three skills are designed to be used together, but each also works standalone.

```
manage-linear-issue  →  plan-linear-issue  →  resolve-linear-issue
   (create / edit)         (plan)               (implement + PR)
```

## Skills

### [`manage-linear-issue`](./skills/manage-linear-issue/SKILL.md)

Creates or edits well-structured Linear issues. Infers issue type (Bug, Feature, Improvement, Technical Debt, Documentation, Infra), maps it to a conventional-commit PR prefix (`fix`, `feat`, `refactor`, `docs`, `ci`, `chore`), applies the right labels, and proposes a parent + sub-issue breakdown for large features. Issue titles and descriptions are always written in English, regardless of the input language.

Use it to report a bug, request a feature, record tech debt, or update an existing issue.

### [`plan-linear-issue`](./skills/plan-linear-issue/SKILL.md)

Reads a Linear issue, explores the affected part of the codebase (project conventions, GitHub permalinks referenced in the issue, related files/tests), and writes a structured implementation plan to `.plans/<ISSUE-ID>.md`. If the issue is complex, it also proposes and creates sub-issues in Linear derived from the plan's steps.

Use it when you want a plan before touching any code.

### [`resolve-linear-issue`](./skills/resolve-linear-issue/SKILL.md)

Implements an issue end-to-end: generates a plan if one doesn't exist yet, creates the branch, moves the issue to *In Progress*, implements each step, runs lint/typecheck/tests, commits, opens a PR via `gh`, waits for CI, and closes the issue once the PR is merged.

Use it when you say "resolve", "implement", or "fix" a Linear issue.

## Requirements

- A Linear MCP server connected to your agent (all three skills start with a `list_teams` connectivity check).
- A `.linear.json` file at the root of the target workspace, linking the repo to a Linear team/project:

  ```json
  {
    "teamId": "...",
    "teamName": "...",
    "projectId": "...",
    "projectName": "..."
  }
  ```

  `manage-linear-issue` creates this file interactively on first use if it's missing. `plan-linear-issue` and `resolve-linear-issue` require it to already exist.
- `gh` CLI authenticated, for the PR steps in `resolve-linear-issue`.
- A workspace with `AGENTS.md` / `CLAUDE.md` (or `docs/conventions/`) so the planning and implementation steps can follow project conventions.

## Installation

Copy the skill directories you want into your agent's skills folder:

```bash
# Claude Code
cp -R skills/manage-linear-issue skills/plan-linear-issue skills/resolve-linear-issue ~/.claude/skills/

# opencode
cp -R skills/manage-linear-issue skills/plan-linear-issue skills/resolve-linear-issue ~/.opencode/skills/
```

Each skill is a single `SKILL.md` with YAML frontmatter (`name`, `description`) — no extra dependencies.
