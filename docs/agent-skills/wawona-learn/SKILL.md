---
name: wawona-learn
description: Capture durable Wawona learnings into skills, Cursor rules, and wwn-mcp RAG. Use after an incident, hard reject, recipe fix, gate flip, or any "never do X" discovered while coding. Do not leave knowledge only in chat.
---

# Capture learnings

A finding that would save the next agent time **must** land in git + RAG, not
only in the thread.

## Promote where

| Kind | Where |
|------|--------|
| Workflow / "how to" / gotcha | Skill under `docs/agent-skills/` + `.cursor/skills/` |
| Hard gate / forbid / shipping firewall | Cursor rule + `docs/agent-rules/` (same change) |
| Architecture summary for retrieval | `wwn-mcp/knowledge/wawona/*.md` |
| Org-wide one-liner | `AGENTS.md` (workspace + `Wawona/AGENTS.md` if needed) |

Do **not** paste a whole existing rule into a new skill. Pointer + delta.

## Same-change checklist

```text
- [ ] Skill updated or added (tracked + both .cursor/skills trees)
- [ ] Rule mirror if it is a hard gate (workspace, Wawona/.cursor, docs/agent-rules)
- [ ] wwn-mcp/knowledge/wawona patched
- [ ] wwn-mcp index --only wwn-knowledge-wawona (or --local-siblings)
- [ ] wawona-priors index row if a new skill/rule name exists
- [ ] No em dash. Code/commits stay normal English.
```

## Skill body shape

Keep `SKILL.md` under 500 lines. Pointers to canonical docs. One-line hard
rejects. Examples only when the wrong path is tempting.

Copy new skills to:

- `~/Wawona/.cursor/skills/<name>/SKILL.md`
- `~/Wawona/Wawona/.cursor/skills/<name>/SKILL.md`
- `~/Wawona/Wawona/docs/agent-skills/<name>/SKILL.md`

`.cursor/` is gitignored in `Wawona/Wawona`. Tracked copy is `docs/agent-skills/`.

## Software bar

New Wawona code must **improve on** the prior (fix a documented hole, extend a
gate, delete a rejected path). Re-implementing a known-bad approach is a bug.
Query `wawona-rag` first.
