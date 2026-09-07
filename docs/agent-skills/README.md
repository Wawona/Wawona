# Agent skills (tracked)

Cursor loads live copies from `.cursor/skills/` (gitignored in `Wawona/Wawona`).
This folder is the **git** mirror, indexed by wwn-mcp via `docs/**/*.md`.

When editing a skill, update **all** of:

- `Wawona/docs/agent-skills/<name>/SKILL.md` (this tree)
- `~/Wawona/.cursor/skills/<name>/SKILL.md` (workspace IDE)
- `~/Wawona/Wawona/.cursor/skills/<name>/SKILL.md` (repo IDE)

| Skill | Role |
|-------|------|
| [wawona-rag](./wawona-rag/SKILL.md) | Always query wwn-mcp; how to reindex |
| [wawona-write](./wawona-write/SKILL.md) | Software must improve on prior knowledge |
| [wawona-learn](./wawona-learn/SKILL.md) | Capture findings into skill + rule + RAG |
| [wawona-caveman](./wawona-caveman/SKILL.md) | Token voice (lite chat, full notes) |
| [wawona-priors](./wawona-priors/SKILL.md) | Index of existing rules (pointers only) |

Org rule: [`../agent-rules/wawona-agent-learn.md`](../agent-rules/wawona-agent-learn.md).
Do not duplicate hard gates here. Pointer + delta. See `wawona-learn`.
