# iOS / Apple-mobile app entry (process `@main`)

Authority for **who owns LC_MAIN** on iOS, iPadOS, tvOS, and visionOS app
targets. Measured 2026-10-08: without `Darwin/Sources/Main.swift`, the
linker took `libgbm_es2_demo.a`'s C `_main` as the process entry and the
app exited in the ES2 cube. After renaming that archive symbol, the
linker had **no** `_main` until Main.swift was on the mobile targets.

Cross-links: `wawona-apple-swift-glue`, `wawona-ios-min-os`,
`wawona-swiftui-backports`, `wawona-ios-link-contract`. Skill:
`wawona-ios-sim-runtime`.

## Process entry (hard)

| Target | Entry | Notes |
|---|---|---|
| **macOS** | `Darwin/Sources/Main.swift` `@main` → SwiftUI `App` | LaunchAgent roles before UI |
| **iOS / iPadOS / tvOS / visionOS** | Same `Main.swift` `@main` → `UIApplicationMain` → `AppMainDelegate` + `WWNSceneDelegate` | iOS **15.0** floor; the UIKit scene delegates own CarPlay and external display |
| **watchOS** | `Sources/WawonaWatch` `@main` | Separate; do not share phone Main |

`Wawona.xcodeproj/project.xcproj` keeps the `Darwin/Sources` folder
in **every** Apple phone/TV/vision app target, not only macOS.

Info.plist names `WWNSceneDelegate` / CarPlay / external display. Scene hosts
`UIHostingController(rootView: WawonaRootView())`. Do **not** insert a
raw `UIView` under `UIHostingController.view` (SwiftUI runtime warning).

## Bundled client archives (hard)

In-process demos (`gbm_es2_demo`, kmscube, cubes, …) must **never** export
C `_main` into a static archive linked into the app.

`wwn-kmscube` `gbm-es2-demo`:

- Source already has `extern "C" int gbm_es2_demo_main(...)`.
- Compile `demo/main.cpp` with `-Dmain=gbm_es2_demo_cli_main` so the C++
  `main()` is renamed. That name is dead weight in the archive.
- **Never** `-Dmain=gbm_es2_demo_main` (redefines the product ABI).
- Header + Swift `@_silgen_name("gbm_es2_demo_main")` stay on the extern C
  entry.

Same idea for any other upstream `main.cpp` force-loaded into Wawona.

## Host compositor on Apple mobile (hard)

Before `WWNCoreStart` / `WWNCompositorBridge.start`:

1. Set `XDG_RUNTIME_DIR` to `WWNPreferencesManager.preferredSharedRuntimeDir()`
   (simulator: `/tmp/wawona_sim_<uid>_<udid8>` when `SIMULATOR_UDID`
   is set; else `/tmp/wawona_sim_<uid>`).
2. `mkdir` that path mode `0700`.

Default Rust fallback `/tmp/wawona-<uid>` **fails to bind** on iOS Simulator
(`Failed to bind primary socket at /tmp/wawona-503/wayland-0`). Then
Machines Start reports `Host compositor failed to start.`

## iOS 15 SwiftUI floor (reminders)

APIs newer than iOS 15 need a guard or a `WawonaBackport` path
(`wawona-swiftui-backports`).

## Hard rejects

❌ Ship an Apple-mobile app target without `Darwin/Sources/Main.swift`  
❌ Rely on a bundled client's C `_main` as the process entry  
❌ `-Dmain=gbm_es2_demo_main` when that symbol already exists as extern C  
❌ Start the host compositor without setting mobile `XDG_RUNTIME_DIR`  
❌ Nest UIKit subviews under `UIHostingController.view`  
❌ Replace the UIKit entry with SwiftUI `App` (scene delegates own CarPlay and external display)  

## Verify

```bash
# Archive: product ABI, no C _main
nm -gU "$GBM_A" | rg 'T _' | rg -i 'main|gbm'
# App: has _main; LC_MAIN is the app, not ES2Cube-only life
nm -gU result-ios-sim/Wawona.app/Wawona | rg 'T _main'
# Sim compositor: per-UDID socket under wawona_sim_*
ls /tmp/wawona_sim_${UID}_*/wayland-0
```
