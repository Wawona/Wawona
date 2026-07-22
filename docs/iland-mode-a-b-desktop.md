# iland Mode A / Mode B and Desktop Replacement

Canonical description of how Wawona uses **wwn-iland** for graphics present and
macOS Desktop Replacement. When this conflicts with older docs or comments,
**this file wins** (also mirrored in `.cursor/rules/wawona-iland-mode-b-desktop.mdc`
and `AGENTS.md`).

Upstream inspiration: [CoreBedtime/iland](https://github.com/CoreBedtime/iland).
Wawona packaging: [wwn-iland](https://github.com/Wawona/wwn-iland).

## Summary

- **Mode A** is the default, App Store–safe path: static `libiland_userland.a`,
  in-window DRM/KMS/EGL/GBM over IOSurface + ANGLE, present via
  `iland_drm_set_present_callback` into Wawona’s Metal layer.
- **Mode B** is optional, **macOS-only**, **not** App Store safe: ship
  `libwayland-mac.dylib`, load with `DYLD_INSERT_LIBRARIES` + Dobby (same model
  as CoreBedtime), replace SkyLight/WindowServer via `framebufferd`. Requires
  SIP debugging restrictions off (or SIP fully disabled) and root.
- **Android** has no SIP. Desktop Replacement uses the HOME/launcher role;
  anowaW is rootless (MediaProjection) vs power (Shizuku/root).

## Decision tree

```text
platform?
  iOS / iPadOS / visionOS     → Mode A only
  tvOS / watchOS              → Mode A stub (no ANGLE / IOKit)
  Android                     → anowaW power? → Shizuku/root : rootless baseline
  macOS
    SIP allows Mode B?        (Disabled | PartiallyDisabled)
      no  → Mode A (ignore Desktop toggle; clear if stale)
      yes → DesktopReplacementEnabled?
            no  → Mode A
            yes → Mode B (DYLD_INSERT bundled dylib + DRM weston)
```

SIP detection: `WWNSipStatus` → `csrutil status` text parse (playground
`checkSipStatus` port). Partial disable = line
`Debugging Restrictions: disabled` (typical after
`csrutil enable --without debug`). Do not use CSR_* APIs.

## Artifacts and packages

| Package / recipe | Mode | Notes |
|------------------|------|--------|
| `wwn-iland` `iland` (`macos.nix`, `ios.nix`, …) | A | `libiland_userland.a` |
| `wwn-iland` `iland-baremetal` (`macos-baremetal.nix`) | B | `libwayland-mac.dylib` + embedded daemons |
| `.#wawona-macos` | A only | Product / store-safe shaped; **must not** contain Mode B dylib |
| `.#wawona-macos-desktop-host` | A + B dylib | Developer ID / desktop-host; dylib at `Contents/Library/Wawona/iland/libwayland-mac.dylib` |
| iOS / Android apps | A only | Never ship Mode B dylib |

Cargo features for desktop-host Rust backend: `profile-desktop-host` +
`iland-baremetal` (gated in `src/lib.rs`). Mobile and store-safe builds must
not enable `iland-baremetal`.

## Runtime code anchors (macOS)

| Concern | Location |
|---------|----------|
| SIP classify | `src/platform/macos/ui/Settings/WWNSipStatus.{h,m}` |
| Desktop prefs UI + hard enforce | `WWNPreferences.m` (Desktop section), keys in `WWNPreferencesManager` |
| Mode B engage / disengage | `WWNDesktopReplacementController.{h,m}` |
| Connect / lockscreen handoff | `WWNMachineSessionBridge.m` |
| Mode A present | `WWNIlandPresenter.m` + `iland_present.h` |
| Bundle verify | `.github/scripts/verify-iland-mode-b-bundle.sh` |

Prefs (macOS `NSUserDefaults`):

- `DesktopReplacementEnabled`
- `DesktopReplacementMachineId`
- `LockscreenReplacementEnabled` / `LockscreenReplacementMachineId`
- `AnowaWEnabled`

## Android (no SIP)

| Tier | Pref / condition | Behavior |
|------|------------------|----------|
| Rootless / baseline | Power off, or Shizuku/root unavailable | Own-app VD + consented MediaProjection; waypipe-rs mirror without privileged inject |
| Power | `wawona.anowaW.powerMode` + `AnowawPowerController` available | Trusted VD, any app, privileged input + waypipe-rs |

Auto-fallback power → baseline is required when privilege is missing. See
`DesktopReplacement.kt`, `AnowawSession.kt`, Settings Desktop / App Bridge copy.

## Agent / Cursor rules

- Workspace: `.cursor/rules/wawona-iland-mode-b-desktop.mdc` (alwaysApply)
- Wawona repo: `Wawona/.cursor/rules/wawona-iland-mode-b-desktop.mdc`
- Platform matrix: `.cursor/rules/wawona-platform-targets.mdc` (Desktop /
  LockScreen / anowaW = macOS + Android only)
- tvOS/watchOS GL stubs: `.cursor/rules/wwn-iland-apple-fallback.mdc`
- Agent entry: `Wawona/AGENTS.md`, `wwn-iland/AGENTS.md`
