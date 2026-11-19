# Virtual machines and containers

> **Public subset** for wawona.io. macOS: **available**. Other hosts: see matrix.
> Full Mode A/B: [`mode-a-b.md`](./mode-a-b.md), [`vms-mode-a-b.md`](./vms-mode-a-b.md),
> [`containers-mode-a-b.md`](./containers-mode-a-b.md).
> Runtime map: [`relay-runtime-map.md`](./relay-runtime-map.md).

Wawona lets users add **VM** and **container** machine profiles in the
Machines GUI. Relay owns those runtimes. This is **not** the on-device
[bundled shell](ios-local-shell/README.md), **not**
[Wawona Runtime / Wasm packages](wasm-wasi.md), and **not**
Desktop/LockScreen or Wawona Swinging Bridge.

## Mode A vs Mode B (iOS / iPadOS)

| | **Mode A** (App Store IPA) | **Mode B** (TrollStore / Sileo) |
|---|---|---|
| Engine | Relay `StaticCpu`. Planned. Fail closed. **No** Hypervisor.framework | Relay. `IosHv` when probe window matches (M1/M2/A16, ≤16.3.1); else `StaticCpu` |
| Containers | OCI pull + container-in-VM on that Relay | Same OCI + same backend as the VM |
| Ship | Store / TestFlight only | TrollStore tipa. `repo.wawona.io` Sileo. **never** in App Store |

Design both in Relay / Wawona at all times. Mode B HV code must be compile-time
absent from store artifacts (`ios-hv` feature off). No QEMU. No UTM-as-product.
HV plan: [`relay-ios-hypervisor.md`](./relay-ios-hypervisor.md).

**Backends differ by OS:** macOS → Virtualization / Apple Containerization
(product). macOS HV is lab-only. iOS/iPadOS → Relay (`StaticCpu` / `IosHv`).
Android / Linux → Relay (KVM on Linux). Do not share one hypervisor binary
across those hosts.

## Platforms

| Platform | Gate | Engine |
|---|---|---|
| macOS | **available** | `Virtualization.framework` + Apple Containerization (`wwn-containerd`) |
| Linux | **available** (KVM required) | KVM via cloud-hypervisor or crosvm |
| iOS / iPadOS / visionOS | planned | Relay StaticCpu / AOT; Mode B may use Hypervisor.framework in the UTM-era window |
| Android | planned | Relay. Play = Mode A. Root = Mode B |
| tvOS / watchOS / wearables | **forbidden** | Native + remote + Wasm only (no VM/container kinds) |

App Store / TestFlight copy must **never** pitch jailbreak, TrollStore, or JIT.
Website and `repo.wawona.io` may.

## Machines kinds

- `virtual_machine`. Linux guest via Relay
- `container`. OCI in that same Linux VM

## Not Wasm

Installing `.wasm` is [Runtime package management](wasm-package-manager.md)
(Mode A-safe `/wasm/` channel). Do not conflate with OCI Linux images.

## Agent rules

`.cursor/rules/wawona-mode-a-b.mdc` · `wawona-linux-vms-relay-runtime.mdc` ·
`wawona-platform-targets.mdc` ·
`Sources/WawonaModel/PlatformCapabilities.swift`.
