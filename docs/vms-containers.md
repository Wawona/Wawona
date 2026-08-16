# Virtual machines and containers

> **Public subset** for wawona.io. Status: **planned / coming soon**.
> Full Mode A/B: [`mode-a-b.md`](./mode-a-b.md), [`vms-mode-a-b.md`](./vms-mode-a-b.md),
> [`containers-mode-a-b.md`](./containers-mode-a-b.md).

Wawona will let users add **VM** and **container** machine profiles in the
Machines GUI. This is **not** the on-device [bundled shell](ios-local-shell/README.md),
**not** [Wawona Runtime / Wasm packages](wasm-wasi.md), and **not**
Desktop/LockScreen or anowaW.

## Mode A vs Mode B (iOS / iPadOS)

| | **Mode A** (App Store IPA) | **Mode B** (Sileo Mode B IPA) |
|---|---|---|
| Engine | UTM-SE–class **jitless** interpreter | UTM/QEMU **with JIT** |
| Containers | OCI pull + container-in-VM on jitless VM | Same OCI pull + **JIT** container-in-VM |
| Ship | Store / TestFlight only | `repo.wawona.io` auto-packages Mode B IPA — **never** in App Store |

Design both in `wwn-vms` / `wwn-containers` / Wawona at all times. Mode B code
must be compile-time absent from store artifacts.

**Backends differ by OS:** macOS → Virtualization / Apple Containerization;
iOS family → UTM-SE-class (A) or JIT UTM (B); Android → QEMU±KVM/proot. Do not
share one engine across those hosts. **Note:** active work on macOS Apple
Container in `wwn-containers` — leave that repo alone until it merges; VMs and
Wasm packages proceed independently.

## Platforms

| Platform | Gate | Planned engine |
|---|---|---|
| macOS | planned | `Virtualization.framework` + Apple Containerization (not MAS for run) |
| iOS / iPadOS | planned | **A:** jitless UTM-SE-class. **B:** JIT UTM via Sileo Mode B IPA |
| Android | planned | QEMU ± KVM/AVF; Play = Mode A; root paths = Mode B |
| Linux | planned | Machine profiles via `wwn-vms` / `wwn-containers` |
| tvOS / watchOS / visionOS | **forbidden** | Native + remote only |

App Store / TestFlight copy must **never** pitch jailbreak, TrollStore, or JIT.
Website and `repo.wawona.io` may.

## Machines kinds

- `virtual_machine` — guest VM (`wwn-vms`)
- `container` — OCI container (`wwn-containers`)

## Not Wasm

Installing `.wasm` is [Runtime package management](wasm-package-manager.md)
(Mode A–safe `/wasm/` channel). Do not conflate with OCI Linux images.

## Agent rules

`.cursor/rules/wawona-mode-a-b.mdc` · `wawona-platform-targets.mdc` ·
`Sources/WawonaModel/PlatformCapabilities.swift`.
