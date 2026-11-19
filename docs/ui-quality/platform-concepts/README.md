# Wawona platform UI concepts (visual references)

**Not** validated product screenshots. **Not** Exact Contract. **Not** a pass
criterion for `cargo xtask agent grade`.

Source: owner pack `wawona-all-platform-ui-concepts.zip` (2026-11-18). Thirteen
generated concept PNGs at original resolution. Agents use them for **native
feel** and layout density when adapting Exact chrome per platform.

Editable FigCraft recreation (tokens + Machines frames for ALL_TARGETS):
[`figcraft/`](./figcraft/) (`Wawona-ALL_TARGETS.figcraft`). Open in FigCraft.
Build notes: `figcraft/README.md`, MCP wiring: `figcraft/MCP.md`.

## Authority order (hard)

1. Exact `apps/wawona/app.contract` (what the user can do)
2. Product rules: `wawona-machine-types`, `wawona-global-settings-exclusive`,
   `wawona-platform-targets`, `wawona-ui-five-layers`
3. Repo-root `platforms.json` (`ALL_TARGETS`)
4. These PNGs (how it might feel natively)

If a concept shows Machines|Settings as a **peer root tablist**, **do not**
implement that (Settings stays a gear cover). Images / Runtimes may exist as
**Library destinations inside the Machines catalog** (macOS concept), never as
a Settings peer. Start stays gated by host capability. Keep shared semantics;
diverge chrome only. macOS 1:1 target: `macos/machines-concept.jpg` +
`macos/CONCEPT_GRADE.md`. Interaction rule:
`wawona-platform-native-interaction`.

## File map (`platforms.json` id)

| Concept file | `platforms.json` id | Exact host class |
|---|---|---|
| `macOS.png` | `macos` | apple/macos |
| `Linux.png` | `linux` | linux |
| `Android_Tablet.png` | `android` | android (wide) |
| `Apple_Watch.png` | `watchos` | apple/watch |
| `Wear_OS.png` | `wearos` | wearos |
| `AsteroidOS_Oppo_Watch.png` | `asteroidos` | asteroidos |
| `iOS.png` | `ios` | apple/ios (phone) |
| `iPadOS.png` | `ipados` | apple/ios (wide / multi-window) |
| `Web_DOM.png` | `web` | web |
| `Windows.png` | `windows` | windows (Fluent) |
| `visionOS.png` | `visionos` | apple/ios (spatial) |
| `tvOS_Apple_TV.png` | `tvos` | apple/tv |
| `Android_XR.png` | *(extra)* | concept only; not an `ALL_TARGETS` id yet |

## Concept vs product (filter before coding)

| Concept motif | Product stance |
|---|---|
| Top or bottom **Machines \| Sessions \| Images \| Runtimes \| Settings** | Reject root Settings tab. Settings = gear cover. Machines kinds stay Native Shell / VM / Container only |
| Images / Runtimes as primary destinations | Optional later; not Machines type-picker kinds |
| Planned guest with green **Running** / enabled Start | Gate Start; separate readiness vs execution |
| Three-column Mac (list + browser + inspector) | Semantics OK if Exact split stays; no second Settings hub |
| iPad multi-window sessions | Required on iPadOS / visionOS when product allows |
| Watch / Wear / Asteroid density | Native list + limited chrome; no GPU claims on watchOS |
| Pixel parity across platforms | Hard reject (`wawona-ui-five-layers`) |

## Agent loop

1. Read this README + the PNG for the target under edit.
2. Load `wawona-exact-contract` + `wawona-ui-five-layers`.
3. Change Contract for shared semantics; host adapter for native chrome only.
4. Prove with Exact agent / Appium / grade on a **running** target. Concept PNG
   alone never flips `target-matrix.json` `graded` to true.

## Related

- Progress: `../UI_AUDIT_PROGRESS.md`
- Rubric: `../rubric.json`
- Matrix: `../target-matrix.json`
- Skill: `wawona-ui-five-layers`, `wawona-exact-contract`, `wawona-all-targets`
