# IOSurface dma-buf zero-copy

Wawona implements `zwp_linux_dmabuf_v1` on Apple hosts with IOSurface-backed
buffers. The protocol name is Linux-shaped, but the backing object and lifetime
are entirely userspace. Wawona never opens a kernel DRM node.

## Data path

```text
Wayland EGL, Vulkan, or iland KMS producer
  -> IOSurface-backed dma-buf parameters
  -> Wawona linux-dmabuf import and retained IOSurface owner
  -> shared Metal texture presenter
  -> Mode A CAMetalLayer or Mode B IOMobileFramebuffer
```

The Rust compositor validates width, height, stride, offset, format, and plane
count against the imported IOSurface. `create` and `create_immed` share the same
validation and ownership path. Destroying protocol parameters closes unused
file descriptors, while a successfully imported buffer retains the IOSurface
until the Wayland buffer is released.

On iOS Mode A, `WWNCompositorBridge` keeps an IOSurface in the node cache and
routes it through `WWNCompositorView_ios` and `WWNIlandPresenter`. It does not
create a copied `CGImage`. `wl_shm` buffers retain the CPU upload path.

On iOS Mode B, the same IOSurface must reach IOMFB unchanged. Authority
for that swap is `wwn-iomfb-rs` (`GpuSwapchain::present_external`). The
frozen `wwn-iland-iomfb` sink must not grow. A Metal blit is allowed
only when a producer texture has no IOSurface backing.

## Formats and modifiers

Apple imports use the IOSurface format and plane metadata. Wawona does not
advertise Linux `DRM_FORMAT_MOD_LINEAR` as an Apple allocation promise.
Protocol version negotiation provides compatibility for older clients without
maintaining a duplicate implementation.

## Evidence

Structured logs use `wwn.dmabuf`, `wwn.iland.iomfb`, and
`wwn.modeb.desktop`. A direct frame must report:

```text
create/import: backing_id=<IOSurfaceID>
present: route=direct-iosurface copy=zero backing_id=<same IOSurfaceID>
```

An intentional non-IOSurface producer reports `route=metal-blit`. A `wl_shm`
frame reports its upload fallback separately and is not zero-copy evidence.

The final hardware proof requires a physical TrollStore device because vPhone
does not provide Metal or physical IOMFB behavior. vPhone remains valid for the
TrollStore install path, bundle identity, `ldid` entitlements, JIT attach state,
Rust session policy, and CPU fallback.

## Implementation

- Protocol import: `src/core/wayland/ext/linux_dmabuf.rs`
- Buffer lifetime: `src/core/surface/buffer.rs`
- Mode A presenter: `src/platform/ios/WWNIlandPresenter.m`
- iOS compositor route: `src/platform/ios/WWNCompositorView_ios.m`
- Mode B broker: `src/platform/ios_modeb.rs`
- IOMFB present (Mode B): `wwn-iomfb-rs` (`docs/GPU.md`). Frozen sink:
  `wwn-iland/crates/wwn-iland-iomfb` until Wawona switches.
