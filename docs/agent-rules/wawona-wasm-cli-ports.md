# Wasm CLI ports (two lanes)

Authority: `repo.wawona.io/docs/wasm-abi.md`,
`repo.wawona.io/catalog/wasm/src/p1/docs/package-versioning.md`,
`repo-wawona-io-ports`, `wawona-native-over-wasm`. Skill: `wawona-wasm-cli-ports`.

There is **no** auto-mirror of nixpkgs into `/wasm/v1`. `nixpkgs2wasi` / `n2w`
are retired. Do not revive them. Do not ship a 30-line toy under `sed` / `jq` /
`grep` and call it a port.

## Pick the lane by syscalls

| Need | ABI | Where | Catalog today |
|------|-----|------|---------------|
| stdio + basic files only | **WASI P1** `wasm32-wasip1` | `repo.wawona.io` `catalog/wasm/cli` `abi = wasi-p1` | `/wasm/v1` for store `wpm` / Pulley |
| Component Model | **WASI P2** | wrap P1 with `wasm-tools component new` when needed | same store path when ready |
| fork, threads, sockets, TTY, real POSIX | **WASIX** `wasm32-wasix` | `repo.wawona.io` `catalog/wasm/{cli,gui,lib}` `abi = wasix` | Wasmer smoke; **not** a store P1 row |

Label from what the binary **uses**. Never mark WASIX as store `wasi-p1`.

## Native-first

If the name is in `catalog/wasm/src/p1/scripts/native-all-targets.txt` (uutils on
every product target), do **not** wasm-package it.

`Wawona/wasm-packages` and `Wawona/wasinix` are deleted. Do not recreate them.
Upstream `xtyxtyx/wasinix` stays. Cards are `catalog/wasm/<kind>/<name>/default.nix`.
`abi` is a field, not a directory. Implementation trees stay under
`catalog/wasm/src/p1` and `catalog/wasm/src/wasinix`. Flake output `legacyWasix`
is the WASIX package function. Do not name a recipe directory `packages/`.

## Lane A: store WASI P1 (`abi = wasi-p1`)

1. Curate `catalog/wasm/src/p1/allowlist.toml`: `origin = port`, real
   `upstream_version`, real `homepage` (upstream project URL), `source` = recipe tree.
2. Recipe under `catalog/wasm/src/p1/packages/<name>/` builds the **real upstream**
   (or a known WASI-capable port of that project). Not a stub with a forged name.
3. Card: `catalog/wasm/cli/<name>/default.nix` (or `gui` / `lib` when that is the kind).
4. `sync-recipes-from-allowlist.py` then Wasmtime smoke. Publish path stays `/wasm/v1`.
5. Laptop `cargo` is debug only.

## Lane B: WASIX (`abi = wasix`)

This is the nixpkgs-override path. Kind is the card directory, not a fourth channel.

| Kind | Card | Implementation |
|------|------|----------------|
| **cli** | `catalog/wasm/cli/<name>/` | `catalog/wasm/src/wasinix/pkgs/programs/` |
| **gui** | `catalog/wasm/gui/<name>/` | same programs tree when it draws (gtk4-hello) |
| **lib** | `catalog/wasm/lib/<name>/` | `catalog/wasm/src/wasinix/pkgs/libraries/` |

GTK4 is `catalog/wasm/lib/gtk4`. Never a program named gtk4. A GTK demo is `gui`.

1. Programs: `pkgs/programs/<name>/<name>.nix` from nixpkgs override + wasixcc.
   Libraries: `pkgs/libraries/` (`gtk.nix`).
2. Patches next to the recipe. Programs install `*.wasm` in `$out/bin`.
3. `makeWasmerPackage` → WebC / `wasmer.toml` (`owner = "wawona"`) for programs.
4. Catalog identity: upstream **name**, upstream **version**, `homepage` =
   upstream project, `source` = the catalog recipe path.
5. Do not dump WASIX into Mode A `/wasm/v1` P1 rows. Product gate before
   claiming WASIX runs outside Wasmer-capable paths (`wawona-relay-wasm`).

```bash
# repo.wawona.io, after calling legacyWasix { system, nixpkgs }
# cards: nix eval .#catalogIndex.grep.abi
```

## Catalog metadata (both lanes)

- Field **`homepage`** (nixpkgs-style). Never rename to `website`.
- Never blanket `wawona.io/docs/wasm/` for every row.
- Port `version` = upstream release. Never invent `0.1.0` for “just ported”.
- `source` = port / packaging tree.

## Runtime tests (hard)

| ABI | Smoke runtime | Script |
|-----|---------------|--------|
| WASI P1 / P2 | Wasmtime | `catalog/wasm/src/p1/scripts/smoke-package.sh` |
| WASIX | Wasmer | `catalog/wasm/src/wasinix/smokes.toml` |

Every active package must produce a pass/fail result. Do not claim green without
a Wasmtime (P1/P2) or Wasmer (WASIX) smoke. Do not smoke WASIX with Wasmtime.

## Hard rejects

- Revive `nixpkgs2wasi` / `n2w` / auto-mirror nixpkgs. GitHub #172-#177 closed wontfix. A live `Wawona/nixpkgs2wasi` clone is not a flake input and not the producer. Foot-on-iPhone stays on #143 via `catalog/wasm`
- Stub CLI under an upstream name at fake `0.1.0`
- Toolkit/framework (GTK, Qt, cairo, GLib) under `pkgs/programs/`
- WASIX labeled or shipped as store Pulley P1
- Laptop-built blobs as production catalog source
- Wasm twin of a native-all-targets CLI
- Routing “nixpkgs → wasi” edits to a dead converter repo
- Publishing without a runtime smoke for that ABI
- Using Wasmtime as the WASIX gate (or Wasmer as the store P1/P2 gate)

## Where to edit

| Change | Where |
|--------|------|
| Store P1 allowlist / recipe | `repo.wawona.io` `catalog/wasm/src/p1` |
| Nixpkgs override → WASIX / WebC | `repo.wawona.io` `catalog/wasm/src/wasinix` |
| Card (`abi`, kind) | `catalog/wasm/<kind>/<name>/default.nix` |
| Live `/wasm/v1` index / search UI | `repo.wawona.io` `wasm/v1` |
| Execute engine (Pulley / Wasmer) | `Relay` / Wawona product rules |
