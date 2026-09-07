# Agent learn loop (org-wide)

Wawona knowledge lives in **wwn-mcp RAG**, Cursor **skills**, and Cursor **rules**.
Do not re-derive product facts from model priors. Software changes must improve
on documented prior knowledge.

Cursor rule: `wawona-agent-learn` (`alwaysApply: true`).
Skills: `.cursor/skills/wawona-*` (tracked mirrors under `docs/agent-skills/`).

## Before any software change

1. Query **wwn-mcp** first. `where_to_edit`, `get_capability`, then
   `search_docs` / `search_code` / `get_architecture` / `get_patch`. Trust
   citations over training data. See skill `wawona-rag`.
2. Read the matching skill under `.cursor/skills/wawona-*`. Index:
   `wawona-priors`. Write loop: `wawona-write`. If the task is
   `repo.wawona.io` / wasm catalog / Sileo APT / `/search/?channel`, also
   read `repo.wawona.io/.cursor/skills/repo-wawona-io-priors/SKILL.md`.
3. If the skill points at a Cursor rule, obey that rule. Do not copy a whole
   rule into a skill (pointer + delta only).
4. The change must **improve on** a documented prior (gate, incident, recipe,
   rejected path). If RAG or a rule already forbids the approach, stop.

## After a durable finding

New incident, hard reject, recipe, gate flip, or "never do X":

1. Update or add a skill (`docs/agent-skills/` and both `.cursor/skills/` trees).
2. If it is a hard gate: update workspace `.cursor/rules/`,
   `Wawona/.cursor/rules/`, and this `docs/agent-rules/` folder in the **same**
   change. Update `AGENTS.md` when the fact is org-wide.
3. Patch `wwn-mcp/knowledge/wawona/`, then reindex
   (`wwn-mcp index --only wwn-knowledge-wawona` or `--local-siblings`).
4. Do not leave the learning only in chat. Skill `wawona-learn`.

## Token voice

Skill `wawona-caveman`. User chat: **lite** (full sentences, no filler).
Agent notes: **full**. Code, commits, PRs: normal English. Never em dash
(`wawona-no-em-dash`).

## Integrate (do not replace)

This loop sits on top of `wawona-context`, `wawona-mission`, `wawona-product-map`,
`wawona-repo-dag`, and the rest of `.cursor/rules/`. RAG first still applies
even when a rule is already in context.
