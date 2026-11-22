---
name: wawona-exact-contract
description: >
  Wawona Exact Contract UI (Machines + Settings). Use before editing
  exact/apps/wawona/app.contract or claiming Exact chrome works on ALL_TARGETS.
  Write the web, ship the platform (LLP 1115 / shelf). Mandatory with Exact
  llp-orient when changing Contract structure.
---

# Wawona Exact Contract UI

## Load first

1. Exact skill `llp-orient` (Exact checkout) when touching Contract structure.
2. This skill + `docs/start-here.md` + `apps/shelf/app.contract` as the chrome oracle.
3. `platforms.json` / `ALL_TARGETS` when the task spans hosts.
4. Query `wwn-mcp` for Wawona product gates (`wawona-platform-targets`).

## Where

| Piece | Path |
|---|---|
| Contract | sibling Exact `apps/wawona/app.contract` |
| Manifest | Exact `apps/wawona/app.json` |
| #67 close map | Exact `apps/wawona/docs/issue-67-exact-path.md` |
| Dual-run M1-M8 | Wawona `docs/agent-rules/wawona-exact-dual-run.md` |
| Charter | Exact `docs/wawona-exact-chrome.md` |
| Platform list | Wawona `platforms.json` |

## Hard rules

- **Author writes structure** (header, list, tablist, routes, grouped-form).
- **Leave look unsaid:** no hex chrome, no `font-size` / `font-weight` (use
  `-exact-*` roles / text styles). Gate: `bun scripts/no-tells.mjs apps/wawona`.
- **Portable symbols:** `symbol:package`, `symbol:layers`, … Never `symbol:sf/`
  for ALL_TARGETS chrome (blank on non-Apple).
- **Compact vs wide:** `isWide = viewport.width >= 700`. Compact =
  `appearance="auto"` inset-grouped + UITabBar. Wide = `appearance="none"` +
  `navigationSplit` for Mac sourceList promote. Literal `appearance` only
  (`lower-grouped-list` forbids ternary).
- **Settings switches:** shelf/grouped-form `text` + `input type="checkbox" switch`.
  No PrefSwitch accent strip / scale. Per-section control tint via
  `accent-color=sectionAccent` (`-exact-system-*` roles; matches
  `WawonaSettingsHubChrome`). Catalog glyphs: `image … color=-exact-system-*`
  only (never tile fill).
- **Product forbidden** (VM on watch/tv, Desktop in store IPA) still from
  `wawona-platform-targets`. Contract must not enable them.

## Verify

```bash
cd <exact>
bun scripts/exact.mjs contract build apps/wawona/app.contract --json --errors-only
bun scripts/no-tells.mjs apps/wawona
# Per host under ALL_TARGETS / EXACT_HOSTS: build + screenshot / agent drive
```

Report a host matrix. `implemented` ≠ `verified`.

## Related

- Exact skills: `llp-orient`, `llp-create`, `exact-panel`, `exact-orchestrate`
- Rules: `wawona-all-targets`, `wawona-platform-targets`,
  `wawona-global-settings-exclusive`, `wawona-exact-dual-run`
- Recipe: Exact `docs/recipes/grouped-form.md`, `tabs.md`, `symbols.md`

## ALL_TARGETS matrix (Exact UI)

Read `platforms.json`. Report every id. Typical tip (2026-11-14):

| Target | exact_ui | Notes |
|---|---|---|
| ios / ipados / macos | available | M1 agent green |
| web | available | Exact host; product web planned |
| windows | available | Exact compile-checked; product planned |
| android | available | Exact crate checks; Canvas package planned (M6) |
| asteroidos | available | Exact asteroid host; agent tree/state |
| visionos / tvos / watchos | available | tvOS agent Machines; watch embeds ExactWatch; visionOS sim build |
| wearos | available | `--wear` APK: watch feature, round safe-area, rotary |

Do not delete product chrome until M8.
