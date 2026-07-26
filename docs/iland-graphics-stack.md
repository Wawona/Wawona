# Wawona graphics stack

Canonical architecture and acceptance contract for Wawona's portable graphics
stack. Live grades and evidence are tracked in
[`iland-graphics-progress.md`](iland-graphics-progress.md). Privilege and
packaging rules are in
[`iland-mode-a-b-desktop.md`](iland-mode-a-b-desktop.md); repository ownership
is in [`wwn-repo-dag.md`](wwn-repo-dag.md).

## Architecture

`wwn-iland` is a KMS-like display abstraction, not a replacement API for stock
clients. kmscube, Weston and future toolkit ports keep the standard libdrm,
GBM, EGL, Vulkan and Wayland interfaces.

```text
Wayland client / nested compositor
  ├─ EGL/GLES ──► ANGLE ──► Metal or Android GPU
  ├─ Vulkan ────► one selected ICD ──► Metal or Android GPU
  └─ libdrm/GBM/KMS ──► iland virtual device and objects
                         ├─ Apple: IOSurface FB/BO ──► CAMetalLayer
                         └─ Android: AHardwareBuffer FB/BO ──► Surface
```

IOSurface and AHardwareBuffer are backing storage for GBM buffer objects and
KMS framebuffers. They do not replace GBM. The virtual device exposes
connector, encoder, CRTC, plane, property, framebuffer, modeset and page-flip
semantics required by the accepted stock clients.

## Minimal translation layers

- Apple GLES: EGL → ANGLE Metal.
- Apple Vulkan: Vulkan loader → MoltenVK or KosmicKrisp → Metal.
- Android GLES: EGL → ANGLE or system GLES.
- Android Vulkan: host ANativeWindow → system loader; offscreen iland clients
  → system ICD or bundled SwiftShader.
- Never route GLES through Zink/Vulkan merely to reach Metal or Android.
- virgl, gfxstream and Venus remain VM paths, not Mode A presentation.
- GPU-capable Apple and Android compositor products use GPU renderers. Pixman
  is an explicit software fallback and the tvOS/watchOS path.

`wwn-iland.registryFragment` is the sole L1 registry owner for ANGLE,
SwiftShader, MoltenVK, and KosmicKrisp. Apple-mobile MoltenVK is a pinned, public-API
upstream static release slice; macOS may use the unrestricted native package.
KosmicKrisp is built from upstream Mesa for macOS. Its iOS registry variants
remain fail-loud until upstream Mesa ships the iOS target; Mesa's current
driver documentation explicitly says iOS is not supported yet.
Wawona consumes these through the registry and must not instantiate
`pkgs.angle`, `pkgs.swiftshader`, or `pkgs.moltenvk` directly.

## Mode A and Mode B

Mode A is in-app, unprivileged presentation. Apple mobile statically links
store-safe archives; Android Play uses app-owned surfaces and rootless Home
Desktop integration; macOS uses the most capable native in-window path.

All Wawona DRM/KMS/GBM objects are runtime-only userland emulation. Wawona
never opens `/dev/dri` or `/dev/kgsl`, forwards real DRM/KMS/KGSL ioctls, installs
kernel code, or patches a kernel. Metal and system Vulkan remain normal OS
runtime APIs; direct Turnip/KGSL is excluded by this policy.

Mode B is privileged host-display presentation. It is limited to the separate
macOS desktop-host bundle and optional Android Shizuku/root window-management
operation; privilege never authorizes direct framebuffer or kernel-device access.
Mode B artifacts never enter Apple-mobile or Play product bundles.

## Toolkit readiness contract

SDL, Qt and GTK remain separate ports. They consume Wawona's Wayland and
graphics contracts instead of adding toolkit-private Metal renderers. The
catalog of what those ports need (and which GH issues track them) is
[`toolkit-soft-path.md`](toolkit-soft-path.md).

| Consumer | GPU route | Software route |
|----------|-----------|----------------|
| Weston | GL renderer + iland DRM/GBM/EGL | pixman + wl_shm |
| GTK4 | GDK Wayland + GSK GL/Vulkan | GSK Cairo + wl_shm |
| Qt | QtWayland QPA + GL/Vulkan | QPainter raster + wl_shm |
| SDL2/3 | Wayland video + GLES/Vulkan | software renderer + wl_shm |
| GLFW/EGL | Wayland + EGL | fail explicitly when EGL is unavailable |
| waypipe-rs | linux-dmabuf with IOSurface/AHB transport | SHM/compressed fallback |

A toolkit port is ready to start only after stock acceptance clients prove:

1. libdrm/GBM/KMS with kmscube on macOS, iOS, iPadOS, visionOS and Android.
2. EGL/GLES with weston-simple-egl through ANGLE or the selected system EGL.
3. Vulkan instance/device/present with vkcube where GPU policy allows it.
4. IOSurface/AHB dmabuf transport without a mandatory CPU copy.
5. The shared software buffer path with damage-limited updates.

## Shared software path

```text
Cairo / Qt raster / SDL software / Weston pixman
  → wl_shm or CPU-readable GBM BO
  → one stride- and damage-aware iland CPU present path
  → Apple texture upload or Android Surface upload
```

Pixman remains in `wwn-toolchain` because Cairo and Weston consume it.
`wwn-iland` may link pixman for composition helpers but never owns it. Software
rendering must not be converted into fake GLES, Zink, or a second full-frame
copy. waypipe may intentionally degrade to SHM/compression, but a GPU session
must retain its zero-copy dmabuf route.

## Target policy

- macOS, iOS, iPadOS and visionOS: IOSurface-backed Mode A; full GLES/Vulkan
  where allowed. iPadOS and visionOS require one host scene per Wayland client.
- Android: AHardwareBuffer/Surface-backed Mode A; optional separate Mode B
  power path.
- tvOS and watchOS: native/remote software-only presentation today. No ANGLE,
  MoltenVK, Vulkan ICD, IOKit, VM or container graphics bundles. The two are
  excluded for different reasons and only one is permanent:
  - tvOS is **deferred**. Its SDK ships Metal, MetalKit and (deprecated)
    OpenGLES, and MoltenVK supports tvOS 14.5+ on public API only, so Vulkan is
    reachable and store-legal. Turning it on is the final phase of this stack,
    gated behind `WWN_TVOS_GPU=1` in `verify-iland-graphics-bundle.sh`. The
    Vulkan loader does not work on tvOS, so it must use the same direct ICD
    dispatch (`WWN_VULKAN_LIBRARY`) the other targets already use. GLES is the
    slower half: ANGLE has no maintained Chromium GN tvOS target.
  - watchOS is **blocked**. Its SDK ships no `Metal.framework` (device or
    simulator), no OpenGLES, and `CAMetalLayer` is `API_UNAVAILABLE(watchos)`, so
    ANGLE and MoltenVK have nothing to terminate in. This needs a public
    Metal-equivalent surface to exist first, not a port.
- Every Apple target and Android ships real native Weston and Niri entry points;
  compatibility stubs are not acceptance.

## Evidence required for PROPER

Compilation alone is `WIRED`. A capability is `PROPER` only when the
product-shaped artifact passes bundle audit, authoritative stock client launch,
present-callback metadata checks, runtime logs and device/simulator evidence.
DRM open/resources and KMS modeset/page-flip are graded independently.

## Doc map (P4)

| Doc | Owns |
|-----|------|
| This file | Architecture + acceptance contract |
| [`iland-graphics-progress.md`](iland-graphics-progress.md) | Living grades + evidence log |
| [`iland-mode-a-b-desktop.md`](iland-mode-a-b-desktop.md) | Privilege axis + packaging |
| [`toolkit-soft-path.md`](toolkit-soft-path.md) | SDL/Qt/GTK readiness catalog |
| [`testing/graphics-ci-matrix.md`](testing/graphics-ci-matrix.md) | CI + Agent-Device matrix |
| [`wwn-repo-dag.md`](wwn-repo-dag.md) | L0–L4 ownership |

WWN-MCP indexes these paths under the Wawona project; prefer linking here over
duplicating architecture prose in issue comments.
