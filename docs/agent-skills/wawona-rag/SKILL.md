---
name: wawona-rag
description: Query wwn-mcp RAG before answering or coding in the Wawona org. Use when starting a task, locating a repo, checking a capability gate, reading patches/protocols, or after writing new knowledge that must be reindexed.
---

# wwn-mcp RAG (always)

Wawona stack post-dates model training. Query **wwn-mcp** before coding. Trust
citations over priors. Stdio only. No `mcp.wawona.io`.

## Required order

1. `where_to_edit` / `list_repos` (never invert L0-L4 DAG)
2. `get_capability(platform, feature)` (`available` | `planned` | `blocked` | `forbidden`)
3. `search_docs` / `get_architecture` then `search_code` / `find_symbol` / `get_patch`
4. `get_protocol` when touching Wayland surfaces

Companion: **nixos** MCP for upstream nixpkgs; **wwn-mcp** `get_patch` for Wawona recipes.

## After editing knowledge

Curated corpus: `wwn-mcp/knowledge/wawona/` (`wwn-knowledge-wawona`).

```bash
# from ~/Wawona/wwn-mcp
nix run .#wwn-mcp -- index --only wwn-knowledge-wawona
# or, with sibling checkouts:
nix run .#wwn-mcp -- index --local-siblings
```

Push `WWN-MCP` `main` when the knowledge should ship. Local index is what Cursor
sees from `~/Wawona/wwn-mcp`.

## Do not

- Skip RAG because a Cursor rule is already loaded
- Guess flake inputs, gates, or windowing paths
- Index secrets or `Disk.img` / IPSW
