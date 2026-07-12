# Skills

A collection of [Agent Skills](https://code.claude.com/docs/en/skills) maintained by Variable Land, for use with coding agents such as Claude Code and opencode.

Each skill lives in its own folder under [`skills/`](./skills) as a single `SKILL.md` with YAML frontmatter (`name`, `description`) and no additional dependencies.

## Install

```bash
npx skills@latest add variableland/skills
```

Individual skills can also be installed by hand:

```bash
# Claude Code
cp -R skills/<skill-name> ~/.claude/skills/

# opencode
cp -R skills/<skill-name> ~/.opencode/skills/
```

## Reference

### Linear

Covers the full lifecycle of a Linear issue, from creation to a merged PR. The three skills are designed to be used together, but each also works standalone:

```
manage-linear-issue  →  plan-linear-issue  →  resolve-linear-issue
   (create / edit)         (plan)               (implement + PR)
```

- **[manage-linear-issue](./skills/manage-linear-issue/SKILL.md)** — Creates or edits well-structured Linear issues: infers issue type, maps it to a conventional-commit PR prefix, applies labels, and proposes a parent + sub-issue breakdown for large features.
- **[plan-linear-issue](./skills/plan-linear-issue/SKILL.md)** — Reads a Linear issue, explores the affected codebase, and writes a structured implementation plan to `.plans/<ISSUE-ID>.md`.
- **[resolve-linear-issue](./skills/resolve-linear-issue/SKILL.md)** — Implements an issue end-to-end: plan (if missing), branch, code, tests, PR via `gh`, CI, and closing the issue once merged.

Requires a Linear MCP server connected to the agent, and a `.linear.json` file at the workspace root linking it to a Linear team/project (created automatically by `manage-linear-issue` on first use):

```json
{
  "teamId": "...",
  "teamName": "...",
  "projectId": "...",
  "projectName": "..."
}
```

The `resolve-linear-issue` skill additionally requires the `gh` CLI to be authenticated, for opening and monitoring pull requests.

Additional categories will be documented here as new skills are added.
