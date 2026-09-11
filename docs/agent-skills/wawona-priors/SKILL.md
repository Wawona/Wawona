---
name: wawona-priors
description: Index of Wawona agent knowledge already captured in Cursor rules and skills. Use at task start to pick the right rule/skill instead of rediscovering incidents. Pointers only. Do not duplicate rule bodies.
---

# Priors index (pointer only)

Open the named rule/skill. Do not copy the body here. After adding a rule or
skill, add one row. Capture flow: `wawona-learn`.

## Skills (this set)

| Skill | When |
|-------|------|
| `wawona-rag` | Any fact, repo, gate, patch, protocol |
| `wawona-write` | Editing Wawona / wwn-* software |
| `wawona-learn` | Durable finding this session |
| `wawona-caveman` | Token voice |
| `wawona-vphone-lab-recover` | Dead / stale vphone lab. Sock refused. Stuck SSH wait. |
| `wawona-ios-min-os` | iOS 11-27 min OS vs latest SDK. One ANGLE, one MoltenVK. Never downgrade SDK. |
| `wawona-gh` | GitHub issues/milestones/PRs/`gh run`. Shell + local `gh`. No GitHub MCP. |
| `wawona-nixpkgs2wasi` | Curated nixpkgs → WASI / WPM (`n2w`). Not Relay. Not an auto-mirror. |
| `wawona-relay-ios-hypervisor` | Mode B iOS Hypervisor.framework via Relay. Not QEMU HVF. |
| `wawona-relay` | Linux VMs / OCI / Mode A wasm. Mode A bench + PageTranslate. |

## Rules (hard gates)

| Rule | When |
|------|------|
| `wawona-mission` | Ambiguous product call |
| `wawona-context` | Stack priors + MCP tool map |
| `wawona-agent-learn` | This learn loop |
| `wawona-rust-first` | New Wawona-owned logic |
| `wawona-uniffi-domain` | Product domain vs `WWNCore*`; no JFFI fork |
| `wawona-nix-generated` | Generated files are Nix outputs; never git-track UniFFI |
| `wawona-repo-dag` | Flake input / registry key |
| `wawona-product-map` | Which product you are touching |
| `wawona-mode-a-b` / `wawona-ios-mode-b-channels` | Store vs TrollStore vs Sileo |
| `wawona-macos-mode-a` / `wawona-macos-no-appstore` | macOS in-window vs SIP |
| `wawona-iland-mode-b-desktop` | Desktop dylib / Take Over |
| `wawona-mode-b-watchdog-safety` | `watchdogd` / IOWatchdog |
| `wawona-compositor-backend` | Aqua nested vs Classic DRM |
| `wawona-nested-compositor-cursor` | Host cursor on niri/weston |
| `wawona-inprocess-cairo` | Nested weston teardown |
| `wawona-native-compositors` / `wawona-port-fidelity` | Weston/Niri; waypipe equivalence |
| `wawona-relay-wasm` | WASI Runtime on every target including watchOS |
| `wawona-relay` | One L3′ engine: Linux VMs, OCI-in-VM, Mode A wasm. Never QEMU/UTM |
| `wawona-relay-ios-hypervisor` | Mode B iOS/iPadOS Hypervisor.framework window (not HVF-via-qemu) |
| `wawona-linux-vms-relay-runtime` | NixOS VMs; Mode A/B engines; no QEMU/UTM |
| `wawona-platform-targets` | Four-state gates |
| `wawona-ios-min-os` | iOS 11.0 min OS; latest iPhoneOS SDK only; one ANGLE + one MoltenVK |
| `wawona-swinging-bridge` | Not Desktop, not LockScreen |
| `wawona-test-control` / `wawona-agent-device` | UI / vphone |
| `wawona-agent-device-multitouch` | Wayland client taps |
| `wawona-android-jbr` | Android Gradle / Studio JBR 21 |
| `wawona-local-before-ci` | Link/eval before push |
| `wawona-branch-workflow` | `development` vs `master` |
| `wawona-asc-swift-support` | ITMS-90426 |
| `wawona-release-assets` | Ship filenames |
| `wawona-no-em-dash` | Copy |
| `wawona-host-keymap-bridge` | Keyboard / IME. Bridge host TIS / KeyCharacterMap. No Settings layout. |
| `wawona-gh` | `gh` via Shell. No GitHub MCP. Authorship ban is not a `gh` ban. |
| `wawona-github-funding` / `wawona-discord-github-webhook` | New org repos |
| `wawona-vphone-*` / `wawona-trollstore-*` | Mode B lab / tipa |
| `repo-wawona-io-*` | Dual wasm/deb catalog host (`repo.wawona.io`) |

## Hard-won (do not re-learn)

- GitHub mutations are `gh` via Shell. No GitHub MCP. WebFetch GET cannot
  create issues or milestones. `Wawona/issues` is 404. Use `Wawona/Wawona`.
  A git-authorship ban is not a `gh` ban. Skill `wawona-gh`.
- `watchdogd` SIGTRAP + armed IOWatchdog = XNU panic. Path B ACK first.
- In-process weston: no `cairo_debug_reset_static_data`.
- Nested compositor draws its own cursor. Hide host overlay.
- iOS zsh: user `*.sh` is `source`'d in-process. `chmod` is in the uutils
  subset **and** `wwn_safe_subset` in `wawona-dispatch.c`. `uu_chmod` in
  `libwawona.a` is not enough if the C table omits `chmod` (then
  `command not found`). Mach-O/ELF still refused. Do not treat `./file.sh`
  as 2.5.2 native exec.   `usr/bin/zsh` and `usr/bin/sh` are 755 comment
  placeholders. Never source them. Bare `zsh`/`sh` is the current
  interpreter (not a nested zsh). `./file.sh`, `file.sh`, and a full
  path run the script (no `sh` prefix).   `./file.wasm` / `file.wasm` run
  Relay (no `wasm` prefix). Ctrl+C is VINTR (0x03 / SIGINT), not SIGTERM.
  iOS `copy:` must not turn it into Ctrl+Shift+C while the PTY is
  active. PTY sets an in-process interrupt flag, fails stdin/stdout
  `read`/`write` with `EIO` (uutils `write_all` retries `EINTR`), and
  calls `wawona_wasm_request_interrupt` (epoch + shut Wayland sockets).
  Do not `pthread_kill(SIGINT)` the zsh thread while wasm is on that
  stack. Dispatch returns 130; zsh `errflag` stops `while yes`. GUI wasm
  windows die with the socket (`client_disconnected`). Do not
  `commit_string` Ctrl+letter when a terminal owns the PTY. Steal Copy
  back with `copy:` → VINTR and `UIKeyCommand` while the terminal is
  active. `iscom` uses `wwn_inproc_runnable_path` so
  hashcmd sees scripts and wasm without Unix X_OK. Shell CLI proof needs
  Machines client `weston-terminal`, not nested `weston`. Simulator
  profiles: write `wawona.machineProfiles.v1` as JSON **NSData** in the
  container plist. `defaults write -string` loses to `dataForKey`.
- Global `DYLD_INSERT_LIBRARIES` kills Apple `arm64e` `/bin/*`. Prefix insert
  on the compositor exec only.
- macOS Aqua weston needs bundled `Resources/bin/weston` plus
  `libweston-13` / `lib/weston` / `share/weston`. Skinny `/Applications`
  and `WAWONA_SKIP_NIX_PREBUILD` Debug drop them. Restage from store
  `wawona-macos`. In-process `--backend=wayland` is the missing-bin
  fallback. niri Aqua is nested only. Knowledge:
  `macos-aqua-weston-bins.md`.
- `launchctl disable` WindowServer is sticky. Missed restore panics login.
- Wayland client taps need Multi-Touch. Touchpad "success" is often a no-op.
- Tipa: bump `CFBundleVersion`. Never install under `/var/jb/Applications` (179).
- Mode B TrollStore proof device is `vphone wawona-jb`. Do not wait for
  STARDUST. TXM MAP_JIT `EPERM` and Metal nil are proven on that guest.
  iOS VMs wait on Relay. Fail closed. No QEMU product path. Linux guests
  stay slim; display is Wayland / iland. Relay owns VMs, containers, and
  wasm. Mode A is store-compliant. Mode B may JIT the same Relay CPU.
  Official tipa embeds NixOS disks only after Relay frames. Do not fake
  MAP_JIT write+exec. `launchNiri` must return before `niri_main` when
  `MTLCreateSystemDefaultDevice` is nil. Do not spin ANGLE.
- Watch-bearing IPA needs `SwiftSupport/`. Watchless tvOS/visionOS must not.
- Prove `ld` locally. Do not burn Gate: products to discover duplicates.
- Relay Wasm ships on every target. Do not size-gate watchOS off.
- hello-wasi-gui (`wl_shm`) must run on Watch Machines Start. Transfer is not run.
- **nixpkgs2wasi** (`n2w`) is the curated nixpkgs → WASI/WPM producer. Not an
  auto-mirror. Not the interpreter (Relay). `n2w verify` is the runtime
  profile, not App Review. Native `wwn-foot` stays. North star is `foot.wasm`.
- Machines kind `wasm` is first-class on every target. Native still runs wasm
  via `wawona-wasm` / `wasm` / `wpm`. Do not strip `bundledAppID` on wasm load.
  Catalog is `repo.wawona.io/wasm/v1` only. Android Start uses JNI
  `nativeRunWasm`. Do not `-lwawona_wasm` until `libwawona_wasm.a` exists
  (current Android package is header-only).
- Port = substitute platform, not client. Waypipe Linux build is the reference.
- Graphics keys live in L1 `wwn-iland`. Never L0 toolchain. Never invert DAG.
- iOS min OS is **11.0** against the **latest** iPhoneOS SDK only (26 now, 27
  next). Never downgrade the SDK. One ANGLE, one MoltenVK, Wawona patches.
  App Store / TrollStore / Sileo share that min. ASC upload range is a
  separate investigation. Rule `wawona-ios-min-os`.
- iOS IOMFB ABI lives in L3′ `wwn-iomfb-rs`. L4 Mode B links `ios.nix` /
  `libwwn_iomfb.a`. Do not grow frozen `wwn-iland-iomfb`. L1 must not import
  the crate. GhidraVibe: `POST /load_program` body `{"file": guest Mach-O}`,
  then `GET /switch_program?program=/IOMobileFramebuffer`. `dyld_import_image`
  defaults to the host macOS DSC (wrong product).
- vphone `wawona-jb` is the IOMFB framebuffer proof. It is not MAP_JIT
  write+exec (TXM can set `CS_DEBUGGED` and still `EPERM`). VMs are Relay,
  never QEMU. Stuck lab: recover from process + sock connect, not
  `booted=true`. `nohup` relaunch. Never foreground `vm launch` in an
  agent Shell. Never `pkill -f vphone` to stop a waiter. Skill
  `wawona-vphone-lab-recover`.
- No real `/dev/dri` / kernel DRM. iland userspace only.
- Android Gradle JVM is JBR 21 (Studio embedded, or Linux `jetbrains.jdk-no-jcef-21`).
  Never export Nix OpenJDK into Android Studio.
- wwn-igetty / Mode B TTY / Doorman is the Linux framebuffer console, not a
  Machines profile. Machine Configuration must never list it.
- Host keymap is a bridge. Soft printable text is TI v3. Do not restore
  `charToLinuxKeycode` or a Settings layout picker. Nested weston/niri use
  the trimmed us/evdev tree, not a full `xkeyboard-config` dump.
- Weston wallpaper is honeycomb `data/background.png`. Never
  `pattern.png` (indexed-color; cairo fails; only solid color shows).
- Machines + Settings share one SwiftUI sidebar (`WawonaMainWindowView`)
  under `Sources/WawonaUI` on macOS / iOS / iPadOS / tvOS / visionOS.
  Product hosts embed `WawonaRootView` (iOS/tvOS/visionOS SceneDelegate
  + Vision shell). Apple TN3154:
  `NavigationSplitView` + `List(selection:)` + `.listStyle(.sidebar)`.
  iPhone is the same sidebar+toggle as iPad/macOS. Always inject
  regular width so the split never becomes a back-arrow stack.
  Portrait starts `.detailOnly` + `.prominentDetail`. Toolbar overlay
  search on iPad + `endEditing` on selection/column change. iPhone
  Machines uses the iOS 26 Messages/Mail bottom search: `.searchable` +
  `DefaultToolbarItem(kind: .search)` + `ToolbarSpacer` + bottomBar
  plus. No custom capsule. No 44/56pt +. Do not put `.searchable` on
  the phone split detail without the spacer. Watch stays the compact
  catalog (`WatchGlobalSettingsView`). Do not restore
  `WatchUIContractAdapters`. Section *order* is Rust `settings_catalog`.
  Swift `GlobalSettingsCatalog` is frozen Label/symbol + field visibility.
  ObjC `WWNPreferences` still builds leftover inventory rows. Do not add
  rows. UIKit settings sidebar is not compiled on Apple mobile. `WWNCore*`
  stays. Nix git flakes omit untracked new `.rs` **and** `.swift` until
  staged or in HEAD. `MachineProfileDomain.swift` / `MachineEditorDomain.swift`
  being untracked made `.#wawona-ios-app-sim` fail with `cannot find` those
  types.
- iPhone / tvOS client chrome is a Safari-style overview (#84), not
  iPad/visionOS scenes. `square.on.square` opens cards with Wayland
  previews. Swipe up (or `xmark`) closes. Last-tab close leaves the
  session (Machines). Do not restore `WWNClientTabStripView` or a top
  `TabView` chip strip. Apple has no public Safari tab-overview class.
- iOS Settings → Desktop appears only on Mode B tipa / Sileo
  (`profile-ios-mode-b`, `WWN_MODE_B`). Store IPA omits it. MCP
  `ios`/`desktop` stays forbidden (App Store row). The section is
  wwn-iland IOMFB + wwn-igetty, not SpringBoard in the store build.
- Darwin `rustPlatform.buildRustPackage` cargoBuildHook targets host
  Darwin even if `CARGO_BUILD_TARGET` is Android. Force `buildPhase`
  `--target aarch64-linux-android` and install only that `libwawona_wasm.a`.
  Same class: `cargoInstallPostBuildHook` copies
  `target/aarch64-apple-darwin/release-tmp` after a custom Apple-mobile
  `cargo rustc --target`. Set `dontCargoInstall = true`, skip
  `runHook postBuild`, and `installPhase` the cross
  `libwawona_relay.a` only. Never a host `.dylib` (watchOS ld prefers it).
- Android `.#wawona-android` must not `builtins.pathExists` the wasm
  archive at eval time. That misses an archive this same build is about
  to produce, so JNI stayed weak (`wawona_wasm_run not linked`). Always
  `-L` / `-lwawona_wasm` now that the Relay recipe ships the `.a`.
- Smithay `register_core_shell` must store `seat_state` **before**
  `set_keymap_from_string` / `set_data_device_focus`. Otherwise
  `SeatHandler::seat_state()` panics: seat must be initialized before
  dispatch. That killed iOS boot after the HostKeymapBridge cutover.
- `niri --session` unsets `WAYLAND_DISPLAY`. Nested niri is
  `NIRI_BACKEND=nested` only. Never pass `--session` on Aqua.
- visionOS VM/container kinds are **forbidden** (Swift +
  `wawona-platform-targets`). RAG markdown and `get_capability` (`_CAPS`
  in `wwn-mcp/src/wwn_mcp/contribute.py`) must both say forbidden. The
  Python table is what MCP returns even after a markdown reindex. User
  test of VMs on Vision is fail-closed, not a gate flip.
- Android `.#wawona-wasm-android` is Relay `registryFragment`
  (`import/wasm/.../android.nix`). Editing sibling `wwn-wasm` alone does
  not change the Wawona flake until `wwn-relay` is overridden or bumped.
- iOS/iPadOS OSK exclusive zone: per-machine
  `resizeDisplayForVirtualKeyboard` (inherit global, default on). When on,
  shrink `wl_output` **and** layout the present plate in the remaining
  rect above the IME (postmarketOS / Phosh). Hardware keyboard: no resize,
  no offset. Do not overlay UIKit selection handles on client glyphs.
- Upstream SwiftUI QoL is PR #168 (`swiftui-redesign`, merged 2026-09-05).
  `development` already contains it. No further open SwiftUI PRs.
- Host Copy/Paste is macOS Edit menu / hardware keyboard through
  `wl_data_device`. Multi-Touch long-press is `wl_touch`; the client
  toolkit owns handles and the Copy menu. Never overlay UIKit or
  Android selection handles or a host ActionMode on Wayland glyphs.
  `characterRangeAtPoint` stays nil.
- Multi-Touch is Smithay `TouchHandle` (`inject_touch_*`). Custom
  `TouchState` only tracks contact ids. One-finger drag is `wl_touch.motion`,
  never host `wl_pointer.axis`. Pointer + `BTN_LEFT` only for nested
  weston/niri chrome, or the off-by-default `TouchPointerEmulation` pref.
- `repo.wawona.io` is two catalogs. Wasm is App Store / Play only. Debs split:
  Sileo iOS jailbreak (rootless/rootful) vs Termux Android sideload (not
  jailbreak, not Play). APT is repo root. `where_to_edit` must not treat the
  hostname as the `wawona.io` website.

Canonical prose: `Wawona/docs/` and `wwn-mcp/knowledge/wawona/`.
