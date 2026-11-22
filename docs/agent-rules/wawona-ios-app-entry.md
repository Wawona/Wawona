# iOS / Apple-mobile app entry (process `@main`)

**Product ship (2026-11 Exact cutover):** Exact `bun host/apple/build.mjs`
owns the product IPA entry for iOS / iPadOS / tvOS / visionOS / macOS.
Exact floor is **17.0**. There is no committed `Wawona.xcodeproj`.

Historical note (dual-run / pre-cutover): without `Darwin/Sources/Main.swift`,
the linker could take a bundled client's C `_main` (e.g. `gbm_es2_demo`).
That lesson still applies to any archive force-loaded into Exact: never
export product `_main` from a client staticlib.

Cross-links: `wawona-apple-swift-glue`, `wawona-ios-min-os`,
`wawona-ios-link-contract`, `docs/compilation.md`.

## Process entry (hard)

| Target | Entry | Notes |
|---|---|---|
| **Product Exact** | Exact Apple host assemble | Store id `com.aspauldingcode.Wawona`; iOS **17.0** |
| **Legacy dual-run** | `Darwin/Sources/Main.swift` (quarantine) | Do not revive as the ship path |
| **watchOS** | Exact `--watchos` follow-on; legacy `Sources/WawonaWatch` | Companion assert skipped until Exact embeds watch |

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

## Hard rejects

❌ Revive `Wawona.xcodeproj` as the product LC_MAIN owner  
❌ Rely on a bundled client's C `_main` as the process entry  
❌ `-Dmain=gbm_es2_demo_main` when that symbol already exists as extern C  
❌ Start the host compositor without setting mobile `XDG_RUNTIME_DIR`  
❌ Floor the Exact product IPA below `host.ios.minimumOS` 17.0  

## Verify

```bash
# Archive: product ABI, no C _main from clients
nm -gU "$GBM_A" | rg 'T _' | rg -i 'main|gbm'
# Exact tip / archive IPA: MinimumOSVersion 17.0, store bundle id
plutil -p "$WAWONA_APP_PATH/Info.plist" | rg 'MinimumOSVersion|CFBundleIdentifier'
```
