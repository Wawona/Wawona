# Virtual machines and containers

> **Public subset** for wawona.io. Status: **planned / coming soon**.
> Full Mode A/B: [`mode-a-b.md`](./mode-a-b.md), [`vms-mode-a-b.md`](./vms-mode-a-b.md),
> [`containers-mode-a-b.md`](./containers-mode-a-b.md).

Wawona will let users add **VM** and **container** machine profiles in the
Machines GUI. This is **not** the on-device [bundled shell](ios-local-shell/README.md),
**not** [Wawona Runtime / Wasm packages](wasm-wasi.md), and **not**
Desktop/LockScreen or Wawona Swinging Bridge.

## Mode A vs Mode B (iOS / iPadOS)

| | **Mode A** (App Store IPA) | **TrollStore** (JIT IPA) | **Mode B** (Sileo Mode B IPA) |
|---|---|---|---|
| Engine | UTM-SE-class **jitless** interpreter | UTM/QEMU **with JIT** | UTM/QEMU **with JIT** |
| Containers | OCI pull + container-in-VM on jitless VM | Same OCI + **JIT** container-in-VM | Same OCI + **JIT** container-in-VM |
| Wasm | No JIT | Wasm JIT allowed | Wasm JIT allowed |
| Desktop / LockScreen / Swinging Bridge | Forbidden | Not implied | **Yes** (out of the box) |
| Ship | Store / TestFlight only | Website sideload | `repo.wawona.io` auto-packages Mode B IPA. **never** in App Store |

Design both in `wwn-vms` / `wwn-containers` / Wawona at all times. Mode B code
must be compile-time absent from store artifacts. Channels:
[`agent-rules/wawona-ios-mode-b-channels.md`](./agent-rules/wawona-ios-mode-b-channels.md).

**Backends differ by OS:** macOS → QEMU+HVF / Apple Containerization;
iOS family → UTM-SE-class (A) or JIT UTM (B); Android → QEMU±KVM. Do not
share one engine binary across those hosts. **Note:** active work on macOS Apple
Container in `wwn-containers`. Leave that repo alone until it merges; VMs and
Wasm packages proceed independently.

## Platforms

| Platform | Gate | Planned engine |
|---|---|---|
| macOS | planned | **QEMU + HVF** (`Hypervisor.framework`). Apple Containerization for containers |
| iOS / iPadOS | planned | **A:** jitless QEMU-TCTI (UTM SE). **B:** JIT UTM via Sileo Mode B IPA |
| Android | planned | **QEMU + Android HV** (`/dev/kvm`) with TCG+JIT fallback; Play = Mode A |
| Linux | planned | Machine profiles via `wwn-vms` / `wwn-containers` |
| tvOS / watchOS / visionOS | **forbidden** | Native + remote only |

App Store / TestFlight copy must **never** pitch jailbreak, TrollStore, or JIT.
Website and `repo.wawona.io` may.

## Machines kinds

- `virtual_machine`. Guest VM (`wwn-vms`)
- `container`. OCI container (`wwn-containers`)

## Not Wasm

Installing `.wasm` is [Runtime package management](wasm-package-manager.md)
(Mode A-safe `/wasm/` channel). Do not conflate with OCI Linux images.

## Agent rules

`.cursor/rules/wawona-mode-a-b.mdc` · `wawona-platform-targets.mdc` ·
`Sources/WawonaModel/PlatformCapabilities.swift`.
