---
name: repo-wawona-io-learn
description: Capture durable repo.wawona.io findings into this repo's Cursor skills and rules. Use after a catalog incident, hard reject, 404 that looked like downtime, mixed wasm/deb list, wrong APT path, or any never-do-X. Do not leave knowledge only in chat.
---

# Capture learnings (this repo)

A finding that would save the next agent time must land in git, not only in
the thread. Software must **improve on** the priors in `repo-wawona-io-priors`.

## Promote where

| Kind | Where |
|------|--------|
| Workflow / how-to / gotcha | Skill under `.cursor/skills/` + `docs/agent-skills/` |
| Hard gate / firewall | `.cursor/rules/*.mdc` in the **same** change |
| Ship invariant (landings, no mixed list) | `scripts/check-packages.py` plus the skill/rule |
| Retrieval for other repos | `wwn-mcp/knowledge/wawona/` then reindex |
| Org-wide one-liner | this `AGENTS.md` |

Do **not** paste a whole existing rule into a new skill. Pointer + delta.

## Same-change checklist

```text
- [ ] Skill updated or added (`.cursor/skills/` + `docs/agent-skills/`)
- [ ] `repo-wawona-io-priors` gained a row if the skill/rule name is new
- [ ] Hard gate: matching `.cursor/rules/*.mdc`
- [ ] Gate script if humans/machines can regress it
- [ ] `wwn-mcp/knowledge/wawona/` if other repos must see it
- [ ] `wwn-mcp index --only wwn-knowledge-wawona` (or `--local-siblings`)
- [ ] No em dash. Code/commits stay normal English.
```

Copy the new skill into `~/Wawona/.cursor/skills/<name>/SKILL.md` so workspace
agents see it when this folder is not the Cursor root.

## Not improve

- Leave the fact in chat only
- Re-ship a mixed wasm+deb results list
- Redirect `/wasm/v1/` or `/Packages`
- Teach store `wpm` to fetch `/jailbreak/`, `/Packages`, or `.deb`
- Treat `repo.wawona.io` as the `wawona.io` website
