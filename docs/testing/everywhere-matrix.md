# Wawona "Everywhere" Runtime Matrix

Structured build verification (CI) plus manual functional smoke per platform.

For copy-pasteable exercise recipes (Waypipe/DELIVERER, native macOS Weston,
iOS on-device shell, agent-device replays), see [`commands.md`](./commands.md).

## Nix build targets (Phase 5A — CI)

| Platform | Flake target | Notes |
|----------|--------------|-------|
| macOS backend | `.#wawona-macos-backend` | Rust static lib + bundled Weston |
| macOS GL | `.#iland-gl-clients` | kmscube over iland + ANGLE |
| iOS device backend | `.#wawona-ios-backend` | |
| iOS sim backend | `.#wawona-ios-sim-backend` | |
| iPadOS sim backend | `.#wawona-ipados-sim-backend` | |
| tvOS sim backend | `.#wawona-tvos-sim-backend` | |
| visionOS sim backend | `.#wawona-visionos-sim-backend` | |
| watchOS sim backend | `.#wawona-watchos-sim-backend` | |
| Weston toytoolkit iOS | `.#weston-ios` | cairo/pango demo clients |
| zsh iOS (planned) | `.#zsh-ios` | App Store–compliant bundled shell — [ios-local-shell](../ios-local-shell/README.md) |
| wawona rootfs iOS (planned) | `.#wawona-rootfs-ios` | usr/bin/zsh + share for app bundle |
| wawona-pty spike (planned) | `.#wawona-pty-spike-ios` | Phase 0 device PTY gate — [ios-local-shell-spike.md](../ios-local-shell-spike.md) |
| Weston compositor iOS | `.#weston-compositor-ios` | nested compositor archive (Wayland/Pixman default) |
| Weston compositor iOS DRM | `.#weston-compositor-ios-drm` / `-sim` | iland DRM + GL renderer (CI validation) |
| Weston GL clients iOS | `.#weston-ios-gl` / `.#weston-ios-gl-sim` | `enableGlClients=true` |
| Android APK | `.#wawona-android` | NDK toytoolkit + compositor + JNI |
| Android compositor | `.#weston-compositor-android` | nested compositor archive |
| ANGLE iOS | `.#angle-ios` / `.#angle-ios-sim` | GLES over Metal |
| ANGLE Android | `.#angle-android` | |
| iland iOS | `.#iland-ios` / `.#iland-ios-sim` | GBM/EGL/DRM userland |
| kmscube iOS | `.#iland-gl-clients-ios` | in-process `kmscube_main` |
| SDL2_gfx demo (planned) | `.#testgfx-ios` / `-macos` / `-android` | in-process `testgfx_main`; software/`wl_shm` first — [#107](https://github.com/Wawona/Wawona/issues/107) |
| Linux reference | `pkgs.weston` (nixpkgs) | baseline |

CI runs `.github/scripts/verify-wayland-profile-smoke.py` (host-scoped `nix eval`). Use `--build` for compile verification on the matching host.

## Developer refresh workflow (Phase 5C)

After changing native dependencies:

```bash
# Apple mobile / macOS
nix run .#wawona-ios-project          # regenerate Xcode project
nix build .#wawona-ios-sim-backend    # refresh libwawona.a paths
nix build .#weston-ios                # refresh toytoolkit archives
nix build .#weston-compositor-ios     # refresh nested compositor archive
nix build .#weston-compositor-ios-drm # refresh DRM+GL compositor variant (CI)
nix build .#iland-gl-clients-ios      # refresh kmscube archive

# Android
nix build .#wawona-android
nix build .#weston-compositor-android
# Then sync Gradle in Android Studio
```

## Automated verification (2026-06-16)

| Check | Status | Command / notes |
|-------|--------|-----------------|
| Profile smoke (eval) | pass | `python3 .github/scripts/verify-wayland-profile-smoke.py` |
| Runtime ownership strict | pass | `python3 .github/scripts/verify-wayland-runtime-ownership.py --strict` |
| `weston-compositor-ios` build | pass | `nix build .#weston-compositor-ios --no-link` |
| `weston-compositor-ios-drm` build | pass | `nix build .#weston-compositor-ios-drm --no-link` |
| Weston iOS patch anchors | pass | `python3 .github/scripts/verify-weston-ios-patches.py` |
| `wawona-android` build | pass | `nix build .#wawona-android --no-link` |
| `iland-gl-clients-ios` build | pass | `nix build .#iland-gl-clients-ios --no-link` |
| Rust integration (Smithay path) | pending CI | `cargo test --tests` (harness uses production registration) |

## Manual functional checklist (Phase 5B)

Run on each simulator/emulator or device. Mark pass/fail with date + build attr.

### All mobile (iOS / iPadOS / tvOS / visionOS / watchOS)

- [ ] Boot Wawona app
- [ ] Launch `weston-simple-shm` — SHM buffer visible
- [ ] Launch `weston-flower` — cairo animation visible
- [ ] Launch `weston-terminal` — **Phase 1:** real cairo `terminal.c`; **today:** SHM stub (`mobile-weston-terminal.c`); **Phase 2:** bundled zsh PTY — see [ios-local-shell](../ios-local-shell/README.md)
- [ ] Keyboard: evdev `KEY_A` → client receives correct keysym (protocol test: `test_keyboard_key_a_keysym`)
- [ ] Launch nested compositor (`weston` / Settings) — child `wayland-N` socket; demo client through nested Weston
- [ ] Nested Weston (default): Settings → **Wayland (Pixman)** — panel + dark background visible within ~2s; no `terminal.png` / cursor errors in log
- [ ] Nested Weston (optional): Settings → **iland DRM (GL)** — Metal overlay via `WWNIlandPresenter`; log shows GL renderer (not Pixman)
- [ ] kmscube smoke (Settings) — IOSurface/Metal overlay updates before enabling DRM Weston
- [ ] waypipe session (where SSH + libssh2 available)

### macOS

- [ ] All mobile checks against nested clients
- [ ] Launch nested Weston compositor (subprocess) — child socket
- [ ] Launch `kmscube` / `weston-simple-egl` — GL frame via iland + ANGLE
- [ ] Live resize + configure ack — no SHM buffer exhaustion (protocol test: `test_configure_serial_backlog_without_ack`)
- [ ] waypipe over SSH

### Android

- [ ] Boot app on emulator/device
- [ ] `weston-simple-shm` visible
- [ ] `weston-flower` / demo client from Settings
- [ ] `weston-terminal` mobile client
- [ ] Keyboard regression
- [ ] Settings "Enable Native Weston" — nested compositor (not flower stub); demo client through child display

### iOS / iPadOS — local shell (Phase 2+, device required)

- [ ] Phase 0 spike report complete — [ios-local-shell-spike.md](../ios-local-shell-spike.md)
- [ ] `echo hello` in bundled zsh via weston-terminal
- [ ] `.zsh_history` in Application Support
- [ ] Session stop reaps shell — no fd leak
- [ ] Spawn rejects `/bin/sh` (compliance unit test or internal)

### watchOS

- [ ] Local zsh **not** offered — stub / redirect only — [WATCHOS-SCOPE.md](../ios-local-shell/WATCHOS-SCOPE.md)

### Linux (reference)

- [ ] `nix build .#wawona-linux` or distro package
- [ ] Weston clients against host compositor

### GL mobile

- [ ] Launch `kmscube` from Machines — GL frame via iland + ANGLE (iOS Simulator: ANGLE dylibs embedded at Xcode link)
- [ ] `weston-simple-egl` when linked from `.#weston-ios-gl` archive

### Deferred (explicit)

- Android iland / kmscube / `weston-simple-egl` — requires AHardwareBuffer GBM rewrite

## Automated test-ID mapping (ci-docs-matrix)

Each manual checklist item above maps to an automated verifier. As coverage
lands, the manual item is retired in favor of the ID. IDs are Rust test fns
(`cargo test`), smoke scripts, or agent-device replays.

| Manual item | Automated ID | Kind | Status |
|-------------|--------------|------|--------|
| Boot Wawona app / client connects | `test_client_connection`, `test_compositor_protocol` | rust | done |
| Registry advertises core globals | `test_protocol_matrix_core_globals_advertised` | rust | done |
| Advertisement honesty per profile | `test_protocol_matrix_profile_honesty` | rust | done |
| Protocol manifest not drifted | `test_generate_protocol_status_manifest` (CI `cargo-test-linux`) | rust+ci | done |
| `weston-simple-shm` SHM buffer visible | `scripts/ci-macos-compat-smoke.sh` (macOS), `test_shm_protocol` | script+rust | done (macOS) |
| `weston-flower` / demo client | `scripts/ci-macos-compat-smoke.sh` | script | done (macOS) |
| Keyboard `KEY_A` → keysym | `test_keyboard_key_a_keysym` | rust | done |
| Live resize + configure ack, no SHM exhaustion | `test_configure_serial_backlog_without_ack` | rust | done |
| Window maximize/fullscreen transitions | `test_window_maximized_transition`, `test_window_fullscreen_transition` | rust | done |
| Subsurface sync commit | `test_subsurface_sync_commit` | rust | done |
| Pointer lock / relative motion | `test_pointer_lock`, `test_relative_pointer_motion` | rust | done |
| dmabuf feedback resolves, no raw formats | `test_protocol_matrix_dmabuf_feedback_resolves` | rust | done |
| iOS boot + launch client (UI) | `.agent-device/wawona-ios-smoke.ad` | agent-device | done |
| Android boot + launch client (UI) | `.agent-device/wawona-android-smoke.ad` | agent-device | done |
| macOS present-frame per bundled client | `scripts/ci-macos-compat-smoke.sh` | script | done |
| Nested Weston child socket + demo client | (capability lane) | script | pending (`ci-capability-lane`) |
| waypipe session | (capability lane) | script | pending |
| UI parity vs golden baselines | `ui_parity_diff.py` + agent-device batch | ci | pending (`ci-l3-parity-agentdevice`) |
| Graphics conformance (GL/Vulkan) | `dependencies/tests/graphics-validate.nix` | nix | pending (`ci-graphics-cts`) |
| Apple UI flows | XCUITest target | xcuitest | pending (`ci-l3-apple-xcuitest`) |
| Android UI flows | Compose UI Test (`testTag`) | espresso | pending (`ci-l3-android-espresso`) |

Run locally: `nix develop -c cargo test --lib --tests`;
`./scripts/ci-macos-compat-smoke.sh`; `agent-device replay .agent-device/<name>.ad`.

