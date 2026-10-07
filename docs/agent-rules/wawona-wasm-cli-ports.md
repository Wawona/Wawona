---
description: Two-lane law for porting CLIs to WASI P1/P2 vs WASIX (no nixpkgs scrape, no stubs)
alwaysApply: true
---

# Wasm CLI ports (two lanes)

Authority: `repo.wawona.io/docs/wasm-abi.md`, `wasinix/docs/wawona-publish.md`,
`wasm-packages/docs/package-versioning.md`, `repo-wawona-io-ports`,
`wawona-native-over-wasm`. Skill: `wawona-wasm-cli-ports`.

There is **no** auto-mirror of nixpkgs into `/wasm/v1`. `nixpkgs2wasi` / `n2w`
are retired. Do not revive them. Do not ship a 30-line toy under `sed` / `jq` /
`grep` and call it a port.

## Pick the lane by syscalls

| Need | ABI | Repo | Catalog today |
|------|-----|------|---------------|
| stdio + basic files only | **WASI P1** `wasm32-wasip1` | `Wawona/wasm-packages` (GHA) | `/wasm/v1` for store `wpm` / Pulley |
| Component Model | **WASI P2** | wrap P1 with `wasm-tools component new` when needed | same store path when ready |
| fork, threads, sockets, TTY, real POSIX | **WASIX** `wasm32-wasix` | `Wawona/wasinix` (Nix + wasixcc) | Wasmer/WebC → `repo.wawona.io/wasm`; **not** store Pulley |

Label from what the binary **uses**. Never mark WASIX as store `wasi-p1`.

## Native-first

If the name is in `wasm-packages/scripts/native-all-targets.txt` (uutils on
every product target), do **not** wasm-package it.

## Lane A: store WASI P1 (`wasm-packages`)

1. Curate `allowlist.toml`: `origin = port`, real `upstream_version`, real
   `homepage` (upstream project URL), `source` = recipe tree.
2. Recipe under `packages/<name>/` builds the **real upstream** (or a known
   WASI-capable port of that project). Not a stub with a forged name.
3. `sync-recipes-from-allowlist.py` → GHA `build-wasm.yml` (Wasmtime smoke) →
   `publish-to-repo.yml` → `repo.wawona.io` `/wasm/v1`.
4. Laptop `cargo` is debug only.

## Lane B: nixpkgs → WASIX (`wasinix`)

This is the right “cross-compile from nixpkgs” path.

1. `pkgs/programs/<name>/<name>.nix`: start from the nixpkgs derivation
   (`override` / `callPackage`), cross with wasixcc + WASIX sysroot.
2. Patches next to the recipe. Install `*.wasm` in `$out/bin`.
3. `makeWasmerPackage` → WebC / `wasmer.toml` (`owner = "wawona"`).
4. Catalog identity: upstream **name**, upstream **version**, `homepage` =
   upstream project, `source` = wasinix recipe / commit.
5. Do not dump WASIX into Mode A `/wasm/v1` P1 rows. Product gate before
   claiming WASIX runs outside Wasmer-capable paths (`wawona-relay-wasm`).

```bash
nix build .#wasix.grep
nix build .#wasmer.grep
```

## Catalog metadata (both lanes)

- Field **`homepage`** (nixpkgs-style). Never rename to `website`.
- Never blanket `wawona.io/docs/wasm/` for every row.
- Port `version` = upstream release. Never invent `0.1.0` for “just ported”.
- `source` = port / packaging tree.

## Hard rejects

- Revive `nixpkgs2wasi` / `n2w` / auto-mirror nixpkgs
- Stub CLI under an upstream name at fake `0.1.0`
- WASIX labeled or shipped as store Pulley P1
- Laptop-built blobs as production catalog source
- Wasm twin of a native-all-targets CLI
- Routing “nixpkgs → wasi” edits to a dead converter repo

## Where to edit

| Change | Repo |
|--------|------|
| Store P1 allowlist / GHA recipe | `wasm-packages` |
| Nixpkgs override → WASIX / WebC | `wasinix` |
| Live `/wasm/v1` index / search UI | `repo.wawona.io` |
| Execute engine (Pulley / Wasmer) | `Relay` / Wawona product rules |
