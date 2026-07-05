# NixOS VM bridge (p26-vm-nixos)

How Wawona runs a full Linux (NixOS) Wayland session as a "machine", using
Apple's native **Virtualization.framework** + **virtio-vsock** + **waypipe** —
the OrbStack model, not WSLg's RDP. This replaces the old QEMU-cocoa
`wawona-linux-vm` path (which rendered into QEMU's own window) with surfaces
presented natively inside Wawona.

Status: **first vertical slice landed** (host launcher + guest image + flake
wiring). Everything — including the `aarch64-linux` guest image — builds locally
on the Mac via **Determinate Nix's native VZ Linux builder**; no separate NixOS
host is needed. End-to-end Wayland-over-vsock still needs a boot-test — see
"Build & run" and "Known gaps".

> **Relocated into [`wwn-vms`](../../wwn-vms).** The VM engine + guests now live in
> the `wwn-vms` dependency (`dependencies/vms/`), consumed by Wawona as a flake
> input. The macOS `microvm-guest.nix`, `vz-launcher.nix`, and `WawonaLinuxVZ.swift`
> moved there; the flake apps `wawona-microvm` / `wawona-vm-bridge` / `wawona-vz`
> are unchanged. Containers are the sibling [`wwn-containers`](../../wwn-containers).
> The deferred `nixos-guest.nix` artifact track stays in Wawona for now.

## Two tracks

There are two ways to boot the guest, both on Virtualization.framework:

1. **Developer track — `microvm.nix` + `vfkit`** (recommended, working now).
   [microvm.nix](https://github.com/microvm-nix/microvm.nix) drives `vfkit`
   (a thin Virtualization.framework CLI). We adopted it after finding it already
   proven in `/etc/nix-darwin/.dotfiles` (`den.aspects.microvm` + a
   `wawona-vm-bridge.sh`). It builds the guest with **`writableStoreOverlay` +
   a virtiofs read-only share of the host `/nix/store`**, so the rootfs is a tiny
   writable overlay disk and **no `make-disk-image`/QEMU/KVM is needed** — which
   is exactly what stalled the hand-rolled guest on the VZ Linux builder.
   Files: [microvm-guest.nix](../../wwn-vms/dependencies/vms/microvm-guest.nix); flake
   apps `wawona-microvm` (boot) and `wawona-vm-bridge` (Wayland relay).
2. **In-app track — native Swift launcher `wawona-vz`** (future, for embedding
   in Wawona.app with no external hypervisor):
   [WawonaLinuxVZ.swift](../../wwn-vms/dependencies/vms/WawonaLinuxVZ.swift) +
   [vz-launcher.nix](../../wwn-vms/dependencies/vms/vz-launcher.nix) +
   [nixos-guest.nix](../dependencies/wawona/nixos-guest.nix) (kernel/initrd/rootfs;
   deferred artifact track, still in Wawona).

### vsock over vfkit — the one caveat

Upstream microvm.nix's vfkit runner still `throw`s on `microvm.vsock.cid != null`
("vfkit vsock support not yet implemented"). The dotfiles setup works because it
carries a **local patch** to the vendored runner. To keep Wawona on **upstream**
microvm.nix (no fork), we instead attach the vsock device through
`microvm.vfkit.extraArgs` (which upstream appends verbatim) and leave `cid` null:

```nix
microvm.vfkit.extraArgs = [
  "--device" "virtio-vsock,port=1024,socketURL=/tmp/wawona-guest-vsock.sock"
];
```

Guest waypipe connects to host **CID 2** on that port; vfkit relays it to the
unix socket; `wawona-vm-bridge` runs a host `waypipe client` + `socat` into
Wawona's `wayland-0`. (If/when upstream lands real vfkit vsock, switch to
`microvm.vsock.cid` and drop the extraArgs.)

### Run (developer track)

```sh
# terminal 1 — build + boot the guest (uses the aarch64-linux builder once)
nix run .#wawona-microvm
# terminal 2 — relay the guest Wayland session into Wawona (must be running)
nix run .#wawona-vm-bridge          # honors WAWONA_RUNTIME=/path/to/xdg-runtime
```

**Build status:** `nix build .#packages.aarch64-darwin.wawona-microvm` is
**verified** — the guest closure, systemd initrd, vfkit runner, and wrapper all
realize in ~90s on the Determinate aarch64-linux (VZ) builder with **no
make-disk-image and no KVM**. Boot-test (guest → bridge → Wawona window) is the
next validation.

### Machines UI wiring

The `virtual_machine` (and `container`) machine type is wired on macOS:
`WWNMachineSessionBridge` → `WWNVirtualMachineRunner` runs the profile's custom
script as a tracked subprocess (with `WAWONA_RUNTIME` exported) and tears it down
on disconnect. Configure a VM profile's custom script to the two `nix run`
commands above. On iOS/etc. the runner is a stub (the in-process UTM SE backend,
p27, is the mobile path).

## What OrbStack does (and what we borrow)

Verified from OrbStack's architecture docs + HN/benchmarks:

- Built on **Apple Virtualization.framework**, heavily tuned; not a custom
  hypervisor for the CPU (Apple won't let third parties set the Rosetta CPU
  flags outside VZ anyway).
- **Shared kernel** across machines (WSL2-style) for near-instant start and low
  overhead. (We don't need this yet — one guest at a time.)
- **vsock transport instead of a virtual NIC** for host↔guest — high throughput,
  low latency. This is the key idea we adopt for the Wayland pipe.
- **Custom VirtioFS** with dynamic caching for fast file sharing. We use plain
  `VZVirtioFileSystemDeviceConfiguration` (virtiofs) for an optional host-dir
  share; OrbStack's caching is a future optimization.
- **Rosetta** for x86_64 Linux binaries — we expose it optionally
  (`--rosetta`, `VZLinuxRosettaDirectoryShare`).
- **Dynamic memory** (balloon, return unused RAM). We attach a virtio balloon.

What we deliberately do **not** copy: OrbStack's proprietary networking stack,
its multi-distro image manager, and its shared-kernel supervisor. Our guest is a
single NixOS system (Nix is already our whole build system, so a NixOS guest is
a natural flake output).

## Architecture

```
  ┌─────────────────────────── macOS host (Apple Silicon, macOS 26) ──────────────────────────┐
  │                                                                                            │
  │   Wawona compositor  ──  wayland-0 (unix socket in $XDG_RUNTIME_DIR)                        │
  │        ▲                                                                                    │
  │        │ unix socket                                                                        │
  │   wawona-vz (Virtualization.framework)                                                      │
  │        │  VZVirtioSocketDevice  ── vsock ──┐                                                │
  └────────┼───────────────────────────────────┼───────────────────────────────────────────────┘
           │                                    │
  ┌────────┼──────────── NixOS guest (aarch64-linux) ─────────────────────────────────────────┐
  │   /dev/vsock (CID 3)                        │                                              │
  │   waypipe --vsock server ── Wayland apps (cage + foot, or wwn-niri/sway/…)                 │
  └────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Host launcher**: `wawona-vz` ([WawonaLinuxVZ.swift](../../wwn-vms/dependencies/vms/WawonaLinuxVZ.swift),
  built by [vz-launcher.nix](../../wwn-vms/dependencies/vms/vz-launcher.nix)). Direct-kernel
  boot (`VZLinuxBootLoader`), virtio-blk root, virtio console on `hvc0`, entropy,
  memory balloon, `VZVirtioSocketDevice`, optional virtiofs + Rosetta. It runs a
  bidirectional **vsock↔unix bridge** so guest Wayland traffic reaches Wawona's
  socket. Ad-hoc signed with `com.apple.security.virtualization` at first run.
- **Guest**: `wawona-nixos-guest` ([nixos-guest.nix](../dependencies/wawona/nixos-guest.nix))
  — a NixOS system producing `Image` (uncompressed arm64 kernel), `initrd`, and a
  raw ext4 `rootfs.img`, plus a `wawona-wayland-bridge` service that runs a Wayland
  session under waypipe over vsock.

### Why direct-kernel boot + uncompressed Image

Virtualization.framework on Apple Silicon requires an **uncompressed** arm64
kernel `Image` (a compressed kernel hangs at boot). NixOS builds this at
`${config.system.build.kernel}/Image`. We boot it directly (no GRUB) with
`root=/dev/vda console=hvc0`.

### vsock, concretely

`VZVirtioSocketDevice` exposes virtio-vsock; the guest sees `/dev/vsock` at CID 3.
`wawona-vz` supports both directions so we can match whatever waypipe wants:

- `--vsock-listen PORT --forward-unix PATH` — host accepts guest-initiated vsock
  connections on `PORT` and forwards each to host unix socket `PATH`
  (e.g. Wawona's `wayland-0`).
- `--vsock-connect PORT --listen-unix PATH` — host listens on unix `PATH` and
  dials the guest on `PORT` for each local client.

## Build & run

### 1. Build the guest — **locally on the Mac** (Determinate native Linux builder)

The guest is an `aarch64-linux` derivation (uncompressed arm64 kernel + initrd +
ext4 rootfs) and can't be realized on `aarch64-darwin` directly — but you do
**not** need a separate NixOS host. **Determinate Nix** on macOS ships a native
Linux builder that runs the `aarch64-linux`/`x86_64-linux` build in a lightweight
VM **using Virtualization.framework** (the same tech `wawona-vz` uses). It's
already configured here via `external-builders` in `/etc/nix/nix.conf`:

```
external-builders = [{"program":"/usr/local/bin/determinate-nixd",
  "args":["builder", ...], "systems":["aarch64-linux","x86_64-linux"]}]
system-features = apple-virt ...
```

So the build is one local command:

```sh
nix build .#packages.aarch64-linux.wawona-nixos-guest -L
# → ./result/{Image,initrd,rootfs.img}   (built via the VZ Linux builder)
```

No remote host, no `scp`, no `nix-darwin` linux-builder to stand up. This is also
the general answer for the other Tier-2 Linux-runtime lanes (WLCS, the GTK
frontend, dEQP): they all realize on the same Determinate builder.

> Fallbacks (only if Determinate's builder is unavailable): a remote
> `aarch64-linux` builder, or building on an aarch64 NixOS host. An x86_64 NixOS
> host would need `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` (slow).

### 2. Run — on the Mac (this M1, macOS 26)

```sh
# rootfs must be writable — copy it out of the read-only Nix store first
cp ~/wawona-guest/rootfs.img /tmp/wawona-rootfs.img && chmod u+w /tmp/wawona-rootfs.img

nix run .#wawona-vz -- \
  --kernel  ~/wawona-guest/Image \
  --initrd  ~/wawona-guest/initrd \
  --disk    /tmp/wawona-rootfs.img \
  --memory-mib 4096 --cpus 4 \
  --vsock-listen 6000 --forward-unix "$XDG_RUNTIME_DIR/wayland-0"
```

With Wawona running, the guest's `wawona-wayland-bridge` service connects out on
vsock:6000 and its Wayland clients appear as Wawona windows.

## Where everything runs (summary)

Thanks to Determinate's native (VZ-backed) Linux builder, **all of this is local
to the Mac** — no separate NixOS host required.

| Task | Where | Notes |
| --- | --- | --- |
| Build `wawona-nixos-guest` (Image/initrd/rootfs) | Mac, via Determinate Linux builder | `nix build .#packages.aarch64-linux.wawona-nixos-guest` |
| Iterate the guest NixOS config (session, packages, waypipe) | Mac (same builder) | rebuild locally; boot-test under `wawona-vz` |
| Validate waypipe vsock direction end-to-end | Mac (`wawona-vz` boots the guest) | needs the guest actually running |
| Build/run `wawona-vz` launcher | Mac | Virtualization.framework is macOS-only |
| Everything else (flake, docs, bridge code) | Mac | pure |

A remote aarch64-linux builder is now only a fallback if the Determinate builder
is disabled. The same builder unblocks the remaining Tier-2 Linux lanes (WLCS,
GTK runtime, dEQP).

## Known gaps (honest status)

- **`wawona-vz` artifact track does not build on the VZ builder**: the
  `wawona-nixos-guest` (kernel/initrd/rootfs for the embedded Swift launcher)
  fails in `make-initrd-ng` on a dangling `ncurses` terminfo symlink
  (`share/terminfo/l/linux`, `No such file or directory`) on the Determinate VZ
  Linux builder — independent of scripted-vs-systemd initrd. The microvm/vfkit
  track builds its own initrd fine, so it is the working path; the embedded
  `wawona-vz` in-app track is deferred until this store/ncurses issue is fixed.
- **waypipe vsock topology unverified**: the guest service runs
  `waypipe --vsock -s <port> server -- cage -- foot`; the precise
  client/server/`-s` semantics for vsock need a real Linux boot to confirm, and
  may need a host-side `waypipe … client`. Treat the guest service + launcher
  bridge as the integration seam, not a proven pipe.
- **rootfs sizing/resize**: `make-disk-image` emits an 8 GiB raw image with
  `autoResize`; not yet tuned.
- **No Machines-UI wiring yet**: this slice is CLI (`nix run .#wawona-vz`). The
  `virtual_machine` machine type + `Machine*Stub` prefs
  ([WWNMachineProfileStore](../src/platform/macos/ui/Machines/WWNMachineProfileStore.m))
  are the next hook to launch this from the app.
- **Not App Store viable** (spawns VMs) — ships in the direct (non-MAS) macOS
  channel, like Mode B.

## Related

- [2026-tier2-roadmap.md](./2026-tier2-roadmap.md) — p26 entry
- [2026-platform-delivery-matrix.md](./2026-platform-delivery-matrix.md) — delivery modes
- `wawona-linux-vm` (QEMU, [linux-vm.nix](../dependencies/wawona/linux-vm.nix)) —
  the legacy full-desktop QEMU path this supersedes for Wayland-into-Wawona.
