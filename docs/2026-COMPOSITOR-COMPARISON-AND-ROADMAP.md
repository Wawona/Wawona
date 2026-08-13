# Wawona vs. Inspiration Compositors — Comparison & Full Protocol Roadmap

> **Purpose**: Compare Wawona’s Wayland implementation to Owl, Wayoa, Weston, Hyprland, Sway, Smithay, Mutter, KWin, and others. Identify gaps and outline a plan for full Wayland protocol support on **macOS and iOS** while keeping Wawona distinct.

---

## 1. Compositor Comparison Matrix

| Compositor | Lang | Target | Key Protocols | Architecture | Notes |
|------------|------|--------|---------------|--------------|-------|
| **Owl** | Obj-C | macOS (GNUstep portable) | Core Wayland, deprecated wl_shell | Cocoa backend | Outdated, WIP, limited protocol set |
| **Wayoa** | Rust | macOS only | Core, XDG, wlr-layer-shell, wlr-screencopy | wayland-server-rs + Metal + Cocoa | Each toplevel → NSWindow |
| **Weston** | C | Linux (reference) | ~50+ protocols, color-management-v2, linux-dmabuf v5 | libweston | Reference implementation |
| **wlroots** (Sway/Hyprland) | C | Linux | XDG + full wlr suite, virtual devices | libwlroots | Used by Sway, Hyprland, River, etc. |
| **Smithay** | Rust | Linux | Modular protocol state, layer shell | Rust crate library | Best pattern for state decomposition |
| **Mutter** | C | Linux (GNOME) | Full GNOME stack, wp_color_management_v1 | C/GObject | Production-grade |
| **KWin** | C++ | Linux (KDE) | KDE protocols, org_kde_* | Qt | Plasma integration |
| **Wawona** | Rust + Obj-C/Kotlin | **macOS, iOS, Android** | 68 globals, most functional | Rust core + Metal/Vulkan native frontends | **Unique: cross-platform Apple + Waypipe** |

---

## 2. Wawona vs. Owl & Wayoa (Apple Platform Peers)

### Owl (Objective-C, Cocoa)

- **Status**: Outdated, WIP; many features incomplete.
- **Lessons**:
  - Use of Cocoa as backend validates a native-UI approach.
  - Deprecated `wl_shell`; Wawona correctly uses XDG Shell.
  - Old structure; not a good reference for modern protocol design.
- **Wawona advantages**: Rust core, full XDG Shell, layer shell, many extensions, Waypipe.

### Wayoa (Rust, Cocoa, Metal)

- **Status**: Newer, actively developed; full Cocoa + Metal stack.
- **Protocols**: Core, XDG Shell, wlr-layer-shell, **wlr-screencopy** (Wawona missing).
- **Architecture**:
  - Each toplevel → NSWindow.
  - Metal rendering with damage tracking.
  - wayland-server-rs for protocol handling.
- **Lessons for Wawona**:
  - Screencopy is implementable on macOS; Wayoa lists it as supported.
  - One NSWindow per toplevel is a viable mapping (Wawona uses similar per-window approach).
- **What Wawona does better**: Broader protocol set (68 vs ~10), iOS/Android, Waypipe, session lock, text input v3, tablet, primary selection, etc.

---

## 3. Wawona vs. Weston / Hyprland / Mutter (Reference Compositors)

### Weston (Reference Implementation)

- **Protocol breadth**: Largest set, including:
  - `color-management-v2`, `wp_single_pixel_buffer`, fractional-scale
  - `linux-dmabuf` v5, tearing control
  - `weston-direct-display`, `weston-test`
  - Newer screenshooter protocol replacing older weston-screenshooter.
- **Relevance for macOS/iOS**:
  - **Not applicable**: linux-dmabuf GPU export, DRM lease, weston-direct-display (Linux-specific).
  - **Applicable**: color management, fractional scale, tearing control, single-pixel buffer (Wawona has this), presentation time.
- **Weston patterns**: Per-protocol modules, clear request/event handling, good testing patterns.

### Hyprland & wlroots

- **Protocol set**: XDG Shell, decorations, activation, dialog, foreign toplevel, output management, virtual keyboard/pointer, text input v3, tablet v2, viewporter, tearing, etc.
- **Relevance**: Most of this is Linux-oriented (DMA-BUF, DRM). Wawona already implements many of these at the protocol level; gaps are mostly platform integration.

### Mutter (GNOME)

- **Notable**: Full `wp_color_management_v1` in GNOME 48.
- **Pattern**: Integration with ColorSync-equivalent via image descriptions (SDR/HDR).

---

## 4. What Makes Wawona Unique

| Aspect | Wawona |
|--------|--------|
| **Platforms** | macOS, iOS, Android — no other compositor targets all three |
| **Remote** | Waypipe integration on all targets (libssh2 on Apple mobile, OpenSSH portable on Android, OpenSSH on macOS) |
| **Architecture** | Rust core + native frontends (Obj-C/Swift, Kotlin) — not a pure Rust UI stack |
| **Buffer path** | IOSurface zero-copy on Apple platforms (modifier ID tunneling via linux-dmabuf) |
| **Nested** | Designed for nested use (e.g., inside Xcode, Simulator, fullscreen) |
| **xkbcommon** | Static linking, `MINIMAL_KEYMAP` fallback for App Store compliance on iOS |

---

## 5. Protocol Gaps for macOS/iOS — Prioritized

### Tier 1 — Critical for Common Clients

| Protocol | Status | Blocker | Reference |
|----------|--------|---------|-----------|
| `zwlr_screencopy_manager_v1` | 🟢 Implemented | macOS: CGWindowListCreateImage; pending FFI for platform write | Wayoa, Weston |
| `zwlr_gamma_control_manager_v1` | 🟢 Implemented | macOS: CGSetDisplayTransferByTable, save/restore on Destroy | Weston |
| `ext_image_capture_source_manager_v1` | Not implemented | Pixel readback | Weston, Mutter |
| `ext_image_copy_capture_manager_v1` | Not implemented | Pixel readback | Weston |

**Implementation notes:**

- **Screencopy / image capture**: Render frame to offscreen Metal texture, read back via `getBytes`, copy into `wl_shm` buffer, send to client. Weston and Wayoa both support screencopy on non-Linux backends.

### Tier 2 — Quality of Life (macOS Applicable)

| Protocol | Status | Blocker | Notes |
|----------|--------|---------|-------|
| `wp_color_management_v1` | Not implemented | ColorSync integration, image descriptions | GNOME 48 Mutter; HDR/SDR |
| `wp_color_representation_manager_v1` | Stub | Renderer pixel format awareness | Pair with color management |
| Output hot-plug | Missing | Platform callback for display connect/disconnect | `wl_output` global add/remove |
| Multi-output | Partial | Platform multi-display enumeration | Output placement logic |

### Tier 3 — Linux-Only (Out of Scope for Apple)

| Protocol | Notes |
|----------|-------|
| `zwlr_export_dmabuf_manager_v1` | GPU DMA-BUF export — Linux only |
| `wp_linux_drm_syncobj_manager_v1` | DRM syncobj — Linux only |
| `wp_drm_lease_device_v1` | DRM lease (VR) — Linux only |
| `zwp_linux_explicit_synchronization_v1` | Sync fences — Linux GPU stack |
| `wl_fixes` | Some compositors use; optional |

### Tier 4 — Low Priority / KDE-Specific

| Protocol | Notes |
|----------|-------|
| `org_kde_kwin_blur_manager` | Platform blur effect |
| `org_kde_kwin_contrast_manager` | Platform contrast effect |
| `org_kde_kwin_shadow_manager` | Platform shadow rendering |
| `org_kde_kwin_dpms_manager` | Display power (CGDisplay… on macOS) |
| `xwayland_shell_v1` | Only if XWayland support is added |

---

## 6. Roadmap: Full Protocol Support on macOS/iOS

### Phase A — Screencopy & Capture (High Impact)

1. **`zwlr_screencopy_manager_v1`**
   - Add `copy_frame()` path: render to offscreen Metal texture, read back via `getBytes`, create `wl_shm` buffer, fill with pixels.
   - Support `Copy` and `CopyWithDamage` (damage-based optimization).
   - Follow Wayoa’s approach: single compositor output capture first.

2. **`ext_image_capture_source_manager_v1`** / **`ext_image_copy_capture_manager_v1`**
   - Same pixel-readback path as screencopy.
   - Capture source from output or toplevel (render node → texture → readback).

### Phase B — Gamma Control (macOS)

1. **`zwlr_gamma_control_manager_v1`**
   - Implement via `CGSetDisplayTransferByTable` / `CGGetDisplayTransferByTable`.
   - Handle multiple outputs; apply per-output gamma ramps.
   - Weston provides a reference for gamma control semantics.

### Phase C — Color Management (Optional but Valuable)

1. **`wp_color_management_v1`**
   - Integrate ColorSync: output ICC profiles → image descriptions.
   - Surface feedback for preferred image descriptions.
   - GNOME 48 Mutter and color-and-hdr docs as references.

### Phase D — Output Hot-Plug & Multi-Output

1. **Output hot-plug**
   - Platform callbacks: `displayConnected` / `displayDisconnected`.
   - Create/destroy `wl_output` globals; send `wl_registry.global_remove` for removed outputs.
   - Update `xdg_output` and layer shell when outputs change.

2. **Multi-output**
   - Enumerate displays via `CGDisplayCount` / `CGGetActiveDisplayList`.
   - Logical output placement; map outputs to `wl_output` geometry.

### Phase E — Polish & Minor Protocols

- DnD action negotiation (copy/move/ask) for `wl_data_device_manager`.
- Subsurface input region clipping to parent in hit-testing.
- SIGBUS handling for truncated SHM fds (complex on macOS/iOS).
- Choreographer vsync on Android (`AChoreographer_postFrameCallback`).

---

## 7. Implementation References by Protocol

| Protocol | Reference | Notes |
|----------|-----------|-------|
| Screencopy | Wayoa, Weston | Metal readback: render → texture → `getBytes` → shm |
| Gamma | Weston `gamma-control.c` | `CGSetDisplayTransferByTable` |
| Color management | Mutter (GNOME 48), wayland-protocols color.rst | ColorSync, image descriptions |
| Output hot-plug | Smithay output handling | DisplayHandle, global add/remove |
| Layer shell | wlroots, Smithay | Wawona already functional |

---

## 8. Summary

- **vs. Owl**: Wawona is far ahead in protocols and architecture; Owl is mostly historical.
- **vs. Wayoa**: Similar Cocoa + Metal stack; Wawona has more protocols and platforms; Wawona should add screencopy like Wayoa.
- **vs. Weston/Hyprland/Mutter**: Wawona implements most shared protocols; main gaps are screencopy, gamma, color management, and output hot-plug.
- **Unique value**: macOS + iOS + Android, Waypipe, IOSurface zero-copy, Rust core + native frontends.

**Priority for macOS/iOS**: Implement screencopy (pixel readback) and gamma control first. These unblock common use cases (screen recorders, night mode) and bring Wawona closer to Wayoa/Weston behavior on Apple platforms.

---

*Last updated: 2026-02-20*
