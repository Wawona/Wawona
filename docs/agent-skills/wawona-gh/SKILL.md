---
name: wawona-gh
description: >-
  Run GitHub CLI (gh) via the Cursor Shell tool for Wawona org issues,
  milestones, PRs, workflow runs, releases, and repo create. Use when the user
  mentions gh, gh cli, GitHub issues, milestones, pull requests, gh api, gh
  run, or github.com/Wawona tracking. Never refuse gh because git authorship
  is forbidden. There is no GitHub MCP.
---

# GitHub CLI (`gh`) via Shell

Cursor has **no GitHub MCP**. Mutations and authenticated reads go through the
**Shell** tool running local `gh`. Auth is the operator's `gh auth login`
(macOS keychain) or `GH_TOKEN`.

Rule: `wawona-gh`. RAG: `wwn-mcp/knowledge/wawona/gh-cli.md`.
Related: `wawona-branch-workflow`, `wawona-github-funding`,
`wawona-discord-github-webhook`.

## When

User asks to create or inspect issues, milestones, PRs, `gh run`, releases,
repo hooks, `FUNDING.yml` via API, or anything on `github.com/Wawona/*`.

## How

1. Call the **Shell** tool. Command starts with `gh` (or `command -v gh` first).
2. Do not ask the user to paste `gh` commands back. Run them.
3. Prefer the repo that owns the work. Product tracker is
   `Wawona/Wawona`. There is **no** `github.com/Wawona/issues` repo (404).
   `github.com/Wawona/Wawona/issues` is the issues list.

```bash
command -v gh
gh auth status
gh issue list --repo Wawona/Wawona --limit 5
```

MCP `PATH` in `~/.cursor/mcp.json` is stripped (often no Homebrew). Shell
uses login zsh PATH. That is why `gh` works in Shell and not inside MCP
server env.

## Common shapes

```bash
# Milestone
gh api --method POST repos/Wawona/Wawona/milestones --input - <<'EOF'
{"title":"iOS 11-27 (latest SDK, ANGLE + MoltenVK)","state":"open","description":"..."}
EOF

# Issue
gh issue create --repo Wawona/Wawona --title "..." --body "..." --milestone "..."

# PR (after the user asked for one)
gh pr create --repo Wawona/Wawona --title "..." --body "..."

# CI
gh run list --repo Wawona/Wawona --branch development --limit 8
```

JSON `--input` for `gh api`. Unquoted zsh `config[url]=` is a glob
(`wawona-discord-github-webhook`).

## Git authorship is a different rule

A user rule may forbid recording Cursor as a git **author**. That is
`git commit` identity. It does **not** forbid `gh`. Do not refuse issues,
milestones, or PRs because of it. Do not append `Co-authored-by: Cursor`.

Standing grant: commit/push **`development`** with the human `user.name`.
Not `master`. Not force-push. Skill does not replace `wawona-branch-workflow`.

## Hard rejects (one line)

- Do not tell the user to run `gh` instead of Shell
- Do not substitute WebFetch / browser GET for `gh api` POST/PATCH
- Do not invent a GitHub MCP or call `mcp.wawona.io`
- Do not look for `gh` on MCP `PATH` from `mcp.json`
- Do not use repo `Wawona/issues` (does not exist)
- Do not echo Discord webhook URLs (`wawona-discord-github-webhook`)
- Do not force-push `master` or `development`

Query `wwn-mcp` for product facts. `gh` is only the GitHub control plane.
