---
name: wawona-wasm-cli-ports
description: Port a CLI to WASI P1/P2 or WASIX for repo.wawona.io. Use when adding grep/sed/jq/curl/git or any nixpkgs-sourced tool to wasm. Cards live in catalog/wasm/{cli,gui,lib}. abi is wasi-p1, wasi-p2, or wasix. Never nixpkgs2wasi stubs.
---

# Wasm CLI ports (how to build)

Hard gate: `.cursor/rules/wawona-wasm-cli-ports.mdc`. Catalog identity:
`repo-wawona-io-ports`. Native-first: `wawona-native-over-wasm`.

## Decision

1. Already in `catalog/wasm/src/p1/scripts/native-all-targets.txt`? **Stop.** Native wins.
2. Needs fork / threads / sockets / TTY / real POSIX? → **WASIX** card under `catalog/wasm/`, `abi = wasix`.
3. Fits Preview 1 stdio + files and must run on store Pulley? → **WASI P1**
   card under `catalog/wasm/cli`, `abi = wasi-p1`. Publish path stays `/wasm/v1`.
4. Component Model only? → P2 wrap of a P1 module when needed.

Never invent a stub named `sed` / `jq` / `grep` at `0.1.0`. Never revive
`nixpkgs2wasi` / `n2w`. Never auto-mirror nixpkgs. GitHub #172-#177 closed
wontfix. A live `Wawona/nixpkgs2wasi` checkout is not the producer.

## Lane A: store P1 (`catalog/wasm`, `abi = wasi-p1`)

```bash
# edit catalog/wasm/src/p1/allowlist.toml
# card: catalog/wasm/cli/<name>/default.nix
python3 catalog/wasm/src/p1/scripts/sync-recipes-from-allowlist.py
```

- Recipe source: `catalog/wasm/src/p1/packages/<name>/`.
- Publish path stays `/wasm/v1`. Laptop cargo = debug only.

## Lane B: WASIX (`catalog/wasm`, `abi = wasix`)

```bash
# Card: catalog/wasm/cli/<name>/default.nix (gui or lib when that is the kind)
# Implementation: catalog/wasm/src/wasinix/pkgs/
```

- Programs: `catalog/wasm/src/wasinix/pkgs/programs/grep/grep.nix`.
- Libraries: `catalog/wasm/src/wasinix/pkgs/libraries/` (`gtk.nix` is `wasm/lib/gtk4`). Never a program named gtk4.
- Entry: `legacyWasix` on the repo.wawona.io flake. Docs sit next to that tree.
- Do **not** put WASIX into Mode A `/wasm/v1` P1 rows. Wasmer-only execute
  until the same-commit product gate (`wawona-relay-wasm`).

## Catalog fields (both lanes)

| Field | Value |
|-------|--------|
| `name` | Upstream name (`grep`, `jaq`, `chess`). Never `wawona-*` brand |
| `version` | Upstream release (not invented `0.1.0`) |
| `homepage` | Upstream project URL (nixpkgs `meta.homepage`). Not `website` |
| `source` | Port tree under `catalog/wasm/src/p1` or `catalog/wasm/src/wasinix` |
| `origin` | `port` (or `scratch` only for true Wawona smokes) |

## Never

- Blanket `homepage` → `wawona.io/docs/wasm/`
- Claim WASIX runs on store Pulley / iOS ≤ 26 Mode A
- Publish laptop blobs as production
- Route “cross-compile nixpkgs to wasi” to a dead converter repo

## Runtime tests (required)

| ABI | Runtime under test | Where |
|-----|--------------------|-------|
| WASI P1 / P2 | **Wasmtime** | `catalog/wasm/src/p1/scripts/smoke-package.sh` |
| WASIX | **Wasmer** | `catalog/wasm/src/wasinix/smokes.toml` |

Each package must pass or fail explicitly (`smoke-result.json` / `out/smoke/*.json`).
Skipped rows need a reason. Empty pass set is red.

## Prove

- P1/P2: green `build-wasm.yml` (Wasmtime smoke + summary) + catalog `check-packages.py`
- WASIX: `legacyWasix` attr plus Wasmer smoke from `catalog/wasm/src/wasinix`
