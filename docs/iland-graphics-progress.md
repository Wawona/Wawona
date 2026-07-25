# wwn-iland graphics stack — living progress + capability matrix

Source-of-truth progress tracker for the **wwn-iland unified graphics stack**
epic. Twin of the Cursor plan `wwn-iland graphics stack — prioritized phased
plan` and of GitHub epic **#122** (`Wawona/Wawona`). Updated every inner-loop
iteration (grades + repos touched + waypipe zero-copy impact).

- Plan: Cursor plan `wwn-iland graphics stack` (dual-loop, P0→P4).
- Canonical stack: [`iland-graphics-stack.md`](iland-graphics-stack.md).
- Canonical Mode A/B: [`iland-mode-a-b-desktop.md`](iland-mode-a-b-desktop.md).
- Repo layering: [`wwn-repo-dag.md`](wwn-repo-dag.md) (enforced).
- Drivers cheat-sheet: [`drivers-how-to/`](drivers-how-to/README.md).
- Related issues: #58 (kmscube `/dev/dri/card0` open), #86 (IOSurface dmabuf
  zero-copy), #87 (macOS Mode B SkyLight replacement), #94 (purple tint +
  edge-to-edge sizing), #110 (nested-client launch umbrella).

> **Phase status:** P0 closed. P1 Mode A acceptance and P2 native graphics
> ownership are **in progress**. No target is PROPER until product build +
> authoritative client + runtime evidence pass.

---

## Status grades (locked vocabulary)

| Grade | Meaning |
|-------|---------|
| **MISSING** | No code path / not shipped on target |
| **STUB** | Symbol/pref exists; returns empty/ENOSYS/ENOENT/no-op — clients cannot succeed |
| **WIRED** | Code path connected; known broken or unproven (issue linked) |
| **FUCKUP** | Intended behavior wrong in practice (wrong present/format, ICD ignored, pixman on GPU host, …) — cite bug |
| **PROPER** | Acceptance client green on that target+mode; evidence logged (build + Agent-Device) |

"Compiles" alone ≠ PROPER. STUB / WIRED / FUCKUP are all **not done**.

---

## Living capability matrix (P0 baseline — honest)

One grade per cell. DRM (open/resources) and KMS (modeset/flip/present) tracked
separately. Evidence is `file:line` in the local tree or an issue.

| Target | Mode | OpenGL / GLES | Vulkan | DRM | KMS | Desktop Repl. DRM/KMS |
|--------|------|---------------|--------|-----|-----|------------------------|
| macOS 3rd-party product | A | **PROPER** (stock kmscube: `gl.display` non-null, no duplicate-ANGLE warning, 600+ presents at ~40 fps, clean GL/GBM/DRM teardown — 2026-07-25 log below) | **PROPER** (both ICDs serve under selection: `libMoltenVK.dylib` / `libvulkan_kosmickrisp.dylib`, each logged `(selected)` not fallback, each rendering through iland KMS/GBM to `rc=0`) | **PROPER** (stock kmscube opens the virtual card, enumerates connector 1 / CRTC 1, picks a mode, and reaches `init gbm success` entirely in userland — no real device open) | FUCKUP → fix in tree (flips are continuous and the fourcc/size contract holds, but cadence juddered at ~35 fps on a 60 Hz display and host resize stretched the fixed-mode framebuffer; texture cache + presented-handler pacing + letterbox landed, re-verification pending) | N/A (Desktop tweak = desktop-host B) |
| macOS desktop-host | A (toggle off) | WIRED (same as product) | WIRED | WIRED | WIRED | N/A |
| macOS desktop-host | B (SIP partial + toggle) | WIRED | WIRED | WIRED (Dobby `open`/`ioctl` hooks virtual calls) | WIRED (framebufferd host-vsync present + Mach ACK drives page-flip event; runtime proof pending) | WIRED (engage path real, not CI-proven; #87) |
| iOS / iPadOS / visionOS | A | WIRED (ANGLE direct-to-Metal present path; target runtime/tint evidence remains pending) | WIRED (pinned store-safe MoltenVK 1.4.1 static slice is L1-owned and force-linked; vkcube runtime proof pending) | WIRED (Mode-A open shim landed — `iland_drm_open_card` + `iland_drm_open_compat.h`; #58 open path fixed, device render unproven) | WIRED (preferred-mode host wiring + fourcc contract landed; scene/multi-window runtime evidence pending) | N/A |
| tvOS | A soft | MISSING (deferred — SDK has GLES/Metal, ANGLE lacks a tvOS GN target) | MISSING (deferred — MoltenVK supports tvOS 14.5+; gated `WWN_TVOS_GPU=1`) | N/A | N/A | N/A |
| watchOS | A soft | N/A (no Metal/GLES in SDK; empty `libiland_userland.a`; correct) | N/A (no Metal backend to target) | N/A | N/A | N/A |
| Android Play / Home Desktop | A (no root) | WIRED (`OpenGLDriver` is consumed at connect; ANGLE remains the bundled direct backend) | split: `system` WIRED (loader owns ANativeWindow WSI) / `swiftshader` **FUCKUP** — selecting it cannot create an instance at all (see the Android WSI trace below); no direct KGSL path either way | WIRED (userland `drm_linux.c`; GBM storage is AHardwareBuffer-backed) | WIRED (present callback; zero-copy import acceptance pending) | WIRED (Home = rootless Mode A launcher/VD; no dylib) |
| Android power | B (Shizuku/root WM) | WIRED | WIRED (same runtime-only drivers) | WIRED | WIRED | WIRED (window/display policy only; no root framebuffer or kernel-device access) |

**Never** mark Desktop-Replacement DRM/KMS PROPER on macOS **product Mode A**
(Desktop tweak is desktop-host Mode B only), or require root to mark Android
Home Desktop / App Store cells PROPER.

---

## P1 progress log

**2026-07-24 P2 graphics-driver ownership loop:** `wwn-iland` now owns
ANGLE, SwiftShader, and MoltenVK registry entries. Apple-mobile MoltenVK uses
the pinned upstream 1.4.1 all-platform release (`sha256:
2c498bf8c98b88ba1e84c1f153403d4c1a8490c122d9e2a3df238b25d4e10557`),
selects the exact iOS/xrOS device or simulator static slice, and records
source/slice/private-API metadata. Wawona force-links it only on
iOS/iPadOS/visionOS; tvOS/watchOS registry variants remain null. Android now
splits Vulkan by role. The host renderer always uses Android's system
`libvulkan.so` for loader-owned `vkCreateAndroidSurfaceKHR` and ANativeWindow
swapchains. A `swiftshader` machine selection identifies the bundled portable
offscreen client ICD (`WWN_SWIFTSHADER_LIBRARY`) for iland KMS/GBM clients; it
is never direct-loaded as the host surface implementation. Android vkcube now
uses an isolated per-client dispatch table to direct-load that library without
changing the process-global host loader. Device evidence remains an acceptance
gap, so the grade stays WIRED.

**2026-07-25 non-hermetic link flags (root cause of recurring Apple stubs):**
`xcodegen.nix` gated ten link-flag helpers (MoltenVK, foot, fastfetch, neovim,
niri, cairo-gobject, fuzzel, ssh-cli, weston-simple-shm) on
`builtins.pathExists <output>/lib/lib*.a`. That predicate reports whether the
archive is *already realised in the store*, not whether the platform provides
it, and evaluation happens before realisation. A target that had never built
niri therefore dropped `-force_load libniri.a` while still emitting the global
`-Wl,-u,_niri_main`, so the link failed with an undefined `_niri_main` — and
because the archive was then never referenced, it was never built, making the
condition permanently false. iOS/iPadOS/visionOS only linked niri because
`niri-ios` is a top-level flake package that had been realised earlier; tvOS had
not. `niriLdflags` now keys off `deps.niri != null` alone, so a null dep is the
only way to opt out and a missing archive fails loudly. The remaining nine sites
carry the same hazard and should follow.

Two further Apple link gaps surfaced from the same area: the tvOS **simulator**
`OTHER_LDFLAGS` block omitted `niriLdflags` entirely (the device block had it),
and neither tvOS nor watchOS linked `-lwayland-egl`, which niri's `wayland-egl`
crate needs for `wl_egl_window_*` even on those software-only surfaces.

**2026-07-25 Apple present-ACK link fix:** the Mach present-ACK added for Mode B
vsync is implemented only in `drm.c`, which is built for the macOS host. Apple
mobile and Android compile `drm_linux.c` against IPC stub translation units, so
`mode_b_flip_worker` referenced an undefined `drm_receive_present_ack` and
`Wawona.app` failed to link for iOS/iPadOS/visionOS. The stub sets now declare
and define the ACK (returning failure), and the call site is unconditional
again: off the macOS Mode B host the flip completes unsynchronised instead of
failing the build. Verified by rebuilding every `iland-*` archive, all of which
now resolve the symbol.

**2026-07-25 bundle policy verified against real artifacts:** running
`verify-iland-graphics-bundle.sh` on built bundles corrected two wrong
assumptions. First, iOS ships ANGLE as **embedded dynamic frameworks**
(`Frameworks/libEGL.dylib`, `libGLESv2.framework`) while visionOS links the
static archives, so "drivers must be static" was wrong; the check now requires
drivers to *resolve inside the bundle* (`@rpath`/`@executable_path`, or a system
path), which is the actual store-safety property. Second, matching with
`strings | grep -q` under `set -o pipefail` reported failure on success, because
`grep -q` exits early and `strings` dies on SIGPIPE. Results: `ios` passes
(MoltenVK in the main executable, ANGLE in the embedded framework), `macos`
passes with MoltenVK + KosmicKrisp and no Mode B dylib, and `macos-desktop`
passes with the Mode B dylib at
`Contents/Library/Wawona/iland/libwayland-mac.dylib`.

**2026-07-25 Apple package matrix proof:** all sixteen Apple graphics packages
(`iland-{macos,ios,ios-sim,ipados,tvos,watchos,visionos,visionos-sim}`,
`iland-baremetal-macos`, `moltenvk-{macos,ios,ios-sim,visionos,visionos-sim}`,
`kosmickrisp-macos`, `angle-{ios,ios-sim}`) build from `wwn-iland`. Slice audit
of the built archives:

| Package | `LC_BUILD_VERSION` | Contents |
|---|---|---|
| `iland-macos` | 1 (macOS) | 93 EGL/GBM/DRM entry points |
| `iland-ios` / `iland-ipados` | 2 (iOS) | 93 entry points |
| `iland-ios-sim` | 7 (iOS sim) | 93 entry points |
| `iland-visionos` | 11 (xrOS) | 93 entry points |
| `iland-visionos-sim` | 12 (xrOS sim) | 93 entry points |
| `iland-tvos` / `iland-watchos` | none | 8-byte empty archive, 0 GPU symbols |
| `moltenvk-ios` / `-ios-sim` | 2 / 7 | `vkCreateInstance` present |
| `moltenvk-visionos` / `-sim` | 11 / 12 | `vkCreateInstance` present |
| `moltenvk-macos` | macOS dylib | `libMoltenVK.dylib` + ICD manifest |
| `kosmickrisp-macos` | macOS dylib | `libvulkan_kosmickrisp.dylib` + aarch64 ICD |
| `iland-baremetal-macos` | macOS dylib | `libwayland-mac.dylib`, `libwwn-iland.dylib` |

The empty tvOS/watchOS archives are the enforced no-GPU contract, not a
regression. `verify-iland-graphics-bundle.sh` now asserts this positively for
iOS/iPadOS/visionOS (statically linked MoltenVK + ANGLE markers, and no dynamic
`libvulkan`/`libEGL`/`libGLESv2` link) and negatively for tvOS/watchOS
(no statically embedded MoltenVK/ANGLE/SwiftShader).

**2026-07-25 all five Apple mobile bundles pass, and the driver markers are now
precise:** the first run of the negative tvOS/watchOS check failed tvOS on both
`MoltenVK` and `ANGLE (`, and both were false positives from shared code that
ships on every target regardless of driver. The bare name `MoltenVK` appears in
the ICD path literal `vulkan/icd.d/MoltenVK_icd.json` used by driver selection,
and in Rust `ash` enum-name metadata such as `IOSSurfaceCreateFlagsMVK`;
`ANGLE (` appears inside kmscube's UI copy, "Spinning GL cube via iland + ANGLE
(userland KMS)". Neither implies a linked driver: tvOS and watchOS define **0**
symbols matching `_vk[A-Z]`, `_egl[A-Z]`, or `_angle_egl`, against 430 Vulkan
entry points on iOS.

The markers are therefore narrowed to things only a real driver emits:
`MoltenVK version` (the driver's own banner) as a substring, and `ANGLE (` as a
**whole-string** match, since ANGLE's renderer string is that literal on its own
while the kmscube sentence merely contains it. The negative check additionally
counts defined Vulkan/EGL entry points, which is the definitive signal and
cannot be tripped by prose. Result: `ios`, `ipados`, `visionos` (MoltenVK +
ANGLE present and resolving inside the bundle) and `tvos`, `watchos` (no driver
markers, 0 entry points) all pass, alongside `macos` and `macos-desktop`.

**2026-07-25 vkcube reaches the Apple app for the first time:** `vkcube-*`
built for every Apple GPU target and had correct slices (macOS `platform 1`,
iOS `2`, iOS-sim `7`, xrOS `11`, xrOS-sim `12`, each exporting `_vkcube_main`),
but **no Apple bundle linked it** — `iland-gl-ldflags.nix` only knew about
kmscube, and no Wawona dep requested `vkcube`. Wired end to end:
`iland-gl-ldflags` now emits the same undefined-symbol archive pull for
`opengl_cube_main` and `vkcube_main`; `mobile-platform-deps.nix` adds `vkcube`
under `allowGpu` (so tv/watch never see it, matching wwn-kmscube having no
tv/watch recipe); and the presenters gained
`-launchNestedIlandGpuClient:width:height:`, a table keyed on the Machines
catalog id, with `-launchNestedKmscubeWithWidth:height:` kept as a wrapper.
`opengl-cube` is in the ldflags generator but out of the Apple presenter table
until wwn-kmscube grows an Apple recipe for it, so nothing weak-imports a
symbol no target defines.

macOS needed one more change. It selects MoltenVK or KosmicKrisp at runtime and
bundles both as ICD dylibs in `Contents/Frameworks` with **no Vulkan loader**,
so linking `vk*` directly left 61 undefined symbols at app link. The Android
runtime dispatch table was generalised (`vulkan_dispatch_android.h` →
`vulkan_dispatch.h`, gated on `__ANDROID__ || TARGET_OS_OSX`) and keyed on a new
`WWN_VULKAN_LIBRARY` that `WWNSettings_ApplyGraphicsDriverSelection` resolves to
the selected ICD; it falls back to `vk_icdGetInstanceProcAddr` for Mesa-derived
ICDs like KosmicKrisp that export only the negotiated name. `libvkcube.a` for
macOS now has 0 undefined Vulkan symbols; Apple mobile keeps its 61 and resolves
them against static MoltenVK.

Result: `_vkcube_main` is defined in macOS, iOS, iPadOS, and visionOS binaries
and absent from tvOS/watchOS, which still define 0 Vulkan/EGL entry points. All
seven Apple bundles pass `verify-iland-graphics-bundle.sh`. Runtime Start of the
`vkcube` machine is the remaining acceptance step.

**2026-07-25 macOS Mode A kmscube: duplicate ANGLE image crash (FUCKUP → fixed):**
macOS had no way to reach a bundled client without UI automation, which needs an
Accessibility grant CI does not have, so the macOS Mode A cells had never been
exercised at runtime. `WAWONA_AUTO_CLIENT=<clientId>` now starts a bundled
client shortly after launch (mirroring watchOS's `WAWONA_WATCH_AUTO_CLIENT`),
and it suppresses the modal welcome sheet, which would otherwise swallow the
start. The first run with it exposed a real crash:

```
[MAIN] WAWONA_AUTO_CLIENT=kmscube — starting bundled client
[BRIDGE] Created iland presentation host 1680x1050 for nested GL client
[KMSCUBE] kmscube enter (iland DRM present)
### Display [0]: CRTC = 1, Connector = 1, format = 0x34325258
### Primary display => ConnectorId = 1, Resolution = 3360x1828
DRM Format is DRM_FORMAT_XRGB8888
init gbm success!
gl.display = 0x0
objc: Class ANGLESwapCGLLayer is implemented in both
  Wawona.app/Contents/Frameworks/libGLESv2.dylib and
  /nix/store/…-angle-7258/lib/libGLESv2.dylib …
CRITICAL: WWN crashed. Emergency cleanup...
```

So DRM open, connector/CRTC enumeration, mode selection, and GBM init all
succeed on macOS — the failure is one layer later, at `eglGetDisplay`. iland's
EGL shim `dlopen`ed ANGLE by absolute Nix store path on macOS (the recipe
rewrote the shim's MacPorts `/opt/local` default), while the app bundle links
its own copy in `Contents/Frameworks`. Two ANGLE images in one process means two
definitions of ANGLE's Objective-C classes, and the client dies.

The shim now resolves macOS ANGLE the way it already resolved it on iOS: a
candidate list, `@rpath/libEGL.dylib` first so dyld returns the image the host
already mapped, then the bundle-relative paths, with the build-time absolute
path last for unbundled CLI use and for Mode B injection into processes that
carry no Wawona rpath. The Android `libEGL.so`/`libGLESv2.so` arms moved into
`egl.c` behind `#elif defined(__ANDROID__)`; they had been patched in by
`android.nix` anchored on the very macOS lines this fix changes, so the Android
recipe would have failed loudly on an anchor that no longer existed.

With one ANGLE image the objc warning disappeared but kmscube still died, now
with `EXC_BAD_ACCESS address=0x0` and `PC = 0`, called straight from
`kmscube_main`. Disassembly named the culprit: `bl eglInitialize` jumped to
address 0. The chain is:

1. This machine's saved preference is `OpenGLDriver=none` (and
   `VulkanDriver=none`), which is a **supported** mode, not a misconfiguration —
   the plan calls it an intentional efficiency mode.
2. `WWNSettings_ApplyGraphicsDriverSelection` therefore exports
   `WWN_OPENGL_DRIVER=none` and `WWN_DISABLE_EGL=1`.
3. `graphics_policy_allows_angle()` refuses, so `load_angle()` returns -1 and
   every `real_egl*` pointer stays NULL.
4. `eglGetDisplay` handles that correctly and returns `EGL_NO_DISPLAY`, but
   kmscube does not check, and the shim's `eglInitialize` called
   `real_eglInitialize` unconditionally.

So a preference could crash the host app, on any target including store builds.
Both halves are fixed. The shim gained a `WWN_REQUIRE_ANGLE(fail_value)` guard on
every entry point that dispatches to `real_egl*`, so ANGLE-absent now means clean
EGL failure rather than a NULL jump. Wawona gained
`WWNGpuClientRefusalReason`, which refuses a GPU-family client when the platform
has no GPU stack *or* the resolved driver is `None`, naming the setting in the
log — replacing two copies of a tvOS/watchOS-only check that let the
driver-preference case through.

Repos touched: `wwn-iland` (EGL shim + macOS/Android recipes), `Wawona`
(autostart hook, present logging, GPU refusal). waypipe zero-copy impact: none —
buffer export and dmabuf paths are untouched; this is which ANGLE image the
process binds and whether EGL fails politely.

**2026-07-25 vkcube runtime acceptance on the iOS simulator:** Start on a
Default Machine with `bundledAppID=vkcube` runs the whole Mode A path in
process. From the launch console:

```
[BRIDGE] Created iland presentation host 402x778 for nested GL client
[VKCUBE] started in-process vkcube 402x778 via iland
[VKCUBE] vkcube enter (iland DRM present)
[mvk-info] MoltenVK version 1.4.1, supporting Vulkan version 1.4.334.
[mvk-info] Created VkDevice to run on GPU Apple iOS simulator GPU
vkcube: rendering 1206x2334 via Vulkan -> iland KMS/GBM
[KMSCUBE] iland present #0 IOSurface 1206x2334 fcc=0x42475241 drawable=1206x2334
...
[VKCUBE] vkcube exit rc=0
```

So the bundled static MoltenVK creates a device, krh/vkcube renders through the
iland virtual DRM (fd 42), and the resulting IOSurfaces reach the Metal
presenter at the right size and fourcc (`0x42475241`, `DRM_FORMAT_ARGB8888`).

The long run with `WAWONA_VKCUBE_FRAMES=100000` looked at first like it stalled
after five frames, and five is also the buffer count, which made a page-flip
recycling bug the obvious suspect. It was not one: `s_presentCount < 5` in
`WWNIlandPresenter` gated the *log line*, not the present, so the frame counter
simply stopped reporting while presentation continued. The presenter now logs
the first five frames and then every 300th, so a genuine stall is
distinguishable from a quiet one. macOS had no present log at all and now emits
the same line, which is what makes the golden `(width, height, fourcc, frame
id)` contract in the I/O verify table checkable on that target.

The waypipe ICD bind is intact on the same bundle: `MoltenVK_icd.json` and
`kosmickrisp_icd.json` ship in `Contents/Resources/vulkan/icd.d/` with
`library_path` `../../../Frameworks/lib{MoltenVK,vulkan_kosmickrisp}.dylib`,
which resolves to the dylibs the bundle actually carries.
`WWNSettings_ApplyGraphicsDriverSelection` points `VK_DRIVER_FILES` at the
manifest for the selected driver, and `WWNWaypipeRunner` falls back to
`--no-gpu` SHM transport when that variable is unset, so a missing ICD degrades
transport instead of producing empty IOSurface frames.

**2026-07-25 visionOS ANGLE slice acceptance:** `angle-visionos` and
`angle-visionos-sim` build from the pinned Chromium/ANGLE sources plus the
checked-in `0001-chromium-build-add-xros-target.patch`, so no GN tree is
patched ad hoc at build time. Slice proof on the built archives: device
`libEGL.a`/`libGLESv2.a` are arm64 with `LC_BUILD_VERSION platform 11` (xrOS)
and the simulator archives are arm64 with `platform 12` (xrOS simulator). Both
export the 21 `_angle_egl*` renamed entry points, and the remaining 94
unrenamed ANGLE EGL symbols have **zero** overlap with the 18 EGL entry points
`libiland_userland.a` exports, so no client EGL call can bypass the iland
present path through a duplicate-symbol resolution. EGL runtime smoke on device
remains the open acceptance item.

**2026-07-25 macOS GPU Weston package:** `wwn-weston` now maps the macOS
`weston-compositor`, `-drm`, and `-gl` registry variants to the same
in-process iland DRM + ANGLE path used by GPU-capable Apple mobile targets.
`nix build .#weston-compositor-macos` passes on Apple Silicon. This closes the
package/build gap; product runtime evidence is still required before PROPER.

**2026-07-24 KosmicKrisp correction:** current upstream Mesa/Nixpkgs provides
KosmicKrisp for Apple-Silicon macOS. `wwn-iland` now exposes a Vulkan-only
Mesa KosmicKrisp package; its build produced
`libvulkan_kosmickrisp.dylib` plus the aarch64 ICD manifest. Wawona's macOS
product bundles and signs it beside MoltenVK. A direct ICD smoke test returned
`VK_SUCCESS` from `vkCreateInstance` and enumerated one physical device.
Mesa's latest driver
documentation still says iOS is not supported, so iOS-family registry variants
remain fail-loud instead of claiming a nonexistent upstream target.

**2026-07-24 waypipe IOSurface acceptance:** the Apple-mobile `waypipe-rs`
build now keeps its real GBM bindings, resolves them from statically linked
`libiland_userland.a`, recognizes iland's IOSurface modifier, and builds
successfully for `aarch64-apple-ios-sim`. This also corrected iland's public
GBM flag values and restored the standard `gbm_import_fd_data` ABI.

**2026-07-24 visionOS native-compositor loop:** visionOS previously linked
`WWNVisionClientStubs.c:niri_main`, which returned `1`; `visionosDeps` omitted
Niri/fuzzel. Working tree now includes real Niri/fuzzel/tool deps for the
`vision` variant, native `aarch64-apple-visionos[-sim]` Rust targets, no
success-shaped vision client stubs, static-process Smithay EGL loading, and an
iland `eglGetProcAddress` bridge into namespaced ANGLE. Native Niri and Neovim
visionOS archives build. Regeneration exposed and fixed a wrong-platform
`cairo-gobject` recipe that emitted iOS objects into xros. Verification:
`xcodegen` completed; `Wawona-visionOS` built, installed, and launched on Apple
Vision Pro simulator; final xros executable exports real `_niri_main` and has
`LC_BUILD_VERSION platform 12` (visionOS). Runtime Niri connect remains
unproven: the matrix gate's host LLDB attach stalls before evaluating
`connectProfile`; a watchdog now bounds that attach instead of hanging CI.
**Grade remains WIRED. waypipe zero-copy impact: none.**

**weston-constraints concurrent crash:** crash stack and Weston source identify
the upstream SHM reuse bug: the current-buffer fast path returned a released
buffer without restoring `buffer->used = true`. The patch is now applied to
Apple mobile, Android compositor-client builds, and macOS. `weston-terminal`
concurrency accelerates release/redraw but is not root cause. Exact dual-client
runtime replay remains required before PROPER.

**#58 Mode-A device open (landed in `wwn-iland`):** added `iland_drm_open_card()`
in `drm_linux.c` + a reusable force-include header
`shims/drm/drm/include/iland_drm_open_compat.h` that redirects a stock client's
raw `open("/dev/dri/cardN")` to the in-process virtual DRM fd (non-DRM paths
defer to libc `open`, incl. `O_CREAT` mode). Store-safe: no DYLD interpose, no
`/dev/dri`, no privilege. Wired the force-include into iland's own GL-clients
recipes (`gl-clients-macos.nix`, `gl-clients-ios.nix`) and installed the header
in `macos.nix` / `ios.nix` / `android.nix`. **Verified (macOS, 4 levels):** (1) `clang -fsyntax-only` on `drm_linux.c` clean;
(2) macro-routing compile/run test — `/dev/dri/*` → shim (fd 42), 2-arg + 3-arg
passthrough opens compile; (3) **`nix build .#iland-macos` green** — archive
compiles, exports `_iland_drm_open_card` (`nm`), ships `iland_drm_open_compat.h`;
(4) **integration** — the real `test/kmscube.c` (`open("/dev/dri/card0")` at
`:237`) compiles against the built artifact with the force-include applied.
**Grade: WIRED** (build + integration proven; in-app kmscube *render* → PROPER
pending full Wawona app build + Agent-Device). **waypipe zero-copy impact: none.**

**#94 format contract + stock-consumer wiring (landed on `development`):**
`wwn-iland` [`eedd2e5`](https://github.com/Wawona/wwn-iland/commit/eedd2e5cf2e62256c048f5a532e8eda50e1314bf)
now records each GBM BO's DRM fourcc, allocates only the matching IOSurface
pixel format (`XRGB8888`/`ARGB8888` → BGRA; supported 10-bit formats → `l10r`),
and makes `drmModeAddFB2` reject unsupported or mismatched backing rather than
claiming successful channel-swapped presentation. `wwn-kmscube`
[`cfb0449`](https://github.com/Wawona/wwn-kmscube/commit/cfb0449) replaces its
private `open()` implementation with the installed iland compatibility header
for Apple and Android; `wwn-weston`
[`5a8fc72`](https://github.com/Wawona/wwn-weston/commit/5a8fc72) force-includes
the same header in Apple DRM compositor builds. Verified: `nix build
.#iland-macos`, `.#kmscube-macos`, and `.#weston-compositor-ios`. This moves the
format implementation from **FUCKUP** to **WIRED**, not **PROPER**: no
product-shaped iOS/iPadOS/visionOS or Android runtime capture has yet proved
the target frame and Android still uses the CPU compatibility surface instead
of an AHardwareBuffer zero-copy backend.

**Apple IOSurface dmabuf bridge (#86, landed):** `wwn-iland`
[`dec66e5`](https://github.com/Wawona/wwn-iland/commit/dec66e5) makes GBM export
the existing waypipe IOSurface modifier convention (high bit + IOSurface ID),
supplies the protocol placeholder fd, and imports that modifier with
`IOSurfaceLookup` without copying pixels. Both `nix build .#iland-macos` and
`nix build .#iland-ios` pass. This proves ABI/build parity with waypipe's
transport contract; cross-process runtime/Mach-port evidence is still required
for **PROPER**, and Android AHardwareBuffer remains a separate open path.

**Remaining to close #58 for the product (next P1 steps):**
1. Preferred-mode set before first connector enumerate on every Apple/Android
   target; re-set on resize.
2. Nix build target variants + Agent-Device kmscube in-app on iOS-shaped build.
3. Replace Android's CPU compatibility surface with an AHardwareBuffer-backed
   BO/FB path and prove waypipe remains zero-copy (#86).

**Android GPU compositor correction (working tree; verification pending):**
the product dependency in `dependencies/wawona/android.nix` now selects
`weston-compositor-gl`, and the nested launch in
`src/platform/android/android_jni.c` explicitly requests `--renderer=gl`.
This follows R10's short path (Wayland backend + Weston GL → host EGL) while
retaining the non-DRM compositor as the explicit pixman fallback. Do not grade
this above **WIRED** until the Android product builds and Agent-Device captures
the renderer/backend logs from the Play/Home session.

Local overrides against `wwn-weston` `b32ab72` and `wwn-iland` `98004e7`
successfully built both static Weston compositor variants and all native
Wawona Android code. The product derivation then stopped only at its expected
signing-input gate (`ANDROID_KEYSTORE_BASE64`/`ANDROID_KEYSTORE_PATH`), not a
graphics compile or link failure. This closes the build half of **WIRED**;
signed install plus runtime renderer logs remain.

**Android AHardwareBuffer conversion (inner loop in progress):** the prior
Android `iosurface_compat` object was only a heap allocation and forced the
EGL→presenter→Vulkan path through repeated CPU copies. The P1 implementation
now allocates `AHardwareBuffer` objects with GPU color-output/sampled-image
usage plus a CPU-mappable fallback, exposes the native buffer to the product
presenter, and synchronizes iland's preferred mode when the Android swapchain
resizes. The next code step is EGL native-buffer rendering plus Vulkan external
memory import; until that lands, the existing mapped fallback remains active
and Android zero-copy is **not** complete. The Android Nix build is the current
inner-loop gate.

**Android product red build (P1/R10 inner-loop evidence):** selecting
`weston-compositor-drm` correctly reached Weston's GL renderer configuration,
but Meson rejected it because the Android compositor recipe exposed iland DRM
metadata without an EGL pkg-config contract (`libweston + gl-renderer requires
egl`). The corrective contract belongs in `wwn-weston`'s DRM-enabled recipe:
publish the selected L1 ANGLE headers/libs as `egl.pc`/`glesv2.pc`; do not
disable GL or fall back to pixman to make the build green.

The EGL/GBM contracts passed on subsequent local-override builds. The product
session actually launches Weston's **Wayland backend + GL renderer**; compiling
the Linux DRM backend additionally pulled in irrelevant seatd/udev/vblank
surface area and conflicting kernel/libdrm headers. The recipe is therefore
split explicitly: `weston-compositor-gl` is the Android product nested path
(ANGLE/EGL/iland GBM, no pixman); `weston-compositor-drm` remains the separate
Mode-A KMS acceptance artifact and must be completed against the canonical
iland libdrm ABI rather than hidden behind product fallback.

---

**2026-07-25 macOS Mode A acceptance (GL + DRM + KMS → PROPER):** with the
single-image ANGLE bind and the EGL policy guards in place, `WAWONA_AUTO_CLIENT`
drives the whole macOS Mode A path headlessly. Two runs, one per policy branch.

`OpenGLDriver=none` — refuses instead of crashing (this used to be the
`EXC_BAD_ACCESS address=0x0` at `eglInitialize`):

```
[MAIN] WAWONA_AUTO_CLIENT=kmscube — starting bundled client
[KMSCUBE] Refusing GPU client kmscube — Settings → Graphics → OpenGL driver is None
```

`OpenGLDriver=angle` — the full stack, end to end:

```
[KMSCUBE] started in-process kmscube 1680x914 via iland
### Display [0]: CRTC = 1, Connector = 1, format = 0x34325258
DRM Format is DRM_FORMAT_XRGB8888
gbm.dev = 0xb46f948a0, gbm.surface = 0xb47f897c0
init gbm success!
gl.display = 0xb46d109b0
[KMSCUBE] iland present #0   IOSurface 3360x1828 fcc=0x42475241 drawable=0x0
[KMSCUBE] iland present #1   IOSurface 3360x1828 fcc=0x42475241 drawable=3360x1828
[KMSCUBE] iland present #300 IOSurface 3360x1828 fcc=0x42475241 drawable=3360x1828
[KMSCUBE] iland present #600 IOSurface 3360x1828 fcc=0x42475241 drawable=3360x1828
Cleanup of GL, GBM and DRM completed
```

Three things this settles. `gl.display` is non-null where it was `0x0` before, and
the `ANGLESwapCGLLayer is implemented in both` warning is gone, so the process
binds exactly one ANGLE image. Frames #300 and #600 land ~15 s after #0, i.e.
~40 fps sustained, which retires the page-flip-recycling suspicion for good on
this target — presentation is not gated on a five-deep buffer ring. And teardown
is clean rather than a leak or a hang. macOS GL, DRM, and KMS therefore move to
**PROPER**; the client is stock kmscube keeping its real libdrm calls, all in
userland with no `/dev/dri` open.

Present #0 reports `drawable=0x0` because the layer has no drawable size until it
is first laid out; it self-corrects at #1 and is cosmetic, not a dropped frame.
The 3360x1828 IOSurface against a 1680x914 client is the 2× backing scale.

**Vulkan needed one more round before it could be graded.** `vkcube` ran and
exited `rc=0` under both `VulkanDriver=moltenvk` and `VulkanDriver=kosmickrisp`,
presenting through the same iland KMS/GBM path — but the two runs were
byte-identical, with neither a MoltenVK nor a KosmicKrisp banner to tell them
apart. A silent fallback to `WWN_VKCUBE_PROVIDER_FALLBACK` would have looked
exactly the same, and passing a cell on ambiguous evidence is how the fourcc and
page-flip misreadings happened earlier. So `vulkan_dispatch.h` now names the
resolved provider on success, and says whether it came from the environment or the
fallback. Re-run:

```
VulkanDriver=moltenvk    → vkcube: Vulkan provider …/Frameworks/libMoltenVK.dylib (selected)
VulkanDriver=kosmickrisp → vkcube: Vulkan provider …/Frameworks/libvulkan_kosmickrisp.dylib (selected)
```

Both resolve inside the bundle, both report `(selected)` rather than the default,
and both render to `rc=0`. Driver selection is therefore real rather than
decorative, and macOS Vulkan moves to **PROPER** on two independent ICDs — which
also means KosmicKrisp's Mesa-style `vk_icdGetInstanceProcAddr`-only export path
is exercised, not just MoltenVK's.

Repos touched: `Wawona` (this doc), `wwn-kmscube` (provider log in
`upstream/vkcube/vulkan_dispatch.h`; the Android/Apple env split became two macros
so both arms share one lookup).
**waypipe zero-copy impact: none** — no buffer, export, or dmabuf path touched.

---

**2026-07-25 Android SwiftShader WSI trace (regrades the `swiftshader` cell to
FUCKUP; design recorded, not yet implemented):** the Android Vulkan cell was
graded as one thing, but the two driver selections behave very differently, and
`swiftshader` is not merely unproven — it cannot start.

`wwn_load_vulkan_driver()` `dlopen`s `libvk_swiftshader.so` directly, bypassing
the Android loader. But `vkCreateAndroidSurfaceKHR` is **loader-owned** WSI on
Android, not ICD-owned, so the ICD's `vkGetInstanceProcAddr` will never return
it — and `wwn_load_vulkan_instance_dispatch()` loads that symbol through a
fail-closed macro. Selecting SwiftShader therefore returns
`VK_ERROR_INITIALIZATION_FAILED` from `create_instance()`, before a surface is
ever requested. The build makes this structural rather than accidental: our
recipe compiles SwiftShader as a portable Linux-style ICD under `__TERMUX__`,
which enables `VK_EXT_headless_surface` and strips `vkCreateAndroidSurfaceKHR`,
Gralloc swapchain, `hwvulkan_module_t`, and AHB external memory. Upstream's
`HeadlessSurfaceKHR::present()` returns `VK_SUCCESS` without displaying
anything, so even a working headless swapchain renders in-process only.

Two packaging gaps compound it: `dependencies/wawona/android.nix` copies only
`*.so` into `jniLibs`, so `vulkan/icd.d/vk_swiftshader_icd.json` never reaches
the APK, and `apply_graphics_driver_selection()` *clears* `VK_ICD_FILENAMES` /
`VK_DRIVER_FILES` instead of pointing them at the bundled manifest — the
opposite of what macOS does in `WWNSettings_ApplyGraphicsDriverSelection()`.

Agreed shape of the fix (deferred to `p3-android`), which keeps the recipe's own
split of "ICD renders, host app owns Android presentation": always load
`libvulkan.so` and select SwiftShader via a staged ICD manifest rather than
direct `dlopen`; branch WSI by driver (`VK_KHR_android_surface` +
`vkCreateAndroidSurfaceKHR` for system, `VK_EXT_headless_surface` +
`vkCreateHeadlessSurfaceEXT` for SwiftShader); and add a small app-owned present
adapter that copies the acquired swapchain image to `ANativeWindow` (CPU
`vkCmdCopyImageToBuffer` + `ANativeWindow_lock`/`unlockAndPost` first, AHB-backed
second). Explicitly rejected: enabling stock Android HAL SwiftShader (needs
non-NDK framework headers), and any Turnip/KGSL path — both barred by the
runtime-only rule.

**waypipe zero-copy impact: none** (analysis only). Note the AHB half of #86
stays blocked on the same missing
`VK_ANDROID_external_memory_android_hardware_buffer` support in this ICD.

---

**2026-07-25 KMS cadence + resize (KMS regraded PROPER → FUCKUP, fixes in tree):**
The promotion above was wrong and user-visible behavior said so: the cube
juddered, and resizing the host window did not change the client's size. Both
were real, and both were in the present path. Sustained ~35 fps on a 60 Hz
display should have been the tell — that is not "slow", it is frames landing an
uneven number of vsyncs apart. Three defects, one function:

1. **A fresh `MTLTexture` per frame.** `newTextureWithDescriptor:iosurface:` ran
   on every present. A GBM surface cycles a handful of buffers, so the same
   IOSurfaces recur and the import is pure overhead on the frame's critical path.
   Now cached per IOSurface (extent-validated, bounded at 16 so a mode change
   cannot grow it without bound).
2. **Page-flip pacing — tried, measured, reverted.** Completing the flip from
   `addCompletedHandler:` releases the client when the GPU finishes drawing,
   which is *before* the frame is visible, so the textbook fix is to complete
   from the drawable's `addPresentedHandler:` and lock the client to scanout.
   Measured: throughput **halved**, ~37 fps to ~18, and staying at ~18 with the
   window frontmost, so it was not background throttling. The reason is
   structural: iland permits a single outstanding flip per CRTC, so gating on
   scanout leaves nothing in flight and each frame costs several vblanks instead
   of one. Reverted to GPU-finish completion. Decoupling client cadence from
   presentation requires more than one in-flight flip, which is an iland ABI
   change rather than a presenter change — recorded as the next lead below.
3. **CALayer geometry read from the client's render thread.** Every present called
   `syncPreferredModeFromLayer`, and the iOS variant went further and *assigned*
   `drawableSize`. That races AppKit/UIKit precisely during a resize drag. It was
   also pointless: `iland_drm_set_preferred_mode` only affects mode
   *enumeration*, and stock kmscube enumerates once, sizes its GBM surface, and
   explicitly declines to watch for hotplug (`kmscube.c:367`). Mode publication
   now happens on the main thread from the host's layout/resize hook.

That last point is also why resize "did not reach the client", and it is worth
being precise: a stock KMS client *cannot* change mode mid-run, so the client
staying at its startup size is correct. The bug was that the presenter stretched
that fixed framebuffer to fill the new drawable, distorting the cube. It now
letterboxes with a centered `MTLViewport`, which is what a real display does when
scaling a mode it cannot change. Making the client itself reconfigure would mean
patching kmscube, which would forfeit the stock-client basis of this acceptance.
Live client-side resize belongs to the Wayland path (xdg configure), not the KMS
path, and is graded separately.

Result after the texture cache, measured over 1,500 frames with the window
frontmost: 37.5 / 42.9 / 50.0 / 42.9 / 42.9 fps per 300-frame bucket. Better than
the ~35–40 baseline, and the per-frame allocation is gone, but it is neither 60
nor steady — the spread across buckets exceeds the ±7 % that 1-second log
timestamps can explain, so **the judder is reduced, not solved**, and KMS stays
FUCKUP rather than being re-promoted.

Two structural leads for the remainder, both outside the presenter:

- **`glFinish()` per swap.** iland's EGL shim zero-copy path calls `glFinish()`
  in `eglSwapBuffers` (`shims/egl/src/egl.c:635`) to guarantee the client's GPU
  work has landed in the IOSurface before the buffer is published. That is a full
  CPU-blocking GPU sync on the frame's critical path, every frame. ANGLE and the
  presenter use separate Metal queues on the same GPU, so *some* sync is
  required, but a shared `MTLSharedEvent` or a GL fence would order the work on
  the GPU instead of stalling the client thread.
- **One outstanding flip.** See item 2 — this caps pipelining regardless of how
  fast either side renders.

Also worth recording: the zero-copy path is the default (`ILAND_EGL_ZEROCOPY`
must be explicitly set to `0` to opt out), so the `glReadPixels` +
`vImagePermuteChannels` readback fallback is *not* what is costing frames here.
That was the first suspect and it was wrong.

Instruments, for the record, found **zero leaks** across a 90 s Leaks recording,
and RSS stayed flat (roughly 280–330 MB) over ~9,600 frames, so none of this was
a leak — it was per-frame work and mis-sequenced completion. Worth noting the
first attempt profiled the wrong process: `pgrep -f` matched the coreutils
`timeout` wrapper (5.9 MB RSS) rather than the app, and a clean "0 leaks" from a
3-line C program is indistinguishable from a clean result for the real target.

Repos touched: `Wawona` (macOS + iOS presenters, `WWNWindow` layout hook).
**waypipe zero-copy impact: none** — buffer import is now cached rather than
repeated; export and dmabuf paths untouched.

---

**2026-07-25 tvOS/watchOS GPU re-scope (policy change, work deferred):** the
`❌` in the platform-targets GPU row was treated as one fact about two platforms.
It is two different facts, and only one of them is permanent. Checked against the
installed SDKs (Xcode 26.6) rather than documentation:

```
=== WatchOS (SDK 26.5) ===        === AppleTVOS ===
  Metal:      ABSENT               Metal:      present
  MetalKit:   ABSENT               MetalKit:   present
  OpenGLES:   ABSENT               OpenGLES:   present
  QuartzCore: present              QuartzCore: present
```

**tvOS is deferred, not impossible.** It has Metal, MetalKit, and even the
deprecated `OpenGLES.framework`, and MoltenVK upstream lists tvOS (14.5+) as a
supported platform built strictly on public API, so it is store-legal. Two
asymmetric paths: Vulkan is short, because MoltenVK already builds for tvOS and
Wawona dispatches straight into the ICD via `WWN_VULKAN_LIBRARY` — which matters,
since LunarG's Jan-2026 status notes the Vulkan **loader** does not work on tvOS
yet, a limitation we already sidestep. GLES is long, because ANGLE has no
maintained Chromium GN tvOS target, the same wall that made visionOS ANGLE a
pinned-artifact-plus-patch-series job (P2a). This is scheduled as the **final**
graphics phase, after every other target is PROPER.

**watchOS has no floor.** The watchOS 26.5 SDK ships no `Metal.framework` at all
— device or simulator — no `OpenGLES.framework`, and no Metal `.tbd` to link.
`CAMetalLayer.h` is present (headers are shared across platforms) but the class is
annotated `API_AVAILABLE(macos(10.11), ios(13.0), tvos(13.0))
API_UNAVAILABLE(watchos)`. The only rendering frameworks are SpriteKit and
SceneKit, which render internally and expose no device, drawable, or shader entry
point. Since ANGLE and MoltenVK both terminate in Metal, neither has a backend;
MoltenVK's own platform list is macOS/iOS/tvOS/visionOS, so watchOS is absent
rather than merely untested. Enabling watchOS GPU therefore requires a public
Metal-equivalent surface to appear first — it is not a porting task today, and
must not be "solved" via private API or SpriteKit as a shader backdoor.

Enforcement: `verify-iland-graphics-bundle.sh` keeps tv/watch strict by default,
but tvOS strictness is now conditional on `WWN_TVOS_GPU != 1`, and setting
`WWN_TVOS_GPU=1` inverts it into a positive MoltenVK assertion — so the deferred
phase flips one variable instead of rewriting the verifier, with no window where a
driver can drift in unnoticed. watchOS strictness is unconditional.

Repos touched: `Wawona` (verifier, this doc), workspace `wawona-platform-targets`
rule (GPU row `❌` → `⏳`, hard rule 1 split per platform).
**waypipe zero-copy impact: none** — no buffer path touched.

---

## R1 — Mode A fail point (#58) + Apple KMS / IOSurface map

**#58 root cause (confirmed):** kmscube logs `could not open drm device
/dev/dri/card0` / `failed to initialize DRM`. The Mode A archive
(`libiland_userland.a`) links the userland `drmMode*` implementation but **does
not interpose `open("/dev/dri/card*")` or `ioctl`** — those hooks live only in
the Mode B dylib (`upstream/shims/drm/.../wayland-mac.c:85-109`, Dobby). Stock
clients therefore fail at the raw card open before any `drmMode*` call.
`wwn-kmscube` works around it with `-include kmscube_compat.h`
(`kmscube_compat.h:21-50`); weston / other clients need the same shim or a
Mode-A-safe open path inside iland.

**Linked libdrm surface is substantially REAL** (all in
`dependencies/libs/iland/upstream/shims/drm/drm/src/drm_linux.c`):

| Symbol | file:line | Grade |
|--------|-----------|-------|
| `drmOpen`/`drmOpenWithType` | `234-244` | REAL (returns virtual fd 42) |
| `drmModeGetResources` | `275-301` | REAL (1 CRTC/1 connector/1 encoder) |
| `drmModeGetConnector` | `315-346` | REAL (fake DP connected; `init_modes()`) |
| `drmModeGetEncoder`/`GetCrtc` | `360-403` | REAL |
| `drmModeCreateDumbBuffer` | `448-495` | REAL (→ IOSurface via DisplaySurface) |
| `drmModeAddFB` | `573-614` | REAL (dumb + GBM handle registry) |
| `drmModeAddFB2`/`WithModifiers` | `616-628`,`1635-1647` | **PARTIAL/BROKEN — `(void)pixel_format`; fourcc ignored** |
| `drmModeSetCrtc` | `656-671` | PARTIAL (records state; no present until flip) |
| `drmModePageFlip` | `673-716` | REAL Mode A (→ `g_present_cb`); else Mode B IPC |
| `drmHandleEvent` | `718-750` | PARTIAL (immediate pipe byte; no vblank timing) |
| `drmIoctl` | `754-759` | STUB (`ENOSYS`) |
| `drmModeGetPlaneResources`/`GetPlane` | `1308-1375` | PARTIAL (primary plane 1 only) |
| `drmModeAtomicCommit` | `1419-1526` | PARTIAL (applies props; immediate flip event) |
| `drmModeSetCursor`/`MoveCursor` | `1541-1554` | STUB (`ENOTSUP`) |
| `drmPrimeHandleToFD`/`FDToHandle` | `1608-1631` | STUB (fake fd/handle) |
| `iland_drm_set_present_callback` | `30-34` | REAL (Mode A gate) |
| `iland_drm_set_preferred_mode` | `59-66` | REAL (**required on iOS/Android**) |

**Apple KMS ↔ IOSurface mapping (as-built):** connector/CRTC/encoder are fixed
fakes (`init_modes()` `89-182`). Mode source priority: (1) `iland_drm_set_preferred_mode`
→ exact host pixels; (2) macOS WindowServer plist `116-157`; (3) default
**1920×1080** `171-181`. Present callback carries **only** `(crtc, fb,
IOSurfaceRef, flags)` — no width/height/format (`iland_present.h:37-41`); host
queries the IOSurface. **Per-target gap:** iOS/iPadOS/visionOS/Android have no
plist, so without a preferred mode they get 1920×1080 then Metal stretch — the
#94 edge-to-edge/sizing class. macOS Mode A product may also skip preferred
mode (windowed host ≠ desktop res).

**GBM↔FB allocator is unified** (single IOSurface shared via a handle registry:
`gbm.m:60-61` `drm_register_gbm_buffer`, `drm_linux.c:581-591` FB lookup), **but**
the format argument is ignored at alloc (always BGRA) → advertised-vs-physical
format lie (#94).

## R2 — Mode B reality (macOS desktop-host)

Engage path is **real and gated** but not a CI-proven finished product.

- SIP detect `WWNSipStatus.m:6-38`; allow-gate `:55-57`; toggle hard-reject when
  SIP blocks `WWNPreferences.m:4041-4049`; toggle also requires bundled dylib
  `:4051-4067` (store-safe builds cannot arm Mode B). — REAL
- `shouldEngageModeB` `WWNDesktopReplacementController.m:53-62`; dylib discovery
  `:77-94`; privileged insert + `weston --backend=drm` `:187-258`; connect hook
  `WWNMachineSessionBridge.m:150-168`. — REAL
- Dylib constructor (root-gated, Dobby hooks, extracts framebufferd/inputd)
  `wayland-mac.c:259-337`; framebufferd CAWindowServer present
  `framebufferd/src/main.m:267-303`. — REAL (upstream-derived)
- **Remaining gaps:** flip completion still signals when the Mach surface message
  is accepted rather than at a display-vblank (`drm_linux.c` page-flip); **no CI
  job builds/runs `wawona-macos-desktop-host`**; and
  `verify-iland-mode-b-bundle.sh` is **not invoked by any workflow** (only an
  inline Nix assert), while `docs/ci.md:51-52` overstates coverage. Tracked by
  #87.

### P3 Mode B hardening — in progress

Mode B remains **macOS desktop-host only**: root + SIP debugging restrictions
disabled/partially-disabled + explicit Desktop Replacement preference. No
mobile/Android/store artifact is changed by this work.

**Lifecycle implementation:** `wayland-mac.c` now records the PIDs of the
root-owned `framebufferd`, `inputd`, and `caffeinate` processes it launches
under `/tmp/libwayland-support/`. Its dylib destructor stops only those
helpers, in reverse startup order, and removes the PID records; it deliberately
does not touch helpers when a pre-existing Mode B Mach service belongs to
another owner. Failed helper extraction/spawn now fails the constructor instead
of falling into an unbounded service-wait loop. The desktop controller now
stops the root-owned injected Weston through the same administrator boundary
that launched it, waits for normal destructor cleanup, and only then escalates;
the escalation consumes the root-owned PID records to prevent orphaned helpers.

**Why:** the old controller used unprivileged `kill(SIGTERM)` on a root process,
so it could silently fail with `EPERM`; it also had no helper teardown
ownership. The new lifecycle closes that leak without adding any Mode B symbol
or package to Mode A/store outputs.

**Acceptance still pending:** build `iland-baremetal-macos`; static/syntax
checks; desktop-host package bundle test (`--mode present`) plus product/mobile
absence checks; a manually authorized SIP-eligible desktop-host smoke proving
Weston → page flip → framebufferd, and a shutdown smoke proving no owned helper
PIDs survive. **waypipe zero-copy impact: none** (the IOSurface Mach-port
handoff remains unchanged).

**Build evidence (macOS arm64):** `nix build .#iland-baremetal-macos` is green
after repairing the recipe's coherent Xcode compiler/SDK selection, ANGLE header
path, and `codesign` invocation without leaking BSD `find`/`cut` into Nix
fixup. The artifact is an ad-hoc-signed arm64
`libwayland-mac.dylib`, exports `drmModePageFlip` and `wayland_mac_init`, and
passes both `verify-iland-mode-b-bundle.sh --mode present` (desktop-host-shaped
fixture) and `--mode absent` (store-shaped fixture). This verifies packaging
and compile/link ownership; it does **not** claim a SIP/root live desktop smoke
or vblank-correct flips. Grade remains **WIRED**, not PROPER.

## R3 — External stacks (reuse cheat-sheet)

- **UTM** (`UTM/Documentation/Graphics.md:6-81`): reusable patterns for Mode A =
  ANGLE Metal backend (`ANGLE_DEFAULT_PLATFORM=metal`), IOSurface as zero-copy
  present substrate, CocoaSpice-style CAMetalLayer + vblank present, ICD select
  via `VK_DRIVER_FILES`/`VK_ICD_FILENAMES`. **VM-only, must not leak into Mode A:**
  virtio-gpu, virglrenderer, Venus, gfxstream (stay in `wwn-vms`/UTM engine;
  confirmed `wwn-vms/README.md:9-11,40`).
- **Local packaging inventory:** `wwn-iland` owns ANGLE, MoltenVK,
  SwiftShader and macOS KosmicKrisp recipes/registry entries. Turnip is
  intentionally not packaged because direct KGSL access violates Wawona's
  runtime-only/no-direct-kernel policy.
- **Termux/Android:** Wawona uses system Vulkan or bundled SwiftShader, and
  system EGL or bundled ANGLE. It never opens KGSL directly.
- **Minimal-layers verdict:** one hop per API — Apple GLES→ANGLE→Metal,
  Vulkan→MVK|KK→Metal; Android GLES→ANGLE|system, Vulkan→system|SwiftShader.
  Reject GLES→Zink→Vulkan→MVK→Metal.

## R4 — Pref apply gap

| Pref | Saved | Applied on connect? | Grade |
|------|-------|---------------------|-------|
| VulkanDriver (macOS) | global `WWNPreferencesManager.m:32,782-788` + per-machine keys `WWNMachineProfileStore.m:131-134` | ICD `setenv` **launch-time only** `main.m:1119-1162`; connect (`applyMachineToRuntimePrefs` `WWNMachineSessionBridge.m:114`) rewrites defaults but **does not re-`setenv`** | PARTIAL |
| OpenGLDriver (macOS) | global `:33,791-799` | read by `WWNSettings_GetOpenGLDriver` `WWNSettings.m:87-94` but **no `setenv`/ANGLE selection site** | STUB |
| VulkanDriver (Android) | `WawonaSettings.kt:62-81`→JNI | REAL at instance create `android_jni.c:1022-1047` (`VK_ICD_FILENAMES`) | PARTIAL (global real; per-machine ad-hoc) |
| OpenGLDriver (Android) | same | stored `android_jni.c:2428-2430`, **no consumer** | STUB |
| DriverSelector abstraction | — | — | **MISSING** |

### P2 DriverSelector / ownership progress

- `wwn-toolchain` `2bd941e` removes `angle` and `swiftshader` from L0's
  `baseRegistry` and deletes Android's SwiftShader bypass.
- `wwn-iland` `55b705c` owns both keys in its L1 `registryFragment`; an Android
  iland build passes against the split registry. ANGLE and SwiftShader recipes
  now live under `wwn-iland/dependencies/libs/`; L0 retains substrate only.
- Apple now applies Vulkan and OpenGL selections through one
  `WWNSettings_ApplyGraphicsDriverSelection` function at startup and after
  per-machine overrides. It sets both Vulkan loader variables, applies the
  KosmicKrisp→MoltenVK fallback, and selects ANGLE/Metal independently.
- Android applies Vulkan and OpenGL policy together before Vulkan instance
  creation; waypipe no longer silently forces SwiftShader. ANGLE selects its
  Vulkan backend independently of the host Vulkan ICD choice.

This advances DriverSelector from **MISSING** to **WIRED**. Android cannot
change the already-created host Vulkan instance per machine without renderer
recreation; that lifecycle remains an acceptance item rather than pretending
an environment rewrite hot-switches Vulkan.

**Hook point:** a `machine>global>default` resolver called from both `main.m`
launch and after `applyMachineToRuntimePrefs` (`WWNMachineSessionBridge.m:114`),
before Mode B engage / WaypipeRunner launch, that re-`setenv`s ICD/ANGLE. Swift
`resolvedSettings` also hardcodes `"moltenvk"` fallback instead of global
(`WawonaPreferences.swift:289`) — inconsistent, fix in P2.

## R5 — Flake DAG (edges)

Actual flake-input edges match L0→L4 with **no inversions**: toolchain (none),
iland (→toolchain), kmscube (→toolchain,iland), weston (→toolchain,iland,kmscube;
`ilandSrc` source-injection only), waypipe/anowaW/vms (→toolchain; no iland
input), Wawona (→ all). Registry merge is `baseRegistry // fragment` (iland
`flake.nix:96`, kmscube `74`, weston `83`, Wawona `222-240`). **Lock skew** (not
a cycle): weston pins toolchain `7e00ad…` vs iland/kmscube `b0bc81…`; re-lock in
land loop.

## R6 — Ranked stub-replacement list (Mode A, iOS-store-shaped)

1. **Card open without Dobby** — Mode-A-safe `open("/dev/dri/card*")` path inside
   iland (or a shared client shim) so stock kmscube/weston open the virtual fd.
   Root cause of #58. (`wayland-mac.c` is Mode B only.)
2. **`drmModeAddFB2` format honor + GBM format→pixelFormat map** — stop ignoring
   fourcc (`drm_linux.c:623-627`); root of #94 format lie.
3. **Present metadata / size sync** — carry format/size or keep preferred mode ≡
   host drawable; host queries IOSurface today (`iland_present.h:37-41`).
4. **Real vsync / flip completion** — replace immediate pipe byte
   (`drm_linux.c:708-713`).
5. **`drmIoctl`→dispatch** — currently ENOSYS; stock libdrm ioctl clients fail.
6. **Planes/atomic completeness** — only primary plane; SetCursor ENOTSUP;
   modifiers off; PRIME fake.
7. **udev(+epoll) in Mode A link set** — `udev.c` enumerates fake `card0` but is
   **not compiled into** the Mode A `.a`; weston needs it.
8. **Android present plumbing** — no AHB/GPU zero-copy; zerocopy forced off.
9. **EGL Android** — dlopen `libEGL.so` + CPU swap, not Metal IOSurface zero-copy.
10. tvOS/watchOS — intentionally empty; do not add GL.

Store builds confirmed to contain **zero** Mode B dylib / inject paths (see R7).

## R7 — Universal A/B + store-matrix audit

Gating is real: `.#wawona-macos` sets `ilandBaremetal = null` (`flake.nix:982-983`)
and `macos.nix:1366-1370` fails the build if the dylib is present; desktop-host
includes it (`flake.nix:987-1000`). iOS/tv/watch/vision xcodegen targets exclude
SIP/Desktop controllers; tv/watch use `finalCxxLdflagsNoIokit` and skip
ANGLE/MVK embed (`xcodegen.nix:1576-1606,2546`; `mobile-platform-deps.nix:38-39,64-68`).
Apple mobile SSH is libssh2-only (`mobile-platform-deps.nix:20-30`). Cargo
`compile_error` blocks `iland-baremetal` on mobile/Android (`src/lib.rs:27-44`).

**Leak vectors to guard (P1 compliance checklist):** manual packaging copying the
dylib (verify script not in CI); sharing iOS GPU post-build phases onto tv/watch;
adding IOKit ldflags to tv/watch; linking OpenSSH into mobile OTHER_LDFLAGS;
shared Settings sections without `#if` platform guards; enabling `desktopHost`
on the wrong flake attr.

**Android Home Desktop = rootless Mode A** (HOME role + nested weston,
`DesktopReplacement.kt:14-24`); anowaW baseline = MediaProjection/own VD
(`AnowawSession.kt:24-28`); power tier (Shizuku/root) only for arbitrary-app
embed, auto-falls back (`:64-76`). No SIP, no dylib on Android.

## R8 — Capability matrix

See "Living capability matrix" above (filled with grades + evidence). This is the
baseline the dual loop updates every iteration.

## R9 — Verify model (draft)

Adopt the closed input→output contract per layer so failures localize to the
first broken seam (bindings ABI → Wayland wire → solved ICD/EGL → iland
DRM/KMS/GBM → present). Authoritative clients: stock **kmscube**,
**weston-simple-egl**, **vkcube** (never a homegrown cube). ANGLE/MVK/KK are
black-box dependencies, not systems-under-test. "Bit-by-bit" = for a pinned
client revision + pinned ICD/ANGLE, the binding/protocol seam matches upstream
symbol-for-symbol and message-for-message; Mode A golden = present-callback
`(width,height,fourcc,frame ids)` sequence for one vsync. **Custom code to
delete/avoid:** homegrown GL init, `iland_open()` client rewrite, "IOSurface
instead of GBM" dual worlds, hand-rolled Rust GL/VK drivers.

## R10 — Compositor backend audit (pixman vs GPU)

GPU-capable Apple defaults now select `iland-drm-gl`; tvOS/watchOS retain the
required software default. Android product wiring selects the DRM/GL archive
and explicitly starts Weston's GL renderer. macOS still lacks a product
`weston-compositor-drm` recipe, so this cross-cutting item remains open.

| Target | Build renderer/backend | Runtime default | Verdict |
|--------|------------------------|-----------------|---------|
| iOS / iPadOS | DRM+GL compiled in (`enableIlandDrm=true`, `mobile-platform-deps.nix:54-57`) | `iland-drm-gl` (GPU-target default) | WIRED; runtime evidence pending |
| visionOS | same | `iland-drm-gl` | WIRED; runtime evidence pending |
| tvOS / watchOS | `renderer-gl=false`, `allowGpu=false` | pixman | correct (no GPU) |
| macOS | `weston-compositor.macos=null`; `backend-drm=false`,`renderer-gl=false` (`macos.nix:57-66`) | requests `iland-drm-gl`, then falls back if `weston_main` is absent | FUCKUP (build gap) |
| Android | product selects `weston-compositor-gl` (DRM acceptance remains separate) | `--backend=wayland --renderer=gl` | WIRED; native build passed, signed device evidence pending |

Remaining fix: add and package a macOS compositor-drm recipe; then verify each
GPU target logs the GL renderer while explicit software mode and tv/watch stay
pixman.

## R11 — DAG / cycle watch list

Flake edges are acyclic (R5). P2 resolved ANGLE, SwiftShader, MoltenVK and
KosmicKrisp ownership under L1
`wwn-iland.registryFragment`; L0 now carries fail-loud ownership sentinels only.
`pixman` correctly stays L0 (cairo depends on it `cairo/ios.nix:24`); moving it
to iland would force cairo→iland (cycle).
In-toolchain `freetype↔harfbuzz↔cairo` disable edges are intentional one-way
(`freetype/ios.nix:4-5`, `harfbuzz/ios.nix:6-7`) — keep. `ffmpeg`/`spirv-tools`
in L0 are borderline but not iland/weston; leave unless proven graphics-only.

**Cycle-risk watch list** (full table in [`wwn-repo-dag.md`](wwn-repo-dag.md)):
pixman/cairo/pango into iland (forbidden); angle left owned by toolchain after
move; iland→weston/kmscube/waypipe flake edges; toolchain baseRegistry absorbing
fragments; kmscube→weston; Wawona as input of any wwn-*; MVK/KK recipe pulling
full mesa+iland headers. Direct Turnip/KGSL is forbidden by runtime-only policy,
not relocated to another layer.

---

## Minimal-layer canonical paths (locked)

```text
Apple (macOS/iOS/iPadOS/visionOS) — parallel, not stacked:
  GLES/OpenGL → EGL → ANGLE(Metal) → IOSurface/Metal present
  Vulkan      → loader → MoltenVK OR KosmicKrisp → Metal present
  DRM/KMS/GBM → iland userland → same present callback (no extra GL/VK hop)
Android:
  GLES → EGL → ANGLE OR system GLES → Surface present
  Vulkan → loader → system OR SwiftShader
tvOS: software/pixman today; deferred final phase adds
  Vulkan → MoltenVK(tvOS) → Metal present   (no loader: direct ICD dispatch)
watchOS: software/pixman only — no Metal in the SDK, so no translate stack exists
```

Reject: GLES→Zink→Vulkan→MVK→Metal; virgl/Venus in Mode A; pixman nested on
GPU-capable Apple/Android; two active Vulkan ICDs in one process.

## waypipe-rs zero-copy (cross-cutting)

#86 target: iland GBM/FB IOSurface exported as `zwp_linux_dmabuf`, importable by
`wwn-waypipe` and nested clients without CPU blit when DmabufEnabled. waypipe
does **not** take iland as a flake input today (`wwn-waypipe/flake.nix` →
toolchain + ssh only) — GPU wiring is via env/ICD, keep it that way (no L1→L3'
inversion). Every buffer-touching change must log **waypipe zero-copy impact:
none | preserved | broken→fix**. P0 impact: **none** (research-only).

## Repos touched this phase

P0 (docs-only, `Wawona`): this progress doc, draft `wwn-repo-dag.md`, GitHub epic.
No `wwn-*` recipe edits; no flake.lock bumps.

P1 (in progress):
- `Wawona`: Mode A/B store matrix + portable-KMS model in `iland-mode-a-b-desktop.md`;
  workspace `wawona-repo-dag.mdc` Cursor rule; AGENTS.md DAG stub (on disk).
- `wwn-iland`: `iland_drm_open_card` + `iland_drm_open_compat.h` (#58 Mode-A open
  shim); header install in `macos.nix`/`ios.nix`/`android.nix`; force-include in
  `gl-clients-macos.nix`/`gl-clients-ios.nix`; AGENTS/README DAG layer identity.
- `wwn-toolchain`: AGENTS.md (new) + README DAG layer identity (on disk).
**waypipe zero-copy impact: none.**

## P1 entry criteria (written; P1 not started)

1. #58 fix design chosen: Mode-A-safe card-open shim inside iland vs shared client
   `kmscube_compat.h`-style include (prefer iland-internal so weston benefits).
2. Format path: single `DRM_FORMAT_XRGB8888`/BGRA reality first; `AddFB2` honors
   fourcc; GBM format map.
3. Preferred-mode set on every mobile/Apple target before first connector enumerate;
   re-set on resize.
4. Present callback size/format contract decided (extend callback vs host-queries-IOSurface).
5. Compositor default flip to GPU (`iland-drm-gl`) staged for iOS/iPadOS/visionOS/
   macOS/Android product sessions; tv/watch stay pixman.
6. waypipe zero-copy regression check defined for #86.
7. Store-compliance checklist (R7 leak vectors) ready to assert per build.
