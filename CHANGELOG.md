# Changelog

All notable changes to Wawona are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning is **CalVer** `YY.M.D` (year · month · day), Apple-style year major
(26 = 2026). Tags are `vYY.M.D` (e.g. `v26.8.6`). Same calendar day re-ships
bump **build number** only. Historical `0.2.x` / mistaken `2.5.0` tags remain
as history.

## [Unreleased]

### Fixed

- **`ITMS-90426` on build 119 — the settled Swift Support rule** (supersedes
  the 26.8.8 "root cause" below, which was right for tvOS/visionOS and wrong
  for iOS+Watch). Build 119 shipped a textbook ABI-stable iOS+Watch IPA
  (every Swift ref `/usr/lib/swift/*`, minos iOS 17 / watchOS 10, GM `DT*`
  metadata, classic `Watch/` embed, no `SwiftSupport/`) and Apple still
  rejected it `ITMS-90426`, while the identical-commit watchless tvOS and
  visionOS IPAs were accepted (ASC `buildUploads` API: iOS `FAILED`
  errors=[90426], tvOS/visionOS `COMPLETE`) — the same split as every one of
  builds 89-118. Conclusion, cross-checked by reproducing build 95's
  ITMS-90429 expected-file list name-for-name from our own binaries: **ASC
  runs the legacy pre-ABI-stability Swift packaging validator on any IPA
  containing a watch companion, deployment targets notwithstanding.** Each
  platform bundle must carry `Frameworks/libswiftX.dylib` (re-signed with the
  app's own identity) *and* `SwiftSupport/<plat>/libswiftX.dylib`
  (byte-identical Apple-signed toolchain originals), where X = the bundle's
  referenced `/usr/lib/swift` names (weak included) ∩ toolchain
  `swift-5.0/<plat>/` contents. `embed_swift_runtime_into_archive!` now
  applies this legacy mode to watch-bearing archives — populating both
  bundles' `Frameworks/` and archive-root `SwiftSupport/{iphoneos,watchos}`
  before `xcodebuild -exportArchive` so Apple's own exporter signs and
  packages them — while watchless archives keep the accepted no-SwiftSupport
  shape. `assert_ipa_has_swift_support!` is now a hard pre-upload gate on the
  final ipa's actual zip contents: watch-bearing ipas fail the lane unless
  `SwiftSupport/{iphoneos,watchos}` hold exactly the expected set with full
  Frameworks parity and untouched Apple signatures
  (`assert_legacy_swift_support!`); watchless ipas fail if `SwiftSupport/`
  sneaks in. No ipa reaches App Store Connect without passing this.

## [26.8.8] - 2026-08-07

### Fixed

- **`ITMS-90426` on build 110, second cause**: after the SwiftSupport root
  cause below was fixed, one more attempt was made to embed the watchOS
  companion under `PlugIns/` (`dstSubfolderSpec=13`) instead of the legacy
  `Watch/` (`dstSubfolderSpec=16`), following upstream reports that Xcode 26
  requires it for on-device install. That embed location archived and
  exported fine locally, but broke `xcrun altool`/`upload_to_testflight`
  outright with `[altool.CBF038400] Cannot determine the 'platform' from the
  info.plist.` — before the ipa ever reached App Store Connect. Reverted to
  XcodeGen's own default `Watch/` location, which every build 89-110
  successfully uploaded through `altool`; no real Apple rejection ever named
  the embed directory as a problem, only SwiftSupport content (fixed below).
  Build 119 uploaded clean (iOS/tvOS/visionOS) with both fixes combined.
- **App Store Connect Swift Support rejections, root cause** (`ITMS-90426`/
  `ITMS-90429`/`ITMS-90433`, builds 89-104) — every prior fix in `26.8.7`
  (re-signing, timestamps, bundle-level re-sign, full-zip-rebuild, parity
  assertion) was real but none were the actual bug. Diffing a downloaded
  debug-export ipa's own signatures/dependencies directly showed
  `embed_swift_runtime_into_archive!` treated *every* `/usr/lib/swift/lib*
  .dylib` reference in `otool -L` (the full ABI-stable overlay set every
  Swift binary links, mostly `weak`) as needing embedding, and fell back to
  dumping the entire toolchain `swift-5.0/<platform>` folder into
  `SwiftSupport/` whenever nothing matched — manufacturing content no real
  Xcode 26 export at Wawona's deployment target (iOS/tvOS 17.0+, watchOS
  10.0+) would ever produce. Now only a narrow, named whitelist of real
  back-deployment compatibility dylibs (Concurrency, Span, legacy
  Compatibility5x/DynamicReplacements/StringProcessing/RegexParser shims) is
  ever embedded, each gated by its own minimum-OS threshold against the
  bundle's `MinimumOSVersion`. At current deployment targets none apply, so
  builds now correctly ship with no `SwiftSupport/` at all instead of a
  bogus one. `Ship: beta (stores)`'s `workflow_dispatch` now also uploads
  `debug_export` ipas as workflow artifacts for direct inspection
  (`altool --validate-app`, `codesign -dvvv`, etc.) instead of waiting on an
  async ASC rejection email.

## [26.8.7] - 2026-08-07

### Fixed

- **App Store Connect Swift Support rejections** (`ITMS-90426`/`ITMS-90429`,
  builds 93-95) — `embed_swift_runtime_into_archive!`'s `filter_map` leaked a
  skipped dylib's `UI.important` return value as a fake "copied" entry,
  making counts look inflated versus the later, correct `Frameworks/` scan
  (e.g. reported 15 when only 10 real files existed). Fixed the count, added
  a bundle-level re-sign after touching `Frameworks/`, switched
  `SwiftSupport/` injection from appending onto the exported ipa to a full
  rebuild from a fully-unzipped directory, and added
  `assert_swift_support_frameworks_parity!` to catch a
  `SwiftSupport`/`Frameworks` mismatch locally before upload.

## [26.8.6] - 2026-08-06

### Added

- **watchOS App Store path** — companion embedded in `Wawona-iOS` under
  `PlugIns/` (Xcode 26 has no bare-watch `app-store` export); see #136.
- **Beta prebuilt distribution** — Fastlane TestFlight (iOS/iPad/tvOS/visionOS;
  watch via iOS IPA) + Play internal + Linux AppImage artifacts.

### Changed

- Adopt **CalVer `YY.M.D`**; retire mistaken marketing version `2.5.0`
  (was meant to be `0.2.5`).
- Actions workflow display names use role prefixes (`Gate` / `Build` / `Watch` /
  `Ship`); promote blockers: **Gate: packages** + **Gate: products**.

## [2.5.0] - 2026-08-06 (superseded)

Mistaken semver tag for the first CalVer beta ship. Use **26.8.6** / `v26.8.6`.

## [0.2.4] - 2026-06-27

### Added

- **Full dependency parity** — zsh, fastfetch, neovim, weston clients, and kmscube across macOS (bundled), Linux GTK UI, Android, and Apple mobile targets.
- **macOS bundled CLI from nixpkgs** — zsh, neovim, and fastfetch ship as nixpkgs binaries in `Wawona.app`; weston clients and kmscube remain wwn-toolchain cross-builds.
- **Fastlane beta automation** — `fastlane/` lanes for TestFlight (iOS, iPadOS, tvOS, watchOS, visionOS; excludes macOS) and Play internal track (Android).
- **Release infrastructure** — `scripts/bootstrap-apple-signing.sh`, `scripts/sync-github-secrets.sh`, `.release-secrets.env.template`, GitHub Environment `release-beta`, workflow `.github/workflows/release-beta.yml`.
- **Nix release outputs** — `wawona-{ipados,tvos,watchos,visionos}-ipa`, `wawona-android-aab`.
- **VM launcher (macOS)** — Machine profiles with type Virtual Machine open UTM/UTM SE when installed.
- **Linux 1:1 parity foundation** — canonical `wawona.machineProfiles.v1` machine-profile model in Rust (`src/linux/machine_profile.rs`) with the same five machine types, runtime overrides, and JSON keys as the Apple/Android front-ends; canonical JSON persistence with one-time migration from the legacy `linux-config-v1.json` (`src/linux/profile_store.rs`); the shared 19-entry bundled-client catalog (`src/linux/bundled_clients.rs`); and GTK-free adaptive view-model helpers (`src/linux/ui_model.rs`).
- **Linux GTK compile gate** — `wawona-linux-ui` (+ tray and compositor-host helpers) now compiles ahead-of-time and reproducibly via Nix (`dependencies/wawona/linux-ui-prebuilt.nix`, `packages.<linux>.wawona-linux-ui-bin`) and in the `cargo-test-linux` CI job, so UI/model parity work can no longer silently break the Linux build.
- **Linux AppImage prebuilt** — self-contained, glibc-portable AppImage of the GTK UI (`packages.<linux>.wawona-appimage`) for x86_64 and aarch64, built reproducibly on the Determinate Linux builder. A single artifact serves both X11 and Wayland hosts (the binary auto-selects the GDK backend from `$WAYLAND_DISPLAY` at startup). CI builds, smoke-tests, and uploads it as a workflow artifact.
- **Linux parity CI gates** — `verify-linux-machines-parity.py`, `verify-linux-bundled-clients.py`, and `verify-linux-shell-tools.py` enforce that the Linux canonical model, bundled-client catalog, and shell-tool/runtime wiring stay in lockstep with the other platforms.

### Changed

- Version bumped to 0.2.4 across VERSION, Cargo.toml, and platform headers.
- Linux UI/model stub copy is now version-agnostic (no hard-coded `v0.2.3` strings) across the GTK, Android, and macOS front-ends.
- `nix.yml` and `android-parity.yml` use `concurrency` groups so superseded CI runs auto-cancel; `publish.yml` now also triggers on `master`.
- Documentation: all paths that referenced removed in-tree `dependencies/toolchains`, `dependencies/libs`, and `dependencies/apple` now point at upstream `wwn-*` flake inputs (`wwn-toolchain`, `wwn-weston`, `wwn-zsh`, `wwn-waypipe`, …).
- `wwn-neovim` flake input uses `path:../wwn-neovim` (local monorepo); switch to `github:Wawona/wwn-neovim` when published.
- Waypipe version string aligned to 0.11.0 in xcodegen.
- `nix develop` devShell includes fastlane, ruby, cocoapods, jdk17, and gh; `nix develop .#release` for release hints.

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
  - Weston iOS build (`wwn-weston/dependencies/clients/weston/ios.nix`)
  - Weston Android build (`wwn-weston/dependencies/clients/weston/android.nix`)
- **Graphics**
  - `graphics-smoke` binary — Vulkan driver probe with JSON output
- **Nix / Build**
  - `app-programs.nix` — wawona-ios, weston-run wrappers
  - `devshells.nix` — nix develop with XDG_RUNTIME_DIR / WAYLAND_DISPLAY
  - `shell-wrappers.nix` — weston-run, foot, etc.
  - libssh2 streamlocal patch (`patch-streamlocal.sh`)
  - OpenSSH dbclient streamlocal patch (`patch-dbclient-streamlocal.sh`)
- **Debugging**
  - `--debug` flag for flake apps (`.#wawona-macos`, `.#wawona-ios`, `.#wawona-android`, `.#wawona-linux`, …) — **opt-in** LLDB for crash/freeze catch (`process interrupt`). Default `nix run` is plain (no debugger). macOS also supports `--debug-attach`. See `docs/debugging.md`.
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
  - `wwn-toolchain/dependencies/toolchains/default.nix`: Major simplification (now upstream flake input)
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
