---
description: Per-target Wawona capability matrix (machines, windows, GPU, anowaW)
alwaysApply: true
---

# Wawona platform targets

Authority for feature gating across Apple + Android. Prefer this over older
docs when they conflict (e.g. watchOS is no longer remote-only).

## Full Apple support (non-negotiable)

The **entire Apple family** must be fully supported as first-class product
targets — not best-effort, not “ship iOS first and defer the rest”:

- **macOS**, **iOS**, **iPadOS**, **tvOS**, **watchOS**, **visionOS**

“Fully supported” means each target builds, archives, runs, and ships within
its row in the matrix below (native/remote/VM/GPU/windows as allowed). Do not
drop schemes from TestFlight/CI, leave link/deps broken, or treat a platform
as optional to unblock another. Fix the failing target (or its allowed
fallback) instead of removing it from the product surface.

## Capability matrix

| Capability | macOS | Android | iPadOS | visionOS | iOS (phone) | tvOS | watchOS |
|---|---|---|---|---|---|---|---|
| Native machines | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Remote (SSH/waypipe) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| VM / containers | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Multi-window (1 window per Wayland client) | ✅ | ✅ (if OS allows) | ✅ **required** | ✅ **required** | ⚠️ single primary | ❌ | ❌ |
| Nested compositors + bundled clients | ✅ | ✅ | ✅ | ✅ **macOS parity** | ✅ | ⚠️ limited | ⚠️ limited |
| Vulkan / OpenGL / ANGLE bundle | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Desktop + LockScreen replacement | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| anowaW windowing bridge | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

## Hard rules

0. **All Apple platforms** — keep every Apple target green and in scope.
   Temporary CI skips need an explicit fix follow-up; never “solve” breakage by
   permanently excluding macOS/iOS/iPadOS/tvOS/watchOS/visionOS.
1. **watchOS / tvOS** — native + remote only. Never ship VM/container machine
   types, engines, or UI on these targets. No bundled Vulkan/OpenGL/ANGLE/ICD.
2. **visionOS / iPadOS** — multi-window is mandatory: one host window/scene per
   Wayland client, same model as macOS. Android should match when the OS can
   host multiple app windows.
3. **visionOS = macOS product parity** for bundled software, nested
   compositors/clients, Vulkan/OpenGL, VMs, containers, and Machines UX
   (including Add New Machine). Do not leave visionOS on a reduced iOS-phone
   feature set.
4. **Desktop / LockScreen / anowaW** — exclusive to **macOS and Android**. Do
   not wire these into iOS, iPadOS, tvOS, watchOS, or visionOS.
5. **wwn-iland** — platforms without IOKit / without GL (watchOS, tvOS, …)
   need a non-IOKit, non-GL fallback path. See `wwn-iland-apple-fallback`.
6. **iland Mode B dylib** — `libwayland-mac.dylib` is **macOS desktop-host
   only** (`wawona-macos-desktop-host`). SIP-gated Desktop Replacement
   (`WWNSipStatus` + Settings Desktop). Never ship in store-safe
   `wawona-macos`, iOS family, or Android. Default present path is Mode A
   (`libiland_userland.a`). See `wawona-iland-mode-b-desktop` and
   `Wawona/docs/iland-mode-a-b-desktop.md`.
7. **SSH backend** — Apple mobile (iOS / iPadOS / tvOS / watchOS / visionOS)
   uses **libssh2 in-process only** (including `libwwn-ssh-cli` /
   `ssh_main` over libssh2). Never link or ship OpenSSH
   (`libssh-inprocess.a`) on those targets. **macOS** uses regular OpenSSH;
   **Android** uses OpenSSH portable (`libssh_bin.so` / keygen / scp).
   Remote/waypipe on Apple mobile goes through libssh2.
8. **Android Desktop / anowaW** — no SIP. Rootless (MediaProjection) vs
   Shizuku/root power mode; never Mode B dylib.
9. **Host window manager** — macOS = AppKit zoom/fullscreen/miniaturize.
   iOS/iPadOS/tvOS/visionOS/Android = **fill-primary**: maximize and
   fullscreen both configure to the host surface bounds and sync xdg
   state (no floating restore geometry). Minimize parks the session to
   Machines without terminating the client; **Focus** reveals the
   compositor again. watchOS stubs ignore WM requests. See
   `PlatformCapabilities.hostWindowManagerPolicy` and
   `docs/wslg-weston-desktop-map.md`.

## Implementation checkpoints

- Gate in `mobile-platform-deps.nix` variants, `xcodegen.nix` `OTHER_LDFLAGS`,
  Machines profile kinds, and platform UI — not ad-hoc `#ifdef` sprawl.
- tvOS/watchOS link flags must not pull `-framework IOKit`, ANGLE, MoltenVK,
  or Vulkan ICDs.
- When adding a Machines feature: classify it (native / remote / VM /
  container) and refuse it on targets that forbid that class.
