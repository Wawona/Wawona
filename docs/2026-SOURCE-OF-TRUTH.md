# Wawona. Single Source of Truth (2026)

This document is the canonical reconciliation point for facts that were
previously scattered (and drifting) across the docs tree: protocol counts,
per-platform scope, the X11 story, and settings inventory. When any of these
change, update **here first**, then the specialized docs linked below.

> **Public subset:** wawona.io/docs may cite this file. Do not copy audits,
> issue ledgers, or App Review checklists onto the site.

> Rule: numbers and scope claims elsewhere must cite this file or the
> auto-generated manifests it points at. Prose that contradicts an
> auto-generated artifact is wrong by definition.

## Protocol counts (authoritative)

- **Advertised Wayland globals: see [`protocol-status.md`](./protocol-status.md)**
  (auto-generated from the live registry for the active `ProtocolProfile`).
  Do **not** hand-maintain a count anywhere else.
- Regenerate: `scripts/gen-protocol-status.sh`. CI (`cargo-test-linux`) fails if
  the committed manifest drifts from the live registry.
- Behavioral requirements (not just presence) live in
  [`compliance/wayland-protocol-conformance-matrix.md`](./compliance/wayland-protocol-conformance-matrix.md).
- Advertisement **honesty** (a global is only exposed when serviceable for the
  active `ProtocolProfile`) is machine-verified by
  `src/tests/protocol_matrix.rs`.

## Per-platform scope (authoritative)

| Platform | UI toolkit | Present path | Wayland delivery | Local shell | Notes |
|----------|-----------|--------------|------------------|-------------|-------|
| macOS | AppKit (+ SwiftUI settings) | Mode A: CAMetalLayer / `WWNIlandPresenter`; Mode B (optional): `libwayland-mac.dylib` + `framebufferd` | native, nested Weston/Niri, waypipe/SSH | yes | Mode A default (store-safe). Mode B = SIP-gated Desktop Replacement in `wawona-macos-desktop-host` only. See [`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md) |
| iOS / iPadOS | UIKit | CAMetalLayer | native, nested Weston/Niri, waypipe/SSH (libssh2) | bundled zsh PTY | App Store compliant. Optional software: WASI `.wasm` via Wawona Runtime (Files + package client). Containers: planned container-in-VM (UTM-SE jitless), not Wasm |
| tvOS | UIKit | CAMetalLayer / ANGLE + MoltenVK (rendered-frame evidence pending) | native, nested Weston/Niri, waypipe | constrained zsh | Focus-engine on Machines. In a client: Siri Remote clickpad is a virtual pointer (Select clicks). Play/Pause toggles the system keyboard. Menu confirms session exit. GPU drivers linked (`WWN_TVOS_GPU`). VM/container forbidden. |
| visionOS | UIKit | CAMetalLayer | native, nested Weston/Niri, waypipe | bundled zsh PTY | macOS product parity for bundled clients / Machines UX; **VM/container kinds forbidden** |
| watchOS | WatchKit | SHM/CPU (`wwn-iland-apple-fallback`); GPU ⛔ blocked | native + remote (waypipe) | constrained zsh (no coreutils) | GPU: no public Metal. Compositor is not remote-only. See [WATCHOS-SCOPE](./ios-local-shell/WATCHOS-SCOPE.md) |
| Android | Jetpack Compose (Material You 3) | ANativeWindow / dedicated render thread | native, nested Weston/Niri, waypipe (OpenSSH portable via `wwn-ssh`) | via container | Render off JNI thread. Direct Turnip/KGSL forbidden |
| Linux (host) | GTK4 + libadwaita | Cairo/GTK | client to host compositor; nested | yes | Reference target |

Build targets per platform: [`testing/everywhere-matrix.md`](./testing/everywhere-matrix.md).

## X11 story (authoritative)

Wawona has **no local X server** on any platform. X11 clients are served via:

1. **Remote XWayland over waypipe** (`waypipe --xwls`). Primary, App Store safe.
2. **Nested-Weston XWayland**. Only on non-store macOS builds (nested Weston can
   spawn its own Xwayland).

`xwayland_shell_v1` + `zwp_xwayland_keyboard_grab_manager_v1` are advertised so a
remote/nested Xwayland can attach. Details: [`2026-x11-strategy.md`](./2026-x11-strategy.md).

## Settings inventory (drift control)

- Preference keys are declared in
  `src/platform/macos/ui/Settings/WWNPreferencesManager.{h,m}` (shared with iOS).
- Machine engine keys (`MachineVMProvider`, `MachineVMVsockPort`,
  `MachineContainerRuntime`, `MachineContainerImageStore`) are backed by the
  `wwn-vms` (VM engine) and `wwn-containers` (OCI) dependencies and consumed by
  `WWNMachineProfileStore.m` + the VM/container runners. They are
  capability-driven per target (see each dep's `COMPLIANCE.md`), not stubs.
- Graphics driver default is capability-tiered:
  `+[WWNPreferencesManager defaultVulkanDriverForHardware]` → KosmicKrisp on
  Apple Silicon + macOS 26+, else MoltenVK.
- Settings semantics: [`settings.md`](./settings.md).
- Desktop / LockScreen / Mode B keys and SIP gates:
  [`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md).

## Related canonical docs

- iland Mode A / Mode B + Desktop Replacement: [`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md)
- Platform delivery matrix: [`2026-platform-delivery-matrix.md`](./2026-platform-delivery-matrix.md)
- X11 strategy: [`2026-x11-strategy.md`](./2026-x11-strategy.md)
- wlroots compatibility: [`2026-wlroots-compat.md`](./2026-wlroots-compat.md)
- Smithay adoption decision (RFC #35 closure): [`compliance/smithay-adoption-decision.md`](./compliance/smithay-adoption-decision.md)
- Compositing frameworks / present-path contract: [`2026-compositing-frameworks.md`](./2026-compositing-frameworks.md)
- Toolkit / DE compatibility: [`2026-toolkit-de-compat.md`](./2026-toolkit-de-compat.md)
- Universal client strategy: [`2026-universal-client-strategy.md`](./2026-universal-client-strategy.md)
- Green-light gates: [`2026-greenlight-gates.md`](./2026-greenlight-gates.md)
- wwn-* porting convention: [`2026-wwn-porting-convention.md`](./2026-wwn-porting-convention.md)
- Build/CI optimization: [`2026-build-ci-optimization.md`](./2026-build-ci-optimization.md)
- CI branch matrix + FlakeHub: [`ci.md`](./ci.md)
- Org FlakeHub Cache: [`flakehub-cache.md`](./flakehub-cache.md)
- Tier-2 roadmap (remaining large features): [`2026-tier2-roadmap.md`](./2026-tier2-roadmap.md)
