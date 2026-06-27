# Wawona "Everywhere" Runtime Matrix

Structured build verification (CI) plus manual functional smoke per platform.

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
| Weston compositor iOS | `.#weston-compositor-ios` | nested compositor archive |
| Weston GL clients iOS | `.#weston-ios-gl` / `.#weston-ios-gl-sim` | `enableGlClients=true` |
| Android APK | `.#wawona-android` | NDK toytoolkit + compositor + JNI |
| Android compositor | `.#weston-compositor-android` | nested compositor archive |
| ANGLE iOS | `.#angle-ios` / `.#angle-ios-sim` | GLES over Metal |
| ANGLE Android | `.#angle-android` | |
| iland iOS | `.#iland-ios` / `.#iland-ios-sim` | GBM/EGL/DRM userland |
| kmscube iOS | `.#iland-gl-clients-ios` | in-process `kmscube_main` |
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
| `wawona-android` build | pass | `nix build .#wawona-android --no-link` |
| `iland-gl-clients-ios` build | pass | `nix build .#iland-gl-clients-ios --no-link` |
| Rust integration (Smithay path) | pending CI | `cargo test --tests` (harness uses production registration) |

## Manual functional checklist (Phase 5B)

Run on each simulator/emulator or device. Mark pass/fail with date + build attr.

### All mobile (iOS / iPadOS / tvOS / visionOS / watchOS)

- [ ] Boot Wawona app
- [ ] Launch `weston-simple-shm` — SHM buffer visible
- [ ] Launch `weston-flower` — cairo animation visible
- [ ] Launch `weston-terminal` — mobile terminal client (not PTY)
- [ ] Keyboard: evdev `KEY_A` → client receives correct keysym (protocol test: `test_keyboard_key_a_keysym`)
- [ ] Launch nested compositor (`weston` / Settings) — child `wayland-N` socket; demo client through nested Weston
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

### Linux (reference)

- [ ] `nix build .#wawona-linux` or distro package
- [ ] Weston clients against host compositor

### GL mobile

- [ ] Launch `kmscube` from Machines — GL frame via iland + ANGLE (iOS Simulator: ANGLE dylibs embedded at Xcode link)
- [ ] `weston-simple-egl` when linked from `.#weston-ios-gl` archive

### Deferred (explicit)

- Android iland / kmscube / `weston-simple-egl` — requires AHardwareBuffer GBM rewrite
