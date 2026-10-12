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
| `repo-wawona-io-catalogs` | Search UI, indexes, landings, `wpm`, APT, firewall, GHA wasm builds |
| `wawona-wasm-cli-ports` | Port a CLI to WASI P1 vs WASIX (wasm-packages vs wasinix) |
| `repo-wawona-io-learn` | Durable finding this session |

Org skills still apply: `wawona-rag`, `wawona-write`, `wawona-learn`,
`wawona-caveman`. Product map: `wawona-product-map`.

## Rules (hard gates)

| Rule | When |
|------|------|
| `repo-wawona-io-agent-learn` | Always. Read skills. Write new learnings back. |
| `repo-wawona-io-channels` | Two catalogs. Never one list. |
| `repo-wawona-io-maintainers` | GitHub-queryable maintainers on every package |
| `repo-wawona-io-ports` | Port names = upstream; versions = upstream; homepage + source |
| `wawona-wasm-cli-ports` | Two lanes inside `catalog/wasm`. `abi` is a field. No nixpkgs scrape. |
| `wawona-product-map` | Wasm Runtime vs Sileo vs Termux. Do not conflate. |
| `wawona-no-em-dash` | Copy |

Wasm ABI / later Wasmer WebC: `docs/wasm-abi.md`.
P1 sources: `catalog/wasm/src/p1`. WASIX sources: `catalog/wasm/src/wasinix`. Do not recreate those old repos.
Do not revive `nixpkgs2wasi`. Do not publish laptop blobs.

## Hard-won (do not re-learn)

- Do not rank iOS APT clients in `/search/` copy (no "Sileo, then Irisin…"). They are interchangeable package managers.
- Ports use the upstream software version and `homepage` (nixpkgs-style), not a fake `0.1.0` or a blanket `wawona.io/docs/wasm/` link. Never brand names with `wawona-` / `wwn-`. Stubs are not ports.
See `repo-wawona-io-catalogs` and `repo-wawona-io-ports`. Canonical RAG:
`wwn-mcp/knowledge/wawona/repo-wawona-io-catalogs.md`,
`wawona-ports.md`, and `wasm-abi-registry.md`.


Procursus launchctl: XPC client to host launchd, not a second launchd.
`nix build .#launchctl` uses host stdenv + xcrun, never ios-cross stdenv.
