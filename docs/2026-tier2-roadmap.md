# Wawona — Tier 2 Roadmap (large, multi-session features)

These are the deliberately-deferred large features from the compositor campaign.
Each is genuinely multi-session (new native subsystems, entitlements, OS/SDK
gating, hardware). This doc captures the design + concrete entry points so the
work can start cleanly; it does **not** claim they are implemented.

Status source of truth: [`2026-SOURCE-OF-TRUTH.md`](./2026-SOURCE-OF-TRUTH.md).

## p9-iland-dmabuf — IOSurface-backed dmabuf zero-copy

- **Goal**: clients' GBM buffers presented as IOSurface-backed dmabuf without a
  CPU copy (currently SHM/copy path on Apple).
- **Entry points**: `wwn-iland` (GBM/EGL/DRM userland), `zwp_linux_dmabuf_v1`
  (`src/core/wayland/ext/linux_dmabuf.rs` — currently advertisement-honest, no
  raw formats), `WWNIlandPresenter` (Metal present).
- **Plan**: back GBM allocations with IOSurface; export dma-buf fd via the
  iland shim; import on the compositor side as an `IOSurface`-wrapped
  `CVPixelBuffer`/`MTLTexture`; advertise the real modifiers once import works;
  update the dmabuf feedback tranche.
- **Gate**: `test_protocol_matrix_dmabuf_feedback_resolves` + a new zero-copy
  present test; graphics CTS lane.

## p18-ui-toolkits — cross-platform UI parity

- **Goal**: adaptive layouts + a shared machine-config model + a11y ids across
  AppKit/SwiftUI, UIKit, GTK4, Compose.
- **Entry points**: `WWNMachineProfileStore` (macOS), `MachineProfiles.kt`
  (Android), linux-ui model; a11y ids already added on iOS compositor view +
  Android testTags.
- **Plan**: extract one canonical machine-config schema (already partially
  shared via `WawonaModel`), generate platform bindings, add a11y ids to every
  interactive control, wire `ui_parity_diff.py` golden pairs.
- **Gate**: nightly UI parity job (`nightly-full-matrix.yml`).

## p25-macos-containers — containerization.framework + vsock waypipe (macOS 26+)

- **Goal**: "WSLg for macOS" — run Linux GUI apps in an Apple container, bridged
  to Wawona over vsock waypipe.
- **Entry points**: `Machine*Stub` prefs + `WWNMachineProfileStore`;
  `WWNWaypipeRunner` (`waypipeVsock` flag already exists).
- **Plan**: wrap `containerization.framework` (macOS 26 SDK-gated); expose a
  vsock socket; run `waypipe --vsock` client/server across the boundary; surface
  container lifecycle in the Machines UI (stubs already persisted).
- **Gating**: macOS 26+, new entitlements.

## p26-vm-nixos — prebuilt NixOS VMs via Virtualization.framework

- **Goal**: OrbStack-style prebuilt NixOS VMs, GUI forwarded into Wawona.
- **Status**: **first slice landed** (host launcher + guest image + flake wiring).
  See [2026-nixos-vm-bridge.md](./2026-nixos-vm-bridge.md).
- **Entry points**:
  - `wawona-vz` (macOS host launcher, `nix run .#wawona-vz`) —
    [WawonaLinuxVZ.swift](../src/platform/macos/vm/WawonaLinuxVZ.swift) /
    [vz-launcher.nix](../dependencies/wawona/vz-launcher.nix). Direct-kernel boot,
    virtio-vsock + virtiofs + balloon + optional Rosetta; ad-hoc signed with
    `com.apple.security.virtualization`.
  - `wawona-nixos-guest` (aarch64-linux guest image) —
    [nixos-guest.nix](../dependencies/wawona/nixos-guest.nix). **Built on the
    NixOS host / a Linux builder.**
  - Machines UI `virtual_machine` type + `Machine*Stub` prefs (next hook).
- **Design**: OrbStack model — Virtualization.framework + **vsock** transport
  (not a virtual NIC / RDP). Guest runs `waypipe --vsock` forwarding a Wayland
  session (cage+foot today; wwn-niri/sway/… later) into Wawona's socket.
- **Remaining**: validate the waypipe vsock topology end-to-end on the NixOS
  host; wire the Machines UI; tune rootfs/memory; OrbStack-style virtiofs caching.
- **No host-NixOS dependency**: the `aarch64-linux` guest image builds locally on
  the Mac via **Determinate Nix's native (Virtualization.framework) Linux
  builder** (`external-builders` in `/etc/nix/nix.conf`): just
  `nix build .#packages.aarch64-linux.wawona-nixos-guest`. The same builder
  unblocks the other Tier-2 Linux lanes (WLCS / GTK runtime / dEQP).

## p27-ios-utmse — UTM SE jitless VM backend (iOS/iPadOS/visionOS)

- **Goal**: run a jitless VM on iOS (UTM SE model), reusing Wawona's GUI.
- **Entry points**: `wwn-utm` (per porting convention), Machines UI.
- **Plan**: integrate the jitless (TCG-interpreter) backend; App Store
  compliance (no JIT); present guest via the same compositor path; scope to what
  SE performance allows.

## p11-mode-b — macOS SkyLight/WindowServer replacement (SIP-gated stretch)

- **Goal**: on SIP-relaxed macOS, inject to replace WindowServer/SkyLight so
  Wawona is the desktop compositor (like iland's approach).
- **Gating**: requires partially-disabled SIP; **never** an App Store path.
  Developer/enthusiast only. Highest risk; last in priority.

## Honest status

Tier 1 (bug fixes, toolchain/repro, protocol honesty, ICD tiering, perf, QoS,
docs, CI Layer-1/2 gates, Layer-3 test targets, graphics smoke, port scaffolds,
WLCS skeleton) is landed. The six items above remain and are large; they are
tracked as open Tier-2 work, not done.
