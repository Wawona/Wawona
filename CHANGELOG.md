# Changelog

All notable changes to Wawona are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2026-02-25

### Added

- **Rust core migration completed** — Compositor logic fully moved from C to Rust. All Wayland protocol handling, surfaces, windows, input, IPC, and frame timing now live in the Rust core (`src/core/`). Platform frontends (Objective-C/Swift for macOS/iOS, Kotlin for Android) call Rust via UniFFI/C FFI; they provide rendering and windowing only. The previous C-based compositor implementation has been fully replaced.
- **Initial iOS and Android support** — v0.2.2 finally brings Wawona to all three platforms: macOS, iOS, and Android. Mobile builds are now available via `nix run .#wawona-ios` and `nix run .#wawona-android`.
- **Android**
  - Modifier accessory bar (`ModifierAccessoryBar.kt`) with 1:1 parity to iOS — sticky Shift/Ctrl/Alt/⌘, two rows (ESC ` TAB / — HOME ↑ END PGUP; ⇧ CTRL ALT ⌘ ← ↓ → PGDN ⌨↓)
  - Native Weston and Weston Terminal toggles in Settings
  - Tabbed Settings dialog: Display, Graphics, Advanced, Input, Waypipe, SSH
  - Cairo shim (`cairo_shim.c`, `cairo_shim.h`) for Cairo-dependent clients
  - Android icon generator (`android-icon-assets.nix`) and contract (`android-icon-contract.md`)
- **macOS / iOS**
  - Force SSD (server-side decorations) setting — compositor sends `configure(server_side)`, host draws window chrome
  - Weston Terminal and Native Weston launch toggles in Settings
  - Weston iOS build (`dependencies/clients/weston/ios.nix`)
  - Weston Android build (`dependencies/clients/weston/android.nix`)
- **Graphics**
  - `graphics-smoke` binary — Vulkan driver probe with JSON output
- **Nix / Build**
  - `app-programs.nix` — wawona-ios, weston-run wrappers
  - `devshells.nix` — nix develop with XDG_RUNTIME_DIR / WAYLAND_DISPLAY
  - `shell-wrappers.nix` — weston-run, foot, etc.
  - libssh2 streamlocal patch (`patch-streamlocal.sh`)
  - OpenSSH dbclient streamlocal patch (`patch-dbclient-streamlocal.sh`)
- **Debugging**
  - `--debug` flag for `nix run .#wawona-macos`, `.#wawona-ios`, `.#wawona-android` — launches under LLDB for native debugging. macOS: run from start; iOS: app pauses at spawn, LLDB attaches; Android: lldb-server deployed, LLDB connects via gdb-remote. See `docs/debugging.md`.
- **Documentation**
  - `docs/README.md` — Documentation index
  - `docs/usage.md` — Weston (`nix run .#weston`, `.#weston-terminal`), Waypipe, native commands
  - `docs/settings.md` — All Wawona Settings (Display, Graphics, Input, Waypipe, SSH) for macOS, iOS, Android
  - `docs/compilation.md` — Quick build, project generators
  - `docs/debugging.md` — Attach LLDB with `nix run .#wawona-{macos,ios,android} -- --debug`
  - `docs/goals.md` — Project vision, technical objectives
  - `docs/2026-Wawona-Android-Audit.md` — Android parity audit (~85%)

### Changed

- **Android**
  - Vulkan clear color from black to CompositorBackground `0x0F1018` — eliminates flashing during waypipe transitions
  - Refactored input handling (`input_android.c` / `input_android.h`)
  - Safe area updates with display cutout support
  - New `nativeResizeSurface` JNI path recreates the Vulkan swapchain without full teardown, eliminating blank screens during keyboard show/hide; `surfaceChanged` debounces resize by 200ms
  - `WWNCoreFlushClients()` added after the `NotifyFramePresented` loop in `choreographer_frame_cb`
- **iOS / macOS**
  - `WWNCompositorBridge.m`: XDG_RUNTIME_DIR setup, WAYLAND_DISPLAY export, popup handling refactor
  - `main.m`: XDG_RUNTIME_DIR and WAYLAND_DISPLAY setup before compositor start
  - `WWNAboutPanel.m`: UI branding and layout updates
  - `layoutSubviews` disables CATransaction implicit animations on the content layer to prevent stretched-frame artifacts during rotation
  - `injectWindowResize` and `setOutputWidth` use coalescing to avoid spamming the compositor queue
  - `flushClients` re-implemented to dispatch `WWNCoreFlushClients` to the Rust core (was a no-op)
  - `_compositorBusy` changed to `atomic_bool`; reset moved from compositor queue to end of main-queue UI block
- **Waypipe**
  - Major refactor of `patch-waypipe-source.sh` and `patch-waypipe-android.sh`
  - XDG_RUNTIME_DIR / WAYLAND_DISPLAY handling in remote exec
  - SSH bridge thread loop reworked to proactively drain `libssh2`'s internal buffer after writing to the local Wayland socket
- **Nix**
  - `flake.nix`: Refactor; Weston apps and shell wrappers
  - `dependencies/toolchains/default.nix`: Major simplification
  - `dependencies/wawona/android.nix`: Weston bundling, Gradle, jniLibs
  - `dependencies/wawona/ios.nix`: iOS build pipeline expansion
  - `dependencies/wawona/macos.nix`: Weston client bundling
- **Core**
  - `src/core/compositor.rs`: XDG_RUNTIME_DIR creation with 0700 permissions
  - Popup handling and xdg_decoration updates across protocol modules
  - `process_events` now calls `compositor.flush()` after poll and `flush_clients()` after handling events
  - `flush_buffer_releases()` moved from `SurfaceCommitted` handler to `notify_frame_presented()`
  - `wp_presentation_feedback` presented events now sent in `notify_frame_presented`
- **Documentation**
  - `docs/2026-ARCHITECTURE-STRUCTURE.md` — Force SSD, Waypipe platform notes
  - `docs/2026-LOGGING.md` — Logging format
  - `docs/2026-waypipe.md` — Platform overview (macOS OpenSSH, iOS libssh2, Android Dropbear)

### Fixed

- **Visual flashing on iOS and Android** — Surfaces flashing/disappearing on every keypress. Premature buffer release (old buffers released before frame rendered), iOS `_bufferCache` data race (concurrent read/write on `NSMutableDictionary`), and Android missing `FlushClients` after frame presentation
- **iOS waypipe + libssh2 freeze on first frame** — SSH bridge thread data starvation from `libssh2` internal buffering not signaling `ppoll`
- **`wp_presentation_feedback` events never sent** — `PresentationFeedback` objects were never marked committed, leaking indefinitely
- **`wl_output` retroactive enter** — Surfaces attached before client binds `wl_output` now receive `wl_surface.enter` retroactively
- **XdgOutput Persistence** — Fixed bug where `XdgOutput` resources were dropped prematurely by correctly storing them in the compositor state
- **Stale Window Mitigation** — Prevented orphaned black windows on macOS by deferring visibility until the first buffer commit and using `(0,0)` configuration for Force SSD windows
- **Multi-touch Input** — Fixed multi-touch event forwarding on iOS and Android; ensured `wl_seat` correctly advertises touch capabilities
- **Android Shadow Cropping** — Fixed incorrect shadow rendering by aligning push constant layouts between C renderer and SPIR-V shaders (extended to 48 bytes)
- **macOS Window Controls** — Fixed minimize-to-dock and resolved visual flashing during maximize/restore transitions
- **Buffer Scaling** — Synchronized NSWindow content area precisely with logical dimensions of committed Wayland buffers to eliminate stretching
- Inject XDG_RUNTIME_DIR and WAYLAND_DISPLAY into ProcessBuilder/NSTask for Weston endpoints
- fcft build on macOS: include `xlocale.h`
- Weston build on macOS; expose applications in Nix flake
- Android Vulkan renderer visual flashing (clear color mismatch)
- `android_quad.vert` shader

### Removed

- `WaypipeStatusBanner.kt` (Android)
- `meta.json` (empty)
- Legacy docs: `2026-CHECKLIST.md`, `2026-DECORATION-AND-FORCE-SSD-PLAN.md`, `2026-DMABUF_SUPPORT.md`, `2026-GPU-Drivers.md`, `2026-Graphics-Driver-Settings-Design.md`, `2026-iOS-Static-Drivers.md`, `2026-waypipe-ios-full-plan.md`, `2026-waypipe-ios.md`

---

## [0.2.1] - 2026-02-03

### Added

- **Force SSD (Server-Side Decorations)** — Compositor can enforce native-style decorations regardless of client preference; force_ssd controls exposed in FFI
- **Native popups** — `WawonaMacOSPopup` and `WawonaPopupHost`; Wayland popup handling moved from NSMenu to NSPopover for improved layout and clipping
- **UI branding** — Text labels ('Ko-fi', 'GitHub Sponsors') on donation buttons; `WawonaImageLoader` for asset loading and caching; modern social and donation icons in gallery
- **Documentation** — Liquid Glass design principles; macOS implementation details

### Changed

- **Popup handling** — Refactored to NSPopover; `WawonaCompositorBridge` updated for new popup architecture
- **Waypipe** — Fixed path resolution for `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` for stable remote app connections; enhanced SSH config handling
- **Input** — Improved modifier key tracking for macOS clients
- **Preferences** — Cleaned up `WawonaPreferences` and `WawonaWaypipeRunner` for reliability

[0.2.2]: https://github.com/aspauldingcode/Wawona/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/aspauldingcode/Wawona/releases/tag/v0.2.1
