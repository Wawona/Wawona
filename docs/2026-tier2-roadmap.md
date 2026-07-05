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
- **Now owned by [`wwn-containers`](../../wwn-containers)** (split out of Wawona):
  - Universal OCI image management is the Rust `wwn-oci` core (registry v2 pull,
    CAS store, manifest/index parse, layer unpack) — `nix build .#wwn-oci`.
  - macOS execution backend `wwn-containerd` wraps Apple's Containerization
    framework (per-container VM + `vminitd`, gRPC/vsock); runtime-compiled Swift
    (host SDK) like `wawona-vz`.
- **Entry points**: `MachineContainerRuntime` / `MachineContainerImageStore`
  prefs (the `Machine*Stub` prefs are gone), `WWNContainerRunner`,
  `WWNMachineSessionBridge` (container profiles route here).
- **Gating**: macOS 26+, `com.apple.security.virtualization`; direct/notarized
  only (MAS ships image-management-only). See `wwn-containers/COMPLIANCE.md`.

## p26-vm-nixos — prebuilt NixOS VMs via Virtualization.framework

- **Goal**: OrbStack-style prebuilt NixOS VMs, GUI forwarded into Wawona.
- **Now owned by [`wwn-vms`](../../wwn-vms)** (split out of Wawona). Wawona
  consumes it as a flake input; the built-in VM is **NixOS-only**. See
  [2026-nixos-vm-bridge.md](./2026-nixos-vm-bridge.md).
- **Two macOS tracks** (both on Virtualization.framework), relocated into wwn-vms:
  - **Developer track (working): `microvm.nix` + `vfkit`** —
    `wwn-vms/dependencies/vms/microvm-guest.nix`. `nix run .#wawona-microvm`
    boots the guest; `nix run .#wawona-vm-bridge` relays its Wayland session into
    Wawona. `writableStoreOverlay` + virtiofs ro `/nix/store` → **no
    make-disk-image/KVM**; stays on upstream microvm.nix via `vfkit.extraArgs`.
  - **In-app track: native Swift `wawona-vz`** —
    `wwn-vms/dependencies/vms/{WawonaLinuxVZ.swift,vz-launcher.nix}`. Embeddable,
    ad-hoc signed with `com.apple.security.virtualization`.
- **Machines UI wired**: `virtual_machine` profiles route through
  `WWNVirtualMachineRunner`; the `Machine*Stub` prefs are replaced by real
  `MachineVMProvider` / `MachineVMVsockPort` settings.
- **Design**: OrbStack model — Virtualization.framework + **vsock** transport
  (not a virtual NIC / RDP). Guest runs `waypipe --vsock -s 1024 server -- <client>`
  (connects out to host CID 2; vfkit default listen mode forwards to the host
  unix socket that the bridge listens on).
- **End-to-end verified (2026-07-05)**: guest boots to login under vfkit and a
  Wayland client (`foot`) is relayed all the way to a compositor `wayland-0`
  (`foot → waypipe server → vsock CID2:1024 → vfkit → socat LISTEN → waypipe
  client → wayland-0`; 126 protocol bytes + bidirectional wire-version 17
  handshake observed). Bugs fixed to get here:
  - launcher wraps vfkit in a **pty** (microvm.nix's `virtio-serial,stdio`
    console fails with "operation not supported on socket" under NSTask/headless);
  - bridge `socat` must **UNIX-LISTEN** on the vfkit vsock socket, not connect;
  - guest uses waypipe's real `--vsock -s <port>` form (not `--socket vsock:…`);
  - guest forwards a Wayland **client** (`foot`), not the `sway` compositor
    (waypipe forwards clients; Wawona *is* the compositor). Nested compositors
    are the Phase-29 `wwn-*` path (a compositor bound to `WLR_BACKENDS=wayland`).
  Last inch to a literal on-screen window: run the Wawona GUI and start
  `wawona-vm-bridge` (it defaults `WAWONA_RUNTIME` to Wawona's XDG runtime dir).
- **No host-NixOS dependency**: guest images build locally on the Mac via
  Determinate Nix's native (Virtualization.framework) Linux builder.

## p27-ios-utmse — UTM SE jitless VM backend (iOS/iPadOS/visionOS)

- **Goal**: run a jitless VM on iOS (UTM SE model), reusing Wawona's GUI.
- **Now the mobile engine of [`wwn-vms`](../../wwn-vms)** (unifies with p26/p29
  under the vms/containers split):
  - `wwn-vms/dependencies/vms/mobile/engine.nix` — jitless **QEMU-TCTI** engine
    sourced from the aligned UTM fork **`wwn-utm`** (`../../UTM/flake.nix`,
    wired as a `wwn-vms` input: `qemuUtmPatch`, build scripts, iOS-SE scheme).
  - `wwn-vms/dependencies/vms/mobile/guest.nix` — bundled minimal NixOS guest
    (`nixosConfigurations.wawona-mobile-guest`), shipped as ODR/bundled data.
- **Containers on iOS**: container-in-VM via `wwn-containers`
  (`nixosConfigurations.wawona-container-guest`, crun in the guest, Wayland over
  vsock+waypipe).
- **Compliance**: no JIT, no Hypervisor.framework; guest is data. TCTI is the
  honest ceiling. See `wwn-vms/COMPLIANCE.md`.

## p29-wwn-vms-containers — VM/container substrate split (supersedes p29-utm-orbstack)

- **Done (scaffold + wiring)**: [`wwn-vms`](../../wwn-vms) (VM engines +
  NixOS-only guests) and [`wwn-containers`](../../wwn-containers) (universal OCI
  core + per-target execution backends) are separate `wwn-*` deps consumed by
  Wawona via local `path:` inputs; both `registryFragment`s merge into
  `mergedRegistry`. The UTM fork is aligned as `wwn-utm`.
- **Remaining**: real per-target engine cross-builds (QEMU-TCTI for Apple,
  QEMU/AVF for Android), then flip Wawona inputs from `path:` to `github:` (done).
- **Native `container` CLI (scaffolded, not implemented)**: Wawona's native
  terminals + `wwn-zsh` must expose a `container` command to manage/run OCI
  containers from a shell on every target (Apple ecosystem + Android), as the
  terminal front-end to the same `wwn-containers` substrate as Settings →
  Containers and Machine profile → Containers. Requirement of record:
  [2026-container-cli.md](./2026-container-cli.md).

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
