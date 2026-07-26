# Toolkit soft path — stack readiness (not the ports)

Wawona does **not** port SDL/Qt/GTK inside the graphics epic. Those stay
follow-on repos (`wwn-sdl2` / `wwn-qt` / `wwn-gtk`). This document is the
catalog of what those ports need from the stack that `wwn-iland` + Wawona's
compositor must keep green. Canonical architecture prose also lives in
[`iland-graphics-stack.md`](iland-graphics-stack.md) (§ Toolkit readiness).

Tracking issues already open:

| Toolkit | Issue | How-to doc |
|---------|-------|------------|
| SDL2 / SDL2_gfx | [#107](https://github.com/Wawona/Wawona/issues/107) | [`issues/sdl2-gfx-demo-port.md`](issues/sdl2-gfx-demo-port.md) |
| GTK4 | [#109](https://github.com/Wawona/Wawona/issues/109) | [`issues/gtk4-demo-port.md`](issues/gtk4-demo-port.md) |
| Qt / qmlscene | (follow-on under epic [#122](https://github.com/Wawona/Wawona/issues/122)) | [`issues/qmlscene-port.md`](issues/qmlscene-port.md) |

## What every toolkit needs

| Need | GPU path | Software / tvOS+watchOS path | Proven by |
|------|----------|------------------------------|-----------|
| Wayland display + xdg-shell | yes | yes | weston-simple-shm, weston-simple-egl, opengl-cube |
| `wl_shm` + damage | optional | **required** | weston-simple-shm / flower |
| EGL + `wl_egl_window` + dmabuf (IOSurface/AHB) | **required** for GL toolkits | N/A | opengl-cube, weston-simple-egl (macOS PROPER) |
| Vulkan Wayland WSI (IOSurface/AHB `VkImage`) | required for VK toolkits | N/A | **MISSING** (`wl-winsys-vulkan`) |
| Single shared CPU present spine | fallback | **required** | pixman path; no second full-frame copy |
| Multi-window (iPadOS / visionOS) | required | required | platform-targets rule |

## Spine rules (do not regress)

1. **One software buffer path.** Cairo / Qt raster / SDL software / Weston
   pixman all feed `wl_shm` (or a CPU-readable GBM BO) into the same
   stride-/damage-aware present. Do not invent a second CPU blit pipeline per
   toolkit.
2. **No stacked translation.** Toolkit GLES goes EGL→ANGLE→Metal (or system
   GLES on Android). Toolkit Vulkan goes ICD→Metal. Never Zink-to-reach-Metal.
3. **tvOS / watchOS stay software.** SDL/GTK/Qt demos that want those targets
   must ship a SHM/software renderer; never pull ANGLE/MVK into those schemes.
4. **waypipe zero-copy stays available.** A toolkit that only speaks SHM is
   fine; a GPU session must still be able to use the IOSurface/AHB dmabuf
   route (#86). See [`zerocopy-waypipe`](iland-graphics-progress.md).

## Entry criteria before starting a toolkit port

From `iland-graphics-stack.md`:

1. kmscube Mode A on macOS / iOS / iPadOS / visionOS / Android.
2. weston-simple-egl (or equivalent) through ANGLE on GPU targets.
3. vkcube where GPU policy allows.
4. IOSurface/AHB dmabuf without a mandatory CPU copy on the GPU path.
5. Shared software buffer path with damage-limited updates.

macOS (1)(2)(4) are PROPER as of 2026-07-26. Apple-mobile and Android remain
WIRED for several cells; toolkit ports may begin against the macOS path and
must not claim PROPER on a target the stack has not graded PROPER.
