# Wawona. Compositing Frameworks & Present-Path Contract

One contract, four backends. The Rust core produces composited surface content;
each platform frontend presents it. This doc defines the present-path contract
so every backend behaves identically at the pixel level.

## The contract

For each frame the core hands the frontend a scene of surfaces, where every
surface carries:

- a buffer (`wl_shm` CPU pixels **or** an IOSurface/AHardwareBuffer dmabuf),
- destination geometry in **logical** points,
- a `buffer_scale` (HiDPI factor), and
- damage.

The frontend must:

1. Present at native (physical) resolution. Never upscale a HiDPI buffer.
2. Use top-left gravity and an explicit `contentsScale` when buffer size and
   node size mismatch (no implicit stretch).
3. Honor damage where the backend supports partial present.
4. Composite off the platform's main/UI thread where possible.

## Per-platform backends

| Platform | Framework | Present layer | HiDPI | HDR/EDR |
|----------|-----------|---------------|-------|---------|
| macOS | AppKit | `CAMetalLayer` via `WWNIlandPresenter`; per-window `CALayer` | `window.backingScaleFactor`, dynamic `contentsGravity`/`contentsScale` | `WWNEDRConfigureMetalLayer` (RGBA16Float + extended-linear sRGB) |
| iOS / iPadOS | UIKit | `CAMetalLayer` | `UIScreen.scale` / `traitCollection.displayScale` | same EDR helper |
| tvOS / visionOS | UIKit | `CAMetalLayer` | screen scale | EDR where display supports it |
| Android | NDK | `ANativeWindow` on dedicated render thread | monitor scale | Vulkan swapchain format |
| Linux | GTK4 | Cairo / GTK drawing area | GDK monitor scale factor | deferred |

## HiDPI rule (shared)

Buffer/node size match → `contentsGravity = resize`, `contentsScale = 1`.
Mismatch (Weston-style HiDPI where the client omits `set_buffer_scale`) → infer
scale, set `contentsGravity = topLeft` and the inferred `contentsScale`. macOS
(`WWNCompositorBridge.draw_quads_with_nodes`) and iOS
(`WWNCompositorView_ios.presentWaylandFrame`) implement identical logic; the Rust
side is unit-tested (`view_to_surface_coords`, `view_to_surface_scale`).

## Threading

- macOS/iOS: composite on a `QOS_CLASS_USER_INTERACTIVE` serial queue
  (`_compositorQueue`); present syncs to `CADisplayLink`/`CVDisplayLink`.
- Android: `render_thread` (pthread) at urgent-display priority, vsync-aligned
  via `AChoreographer`; never blocks the JNI thread.

## External display / mirroring (iOS)

`WWNExternalDisplaySupport` mirrors the composited output and virtual cursor to a
`UIWindowSceneSessionRoleExternalDisplayNonInteractive` scene; input can switch
to touchpad + virtual-cursor mode when an external display is attached.
