---
name: wawona-relay
description: Wawona Relay is the only VM, container-in-VM, and Mode A WASI engine. Use when editing Linux guests, OCI, wasm runtime, flake input wwn-relay, or dropping QEMU/UTM.
---

# Wawona Relay (pointer)

Repo: `github.com/Wawona/Relay` (`development`). Flake input: **`wwn-relay`**. Layer **L3′**.

Wawona calls one API (`wawona_relay.h`) for:

- `virtual_machine`: Linux / NixOS prebuilts only
- `container`: OCI unpack, then the **same** Linux VM backend
- WASI / `wpm`: Mode A bytecode (`/wasm/v1`) only
- Machines kind `wasm`: Start is `wasm <file|package>` (same as native shell).
  Native machines keep the `wawona-wasm` client. Do not strip `bundledAppID`
  when loading a `wasm` profile.
- Android product `wawona-wasm` is header-only today (empty `lib/`). Link
  `-lwawona_wasm` only when `libwawona_wasm.a` exists. Weak JNI
  `wawona_wasm_run` stays null until Relay ships that archive. Do not toast
  ProcessBuilder "not bundled" for type wasm.

## Rules to open

- `wawona-linux-vms-relay-runtime`
- `wawona-guest-wayland-iland`
- `wawona-relay-wasm`
- `wawona-repo-dag`
- `wawona-product-map`
- `wawona-mode-a-b` / `wawona-ios-mode-b-channels`

Canonical prose: `Wawona/docs/agent-rules/wawona-linux-vms-relay-runtime.md`, `Relay/README.md`.

## Rust + crate2nix (required)

Relay product logic is **Rust**. C/ObjC/Swift/JNI is only thin ABI or Apple
framework trampolines (`wawona_relay.h`, eventual VZ ObjC bridge). Do not grow
Swift/C engines, spikes as product paths, or new `buildRustPackage` monoliths.

Nix builds of Relay crates must use **crate2nix** for per-crate `/nix/store`
derivations (same granularity as L4 `rust-backend-c2n.nix`):

1. Pin: `crate2nix.follows = "wwn-toolchain/crate2nix"` (L0 owns the tip).
2. Build: `crate2nix.tools.${system}.generatedCargoNix` over the Relay
   workspace / `Cargo.lock`, then per-crate `build` / staticlib assemble.
3. Hard reject: new Relay recipes that only wrap `rustPlatform.buildRustPackage`
   for the whole workspace (one change rebuilds everything).

Open debt: migrate `recipes/relay-staticlib.nix` (Apple mobile / Android) and
`import/wasm/**/*.nix` off `buildRustPackage`. Replace Swift `wawona-vz-run`
(`WawonaLinuxVZ.swift`) with a Rust Virtualization.framework launcher (thin
ObjC only if the ABI forces it). Host macOS/Linux `wawona-relay` already uses
`recipes/relay-crate2nix.nix`. Guest OCI virtiofs needs a rebuilt
`wawona-nixos-guest-*` image (VIRTIO_FS + crun + `wawona-container` unit).

## Case-insensitive Determinate builder

Determinate's native Linux builder exposes the macOS Nix store through
VirtioFS. Relay guest artifacts must handle Nix case-hack names:

- Use the minimal scripted initrd. Disable default modules, suppress `ext2`,
  and request only `virtio_mmio`, `virtio_blk`, `virtio_console`,
  `vmw_vsock_virtio_transport`, and `ext4`.
- Reject any `~nix~case~hack~N` path found in the completed initrd.
- Build the ext4 image from the physical store tree, then rename case-hacked
  directory entries inside the image with `debugfs`. Never materialize the
  decoded tree on the case-insensitive host.
- Do not add `virtio_vsock`. That is not a Linux module name.

Implementation:
`Relay/import/vms/dependencies/vms/mobile/{guest,guest-artifacts}.nix`.

The 4 KiB bundle is boot-proven through macOS
Virtualization.framework `wawona-vz-run`: stage 1, stage 2, automatic login,
and guest Wayland service start. Relay Rust `start_vz` now owns artifact
verification, persistent writable disk state, launcher lifecycle, console
capture, readiness, Wayland endpoint, restart, and stop.

VZ lifecycle details:

- APFS `clonefile` preserves the read-only Nix store mode. Add owner write
  permission to the cloned rootfs before attaching it, or VZ rejects the
  storage attachment.
- Do not scrape ANSI-formatted systemd `Started` lines. The guest
  `ExecStartPost` writes `WAWONA_RELAY_READY=1` to `hvc0`; Rust waits for that
  exact readiness contract.
- A stable machine ID selects persistent disk state. A second live start is
  rejected. A dead process may be recovered and restarted on that same disk.
- Release guest starts require a trusted Ed25519 manifest signature. Unsigned
  bundles require an explicit development-only resource flag.
- Guest kernels are Linux 7.2 or newer (`linuxPackages_latest` / `linux_latest`).
- A 16 KiB page guest needs a real `ARM64_16K_PAGES` kernel. Do not relabel a
  4 KiB Image. On Determinate's native Linux builder, start from the NixOS
  `linux_latest` config, flip to 16 KiB pages, disable large unused trees
  (USB/SOUND/MEDIA/WLAN/DRM/NETFILTER/…), disable `DEBUG_INFO` / DWARF, skip
  `dtbs_install`, and force `# CONFIG_OF is not set` after every
  `olddefconfig` (Apple VZ is ACPI; OF rebuilds every arm64 DTB). Then purge
  loadable modules (`=m` → unset) and force Relay builtins only (`EXT4`,
  virtio blk/console/net/mmio/pci, `VIRTIO_VSOCKETS`, `ACPI`, `PCI`, …) with
  `MODULES=y` so initrd can read `modules.builtin`. Slim `postInstall`: do not
  copy gdb `constants.py` or a full `$dev` source tree (`GDB_SCRIPTS` is off).
  Cap `NIX_BUILD_CORES` (builder is 1 vCPU). A raw defconfig / fat module tree
  fills scratch (`No space left on device` while compiling `net/dsa` or linking
  `vmlinux.o`). A too-thin `allnoconfig` Image under VZ shows empty `hvc0` and
  readiness timeout. `MODULES=n` fails initrd with `Required modules: ext4`.
  Do not leave `relay-vm-state*/**/wayland.sock` under the flake `path:.` tree:
  Nix cannot copy unix sockets.

## Backends (Relay picks them)

| Host | VM | Container | Wasm |
|------|----|-----------|------|
| macOS Apple silicon | VZ | OCI on VZ | Cranelift |
| Linux AppImage | KVM (cloud-hypervisor / crosvm). Fail closed without `/dev/kvm` | OCI on that VM | Cranelift |
| iOS / iPadOS Mode A | static CPU (planned) | OCI on that VM | Pulley |
| iOS / iPadOS Mode B | `IosHv` when probe window matches; else static. Not HVF-via-qemu | OCI on that VM | same /wasm/v1. Pulley |
| Android Play | static CPU (planned). No AVF | OCI-in-VM. No proot | Pulley (Mode A) |
| Android Mode B | AVF lab | OCI-in-VM. No proot | Cranelift |
| tvOS / watchOS / visionOS | forbidden | forbidden | Pulley (required) |

Mode A vs Mode B is **which binary was installed**. Not a Settings toggle.

## Hard rejects

- QEMU, TCTI, HVF-via-qemu, `qemu-*.framework`
- UTM / Spice / CocoaSpice / virgl
- Host Docker, runc-on-host, proot
- Edit target `wwn-vms` / `wwn-containers` / `wwn-wasm` for new work
- AVF in Play. Termux debs as a Relay backend
- "Faster than UTM" or "world's fastest" copy
- New Relay product logic in Swift/C (headers / thin trampolines only)
- New monolithic `buildRustPackage` for the Relay workspace (use crate2nix)
- Hypervisor.framework / `ios-hv` in Mode A store IPA
- Selecting `IosHv` for wasm
- Calling macOS HV the shipping macOS VM backend (product is VZ)

Mode B iOS HV window: rule/skill `wawona-relay-ios-hypervisor`,
`Wawona/docs/relay-ios-hypervisor.md`. Distinguish **forbidden HVF-via-qemu**
from **Relay native Hypervisor.framework** on the Mode B SoC/OS window.

## Where to edit

| Change | Repo |
|--------|------|
| Backend table, C ABI, flake `registryFragment` | `Wawona/Relay` |
| Machines trampoline (`WWNRelay`) | L4 `Wawona` |
| Guest GUI / iland present | `wwn-iland` + L4. Never UTM display |
