---
name: wasm-packages-gha
description: Build store WASI P1 packages inside repo.wawona.io catalog/wasm (abi wasi-p1). Use for allowlist and recipes. WASIX is the same catalog with abi wasix. The old Wawona/wasm-packages repo is deleted.
---

# wasm-packages GHA builds (store WASI P1)

Production path: **GitHub Actions** on `ubuntu-24.04`. Not a laptop.

Sources live in `repo.wawona.io` `catalog/wasm/src/p1`. WASIX is
`catalog/wasm/src/wasinix` with card `abi = wasix`. `Wawona/wasm-packages`
is deleted. Do not `gh workflow run` against it. Decision table:
skill/rule `wawona-wasm-cli-ports`.

| Piece | Path |
|-------|------|
| Allowlist | `catalog/wasm/src/p1/allowlist.toml` |
| Recipes | `catalog/wasm/src/p1/packages/<name>/` |
| Card | `catalog/wasm/<kind>/<name>/default.nix` |
| Smoke | **Wasmtime** `catalog/wasm/src/p1/scripts/smoke-package.sh` |
| Catalog | `repo.wawona.io` `/wasm/v1` on **development** |

WASIX packages are tested with **Wasmer** from `catalog/wasm/src/wasinix`.

Ports need real upstream trees, `upstream_version`, and `homepage` (upstream
URL). Stubs named `jq`/`grep`/`sed` stay **blocked**.

```bash
python3 catalog/wasm/src/p1/scripts/sync-recipes-from-allowlist.py
nix eval .#catalogIndex.hello-wasi.abi
```

Nightly selects packages missing/stale vs live `index.json`, capped by
`meta.max_new_per_nightly`. Green build auto-pushes catalog as `wawona-wasm-bot`
unless `open_pr=true`.

ABI / phase order: `repo.wawona.io/docs/wasm-abi.md`.
Org catalogs skill: `repo-wawona-io-catalogs`.

## Never

- Publish laptop-built `.wasm` as production
- Revive `nixpkgs2wasi` / auto-mirror nixpkgs
- Claim WASIX runs on store Pulley (WASIX = wasinix lane)
- Put WASIX build recipes only in this repo (use `wasinix`)
- Put build recipes only in `repo.wawona.io` (catalog host stays thin)
- Ship empty stubs for `blocked` allowlist rows
- Forge upstream names at invented `0.1.0`

Never package names in `scripts/native-all-targets.txt` (native uutils on all targets).
