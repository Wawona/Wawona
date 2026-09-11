# GitHub CLI (`gh`) via Shell

Cursor has **no GitHub MCP**. Issues, milestones, PRs, `gh run`, releases, and
`gh api` run through the **Shell** tool and the operator's `gh auth`.

Cursor rule: `wawona-gh`.
Skill: `wawona-gh`.
RAG: `wwn-mcp/knowledge/wawona/gh-cli.md`.

## Do

- Shell: `command -v gh` then `gh ...`
- Product issues: `Wawona/Wawona` (not a `Wawona/issues` repo)
- JSON `--input` for `gh api`

A user rule may forbid recording Cursor as a git **author**. That does not
forbid `gh`. Do not append `Co-authored-by: Cursor`.

## Hard rejects

- Refuse `gh` because a user rule forbids Cursor as git author
- Ask the user to run `gh` instead of Shell
- WebFetch GET as a substitute for `gh` mutations
- Discord webhook URLs in git, docs, or chat
