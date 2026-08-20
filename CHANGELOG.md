# Changelog

All notable changes to Wawona are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning is **CalVer** `YY.M.D` (year · month · day), Apple-style year major
(26 = 2026). Tags are `vYY.M.D` (e.g. `v26.8.6`). Same calendar day re-ships
bump **build number** only. Historical `0.2.x` / mistaken `2.5.0` tags remain
as history.

## [Unreleased]

## [26.8.19] - 2026-08-19

### Fixed

- **Mode B stage never probes IOWatchdog with lldb.** Install used to run
  `wwn-iowatchdog disable` then `enable` during `--mode-b-stage`. On
  macOS 26 that attaches `lldb` to live `watchdogd`; a bad attach exited
  the daemon with SIGTRAP (paniclog namespace 2 subcode 0x5) while kernel
  IOWatchdog was still armed (`watchdogd[pid] exited`, 2026-08-20 during
  `nix run .#install`). Stage now only restages files / sudoers and may
  `launchctl enable`+`bootstrap` a disabled watchdogd job (never
  `kickstart -k`). Disable belongs only on Take Over.
- **Mode B Take Over disables kernel IOWatchdog first.** Unloading
  `watchdogd` without that panics immediately (`watchdogd[pid] exited`,
  PanicOnConsecutiveCrash, 2026-08-19). Sequence: `wwn-iowatchdog disable`
  (IOKit type 1 / method 3), then disable+bootout watchdogd, then
  WindowServer, then compositor-only `DYLD_INSERT_LIBRARIES`. Abort and
  restore Aqua if IOWatchdog disable fails. `ws-guard` restores
  WindowServer only (never `kickstart -k` watchdogd; that paniced at
  23:12). Probe may inject while Aqua stays up.
- **`nix run .#install` drops stale `applaunch` LaunchAgents.** After the
  panic reboot, `com.aspauldingcode.wawona.applaunch` still `open -a`'d a
  garbage-collected nix store. Login Services then launched
  `Documents/ahaha/Wawona.app` 0.2.2, which dyld-aborted on a missing
  `libpixman-1.0.dylib`. Install and uninstall now boot out that agent.
- **Mode B `nix run .#install` no longer kills its own restage.** The
  helper used to `kill -KILL` every process whose command line mentioned
  `run-modeb.sh`, including the privileged installer `/bin/sh -c`. Stage
  then reported `install did not finish (output=)`. Cleanup now matches
  only helper argv, and stage no longer runs the old helper or `pkill -f`.
- **Mode B helper no longer `export`s `DYLD_INSERT_LIBRARIES`.** That env
  was inherited by Apple `arm64e` tools (`date`, `mkdir`, `launchctl`),
  dyld refused the `arm64` dylib (`have arm64, need arm64e`), and Take
  Over never kept a compositor PID. Insert is only on the niri/weston
  exec line.
- **macOS `nix run .#uninstall` on a root-owned `/Applications/Wawona.app`.**
  User-level `rm -rf` failed after a pkg or sudo copy. Uninstall now prompts
  once for administrator privileges, removes the app bundle, and tears down
  Mode B helper / sudoers / dylib / ws-guard.
- **Xcode `Wawona-macOS` compile after Mode B uninstall wiring.** Closing
  `appendString:` for `--uninstall` was missing `]`, so the project build
  failed and the Swift fallback reported `no such module 'WawonaModel'`.
  Xcode failure is now fatal instead of that fallback.
- **Mode B Take Over no longer dies on a stale `modeb.lock`.** Leftover helpers
  ignore TERM until framebufferd is live, so steal used to fail with
  "lock could not be claimed" and leave the lock behind. The helper now
  SIGKILLs leftovers, retries mkdir, and drops the lock on failure.

### Changed

- **macOS `--mode-b-*` CLI no longer starts the Aqua compositor.** Staging
  the helper was creating WWNCore and dumping `[BUNDLE]` / `[FFI]` / `[NIRI]`
  logs into `nix run .#install`. That was this process, not dylib injection.
- **macOS menu bar uses the Wayland W silhouette, not the app icon.** Template
  glyph with no yellow disc. Launch at Login is a mini `NSSwitch`.
- **`nix run .#install` restages the Mode B helper for this store.** It runs
  `Wawona --mode-b-stage` (administrator once): copies helper + dylib,
  refreshes sudoers, clears a stale `modeb.lock`, and fails if the helper
  still points at a previous nix store. No Take Over reminder. Does not
  unload WindowServer.
- **Desktop Replacement disable is a full teardown.** Restore Apple's
  WindowServer, kill root niri/weston and framebufferd/inputd, and remove
  leftover login agent, sudoers drop-in, helper, installed dylib, and
  ws-guard. Cancelling the admin prompt leaves the switch on.
- **Take Over Screen Now does not install a login LaunchAgent.** Logout
  returns normal macOS. Take Over disables IOWatchdog first, then unloads
  watchdogd and WindowServer. Unloading watchdogd without IOWatchdog
  disable panics immediately.
- **Take Over `sudo -n` must invoke the helper path, not `bash -c`.**
  Recovery sudoers only allows `run-modeb.sh`. Wrapping in `nohup` via
  bash returned status 1 and the alert showed a stale 11:25 log.
- **macOS Desktop Replacement Mode B requires SIP fully disabled.**
  `csrutil enable --without debug` is not enough (`launchctl bootout` of
  WindowServer returns 150). Recovery: `csrutil disable`. Settings shows
  **Fully Disabled** only in that state and refuses PartiallyDisabled.
- **Stale `modeb.lock` no longer blocks Take Over.** A leftover lock from a
  failed helper used to log `modeb helper already running` and exit without
  a compositor. The helper now steals the lock when no compositor PID is live.

## [26.8.12] - 2026-08-12

### Fixed

- **visionOS static ANGLE / iland EGL-image `ld: duplicate symbol` (real
  dedup).** Per-member `llvm-objcopy` rename of ANGLE's public EGL/GLES image
  entrypoints to `_angle_*` in `wwn-iland` (`c7a3275`); shim stays strong.
  Replaces the interim weak-export workaround. (#122)
- **tvOS Gate: packages compile.** `WWNSceneDelegate` imports
  `WWNRootfsProvider` on all `TARGET_OS_IPHONE` (including tvOS).
- **macOS GBM ES2 Demo no longer kills the host on Start.** Partial EGL/GBM
  bring-up left `ModesetDev::saved_crtc` null; `DRMModesetter::~Impl` then
  dereferenced it (`EXC_BAD_ACCESS` at 0) and took down the whole in-process
  Wawona app. `wwn-kmscube` `ad778d3` null-checks before CRTC restore and
  treats "no usable connector" as init failure. (#52, #140)
- **GBM ES2 Demo no longer mislabeled / aliased as KMS Cube.** Host chrome,
  accessibility, and log modules follow the real client id; a second in-process
  DRM client is refused while another owns iland. (#52, port-fidelity)
- **Ship DMG latest-download alias.** `release.yml` also publishes
  `Wawona-macOS-arm64.dmg` for wawona.io `releases/latest/download/` cards.

### Added

- **Sandbox / rootfs + XDG parity gaps closed.** watchOS niri KDL embed +
  `wwn_ios_refresh_bundle_env` → real shell env; tvOS applications catalog
  embed; macOS writable `XDG_CONFIG_HOME` / `XDG_STATE_HOME` when unset
  (Android `XDG_STATE_HOME` and niri `applyShellEnvironment` already on tip).
  (#31, #33, #88)

## [26.8.11] - 2026-08-11

### Changed

- **Release secrets: SecretSpec + pass only.** Removed public `.secrets/`,
  `.release-secrets.env.template`, and the dotenv migrate script. Tier-0 flow
  is sops-nix (host GPG) → private `aspauldingcode/.password-store` →
  `secretspec.toml` / `./scripts/release-env.sh` /
  `./scripts/sync-github-secrets.sh`. Developer ID P12 base64 keys are part of
  `release-apple` for macOS notarization.

### Added

- **Bundled clients green on every target (no skips).** iOS `vkcube` now
  renders on a bundled SwiftShader CPU ICD (`wwn-iland` `swiftshader-ios-sim`,
  simulator-only; device stays MoltenVK-only). Android `gbm-es2-demo` renders
  via an iland EGL-shim CPU-readback fallback (plain GL texture +
  `glReadPixels`→AHB) when AHB native-buffer import is unavailable on the
  emulator's software Vulkan, plus an empty-blocking-stdin fix so the demo
  doesn't self-exit. `weston-editor` works: the compositor now advertises
  `zwp_text_input_manager_v1` alongside v3. New rule
  `wawona-never-skip-bundled-clients`. Fix the client/platform beneath a
  failing bundled client, never gate it out. (#113, #122, #140)
- **fastfetch on tvOS + watchOS.** Wired the recipe, flake attrs, link flags,
  prebuild privatization, and stub so `fastfetch` builds/links into the tvOS
  and watchOS apps like the rest of the Apple family. (#139)
- **watchOS keyboard → PTY.** Real `wl_keyboard` + embedded US xkb keymap in
  the watch mini Wayland server, driven by a WatchKit `TextField`/Send/Return
  affordance, feeding in-process zsh. uutils/coreutils now links on the
  watchOS arm64 slice (arm64_32 keeps weak stubs). (#95)
- **watchOS share-tree sandbox FS.** The watch app now embeds
  `share/{fonts,weston,X11/xkb,icons}` and `WWNWatchShellEnvironment`
  synthesizes a `fonts.conf` + points `FONTCONFIG`/`WESTON_DATA_DIR`/
  `XKB_CONFIG_ROOT`/`XDG_DATA_DIRS` at it, so `weston-terminal` renders text
  instead of blank. (#31, #33)
- **macOS Developer ID sign + notarize for GitHub DMG.**
  `scripts/macos-sign-and-notarize-dmg.sh` +
  `Wawona-macOS-DeveloperID.entitlements`; `release.yml` `release-macos` uses
  Environment `release-beta` (deep codesign, `productsign` agent pkg,
  `notarytool`, staple). `workflow_dispatch` can re-upload an existing tag
  (`build_ref=development` when the script is ahead of the tag).

### Fixed

- **visionOS device archive `ld: duplicate symbol` for the EGL-image
  entrypoints.** visionOS ships ANGLE as a `-force_load`'d static
  `libEGL.a`/`libGLESv2.a` (iOS/Android ship it as a dylib), and ANGLE already
  exports `eglCreateImageKHR`/`eglDestroyImageKHR`/`glEGLImageTargetTexture2DOES`.
  The iland EGL shim's IOSurface dma_buf copies of those collided with ANGLE's
  static defs on visionOS only. Fixed by real dedup, not weak coexistence:
  `wwn-iland` (`2aaf961`) extends `rename-angle-symbols.sh` so static ANGLE's
  public image entrypoints become `_angle_*` (same pattern as the rest of the
  EGL surface), applied to both `libEGL.a` and `libGLESv2.a`; the shim keeps
  strong ownership of the IOSurface dma_buf path. Also drop visionOS
  `OTHER_LDFLAGS` / rootfs embed fallbacks to iOS packages so one Ld never
  mixes two platform archive trees.
- **The actual root cause of every iOS App Store rejection since July
  (builds 60-120, rotating `ITMS-90426`/`90429`/`90433`): loose non-Swift
  dylibs in `Frameworks/`.** The ASC `buildUploads` API record shows every
  iOS upload from build 60 (weeks **before** the watch companion existed)
  through 120 `FAILED` with a Swift Support error, while the tvOS/visionOS
  ipas of the same commits were always `COMPLETE`. That killed both prior
  theories (SwiftSupport content, builds 89-110; watch-triggered legacy
  validation, build 119-120): build 120 shipped a *perfect* legacy layout -
  `SwiftSupport/{iphoneos,watchos}` with exact set-parity, Frameworks
  mirrors, byte-identical Apple-signed copies, all verified in the uploaded
  artifact. And ASC still answered `90429`, listing dylibs that were
  physically present. The one constant, present only in the iOS ipa: ANGLE's
  loose `Frameworks/libEGL.dylib` + `libGLESv2.dylib` flat convenience
  copies (tvOS never bundles ANGLE; visionOS's embed glob never matched).
  App Store bundles must not contain loose, non-framework-wrapped `.dylib`
  files (TN2435); the only loose dylibs ASC sanctions under `Frameworks/`
  are pre-ABI Swift runtime dylibs, so the ANGLE ones flipped its validator
  into legacy Swift-runtime expectations no matter what SwiftSupport content
  was shipped. Fixed on both sides: `xcodegen.nix` now embeds the flat ANGLE
  copies **simulator-only** (device ships `libEGL.framework`/
  `libGLESv2.framework` only), and `wwn-iland`'s EGL shim (input bumped to
  `d6cf97a`) probes the framework-wrapped binaries first. Canonical shape
  for every Apple-mobile ipa, watch or not, is ABI-stable. No
  `SwiftSupport/`, no `Frameworks/libswift*`.
  `WAWONA_WATCH_LEGACY_SWIFT_SUPPORT=1` keeps the fully-validated legacy
  watch layout (built for build 120) as an escape hatch. New hard pre-upload
  gates on the final ipa's actual zip contents: `assert_no_loose_dylibs!`
  (TN2435. The real regression guard) plus canonical/legacy Swift Support
  shape checks; no ipa reaches App Store Connect without passing them.

## [26.8.9] - 2026-08-09

### Added

- **phoon on every Apple target** (iOS/iPadOS/tvOS/watchOS/visionOS + sims,
  macOS, Android, Linux): in-process `wwn-phoon-rs` shell tool. tvOS/watchOS
  lazy-link `libphoon_rs.a` after niri's force-load so Rust std/core dedupe
  (avoids the prior `ld: 2134 duplicate symbols` failure).

### Fixed

- **fontconfig / meson skew** after the nixpkgs bump: `wwn-toolchain` pins
  fontconfig **2.17.1** for Android/iOS meson cross builds (2.18.x needs meson
  ≥1.11; toolchain meson is 1.10.2).
- **zsh 5.9.2 patch drift**: `wwn-zsh` `getfpfunc` compinit-guard anchor no
  longer keys on `PATH_MAX+1` vs `PATH_MAX`.
- CI idle-memory / product-build harness hardening from the preceding
  `development` cycle (iOS leak PID, smoke open ordering, AppImage reuse).

## [26.8.8] - 2026-08-07

### Fixed

- **`ITMS-90426` on build 110, second cause**: after the SwiftSupport root
  cause below was fixed, one more attempt was made to embed the watchOS
  companion under `PlugIns/` (`dstSubfolderSpec=13`) instead of the legacy
  `Watch/` (`dstSubfolderSpec=16`), following upstream reports that Xcode 26
  requires it for on-device install. That embed location archived and
  exported fine locally, but broke `xcrun altool`/`upload_to_testflight`
  outright with `[altool.CBF038400] Cannot determine the 'platform' from the
  info.plist.`. Before the ipa ever reached App Store Connect. Reverted to
  XcodeGen's own default `Watch/` location, which every build 89-110
  successfully uploaded through `altool`; no real Apple rejection ever named
  the embed directory as a problem, only SwiftSupport content (fixed below).
  Build 119 uploaded clean (iOS/tvOS/visionOS) with both fixes combined.
- **App Store Connect Swift Support rejections, root cause** (`ITMS-90426`/
  `ITMS-90429`/`ITMS-90433`, builds 89-104). Every prior fix in `26.8.7`
  (re-signing, timestamps, bundle-level re-sign, full-zip-rebuild, parity
  assertion) was real but none were the actual bug. Diffing a downloaded
  debug-export ipa's own signatures/dependencies directly showed
  `embed_swift_runtime_into_archive!` treated *every* `/usr/lib/swift/lib*
  .dylib` reference in `otool -L` (the full ABI-stable overlay set every
  Swift binary links, mostly `weak`) as needing embedding, and fell back to
  dumping the entire toolchain `swift-5.0/<platform>` folder into
  `SwiftSupport/` whenever nothing matched. Manufacturing content no real
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
  builds 93-95). `embed_swift_runtime_into_archive!`'s `filter_map` leaked a
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

- **watchOS App Store path**. Companion embedded in `Wawona-iOS` under
  `PlugIns/` (Xcode 26 has no bare-watch `app-store` export); see #136.
- **Beta prebuilt distribution**. Fastlane TestFlight (iOS/iPad/tvOS/visionOS;
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

- **Full dependency parity**. Zsh, fastfetch, neovim, weston clients, and kmscube across macOS (bundled), Linux GTK UI, Android, and Apple mobile targets.
- **macOS bundled CLI from nixpkgs**. Zsh, neovim, and fastfetch ship as nixpkgs binaries in `Wawona.app`; weston clients and kmscube remain wwn-toolchain cross-builds.
- **Fastlane beta automation**. `fastlane/` lanes for TestFlight (iOS, iPadOS, tvOS, watchOS, visionOS; excludes macOS) and Play internal track (Android).
- **Release infrastructure**. `scripts/bootstrap-apple-signing.sh`, `scripts/sync-github-secrets.sh`, `.release-secrets.env.template`, GitHub Environment `release-beta`, workflow `.github/workflows/release-beta.yml`.
- **Nix release outputs**. `wawona-{ipados,tvos,watchos,visionos}-ipa`, `wawona-android-aab`.
- **VM launcher (macOS)**. Machine profiles with type Virtual Machine open UTM/UTM SE when installed.
- **Linux 1:1 parity foundation**. Canonical `wawona.machineProfiles.v1` machine-profile model in Rust (`src/linux/machine_profile.rs`) with the same five machine types, runtime overrides, and JSON keys as the Apple/Android front-ends; canonical JSON persistence with one-time migration from the legacy `linux-config-v1.json` (`src/linux/profile_store.rs`); the shared 19-entry bundled-client catalog (`src/linux/bundled_clients.rs`); and GTK-free adaptive view-model helpers (`src/linux/ui_model.rs`).
- **Linux GTK compile gate**. `wawona-linux-ui` (+ tray and compositor-host helpers) now compiles ahead-of-time and reproducibly via Nix (`dependencies/wawona/linux-ui-prebuilt.nix`, `packages.<linux>.wawona-linux-ui-bin`) and in the `cargo-test-linux` CI job, so UI/model parity work can no longer silently break the Linux build.
- **Linux AppImage prebuilt**. Self-contained, glibc-portable AppImage of the GTK UI (`packages.<linux>.wawona-appimage`) for x86_64 and aarch64, built reproducibly on the Determinate Linux builder. A single artifact serves both X11 and Wayland hosts (the binary auto-selects the GDK backend from `$WAYLAND_DISPLAY` at startup). CI builds, smoke-tests, and uploads it as a workflow artifact.
- **Linux parity CI gates**. `verify-linux-machines-parity.py`, `verify-linux-bundled-clients.py`, and `verify-linux-shell-tools.py` enforce that the Linux canonical model, bundled-client catalog, and shell-tool/runtime wiring stay in lockstep with the other platforms.

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

- **Rust core migration completed**. Compositor logic fully moved from C to Rust. All Wayland protocol handling, surfaces, windows, input, IPC, and frame timing now live in the Rust core (`src/core/`). Platform frontends (Objective-C/Swift for macOS/iOS, Kotlin for Android) call Rust via UniFFI/C FFI; they provide rendering and windowing only. The previous C-based compositor implementation has been fully replaced.
- **Initial iOS and Android support**. V0.2.2 finally brings Wawona to all three platforms: macOS, iOS, and Android. Mobile builds are now available via `nix run .#wawona-ios` and `nix run .#wawona-android`.
- **Android**
  - Modifier accessory bar (`ModifierAccessoryBar.kt`) with 1:1 parity to iOS. Sticky Shift/Ctrl/Alt/⌘, two rows (ESC ` TAB /. HOME ↑ END PGUP; ⇧ CTRL ALT ⌘ ← ↓ → PGDN ⌨↓)
  - Native Weston and Weston Terminal toggles in Settings
  - Tabbed Settings dialog: Display, Graphics, Advanced, Input, Waypipe, SSH
  - Cairo shim (`cairo_shim.c`, `cairo_shim.h`) for Cairo-dependent clients
  - Android icon generator (`android-icon-assets.nix`) and contract (`android-icon-contract.md`)
- **macOS / iOS**
  - Force SSD (server-side decorations) setting. Compositor sends `configure(server_side)`, host draws window chrome
  - Weston Terminal and Native Weston launch toggles in Settings
  - Weston iOS build (`wwn-weston/dependencies/clients/weston/ios.nix`)
  - Weston Android build (`wwn-weston/dependencies/clients/weston/android.nix`)
- **Graphics**
  - `graphics-smoke` binary. Vulkan driver probe with JSON output
- **Nix / Build**
  - `app-programs.nix`. Wawona-ios, weston-run wrappers
  - `devshells.nix`. Nix develop with XDG_RUNTIME_DIR / WAYLAND_DISPLAY
  - `shell-wrappers.nix`. Weston-run, foot, etc.
  - libssh2 streamlocal patch (`patch-streamlocal.sh`)
  - OpenSSH dbclient streamlocal patch (`patch-dbclient-streamlocal.sh`)
- **Debugging**
  - `--debug` flag for flake apps (`.#wawona-macos`, `.#wawona-ios`, `.#wawona-android`, `.#wawona-linux`, …). **opt-in** LLDB for crash/freeze catch (`process interrupt`). Default `nix run` is plain (no debugger). macOS also supports `--debug-attach`. See `docs/debugging.md`.
- **Documentation**
  - `docs/README.md`. Documentation index
  - `docs/usage.md`. Weston (`nix run .#weston`, `.#weston-terminal`), Waypipe, native commands
  - `docs/settings.md`. All Wawona Settings (Display, Graphics, Input, Waypipe, SSH) for macOS, iOS, Android
  - `docs/compilation.md`. Quick build, project generators
  - `docs/debugging.md`. Attach LLDB with `nix run .#wawona-{macos,ios,android} -- --debug`
  - `docs/goals.md`. Project vision, technical objectives
  - `docs/2026-Wawona-Android-Audit.md`. Android parity audit (~85%)

### Changed

- **Android**
  - Vulkan clear color from black to CompositorBackground `0x0F1018`. Eliminates flashing during waypipe transitions
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
  - `docs/2026-ARCHITECTURE-STRUCTURE.md`. Force SSD, Waypipe platform notes
  - `docs/2026-LOGGING.md`. Logging format
  - `docs/2026-waypipe.md`. Platform overview (macOS OpenSSH, iOS libssh2, Android Dropbear)

### Fixed

- **Visual flashing on iOS and Android**. Surfaces flashing/disappearing on every keypress. Premature buffer release (old buffers released before frame rendered), iOS `_bufferCache` data race (concurrent read/write on `NSMutableDictionary`), and Android missing `FlushClients` after frame presentation
- **iOS waypipe + libssh2 freeze on first frame**. SSH bridge thread data starvation from `libssh2` internal buffering not signaling `ppoll`
- **`wp_presentation_feedback` events never sent**. `PresentationFeedback` objects were never marked committed, leaking indefinitely
- **`wl_output` retroactive enter**. Surfaces attached before client binds `wl_output` now receive `wl_surface.enter` retroactively
- **XdgOutput Persistence**. Fixed bug where `XdgOutput` resources were dropped prematurely by correctly storing them in the compositor state
- **Stale Window Mitigation**. Prevented orphaned black windows on macOS by deferring visibility until the first buffer commit and using `(0,0)` configuration for Force SSD windows
- **Multi-touch Input**. Fixed multi-touch event forwarding on iOS and Android; ensured `wl_seat` correctly advertises touch capabilities
- **Android Shadow Cropping**. Fixed incorrect shadow rendering by aligning push constant layouts between C renderer and SPIR-V shaders (extended to 48 bytes)
- **macOS Window Controls**. Fixed minimize-to-dock and resolved visual flashing during maximize/restore transitions
- **Buffer Scaling**. Synchronized NSWindow content area precisely with logical dimensions of committed Wayland buffers to eliminate stretching
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

- **Force SSD (Server-Side Decorations)**. Compositor can enforce native-style decorations regardless of client preference; force_ssd controls exposed in FFI
- **Native popups**. `WawonaMacOSPopup` and `WawonaPopupHost`; Wayland popup handling moved from NSMenu to NSPopover for improved layout and clipping
- **UI branding**. Text labels ('Ko-fi', 'GitHub Sponsors') on donation buttons; `WawonaImageLoader` for asset loading and caching; modern social and donation icons in gallery
- **Documentation**. Liquid Glass design principles; macOS implementation details

### Changed

- **Popup handling**. Refactored to NSPopover; `WawonaCompositorBridge` updated for new popup architecture
- **Waypipe**. Fixed path resolution for `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` for stable remote app connections; enhanced SSH config handling
- **Input**. Improved modifier key tracking for macOS clients
- **Preferences**. Cleaned up `WawonaPreferences` and `WawonaWaypipeRunner` for reliability

[0.2.2]: https://github.com/aspauldingcode/Wawona/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/aspauldingcode/Wawona/releases/tag/v0.2.1
