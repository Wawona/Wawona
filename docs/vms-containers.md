# Virtual machines and containers

> **Public subset** for wawona.io. Status: **planned / coming soon**.

Wawona will let users add **VM** and **container** machine profiles in the
Machines GUI and run guests directly through per-machine configuration. This is
**not** the on-device [bundled shell](ios-local-shell/README.md) and **not**
Desktop/LockScreen or anowaW.

## Platforms

| Platform | Gate | Planned engine |
|---|---|---|
| macOS | planned | `Virtualization.framework` (VMs) + Apple Containerization (`Containerization.framework`) |
| iOS / iPadOS | planned | **UTM-SE** interpreter (store-shaped). Jailbreak: JIT-enabled UTM. Sideload: make **TrollStore** JIT launch easy. |
| Android | planned | Containers and VMs via Wawona machine profiles (`wwn-vms` / `wwn-containers`) |
| Linux | planned | Containers and VMs via Wawona machine profiles |
| tvOS / watchOS / visionOS | **forbidden** | Native + remote only for machine kinds |

App Store / TestFlight copy for iOS/iPadOS must **never** pitch jailbreak,
TrollStore, or JIT as a store feature. Website and sideload docs may.

## Machines kinds

- `virtual_machine` — guest VM
- `container` — OCI / platform container

Engine selection stays automatic per target (`vmSubtype` / `containerSubtype`
removed). See [`machine-profiles.md`](machine-profiles.md).

## Agent rules

`.cursor/rules/wawona-platform-targets.mdc` · gates in
`Sources/WawonaModel/PlatformCapabilities.swift`.
