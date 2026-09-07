---
name: repo-wawona-io-priors
description: Index of repo.wawona.io Cursor skills and rules. Use at every task start in this repo, and whenever the work mentions wasm catalog, Sileo iOS debs, Termux Android debs, /search/, /wasm/v1, Packages, jailbreak landing, or store-only wasm. Pointers only. Do not duplicate rule bodies.
---

# Priors index (this repo)

Read the named skill or rule. Do not copy the body here. After adding a skill
or rule, add one row. Capture flow: `repo-wawona-io-learn`.

Tracked copies: `.cursor/skills/` and `docs/agent-skills/`. Rule:
`repo-wawona-io-agent-learn`.

## Skills

| Skill | When |
|-------|------|
| `repo-wawona-io-priors` | Task start. Pick the row. |
| `repo-wawona-io-catalogs` | Search UI, indexes, landings, `wpm`, APT, firewall |
| `repo-wawona-io-learn` | Durable finding this session |

Org skills still apply: `wawona-rag`, `wawona-write`, `wawona-learn`,
`wawona-caveman`. Product map: `wawona-product-map`.

## Rules (hard gates)

| Rule | When |
|------|------|
| `repo-wawona-io-agent-learn` | Always. Read skills. Write new learnings back. |
| `repo-wawona-io-channels` | Two catalogs. Never one list. |
| `repo-wawona-io-maintainers` | GitHub-queryable maintainers on every package |
| `wawona-product-map` | Wasm Runtime vs Sileo vs Termux. Do not conflate. |
| `wawona-no-em-dash` | Copy |

## Hard-won (do not re-learn)

See `repo-wawona-io-catalogs`. Canonical RAG:
`wwn-mcp/knowledge/wawona/repo-wawona-io-catalogs.md`.
