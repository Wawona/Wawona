# NixOS MicroVM + waypipe (Linux-first VM path)

How Wawona runs a full Linux (NixOS) Wayland client as a machine without a
native port of every app: **NixOS MicroVM** (microvm.nix + vfkit on macOS) with
**virtio-vsock** + **waypipe** into the host Wawona compositor (iland present).
OrbStack-style. Not WSLg RDP. Not QEMU. Not UTM.

**Linux-first for breadth:** fidelity-critical natives (Weston, Niri, shell,
demos) stay native ports. Everything else can run as Linux in a MicroVM with
GUI over vsock + waypipe. Fidelity is still judged by the same Linux + waypipe
into Wawona standard (`wawona-port-fidelity`).

## Ownership

| Piece | Repo / path |
|---|---|
| Guest module | [`Relay/import/vms/dependencies/vms/microvm-guest.nix`](../../Relay/import/vms/dependencies/vms/microvm-guest.nix) |
| Host flake apps | Wawona `flake.nix`: `wawona-microvm-session` (preferred), thin internals `wawona-microvm` / `wawona-vm-bridge` |
| Product VM engine | **Wawona Relay** (`wwn-relay`): VZ / StaticCpu / KVM. microvm.nix is guest definition + macOS dogfood hypervisor (vfkit), not a second product engine |
| Containers | Relay OCI-in-VM (sibling track) |

Never document QEMU or UTM as a Start path.

## One-command dogfood (macOS)

Wawona must already be running (`wayland-0` under `$WAWONA_RUNTIME`, default
`/tmp/wawona-$UID`).

```sh
# Preferred: bridge + vfkit MicroVM under one supervisor
nix run .#wawona-microvm-session

# Local Relay checkout (guest module tip):
nix run --override-input wwn-relay path:../Relay .#wawona-microvm-session

# Automation proof
scripts/microvm-waypipe-session-smoke.sh
```

Thin internals (debug only):

```sh
nix run .#wawona-vm-bridge    # terminal A
nix run .#wawona-microvm      # terminal B
```

Guest default session: `waypipe --no-gpu --vsock -s 1024 server -- foot`.
Swap the client via `sessionClient` / `extraModule` in `microvm-guest.nix`.
Ready marker: `WAWONA_RELAY_READY=1` on the guest console (same string as Relay
guest units). vsock port stays **1024** (vfkit runner hardcode).

## Machines UI (macOS)

`virtual_machine` Start on macOS:

`WWNMachineSessionBridge` → `WWNVirtualMachineRunner` → supervised
`wawona-microvm-session` (Process), with `WAWONA_RUNTIME` exported. Stop tears
the session down (restful Stop when available, then SIGTERM).

Resolve order for the session binary:

1. `WAWONA_MICROVM_SESSION` (absolute path)
2. `wawona-microvm-session` on `PATH`
3. `nix run $WAWONA_FLAKE#wawona-microvm-session` (default flake `~/Wawona/Wawona`)

iOS / iPadOS / Android VM Start stays on **Relay** (StaticCpu / planned). Do not
route mobile through vfkit.

Container Start stays on Relay on every target.

## vsock topology (vfkit listen mode)

```text
guest foot
  -> waypipe --no-gpu --vsock -s 1024 server
  -> vfkit virtio-vsock port 1024
  -> unix /tmp/wawona-guest-vsock.sock
  -> socat + waypipe client
  -> Wawona wayland-0
```

Upstream microvm.nix still throws on `microvm.vsock.cid != null` for vfkit, so
the guest attaches vsock through `microvm.vfkit.extraArgs` and leaves `cid`
null. Keep Wawona on upstream microvm.nix (no fork).

## Product stance

- **Relay** remains the product Machines VM/container engine (no QEMU/UTM).
- **microvm.nix + vfkit** proves and automates the Wayland contract on macOS
  before (and alongside) Relay VZ/StaticCpu.
- Guest GUI is always Wayland into Wawona (iland). Never Spice / virgl /
  virtio-gpu into a second window (`wawona-guest-wayland-iland`).

## Related

- Checklist: [`docs/issues/relay-vm-container-checklist.md`](issues/relay-vm-container-checklist.md)
- Rules: `wawona-linux-vms-relay-runtime`, `wawona-guest-wayland-iland`,
  `wawona-port-fidelity`, `wawona-product-map`
- Skill: `wawona-relay`, `wawona-machine-types`
