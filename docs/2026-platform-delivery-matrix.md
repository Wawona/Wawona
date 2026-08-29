# Wawona. Per-Platform Wayland Delivery Matrix

How a Wayland client's pixels reach the screen on each target. Three delivery
modes exist; a platform may support several. Scope authority:
[`2026-SOURCE-OF-TRUTH.md`](./2026-SOURCE-OF-TRUTH.md).

## Delivery modes

- **native**. Client connects directly to the Wawona compositor socket
  (`$WAYLAND_DISPLAY`) running in-process. Buffers are `wl_shm` (CPU) or, where
  supported, IOSurface/AHardwareBuffer-backed dmabuf. Compositor composites into
  the platform present layer.
- **nested**. A bundled Weston runs as a child compositor on its own
  `wayland-N` socket; its output is a single client surface into Wawona. Used for
  full desktop sessions and XWayland on non-store builds.
- **waypipe**. Client runs remotely (or in a VM); `waypipe` proxies the Wayland
  protocol over SSH (libssh2 on Apple mobile, OpenSSH portable on Android,
  OpenSSH on macOS) or vsock. GPU transport requires a Vulkan ICD; without one
  we force `--no-gpu` SHM transport.

## Matrix

| Platform | native | nested Weston | waypipe | Default first-run path |
|----------|:------:|:-------------:|:-------:|------------------------|
| macOS | ✅ | ✅ | ✅ (SSH/vsock) | native |
| iOS / iPadOS | ✅ | ✅ | ✅ (libssh2) | native |
| tvOS | ⚠️ focus-only | ✅ | ✅ | nested |
| visionOS | ✅ | ✅ | ✅ | native |
| watchOS | ✅ (SHM/CPU) | ✅ | ✅ (libssh2) | native |
| Android | ✅ | ✅ | ✅ (OpenSSH portable) | native |
| Linux (host) | client-to-host | ✅ | ✅ | client-to-host |

Legend: ✅ supported · ⚠️ limited · ❌ not offered.

## Platform notes

### watchOS. Native + remote; GPU blocked
The compositor runs natively (SHM/CPU present; no public Metal). Waypipe remote
sessions are also offered. Local zsh is constrained (no coreutils). See
[WATCHOS-SCOPE](./ios-local-shell/WATCHOS-SCOPE.md) and
[`2026-SOURCE-OF-TRUTH.md`](./2026-SOURCE-OF-TRUTH.md).

### tvOS. Focus model
No absolute pointer. Input is driven by the UIKit focus engine and
`GCController`; a virtual pointer can be moved by the remote/siri controller.
Clients that require a real pointer should run through the virtual-pointer path.
Prefer nested/waypipe delivery.

### GPU vs SHM (all platforms)
`waypipe` and dmabuf import need a working Vulkan ICD. `main.m` resolves the
bundled ICD (KosmicKrisp/MoltenVK) into `VK_DRIVER_FILES`; `WWNWaypipeRunner`
forces `--no-gpu` when `VK_DRIVER_FILES` is unset so sessions never stall on a
missing GPU transport. See [`drivers-how-to`](./drivers-how-to/) and
[`2026-compositing-frameworks.md`](./2026-compositing-frameworks.md).

### Build targets
Flake attributes per platform: [`testing/everywhere-matrix.md`](./testing/everywhere-matrix.md).
