# iland Mode A / Mode B and Desktop Replacement

Canonical description of how Wawona uses **wwn-iland** for graphics present and
macOS Desktop Replacement. When this conflicts with older docs or comments,
**this file wins** (also mirrored in `.cursor/rules/wawona-iland-mode-b-desktop.mdc`
and `AGENTS.md`).

Upstream inspiration: [CoreBedtime/iland](https://github.com/CoreBedtime/iland).
Wawona packaging: [wwn-iland](https://github.com/Wawona/wwn-iland).
Stack architecture and toolkit contracts:
[`iland-graphics-stack.md`](iland-graphics-stack.md). Repository ownership:
[`wwn-repo-dag.md`](wwn-repo-dag.md).

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

## Store / distribution compliance (per target)

macOS is **third-party distribution** (Developer ID / notarized), **not** Mac
App Store — never gated on Mac App Store review rules (see
`wawona-macos-no-appstore.mdc`). Everything that ships to a store must be
**Mode A–shaped end-to-end**.

| Target | Distribution | Compliance bar for graphics / Desktop |
|--------|--------------|----------------------------------------|
| **iOS** | App Store | Mode A only; static `libiland_userland`; in-app KMS/DRM; no `DYLD_INSERT`, no private SkyLight/IOKit abuse, no Mode B dylib; SSH = libssh2 only |
| **iPadOS** | App Store | Same + multi-window (1 host window per Wayland client) |
| **visionOS** | App Store | Same Mode A / macOS-product GLES+Vulkan parity via store-safe stack (MVK/ANGLE); no Mode B; multi-window required |
| **tvOS** | App Store | Mode A **software only** — no ANGLE/MVK/KK/Vulkan ICD, no IOKit, no GPU DRM clients |
| **watchOS** | App Store | Same software policy as tvOS |
| **Android** | Google Play | Mode A: in-app KMS/DRM + consented MediaProjection / own VD; Home Desktop **without root**; optional power/root is sideload/opt-in, never Play-required |
| **macOS** | **3rd-party** (not MAS) | Mode A default (SIP OK). Mode B desktop-host OK under SIP partial\|off; never contaminate iOS/Android store artifacts |

### Store-compliance checklist (assert per store build)

1. **No Mode B artifacts** in App Store IPA / Play AAB/APK (no
   `libwayland-mac.dylib`, no inject, no `framebufferd`).
2. **No SIP disablement / root** required for any store-listed feature
   (including kmscube, waypipe, Android Home Desktop).
3. **Private API / entitlement firewall:** Mode A present = public
   Metal/UIKit/AppKit/Surface + userland DRM shims only.
4. **tvOS/watchOS:** software Mode A only — never "fix" compliance by shipping
   GPU stacks.
5. **visionOS/iPadOS:** store Mode A meets multi-window + product GLES/Vulkan
   expectations without Mode B.
6. **Shared Nix/xcodegen:** gate Mode B + desktop-host dylibs so store schemes
   cannot link them; `verify-iland-mode-b-bundle.sh` is the evidence.
7. **macOS 3rd-party:** may ship desktop-host flavor separately; never reuse
   its packaging for iOS/Android store builds.

Leak vectors to watch (from graphics-stack epic R7): manual packaging copying
the dylib; sharing iOS GPU post-build phases onto tv/watch; adding IOKit
ldflags to tv/watch; linking OpenSSH into mobile `OTHER_LDFLAGS`; shared
Settings sections without `#if` platform guards; enabling `desktopHost` on the
wrong flake attr.

## Portable KMS abstraction + IOSurface (Mode A)

`wwn-iland` is a **portable KMS-like display stack**, not "IOSurface replaces
GBM." On Apple, a backend **emulates the KMS object model** (connector, encoder,
CRTC, plane, framebuffer); **GBM and libdrm stay the client-facing ABI** and map
into that allocator/present path. IOSurface is the shared **FB / BO backing**;
page-flip triggers the present callback into the Metal layer.

| Concept | Linux-shaped ABI (clients keep) | Apple backend meaning |
|---------|----------------------------------|------------------------|
| Device | `drmOpen` / card fd | iland device → window/display session |
| Connector + mode | `drmModeGetConnector` / modes | Display or window size + Hz (must reflect real scene size) |
| CRTC | `drmModeGetCrtc` / page-flip | Metal present cadence |
| Framebuffer | `drmModeAddFB*` | IOSurface-backed FB id (must honor fourcc) |
| GBM BO | `gbm_bo_*` | Same IOSurface (unified allocator, not a second buffer world) |
| Page-flip | `drmModePageFlip` | present callback → CAMetalLayer drawable / host import |

All of these objects are runtime-only userland emulation. Even the historical
Mode B `baremetal` package name does not authorize kernel DRM/KMS: virtual
`/dev/dri` opens and ioctls terminate inside iland, while framebufferd returns
a Mach present ACK from its host-vsync path. No Wawona kernel module, kernel
patch, real DRM node, or direct KGSL path is permitted.

Minimal layers: GLES → **ANGLE → Metal**; Vulkan → **MoltenVK or KosmicKrisp →
Metal**. IOSurface is the shared backing for FB/dmabuf zero-copy (#86), not a
third GL stack. Per-target IOSurface reality + current gaps (#58 card-open, #94
format/size) are tracked in [`iland-graphics-progress.md`](iland-graphics-progress.md).

## Agent / Cursor rules

- Workspace: `.cursor/rules/wawona-iland-mode-b-desktop.mdc` (alwaysApply)
- Wawona repo: `Wawona/.cursor/rules/wawona-iland-mode-b-desktop.mdc`
- Repo DAG: `.cursor/rules/wawona-repo-dag.mdc` (+ Wawona repo mirror);
  canonical `docs/wwn-repo-dag.md`
- Platform matrix: `.cursor/rules/wawona-platform-targets.mdc` (Desktop /
  LockScreen / anowaW = macOS + Android only)
- tvOS/watchOS GL stubs: `.cursor/rules/wwn-iland-apple-fallback.mdc`
- Agent entry: `Wawona/AGENTS.md`, `wwn-iland/AGENTS.md`
- Graphics-stack progress + capability matrix:
  [`iland-graphics-progress.md`](iland-graphics-progress.md); epic #122
