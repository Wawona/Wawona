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

## Rules to open

- `wawona-linux-vms-relay-runtime`
- `wawona-guest-wayland-iland`
- `wawona-relay-wasm`
- `wawona-repo-dag`
- `wawona-product-map`
- `wawona-mode-a-b` / `wawona-ios-mode-b-channels`

Canonical prose: `Wawona/docs/agent-rules/wawona-linux-vms-relay-runtime.md`, `Relay/README.md`.

## Backends (Relay picks them)

| Host | VM | Container | Wasm |
|------|----|-----------|------|
| macOS Apple silicon | VZ | OCI on VZ | Cranelift |
| Linux AppImage | KVM (cloud-hypervisor / crosvm). Fail closed without `/dev/kvm` | OCI on that VM | Cranelift |
| iOS / iPadOS Mode A | static CPU (planned) | OCI on that VM | Pulley |
| iOS / iPadOS Mode B | JIT CPU (planned) | OCI on that VM | no Mode B wasm product |
| Android Play | static CPU (planned). No AVF | OCI-in-VM. No proot | Cranelift or Pulley |
| tvOS / watchOS / visionOS | forbidden | forbidden | Pulley (required) |

Mode A vs Mode B is **which binary was installed**. Not a Settings toggle.

## Hard rejects

- QEMU, TCTI, HVF-via-qemu, `qemu-*.framework`
- UTM / Spice / CocoaSpice / virgl
- Host Docker, runc-on-host, proot
- Edit target `wwn-vms` / `wwn-containers` / `wwn-wasm` for new work
- AVF in Play. Termux debs as a Relay backend
- "Faster than UTM" or "world's fastest" copy

## Where to edit

| Change | Repo |
|--------|------|
| Backend table, C ABI, flake `registryFragment` | `Wawona/Relay` |
| Machines trampoline (`WWNRelay`) | L4 `Wawona` |
| Guest GUI / iland present | `wwn-iland` + L4. Never UTM display |
