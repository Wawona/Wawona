---
name: wawona-ios-sim-runtime
description: Dogfood Wawona on iOS Simulator. Build tip app, inject profiles, Start via SIMCTL_CHILD_WWN_AUTO_START_MACHINE when agent-device XCUITest is broken. XDG_RUNTIME_DIR and Main.swift gates. Use for iOS Machines, wasm, waypipe, ssh, weston runtime proof.
---

# iOS Simulator runtime dogfood

Pointer: rule `wawona-ios-app-entry`. Link contract: `wawona-ios-link-contract`.
UI control preference stays `wawona-agent-device` when AX works.

## Build + install

```bash
cd ~/Wawona/Wawona
nix build .#wawona-ios-app-sim --out-link result-ios-sim-tip -j 1
rm -rf /tmp/Wawona-ios-tip.app
ditto result-ios-sim-tip/Wawona.app /tmp/Wawona-ios-tip.app
chmod -R u+w /tmp/Wawona-ios-tip.app && xattr -cr /tmp/Wawona-ios-tip.app
xcrun simctl install booted /tmp/Wawona-ios-tip.app
```

Prove entry: `nm -gU …/Wawona | rg 'T _main'` and `gbm_es2_demo_main` present,
no archive C `_main` as sole life. Socket after launch:
`/tmp/wawona_sim_$UID/wayland-0`.

## Profiles into the guest (hard)

**Do not** only rewrite the container `Library/Preferences/*.plist` on disk.
`cfprefsd` ignores that; `defaults read` still says the key is missing.

```bash
# Build a small plist with WWNMachineProfiles + wawona.machineProfiles.v1 (NSData JSON)
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
# Expect: WWN_AUTO_START_MACHINE: started e2e-wasm-hello
# And compositor: Compositor started successfully
```

Also useful: weston `e2e-weston-terminal-default`, waypipe `e2e-ssh-waypipe`.

Caveat: AUTO_START calls `WWNMachineSessionBridge.connect` directly. The
Machines **Connected** badge (ViewModel) may stay 0. Trust stderr / socket /
session logs, not the pill alone.

If Start fails with `Host compositor failed to start`, check
`XDG_RUNTIME_DIR` (rule `wawona-ios-app-entry`).

## Evidence

```bash
xcrun simctl io booted screenshot …/ios-tip-….png
rg -i 'AUTO_START|Compositor started|fail|wasm|waypipe' /tmp/w.err
ls /tmp/wawona_sim_$UID/wayland-0
```

## Hard rejects

❌ `simctl launch … -e VAR=val` expecting env (it is argv)  
❌ Raw plist rewrite without `defaults import`  
❌ Claiming Start green from Connected=0 alone after AUTO_START  
❌ Parking iOS runtime proof on agent-device when build-for-testing is red  
❌ Forgetting Main.swift / gbm `_main` / XDG gates (see rule)  
