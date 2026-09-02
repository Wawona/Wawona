# linux-dmabuf zero-copy (Wawona)

Canonical matrix for `zwp_linux_dmabuf_v1` on every Wawona target. Complements
[`iland-graphics-stack.md`](./iland-graphics-stack.md) and
[`mode-a-b.md`](./mode-a-b.md). Site: wawona.io `/docs/linux-dmabuf/`.

**Goal:** one `wl_buffer` object, no CPU blit on GPU sessions, every client
backend (EGL, Vulkan WSI, DRM/KMS, waypipe) and every present sink on that OS.

This is **not** Linux kernel dma-buf on Apple/Android. `wwn-iland` emulates
KMS/GBM over IOSurface (Apple) / AHardwareBuffer (Android). Never open
`/dev/dri` or `/dev/kgsl`.

## Modifier convention

| OS | Advertise | Import |
|---|---|---|
| Apple (macOS / iOS family except watchOS) | High-bit modifier `0x8000_0000_0000_0000` + IOSurface id | `IOSurfaceLookup` |
| Android | Same high-bit + AHB id | AHB registry |
| Linux | `DRM_FORMAT_MOD_LINEAR` + real modifiers | GBM import of the fd |
| watchOS | **Do not register** `zwp_linux_dmabuf_v1` | SpriteKit of `wl_shm` only |

Never advertise `DRM_FORMAT_MOD_LINEAR` on Apple or Android.

## Present sinks

| Sink | Target / mode | Notes |
|---|---|---|
| `CAMetalLayer` | macOS Mode A; iOS/iPadOS/visionOS/tvOS Mode A | Default in-window GPU path |
| `framebufferd` | macOS Mode B Classic | Page-flip is the IOSurface; no extra blit |
| IOMobileFramebuffer | iOS/iPadOS TrollStore and Sileo | `ldid` entitlements; **never** in store link |
| `ANativeWindow` / Surface | Android Mode A and Home Mode B | AHB import then present |
| Host GBM/EGL | Linux | Real dma-buf fd |
| SpriteKit | watchOS | SHM upload only |

macOS Mode A must stay green while Classic and TrollStore sinks land.

## Client backends (`wwn-iland`)

| Backend | Done means |
|---|---|
| Wayland-EGL | Swap posts IOSurface/AHB dmabuf `wl_buffer` |
| Vulkan Wayland WSI | `VK_KHR_wayland_surface` shim; `vkcube` leaves KMS host |
| DRM/KMS/GBM | Same IOSurface/AHB as dmabuf export |
| `wl_shm` | Software fallback only (allowed; log `fallback_shm`) |

## Completion gates

A GPU session is green only when structured logs show `copy=zero` for
create → import → present. `copy=cpu` or unexpected `fallback_shm` is red.

Catalog `zwp_linux_dmabuf_v1` stays **Partial** until the proof matrix in
[`testing/everywhere-matrix.md`](./testing/everywhere-matrix.md) has log +
screenshot (or explicit N/A) under
`Wawona/.agent-device/test-artifacts/dmabuf/`.

### Logging schema (`wwn.dmabuf`)

| Field | Meaning |
|---|---|
| `op` | bind, modifier_ad, feedback, add_plane, create, create_immed, import, present, fallback_shm |
| `os` / `sink` | apple_metal, framebufferd, iomfb, ahb_surface, linux_gbm, watch_spritekit |
| `modifier` | hex |
| `backing_id` | IOSurface id / AHB id / drm name |
| `format` | fourcc |
| `copy` | `zero` or `cpu` |
| `client` | opengl-cube, weston-simple-egl, vkcube, waypipe, nested weston/niri |

```text
RUST_LOG=wwn.dmabuf=trace,linux_dmabuf=trace
WAYLAND_DEBUG=1   # on the client
adb logcat -s WawonaDmabuf
```

## Mode A vs Mode B

Mode A and Mode B are **separate** proofs. A Classic or TrollStore green cell
does not promote the store IPA. Store CI must grep-fail Mode B / IOMFB symbols.

Jailbreak proof for iOS Desktop uses a **vphone-cli `jb` guest** (real iOS
kernel VM), not the Xcode Simulator. See Mode B channels and the vphone harness
docs under `docs/testing/`.

## Hard rejects

- LINEAR ads on Apple/Android
- Fake dmabuf global on watchOS
- Real kernel DRM / KGSL
- Mode B / IOMFB in store IPA
- Marking catalog Functional from a unit test alone
