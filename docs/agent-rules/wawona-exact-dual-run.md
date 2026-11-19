# Exact dual-run chrome (M1-M8)

Authority: Exact `docs/wawona-exact-chrome.md` (sibling Exact checkout) and
`platforms.json`.

## Split

| Layer | Owns |
|---|---|
| Exact `apps/wawona/app.contract` | Machines + Global Settings chrome |
| Exact hosts | Native bars, type, Present NativeView (`wayland-present`) |
| Rust UniFFI / `wawona-data` | Schema, prefs, launch validate |
| Product `Sources/WawonaUI` / Compose | Quarantined after Exact product ship; Present glue may still compile into Exact module |

## Milestone map

| Milestone | Goal | Status |
|---|---|---|
| M0 | Charter + Contract scaffold | done |
| M1 | Machines + Settings Contract chrome | done |
| M2 | Present native view hatch | done (`wayland-present` Exact NativeView) |
| M3 | `wawona-data` prefs + profiles seam | planned |
| M4 | Exact hosts: web + Windows | web green; Windows compile-checked |
| M5 | tvOS / watchOS Exact chrome | planned |
| M6 | Android Exact Canvas package wire | Exact AAB via `cargo xtask archive android` |
| M7 | AsteroidOS / WearOS hosts | Asteroid available; Wear blocked |
| M8 | Delete product SwiftUI / Compose chrome; no Xcode/Gradle product | **complete** for product ship surface: `Wawona.xcodeproj` + root Gradle gone; Exact IPA/AAB is the ship path. Quarantine leftover SwiftUI/Compose chrome per host after matrix green. Exact is **forced**, not an optional forever dual. End state: Exact-only chrome (`wawona-exact-forced`) |

## Hard rules

- One Contract file. `bun scripts/no-tells.mjs apps/wawona` clean.
- Portable `symbol:` roles only across `ALL_TARGETS`.
- Product forbidden rows still from `wawona-platform-targets`.
- Do not revive `Wawona.xcodeproj` or root Gradle as the product authoring surface.
- Do not replace Exact with iced/egui/gpui or a second hand SwiftUI/Compose
  Machines UI. Pure Rust policy + forced Exact paint (`wawona-exact-forced`).

## Verify

```bash
cd <exact>
bun scripts/exact.mjs contract build apps/wawona/app.contract --json --errors-only
bun scripts/no-tells.mjs apps/wawona
cargo xtask build macos   # from Wawona checkout
```

Skill: `wawona-exact-contract`. Rule: `wawona-all-targets`.
