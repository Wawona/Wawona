# Guest GUI is Wayland into Wawona (iland)

**Product boundary.** A Linux guest in Wawona is a **Wayland client of Wawona**.
Pixels go through **wwn-iland** (IOSurface + Metal on Apple, AHardwareBuffer on
Android). Same nested-compositor path as weston/niri: vsock + **waypipe**, then
iland present. Not a second display stack inside the VM engine.

This is **not** UTM’s CocoaSpice / Spice / ANGLE / virgl / virtio-gpu-into-UTM
window. Those paths are forbidden in Wawona products.

## Required

- Guest compositor and apps bind Wayland globals on Wawona (or waypipe into it).
- Host present is `iland_drm_set_present_callback` / `WWNIlandPresenter`.
- Graphics keys (ANGLE, MoltenVK, KosmicKrisp, SwiftShader) stay **L1**
  `wwn-iland`. Never rebuild them inside `wwn-vms` / UTM.

## Hard rejects

- Shipping or linking UTM Spice, CocoaSpice, virgl, or UTM’s ANGLE/MoltenVK
- Treating virtio-gpu-into-UTM as the guest GUI
- A guest that only looks correct in UTM’s viewer
- Re-hosting a Wayland guest onto UTM’s display because iland is unfinished

Canonical: `wawona-linux-vms-relay-runtime`, `wawona-port-fidelity`,
`wawona-repo-dag`. Cursor: `.cursor/rules/wawona-guest-wayland-iland.mdc`.
