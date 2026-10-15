---
name: wawona-ios-sim-runtime
description: Dogfood Wawona on iOS Simulator. Build tip app, inject profiles, Start via SIMCTL_CHILD_WWN_AUTO_START_MACHINE when agent-device XCUITest is broken. XDG_RUNTIME_DIR and Main.swift gates. Use for iOS Machines, wasm, waypipe, ssh, weston runtime proof.
---

# iOS Simulator runtime dogfood

Pointer: rule `wawona-ios-app-entry`. Link contract: `wawona-ios-link-contract`.
UI control preference stays `wawona-agent-device` when AX works.
Flake rename cascade: skill `wawona-flake-consumer-rename`.

## Build ladder (use smallest cell first)

| Goal | Attr / path | Notes |
|------|-------------|--------|
| Rust backend only | `.#wawona-ios-sim-backend` | Proves crate2nix + nativeDeps |
| Full store-shaped app | `.#wawona-ios-app-sim` | Embeds **Watch** companion. Watch Ld red ≠ phone UI broken |
| Phone UI tip (lab) | `WAWONA_BACKEND_OUT=…` + `xcodebuild -scheme Wawona-iOS` | After backend green; see traps below |

```bash
cd ~/Wawona/Wawona
nix build .#wawona-ios-sim-backend --out-link /tmp/wawona-ios-sim-backend -L
# full app when Watch also links:
nix build .#wawona-ios-app-sim --out-link result-ios-sim-tip -L
```

### Agent nix log hygiene

Do **not** pipe long `nix build` through `tee … | tail`. Pipeline exit can
be 0 while nix failed; terminal file shows only the last lines. Prefer
`nix build -L 2>&1 | tee /tmp/build.log` (no `tail`), then `rg error:
/tmp/build.log` / `nix log <drv>`.

## nativeDeps: waypipe video needs ffmpeg (2026-10-12)

Root `Cargo.toml` enables waypipe features `lz4` / `zstd` / `video`.
crate2nix builds `waypipe-ffmpeg-wrapper`. That build.rs **unwraps**
`pkg-config libavutil`.

Symptom:

```text
Package libavutil was not found …
PKG_CONFIG_PATH contains …/jq-…/lib/pkgconfig
```

Fix: `dependencies/wawona/mobile-platform-deps.nix` must pass
`ffmpeg = buildFn "ffmpeg" { inherit simulator; };` for Apple-mobile
variants that pull waypipe (same idea as `wwn-waypipe` `ios.nix`).
`rust-backend-c2n.nix` only sets `PKG_CONFIG_PATH` when
`nativeDeps ? ffmpeg`.

Prove: `nix build .#wawona-ios-sim-backend` shows
`-L native=…/ffmpeg-ios/lib` on the waypipe/wawona rustc line.

## Watch companion vs phone proof

`wawona-ios-app-sim` builds Watch into the iPhone scheme. Failure:

```text
Ld …/WawonaWatch.app/WawonaWatch …
Undefined symbols: _wl_display_create, _xdg_wm_base_interface, …
referenced from WWNMiniWaylandServer.o
```

That is a **Watch** link debt. Do not park machine-editor / Machines UI
proof on it. Phone path:

1. Green `.#wawona-ios-sim-backend`
2. `export WAWONA_BACKEND_OUT=/tmp/wawona-ios-sim-backend`
3. `xcodebuild -scheme Wawona-iOS …` (or XcodeBuildMCP) with tip Sources
4. Install + agent-device

Stale local `Wawona.xcodeproj` may still `-force_load` `libfoot.a` /
`libfuzzel.a` after optional-software unbundle. Prebuild does **not**
build those archives. Provide ios-sim stubs exporting `foot_main` /
`fuzzel_main`, or regenerate xcodegen from tip Nix (skill
`wawona-optional-software`).

## Install tip app

```bash
rm -rf /tmp/Wawona-ios-tip.app
ditto result-ios-sim-tip/Wawona.app /tmp/Wawona-ios-tip.app   # or Xcode DerivedData app
chmod -R u+w /tmp/Wawona-ios-tip.app && xattr -cr /tmp/Wawona-ios-tip.app
xcrun simctl install booted /tmp/Wawona-ios-tip.app
```

Prove entry: `nm -gU …/Wawona | rg 'T _main'` and `gbm_es2_demo_main` present,
no archive C `_main` as sole life. Socket after launch:
`/tmp/wawona_sim_$UID_<udid8>/wayland-0` (per-UDID; avoids multi-sim bind clash).

## Machine editor half-sheet (UI proof)

Tip Sources: `backport.machineEditorSheet` / `editorSheet` (medium→large,
not `fullScreenCover`). After Add Machine:

- AX: `Sheet Grabber`, `dismiss popup`, title `Add Machine Profile`
- Screenshot: sheet ~half height, Machines chrome still visible above
- Artifact path: `.agent-device/test-artifacts/machine-editor-half-sheet.png`

## Profiles into the guest (hard)

**Do not** only rewrite the container `Library/Preferences/*.plist` on disk.
`cfprefsd` ignores that; `defaults read` still says the key is missing.

```bash
xcrun simctl spawn booted defaults import com.aspauldingcode.Wawona /tmp/wawona-sim-prefs.plist
xcrun simctl spawn booted defaults read com.aspauldingcode.Wawona WWNMachineProfiles
```

`wawona.machineProfiles.v1` must be JSON **NSData**, not a string (priors:
`defaults write -string` loses to `dataForKey`).

Native Shell sessions: `type` native + `settingsOverrides.NativeShellKind` in
`wayland` | `wasm` | `waypipe` | `terminal`. Domain blob may use `wasm` /
`ssh_waypipe` for rust decode.

## Start without AX (Xcode 26 gap)

As of 2026-10-08, agent-device iOS snapshot/press often fails with
`xcodebuild build-for-testing failed`. Host `osascript` clicks do **not**
reach guest buttons.

Lab hook (SceneDelegate):

```bash
# Env into guest. NOT argv. simctl launch -e FOO=bar becomes argv "-e" "FOO=bar".
SIMCTL_CHILD_WWN_AUTO_START_MACHINE=e2e-wasm-hello \
  xcrun simctl launch --stdout=/tmp/w.out --stderr=/tmp/w.err booted com.aspauldingcode.Wawona
```

Caveat: AUTO_START must mount the session Metal surface before connect
(`WWNShowSessionSurfaceNotification`). Connected badge may stay 0.

If Start fails with `Host compositor failed to start`, check
`XDG_RUNTIME_DIR` (rule `wawona-ios-app-entry`).

## Host Start: socket path + wasm (macOS too)

`WWNCoreIsRunning` alone is not enough. Heal:

```bash
pkill -9 -f '/Applications/Wawona.app/' || true
rm -f /tmp/wawona-$UID/wayland-* /tmp/wawona-$UID/*.lock
open -n /Applications/Wawona.app
```

## Evidence

```bash
xcrun simctl io booted screenshot …/ios-tip-….png
# or agent-device screenshot --session …
rg -i 'AUTO_START|Compositor started|fail|wasm|waypipe' /tmp/w.err
ls /tmp/wawona_sim_$UID/wayland-0
```

## Hard rejects

❌ `simctl launch … -e VAR=val` expecting env (it is argv)  
❌ Raw plist rewrite without `defaults import`  
❌ Claiming Start green from Connected=0 alone after AUTO_START  
❌ Parking iOS runtime / half-sheet proof on red Watch companion Ld  
❌ Ignoring `libavutil` / empty `nativeDeps.ffmpeg` when waypipe video is on  
❌ `nix build … | tee | tail` as the only status signal  
❌ Forgetting Main.swift / gbm `_main` / XDG gates (see rule)  
