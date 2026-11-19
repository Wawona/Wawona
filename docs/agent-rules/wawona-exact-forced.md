# Exact is forced for product chrome

Wawona is **pure Rust** for product policy (compositor, Machines/Settings
schema, prefs, launch, wasm, VMs) **and** forced to use Wawona's fork of
Expo Exact UI for Machines / Global Settings chrome.

## Shape

| Layer | Owner |
|---|---|
| Policy / schema / validate / store | Rust `src/domain` + UniFFI |
| Chrome structure | Exact `apps/wawona/app.contract` |
| Native paint | Exact hosts (AppKit / UIKit / Canvas / Fluent / web / …) |
| Present / compositor poll | `WWNCore*` C + thin Swift/JNI glue |

## Hard rejects

- Product Machines/Settings chrome in iced, egui, gpui, or a second hand
  SwiftUI / Compose tree that is not an Exact host
- "Pure Rust UI" that bypasses Exact for ALL_TARGETS chrome
- Reviving `Wawona.xcodeproj` / root Gradle as the product chrome authoring
  surface
- Treating Exact dual-run quarantine SwiftUI/Compose as a permanent parallel
  product UI

## Allowed

- Exact host Swift/Kotlin/C++ as **paint** only (bars, type, Present
  NativeView)
- Quarantine `Sources/WawonaUI` / Compose until matrix green, then delete
  chrome (dual-run M8)
- Present / Metal / CarPlay / WWNCore glue outside Exact Contract chrome

## Agent tooling (Exact, not Expo RN)

There is **no** official Exact MCP server or Exact skill on Expo's public
Expo Skills / Expo MCP (those target Expo Router, EAS, RN Simulator). Exact
agents use the **checkout**:

1. Sibling Exact `AGENTS.md` + `docs/start-here.md` (LLP 1115)
2. CLI: `bun scripts/exact.mjs` / `bun exact.mjs` (`contract build --json
   --errors-only`, feedback, …) and `scripts/agent.mjs` for host tests
3. Wawona wrappers: `cargo xtask run|agent …`, skill `wawona-exact-contract`,
   Exact `llp-orient` when changing Contract structure
4. UI craft: skill `wawona-exact-ui-design` + installed global skills
   (`frontend-design`, `impeccable`, `ui-ux-pro-max`, `better-*`,
   `web-design-guidelines`, `frontend-ui-engineering`). Hierarchy / a11y /
   polish only; never React/Tailwind/hex into Contract

### Hard reject

- Installing **Expo RN / Expo MCP skills plugins** for Exact chrome work
  (agents then emit JSX / Router patterns instead of Contract)
- Inventing a Wawona Exact MCP as a substitute for Exact's JSON compiler loop
- Pasting design-skill React/Tailwind/hex examples into `app.contract`

## Dogfood

```bash
cd Wawona
cargo app                 # alias → cargo xtask run macos
cargo xtask run ios
cd ../exact
bun scripts/exact.mjs contract build apps/wawona/app.contract --json --errors-only
```

Canonical dual-run: `wawona-exact-dual-run`. Skill: `wawona-exact-contract`.
#67 map: `exact/apps/wawona/docs/issue-67-exact-path.md`.
Cursor rule: `wawona-exact-forced`.
