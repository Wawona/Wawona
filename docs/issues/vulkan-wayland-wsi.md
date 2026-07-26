# Vulkan Wayland WSI (IOSurface / AHB dmabuf)

Tracking for plan follow-on `wl-winsys-vulkan`. Complements the Wayland-EGL
winsys that already makes `opengl-cube` / `weston-simple-egl` PROPER on macOS.

## Goal

Stock Vulkan Wayland clients (`VK_KHR_wayland_surface` + `VK_KHR_swapchain`)
present through Wawona's compositor the same way GLES clients do: each swap
posts an IOSurface (Apple) or AHardwareBuffer (Android) as a
`zwp_linux_dmabuf_v1` `wl_buffer` under the high-bit buffer-id modifier.

Then re-host **Vulkan Cube** as a real Wayland client (drop the iland KMS host
for that catalog id), mirroring the OpenGL Cube correction.

## Why not MoltenVK's native WSI

MoltenVK implements `VK_EXT_metal_surface` / `VK_MVK_macos_surface`, not
`VK_KHR_wayland_surface`. Asking the ICD for Wayland WSI returns NULL. The
fix is an **iland-owned WSI shim** in front of the selected ICD
(MoltenVK / KosmicKrisp on Apple; system / SwiftShader on Android), not a
fork of MoltenVK.

## Architecture

```text
Vulkan client
  vkCreateWaylandSurfaceKHR / vkCreateSwapchainKHR / vkQueuePresentKHR
        │
        ▼
iland Wayland-Vulkan WSI  (new, next to libiland_wayland_egl)
  ├─ reuse IlandWlWinsys / IlandWlSwapchain (dmabuf post + IOSurface slots)
  ├─ bind each slot's IOSurface as a VkImage via VK_EXT_metal_objects
  │    (or VK_ANDROID_external_memory_android_hardware_buffer on Android)
  └─ present = queue submit fence → iland_wl_swapchain_post(slot)
        │
        ▼
Wawona compositor  (existing IOSurfaceLookup / AHB import)
```

Dispatch: wrap `vkGetInstanceProcAddr` / `vkGetDeviceProcAddr` (same pattern as
`WWN_VULKAN_LIBRARY` direct ICD load) so Wayland WSI entry points resolve to
iland and everything else falls through to the ICD.

## Reuse (do not reinvent)

| Piece | Where |
|-------|--------|
| IOSurface dmabuf modifier + post | `iland_wl_winsys.h` / `egl_wayland.c` |
| `wl_egl_window` geometry | extend with surface-only swapchain create |
| Compositor import | `WWNCompositorBridge.m` `IOSurfaceLookup` |
| ICD selection | `WWNSettings_ApplyGraphicsDriverSelection` / Android `apply_graphics_driver_selection` |
| Cube packaging | `wwn-kmscube` vkcube recipes (today KMS/GBM) |

## Phases

1. **Swapchain from `wl_surface`** — `iland_wl_swapchain_create_for_surface(ws, surface, w, h)` so Vulkan does not need a fake `wl_egl_window`.
2. **WSI shim archive** — `libiland_wayland_vulkan.a`: surface, swapchain, images, present; force-loaded only for Vulkan Wayland clients.
3. **IOSurface → VkImage** — MoltenVK `VK_EXT_metal_objects` import; fail loud if the ICD cannot.
4. **Re-host vkcube** — Wayland + xdg-shell + WSI; remove from `WWNIsIlandGpuCubeClientId` like opengl-cube.
5. **Android AHB variant** — same WSI shape, different import extension.
6. **Evidence** — Agent-Device / log proof; grade Wayland+Vulkan row PROPER on macOS.

## Hard don'ts

- Do not claim Wayland for the KMS-hosted vkcube.
- Do not stack GLES→Zink→Vulkan to reach Metal.
- Do not ship this WSI into tvOS/watchOS until `final-tvos-gpu`.
- Do not put Wayland symbols into `libiland_userland.a` (KMS-only clients must stay Wayland-free).

## Status

**WIRED 2026-07-26.** Landed:

- `iland_wl_swapchain_create_for_surface` + `iland_wl_swapchain_present_pixels`
  (orientation-aware; TOP_DOWN for Vulkan)
- `libiland_wayland_vulkan.a` (`iland_vk_wayland_wrap_gipa` + Wayland WSI)
- `vkcube` re-hosted as xdg-shell Wayland client; KMS kept as `vkcube_kms.c`
- Machines Start routes `vkcube` via compositor (not `WWNIlandPresenter`)

macOS Wayland+Vulkan cell stays **WIRED** until Agent-Device shows a rendered
frame; then promote to PROPER.
