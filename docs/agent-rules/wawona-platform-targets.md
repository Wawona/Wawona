# Wawona platform targets

Authority for feature gating across Apple + Android. Prefer this over older
docs when they conflict (e.g. watchOS is no longer remote-only).

## Full Apple support (non-negotiable)

The **entire Apple family** must be fully supported as first-class product
targets. Not best-effort, not “ship iOS first and defer the rest”:

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
| VM / containers | ⏳ planned | ⏳ planned | ⏳ planned | ❌ | ⏳ planned | ❌ | ❌ |
| Multi-window (1 window per Wayland client) | ✅ | ✅ (if OS allows) | ✅ **required** | ✅ **required** | ⚠️ single primary | ❌ | ❌ |
| Nested compositors + bundled clients | ✅ | ✅ | ✅ | ✅ **macOS parity** | ✅ | ⚠️ limited | ⚠️ limited |
| Vulkan / OpenGL / ANGLE bundle | ✅ | ✅ | ✅ | ✅ | ✅ | ⏳ planned | ⛔ blocked |
| Desktop + LockScreen replacement | ⏳ planned | ⏳ planned | ❌ App Store | ❌ | ❌ App Store | ❌ | ❌ |
| Wawona Swinging Bridge | ⏳ Mode A+B | ⏳ Mode A+B | ❌ App Store (Mode B only) | ❌ | ❌ App Store (Mode B only) | ❌ | ❌ |

### Legend. The four gate states

Never collapse these into "unsupported". Each has a different correct response,
and mixing them is how unfinished work turns into a permanent exclusion.

| Mark | State | Meaning | What to do |
|---|---|---|---|
| ✅ | available | Shipping | Keep it green |
| ⏳ | **planned** | Our work is unfinished; platform allows it | Finish it; never remove the target |
| ⛔ | **blocked** | We want it; no public platform API exists | Re-check on SDK updates; never use private API |
| ❌ | **forbidden** | Product/store policy | Never enable; refuse features of that class |

Mirrored in code by `CapabilityGate` in
`Wawona/Sources/WawonaModel/PlatformCapabilities.swift`. A gate change belongs
in both places.

**Linux** (not in the Apple/Android columns): native + remote ✅; VM/containers
⏳ planned; Desktop/LockScreen ❌; Wawona Swinging Bridge ❌.

**iOS and iPadOS are the same** for Desktop/LockScreen and Wawona Swinging Bridge (store Mode A
vs `repo.wawona.io` Mode B / jailbreak Desktop). Do not special-case iPadOS as
forbidden while iPhone is planned for those features.

**Desktop / LockScreen vs Wawona Swinging Bridge vs local shell vs VMs (do not conflate):**

- **Desktop + LockScreen**. Host DE / greeter. macOS + Android ⏳; **iOS and
  iPadOS** jailbreak path via `repo.wawona.io` (website only); App Store builds
  ❌ and must never mention jailbreak. Not Linux. Not tvOS/watchOS/visionOS.
- **Wawona Swinging Bridge**. MacOS/Android (and iOS Mode B) apps → Wayland
  (+ waypipe to Linux). See `wawona-swinging-bridge`. Not Desktop/LockScreen.
- **On-device shell**. Bundled **zsh** + Weston terminal (native port path).
  Not a VM and not a container. Separate from `virtual_machine` / `container`
  machine kinds.
- **VM / containers**. Machines GUI kinds `virtual_machine` / `container`,
  configured per-machine. ⏳ on **macOS, iOS, iPadOS, Android, Linux**. ❌ on
  **tvOS, watchOS, visionOS**. Design **Mode A and Mode B** together
  (`wawona-mode-a-b`, `docs/mode-a-b.md`); never ship Mode B to App Store/Play.
  Engines (planned):
  - **iOS / iPadOS Mode A (store):** UTM-SE-class **jitless** interpreter
    (`wwn-vms` TCTI); containers = OCI pull + container-in-VM on that engine.
  - **iOS / iPadOS Mode B (Sileo Mode B IPA from `repo.wawona.io`):** JIT-enabled
    UTM/QEMU for VMs **and** containers; unsandboxed shell + host APT. Auto-
    package Mode B IPA on the repo. **absent** from store IPA.
  - **Sideload / TrollStore:** website may document JIT; App Store copy must not.
  - **macOS:** Apple Containerization (`Containerization.framework`) + VMs via
    `Virtualization.framework`, bundled into Wawona. The Apple `container` CLI
    and Containerization.framework are **macOS-only** (`appleContainerizationGate`);
    never evaluate that engine on iOS/Android/Linux.
  - **Android / Linux:** containers and VMs through Wawona machine profiles
    (engines TBD in `wwn-vms` / `wwn-containers`); Play = Mode A, root = Mode B.

## Hard rules

0. **All Apple platforms**. Keep every Apple target green and in scope.
   Temporary CI skips need an explicit follow-up; never “solve” breakage by
   permanently excluding macOS/iOS/iPadOS/tvOS/watchOS/visionOS.
1. **watchOS / tvOS machines**. Native + remote only. VM/container machine
   types, engines, and UI are **❌ forbidden** on these targets: that is policy,
   not a gap. GPU is a *separate* question, and the two platforms differ -
   verified against the 26.5 SDKs, re-verify rather than trusting memory:
   - **tvOS GPU is ⏳ planned.** `AppleTVOS26.5.sdk` ships `Metal.framework`,
     `MetalKit`, `MetalFX`, MPS/MPSGraph, **and** `OpenGLES.framework`, and
     `CAMetalLayer` is available since tvOS 9. So Wayland GL **and** Vulkan
     **and** iland DRM/KMS/GBM are all legal public-API work on tvOS. The only
     reason they are off is that we have not done them. This is the **last**
     phase of the graphics stack, after every other target is PROPER. Gate:
     `WWN_TVOS_GPU=1` in `verify-iland-graphics-bundle.sh`. Vulkan is the short
     path (MoltenVK supports tvOS 14.5+); GLES is the long one (ANGLE has no
     maintained Chromium GN tvOS target. Same wall as visionOS. Though tvOS's
     own `OpenGLES.framework` may serve instead). The Vulkan **loader** does not
     work on tvOS: dispatch straight into the ICD, as `WWN_VULKAN_LIBRARY`
     already does. Never drop tvOS from the graphics roadmap.
   - **watchOS GPU is ⛔ blocked, not forbidden and not deferred.** `WatchOS26.5.sdk`
     ships **no `Metal.framework` at all** (device *or* simulator), no
     `OpenGLES.framework`, and `CAMetalLayer` is annotated
     `API_UNAVAILABLE(watchos)`. Only `QuartzCore`, `SceneKit`, and `SpriteKit`
     are present. ANGLE and MoltenVK both terminate in Metal, so neither has a
     floor to stand on, and iland has no present target. We *want* this; Apple
     currently offers nothing to build it from. Re-check on each SDK bump by
     listing `$(xcrun --sdk watchos --show-sdk-path)/System/Library/Frameworks`.
     Do **not** "fix" it with private Metal or by abusing SpriteKit/SceneKit as a
     shader backdoor. That forfeits store compliance, which is the whole point
     of Mode A. Until then watchOS stays on the SHM/CPU present path
     (`wwn-iland-apple-fallback`) and the verifier enforces GPU absence
     unconditionally.
2. **visionOS / iPadOS**. Multi-window is mandatory: one host window/scene per
   Wayland client, same model as macOS. Android should match when the OS can
   host multiple app windows.
3. **visionOS ≈ macOS product parity** for bundled software, nested
   compositors/clients, Vulkan/OpenGL, and Machines UX (including Add New
   Machine). **except VM/container machine kinds**, which are **❌ forbidden**
   on visionOS (same class as tvOS/watchOS). Do not leave visionOS on a reduced
   iOS-phone feature set for everything else.
4. **Desktop / LockScreen replacement**. **macOS + Android** (⏳ planned),
   plus **iOS and iPadOS** jailbreak tweaks documented only on the website /
   `repo.wawona.io` (Sileo). **Forbidden** on Linux and on App Store builds of
   iOS/iPadOS (and all of tvOS/watchOS/visionOS). Machine profiles for
   Desktop/LockScreen: **native ports only**. macOS engage path: partial SIP
   (system debugging) + `.dylib`. Android: Default Home App + LockScreen APIs -
   **no root required, no fallback tier required**. Never wire Desktop/LockScreen
   UI into App Store Apple-mobile builds; never mention jailbreak in those
   binaries.
5. **wwn-iland**. Platforms without IOKit / without GL (watchOS, tvOS, …)
   need a non-IOKit, non-GL fallback path. See `wwn-iland-apple-fallback`.
6. **iland Mode B dylib**. `libwayland-mac.dylib` is **macOS desktop-host
   only** (`wawona-macos-desktop-host`). SIP-gated Desktop/LockScreen
   Replacement (`WWNSipStatus` + Settings Desktop). Never ship in store-safe
   `wawona-macos`, iOS family, or Android. Default present path is Mode A
   (`libiland_userland.a`). See `wawona-iland-mode-b-desktop` and
   `Wawona/docs/iland-mode-a-b-desktop.md`. This dylib is **not** Wawona Swinging Bridge.
7. **SSH backend**. Apple mobile (iOS / iPadOS / tvOS / watchOS / visionOS)
   uses **libssh2 in-process only** (including `libwwn-ssh-cli` /
   `ssh_main` over libssh2). Never link or ship OpenSSH
   (`libssh-inprocess.a`) on those targets. **macOS** uses regular OpenSSH;
   **Android** uses OpenSSH portable (`libssh_bin.so` / keygen / scp).
   Remote/waypipe on Apple mobile goes through libssh2.
8. **Wawona Swinging Bridge** (formerly anowaW). Cocoa/Android/(future UIKit)
   apps as Wayland clients, including **waypipe-rs** to a Linux compositor.
   **macOS + Android:** ⏳ Mode A + Mode B. **iOS/iPadOS:** Mode B only
   (`repo.wawona.io` / jailbreak). **forbidden** in the App Store IPA.
   **Not** Desktop/LockScreen. **Not** MediaProjection-as-desktop.
   Full rule: `wawona-swinging-bridge`.
9. **VM / containers**. ⏳ planned for macOS, iOS, iPadOS, Android, Linux via
   Machines profiles. ❌ on tvOS, watchOS, visionOS. Do not document as shipping
   until gates flip. Local shell is not a substitute for a VM.
10. **Host window manager**. MacOS = AppKit zoom/fullscreen/miniaturize.
    iOS/iPadOS/tvOS/visionOS/Android = **fill-primary**: maximize and
    fullscreen both configure to the host surface bounds and sync xdg
    state (no floating restore geometry). Minimize parks the session to
    Machines without terminating the client; **Focus** reveals the
    compositor again. watchOS stubs ignore WM requests. See
    `PlatformCapabilities.hostWindowManagerPolicy` and
    `docs/wslg-weston-desktop-map.md`.
11. **Weston + Niri bundles**. Both real compositors must compile natively and
    ship inside every macOS/iOS/iPadOS/tvOS/watchOS/visionOS and Android Wawona
    app. Fake entry points and compatibility stubs do not count. tvOS/watchOS
    must use their allowed non-GL fallback and must not gain forbidden GPU
    bundles. Fix each target's recipe/link/package/runtime path; never exclude
    either compositor to make the matrix green.
12. **Runtime-only graphics**. Iland DRM/KMS/GBM is userland emulation.
    Wawona code must never open real `/dev/dri` or `/dev/kgsl` nodes, forward
    real DRM/KMS/KGSL ioctls, ship kernel code, or require kernel patches.
    Mode B `baremetal` is a legacy package name, not kernel access. Android
    direct Turnip/KGSL is forbidden; use system Vulkan/Metal or SwiftShader.

## Implementation checkpoints

- Gate in `mobile-platform-deps.nix` variants, `xcodegen.nix` `OTHER_LDFLAGS`,
  Machines profile kinds, and platform UI. Not ad-hoc `#ifdef` sprawl.
- tvOS/watchOS link flags must not pull `-framework IOKit`, ANGLE, MoltenVK,
  or Vulkan ICDs. Until the deferred tvOS GPU phase, which flips only tvOS and
  only behind `WWN_TVOS_GPU=1`. watchOS keeps this checkpoint permanently.
- When adding a Machines feature: classify it (native / remote / VM /
  container) and refuse it on targets that forbid that class.
