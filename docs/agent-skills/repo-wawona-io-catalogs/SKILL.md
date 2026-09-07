---
name: repo-wawona-io-catalogs
description: Dual catalog host for repo.wawona.io. Use when editing /search/, wasm/v1, Packages, jailbreak landing, OpenSearch, wpm registry, Sileo/Termux debs, wawona.io Search packages CTAs, or check-packages.py. Two lanes. Never one results list.
---

# Dual catalogs

One host. Two catalogs. Never one results list. Hard gate:
`.cursor/rules/repo-wawona-io-channels.mdc`. RAG:
`wwn-mcp/knowledge/wawona/repo-wawona-io-catalogs.md`.

| Lane | Humans | Machines | Who |
|------|--------|----------|-----|
| Mode A wasm | `/search/?channel=wasm` | `/wasm/v1/index.json` (`wpm`) | App Store / Play / macOS |
| Mode B debs | `/search/?channel=deb` | APT at `https://repo.wawona.io/` (`Packages`) | Sileo / Termux |

`/search/` is a chooser, not a mixed All channel. `/wasm/`, `/deb/`, and
`/jailbreak/` are HTML landings onto `/search/?channel=…`.

## Firewall

| Consumer | `/wasm/v1` | APT `/` (`Packages`) |
|----------|------------|----------------------|
| store `wpm` | Yes | **Never** |
| Sileo / Termux | Optional | Yes |

Store `wpm` default registry: `https://repo.wawona.io/wasm/v1` (client fetches
`/index.json`). Never fetch `/jailbreak/`, `/Packages`, or `.deb`.

## Never

- Concatenate wasm + deb into one search list (`[...wasmPkgs, ...debPkgs]`)
- Redirect `/wasm/v1/` or `/Packages`
- Add `wasm/v1/index.html` (GitHub Pages would shadow `index.json`)
- Treat `/jailbreak/` as APT. APT is repo root. `/jailbreak/` is a bookmark.
- Claim this host is jailbreak-only. `/wasm/v1` is the store-safe exception.
- Route `where_to_edit("repo.wawona.io …")` to the `wawona.io` website.
  Match `repo.wawona.io` **before** `wawona.io`. If Cursor still lands on the
  website, restart the wwn-mcp server. Do not edit wawona.io for catalog code.
- Mention retired `wwn-apt` in `setup.sh`
- Drop `hello-wasi` from `wasm/v1/index.json`
- Mix handwritten display names into package metadata (GitHub maintainers)

## Humans

- Deb catalog: architecture + section filters. Permalink copy on cards.
- OpenSearch: `search/opensearch.xml` (chooser), `opensearch-wasm.xml`,
  `opensearch-deb.xml`
- `404.html` links both lanes (unknown paths looked like downtime)
- wawona.io Explore **Search packages**: primary wasm CTA, secondary Sileo /
  Termux debs. Site repo is `wawona.io`, not this one.
- GitHub about: dual-catalog. Homepage `https://repo.wawona.io/search/`

## Prove

```bash
python3 scripts/check-packages.py --offline --root .
```

CI (network): `python3 scripts/check-packages.py`. Maintainers:
`repo-wawona-io-maintainers`.

## Out of scope unless asked

Mode B IPA auto-publish to Sileo. In-app Packages GUI. OCI `/wasm/v2`.
