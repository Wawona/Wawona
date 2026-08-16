# Virtual machines and containers

> **Public subset** for wawona.io. Status: **planned / coming soon**.

Wawona will let users add **VM** and **container** machine profiles in the
Machines GUI and run guests directly through per-machine configuration. This is
**not** the on-device [bundled shell](ios-local-shell/README.md), **not**
[Wawona Runtime / Wasm packages](wasm-wasi.md), and **not** Desktop/LockScreen
or anowaW.

## Platforms

| Platform | Gate | Planned engine |
|---|---|---|
| macOS | planned | `Virtualization.framework` (VMs) + Apple Containerization (`Containerization.framework`). The Apple `container` CLI is **macOS-only** — see `wwn-containers` `.#apple-container` (swiftpm2nix). |
| iOS / iPadOS | planned | **Container / VM in interpreter:** UTM-SE–class **jitless** QEMU (App Store). Pull OCI images (e.g. Docker Hub) via `wwn-oci` / `wwn-containers`, run the rootfs **inside** that VM (same idea as Apple Container on macOS, without JIT). Jailbreak/sideload may use JIT UTM / TrollStore — **never** pitched in store copy. |
| Android | planned | Containers and VMs via Wawona machine profiles (`wwn-vms` / `wwn-containers`) |
| Linux | planned | Containers and VMs via Wawona machine profiles |
| tvOS / watchOS / visionOS | **forbidden** | Native + remote only for machine kinds |

App Store / TestFlight copy for iOS/iPadOS must **never** pitch jailbreak,
TrollStore, or JIT as a store feature. Website and sideload docs may.

## Machines kinds

- `virtual_machine` — guest VM
- `container` — OCI / platform container (Linux image → container backend)

Engine selection stays automatic per target (`vmSubtype` / `containerSubtype`
removed). See [`machine-profiles.md`](machine-profiles.md).

## Not Wasm

Installing or running `.wasm` for Wawona Runtime is **shell + Runtime package
management**, not a `container` machine. Do not conflate OCI *Wasm artifacts*
(optional package distribution) with OCI *Linux container images*.

## Agent rules

`.cursor/rules/wawona-platform-targets.mdc` · gates in
`Sources/WawonaModel/PlatformCapabilities.swift`.
