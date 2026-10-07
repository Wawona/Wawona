---
name: repo-wawona-io-catalogs
description: Dual catalog host for repo.wawona.io. Use when editing /search/, wasm/v1, Packages, jailbreak or Termux landings, OpenSearch, wpm, Sileo iOS debs, Termux Android debs, wawona.io Search packages CTAs, or check-packages.py. Wasm is store-only. Termux is not jailbreak.
---

# Dual catalogs, three audiences

One host. Two catalogs. Never one results list. Hard gate:
`.cursor/rules/repo-wawona-io-channels.mdc`. RAG:
`wwn-mcp/knowledge/wawona/repo-wawona-io-catalogs.md`.

| Catalog | Humans | Machines | Who |
|---------|--------|----------|-----|
| wasm | `/search/?channel=wasm` | `/wasm/v1/index.json` (`wpm`) | **App Store / Play only** (store compliance). macOS `wpm` too. |
| debs | `/search/?channel=deb` | APT at `https://repo.wawona.io/` (`Packages`) | Two APT audiences. Never mix with wasm. |

Deb APT is one `Packages` file. Split by Architecture. **Never** call Termux
jailbreak.

| Deb audience | Client | Architecture | Jailbreak? | Store/Play? |
|--------------|--------|--------------|------------|-------------|
| Jailbroken iOS / iPadOS | Sileo, then Irisin, then Zebra, then Cydia | `iphoneos-arm64` rootless, `iphoneos-arm` rootful (Sileo, Zebra, Cydia), `iphoneos-arm64e` RootHide. Irisin is iOS 16+ rootless and roothide. Cydia is last, for older jailbreaks such as iOS 13. | Yes | No |
| Sideloaded Android | Termux `apt` | `aarch64` (and `arm`) | **No** | **No** |

`/search/` is a chooser, not a mixed All channel. HTML landings:

- `/wasm/` → wasm catalog
- `/deb/` → deb catalog (both APT audiences)
- `/jailbreak/` → iOS bookmark. Order: Sileo, Irisin, Zebra, Cydia. Not Termux. Not APT root.
- `/termux/` → Termux Android sideload bookmark. Not jailbreak. Not Play.

## Firewall

| Consumer | `/wasm/v1` | APT `/` (`Packages`) |
|----------|------------|----------------------|
| App Store / Play `wpm` | Yes | **Never** |
| Sileo, Irisin, Zebra, or Cydia (jailbroken iOS) | Optional | Yes |
| Termux (sideloaded Android) | Optional | Yes |

Store `wpm` default registry: `https://repo.wawona.io/wasm/v1` (client fetches
`/index.json`). Never fetch `/jailbreak/`, `/termux/`, `/Packages`, or `.deb`.

This host publishes `/wasm/v1` today. Do not auto-mirror nixpkgs here.
ABI labels and later Wasmer/WebC (wasinix): `docs/wasm-abi.md`.

## Wasm package builds (GHA)

Production builds: **`Wawona/wasm-packages`** on `ubuntu-24.04` (not a laptop).

| Piece | Where |
|-------|--------|
| Recipes | `wasm-packages` `recipes.json` + `packages/<name>/` |
| Build CI | `build-wasm.yml` (matrix + wasmtime smoke + artifacts) |
| Publish CI | `publish-to-repo.yml` (needs `WAWONA_REPO_TOKEN`; PRs into this repo) |
| Catalog | this repo `wasm/v1/` |

```bash
gh workflow run build-wasm.yml --repo Wawona/wasm-packages
# after green: publish workflow or stage via scripts/stage-for-repo.py
```

Proven: `hello-wasi` 0.1.2 and `wasi-true` 0.1.0. Local `cargo` is debug only.
Do not claim WASIX/WebC shipping. Do not revive `nixpkgs2wasi` / `n2w`.

## Never

- Concatenate wasm + deb into one search list
- Redirect `/wasm/v1/` or `/Packages`
- Add `wasm/v1/index.html` (would shadow `index.json`)
- Treat `/jailbreak/` as APT or as Termux
- Call Termux debs jailbreak, or lump "Sileo / Termux" as one jailbreak product
- Put `.deb` install paths in App Store / Play binaries (wasm only for stores)
- Claim this host is jailbreak-only. `/wasm/v1` is the store-safe exception.
- Claim WASIX / WebC / wasinix packages are shipping before `docs/wasm-abi.md`
  phase work lands
- Publish laptop-built `.wasm` as the production catalog source
- Revive `nixpkgs2wasi` / `n2w` as the wasm producer
- Route `where_to_edit("repo.wawona.io …")` to the `wawona.io` website
- Route wasm **build** recipes to this repo (builds live in `Wawona/wasm-packages`)
- Mention retired `wwn-apt` in `setup.sh`
- Drop `hello-wasi` from `wasm/v1/index.json`

## Humans

- Deb filters: architecture (labeled rootless / rootful / Termux) and section
- OpenSearch: chooser, wasm lane, deb lane
- wawona.io Explore: primary wasm (stores). Separate Sileo vs Termux debs.
  Termux copy must say sideloaded Android, not jailbreak. Site repo is `wawona.io`.

## Prove

```bash
python3 scripts/check-packages.py --offline --root .
```

## Out of scope unless asked

Mode B IPA auto-publish to Sileo. In-app Packages GUI. OCI `/wasm/v2`.

## Procursus launchctl (Mode B APT)

Procursus did **not** port `launchd`. Apple's daemon still owns LaunchAgents
and LaunchDaemons plists. `ProcursusTeam/launchctl` `v1.2.0` is an XPC client
(`bootstrap` / `bootout` / `load` / `unload` / `list` / `kickstart`).

Recipe: `pkgs/systems/launchctl`. Flake: `nix build .#launchctl` (rootless
`iphoneos-arm64`) and `.#launchctl-rootful` (`iphoneos-arm`). Package id
`wawona-launch-tools` Provides/Conflicts/Replaces `launchctl`.

Build on **host Darwin stdenv + Xcode `xcrun` iphoneos**, not the iOS-cross
stdenv (that rebuilds a Darwin bootstrap for a clang you replace). Unset
nixpkgs `DEVELOPER_DIR` before `xcrun`. Sign with `ldid-procursus` (AGPL
nativeBuildInput, never linked into the App Store app). Never ship this
binary in Mode A / TestFlight IPA. `dpkg-deb -b` must not nest `$out/deb`
inside `data.tar`.

vphone lab writes this source for you:
`/var/jb/etc/apt/sources.list.d/wawona.list` plus the Irisin add URL.
Do not HID-type `https://repo.wawona.io/` into Irisin Search.

## Third-party wasm submissions

- A generated upstream `index.json` may be a single-package fragment. Merge
  its rows into the existing `packages` array; preserve the current catalog.
- Match the shipped blob's SHA-256 against the submitted `digest`. Pin the
  source URL to the commit used to build it, and include dependency licenses.
- `wasi: p1` packages can use the conventional filename `component.wasm`
  while remaining core modules. Do not relabel them as WASI P2 components.
- Host ABI tests on Linux are not Apple/Android Wawona device validation.
