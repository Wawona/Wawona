---
name: wawona-wasm-cli-ports
description: Port a CLI to WASI P1/P2 or WASIX for repo.wawona.io. Use when adding grep/sed/jq/curl/git or any nixpkgs-sourced tool to wasm. Two lanes: wasm-packages GHA (P1) vs wasinix (WASIX). Never nixpkgs2wasi stubs.
---

# Wasm CLI ports (how to build)

Hard gate: `.cursor/rules/wawona-wasm-cli-ports.mdc`. Catalog identity:
`repo-wawona-io-ports`. Native-first: `wawona-native-over-wasm`.

## Decision

1. Already in `wasm-packages/scripts/native-all-targets.txt`? **Stop.** Native wins.
2. Needs fork / threads / sockets / TTY / real POSIX? → **WASIX** (`wasinix`).
3. Fits Preview 1 stdio + files and must run on store Pulley? → **WASI P1**
   (`wasm-packages` GHA).
4. Component Model only? → P2 wrap of a P1 module when needed.

Never invent a stub named `sed` / `jq` / `grep` at `0.1.0`. Never revive
`nixpkgs2wasi` / `n2w`. Never auto-mirror nixpkgs. GitHub #172-#177 closed
wontfix. A live `Wawona/nixpkgs2wasi` checkout is not the producer.

## Lane A: store P1 (`Wawona/wasm-packages`)

```bash
# edit allowlist.toml (origin=port, upstream_version, homepage=upstream URL)
python3 scripts/sync-recipes-from-allowlist.py
gh workflow run build-wasm.yml --repo Wawona/wasm-packages
```

- Recipe: `packages/<name>/` builds the **real upstream** tree.
- Publish: GHA → `repo.wawona.io` `/wasm/v1` (bot). Laptop cargo = debug only.
- Skill detail: `wasm-packages-gha`.

## Lane B: nixpkgs → WASIX (`Wawona/wasinix`)

```bash
# pkgs/programs/foo/foo.nix : override nixpkgs pkg + wasixcc
nix build .#wasix.foo
nix build .#wasmer.foo   # WebC / wasmer.toml, owner=wawona
```

- Pattern: see `pkgs/programs/grep/grep.nix` (gnugrep.override + patches).
- Docs: `wasinix/docs/wawona-publish.md`.
- Do **not** put WASIX into Mode A `/wasm/v1` P1 rows. Wasmer-only execute
  until the same-commit product gate (`wawona-relay-wasm`).

## Catalog fields (both lanes)

| Field | Value |
|-------|--------|
| `name` | Upstream name (`grep`, `jaq`, `chess`). Never `wawona-*` brand |
| `version` | Upstream release (not invented `0.1.0`) |
| `homepage` | Upstream project URL (nixpkgs `meta.homepage`). Not `website` |
| `source` | Port / packaging tree (wasm-packages or wasinix path) |
| `origin` | `port` (or `scratch` only for true Wawona smokes) |

## Never

- Blanket `homepage` → `wawona.io/docs/wasm/`
- Claim WASIX runs on store Pulley / iOS ≤ 26 Mode A
- Publish laptop blobs as production
- Route “cross-compile nixpkgs to wasi” to a dead converter repo

## Runtime tests (required)

| ABI | Runtime under test | Where |
|-----|--------------------|-------|
| WASI P1 / P2 | **Wasmtime** | `wasm-packages` `smoke-package.sh` + `build-wasm.yml` |
| WASIX | **Wasmer** | `wasinix` `smokes.toml` + `smoke-wasix-package.sh` + CI matrix |

Each package must pass or fail explicitly (`smoke-result.json` / `out/smoke/*.json`).
Skipped rows need a reason. Empty pass set is red.

## Prove

- P1/P2: green `build-wasm.yml` (Wasmtime smoke + summary) + catalog `check-packages.py`
- WASIX: green wasinix CI matrix (build `.#wasmer.<name>` + Wasmer smoke)
