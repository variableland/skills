# Skills

[![skills.sh](https://skills.sh/b/variableland/skills)](https://skills.sh/variableland/skills)

A collection of [Agent Skills](https://code.claude.com/docs/en/skills) maintained by Variable Land, for use with coding agents such as Claude Code and opencode.

Each skill lives in its own folder under [`skills/`](./skills) as a `SKILL.md` with YAML frontmatter (`name`, `description`); some bundle helper scripts under `scripts/`. Each `SKILL.md` is the source of truth for how its skill works — this reference only covers what each skill is for and how they fit together.

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

Covers the full lifecycle of a Linear issue, from creation to a merged PR. Designed to be used together, but each also works standalone:

```
manage-linear-issue  →  plan-linear-issue  →  resolve-linear-issue
   (create / edit)         (plan)               (implement + PR)
```

- **[manage-linear-issue](./skills/manage-linear-issue/SKILL.md)** — Creates or edits well-structured Linear issues: infers the issue type, maps it to a conventional-commit PR prefix, applies labels, and breaks large features into sub-issues.
- **[plan-linear-issue](./skills/plan-linear-issue/SKILL.md)** — Reads an issue, explores the affected codebase, and writes an implementation plan to `.plans/<ISSUE-ID>.md`.
- **[resolve-linear-issue](./skills/resolve-linear-issue/SKILL.md)** — Implements an issue end-to-end: plan (if missing), branch, code, tests, PR, CI, and closing the issue once merged. Inside Herdr it delegates the implementation to a worker via `spawn-worktree-agent`.

Requirements: a Linear MCP server connected to the agent, and a `.linear.json` file at the workspace root linking the repo to a Linear team/project (`manage-linear-issue` creates it on first use). `resolve-linear-issue` also needs an authenticated `gh` CLI for opening and monitoring pull requests.

### Herdr

For sessions running inside [Herdr](https://herdr.dev) (`HERDR_ENV=1`):

- **[herdr-worktree](./skills/herdr-worktree/SKILL.md)** — Creates a git worktree that registers in Herdr's sidebar (a bare `git worktree add` would be invisible there).
- **[spawn-worktree-agent](./skills/spawn-worktree-agent/SKILL.md)** — Delegates a task or investigation to an autonomous worker agent (Claude by default; any Herdr kind) in an isolated worktree created via `herdr-worktree`. Supports nested and cross-repo spawning. Requires herdr >= 0.7.5.

`resolve-linear-issue` builds on these: it delegates through `spawn-worktree-agent` when available, and falls back to an in-session `herdr-worktree` checkout otherwise.

Additional categories will be documented here as new skills are added.
