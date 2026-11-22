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

1. Exact checkout **`AGENTS.md`** + `docs/start-here.md` (official Exact agent
   loop: CLI + compiler JSON, not Expo RN MCP).
2. Exact skill `llp-orient` when touching Contract structure.
3. **`wawona-exact-ui-design`** then global `frontend-design` /
   `impeccable` / `better-*` / `web-design-guidelines` (visual craft only;
   Contract syntax + no-tells still win).
4. This skill + `apps/shelf/app.contract` as the chrome oracle.
5. `platforms.json` / `ALL_TARGETS` when the task spans hosts.
6. Query `wwn-mcp` for Wawona product gates (`wawona-platform-targets`).

**Do not** install Expo Router / EAS / Expo MCP skills for this work. They
target React Native, not Contract. Fix with
`bun scripts/exact.mjs contract build … --json --errors-only` and
`scripts/agent.mjs` (or `cargo xtask agent`).

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

- **Forced Exact.** Product Machines/Settings chrome is Exact only (pure Rust
  policy + Exact paint). Hard reject iced/egui/gpui or a second hand
  SwiftUI/Compose Machines tree. Rule: `wawona-exact-forced`.
- **Author writes structure** (header, list, tablist, routes, grouped-form).
- **Leave look unsaid:** no hex chrome, no `font-size` / `font-weight` (use
  `-exact-*` roles / text styles). Gate: `bun scripts/no-tells.mjs apps/wawona`.
- **Portable symbols:** `symbol:package`, `symbol:layers`, … Never `symbol:sf/`
  for ALL_TARGETS chrome (blank on non-Apple).
- **Five layers.** Contract = what. Adapter = how. Guidelines = feel.
  Bend = never break. Computer-use critic = verify. Platforms may look
  different. Shared semantics stay.
- **One catalog: machines.** Settings is a cover (`openSettings` / gear).
  No Machines|Settings tab pair. Keep one hidden root tablist
  (`display="none"`) so Mac can promote the wide list into `.sourceList`;
  without it `appearance="none"` smashes rows. Wide: `appearance="none"` +
  `navigationSplit`. Compact: inset-grouped. Literal `appearance` only.
- **Titles.** Each route has one `head title` (never a raw id). Only the
  top header is visible.
- **Wayland surface.** Session route only. Open in Tab or Window
  (`sessionChrome`). xdg-decoration CSD/SSD. One emphasized header action.
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
```

**macOS Exact UI (hard, Rust-driven):**

```bash
cargo app                 # from Wawona/; alias → xtask run macos
cargo xtask run macos
cargo xtask run ios
cargo xtask agent grade macos --rebuild
cargo xtask agent drive macos -- tree state check "tap toolbar-settings"
```

Never computer-use for Exact chrome. Rule: `wawona-exact-macos-run`.
Report a host matrix. `implemented` ≠ `verified`.

## Related

- Exact skills: `llp-orient`, Exact `AGENTS.md`, `docs/start-here.md`
- Design gate: `wawona-exact-ui-design` (+ `frontend-design`, `impeccable`, …)
- Rules: `wawona-exact-forced`, `wawona-exact-macos-run`, `wawona-all-targets`,
  `wawona-platform-targets`, `wawona-global-settings-exclusive`,
  `wawona-exact-dual-run`, `wawona-rust-first`
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
