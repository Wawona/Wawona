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
| Jailbroken iOS / iPadOS | Sileo / Zebra | `iphoneos-arm64` rootless, `iphoneos-arm` rootful, optional `iphoneos-arm64e` RootHide | Yes | No |
| Sideloaded Android | Termux `apt` | `aarch64` (and `arm`) | **No** | **No** |

`/search/` is a chooser, not a mixed All channel. HTML landings:

- `/wasm/` → wasm catalog
- `/deb/` → deb catalog (both APT audiences)
- `/jailbreak/` → iOS Sileo bookmark. Not Termux. Not APT root.
- `/termux/` → Termux Android sideload bookmark. Not jailbreak. Not Play.

## Firewall

| Consumer | `/wasm/v1` | APT `/` (`Packages`) |
|----------|------------|----------------------|
| App Store / Play `wpm` | Yes | **Never** |
| Sileo (jailbroken iOS) | Optional | Yes |
| Termux (sideloaded Android) | Optional | Yes |

Store `wpm` default registry: `https://repo.wawona.io/wasm/v1` (client fetches
`/index.json`). Never fetch `/jailbreak/`, `/termux/`, `/Packages`, or `.deb`.

## Never

- Concatenate wasm + deb into one search list
- Redirect `/wasm/v1/` or `/Packages`
- Add `wasm/v1/index.html` (would shadow `index.json`)
- Treat `/jailbreak/` as APT or as Termux
- Call Termux debs jailbreak, or lump "Sileo / Termux" as one jailbreak product
- Put `.deb` install paths in App Store / Play binaries (wasm only for stores)
- Claim this host is jailbreak-only. `/wasm/v1` is the store-safe exception.
- Route `where_to_edit("repo.wawona.io …")` to the `wawona.io` website
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
