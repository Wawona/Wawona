---
description: Mode B iOS/iPadOS Hypervisor.framework via Relay. Not QEMU HVF. Store IPA never.
alwaysApply: true
---

# Relay iOS Hypervisor (Mode B)

Authority: `Wawona/docs/relay-ios-hypervisor.md`. Engine:
`github.com/Wawona/Relay` (`wwn-relay`). Guest GUI is vsock + waypipe into
Wawona (iland).

## What this is

Native **Hypervisor.framework** for Mode B **VM and container-in-VM** on
iOS / iPadOS inside the UTM-era window (kernel HV on **14.0–16.3.1**, public
SoCs **M1 / M2 / A16**). Probe: `Relay/crates/relay-core/src/ios_hv.rs`.

## What this is not

- QEMU, TCTI, UTM-as-product, Spice / CocoaSpice / virgl
- **HVF-via-qemu** (`-accel hvf`). Forbidden as the Wawona engine
- Wasm / Pulley / `MAP_JIT` (those are not Hypervisor.framework)
- macOS product VM backend (that is **Virtualization.framework**; macOS HV
  is lab-only for the shared FFI)
- A Settings toggle or Mode A→B in-app switch

## Resolve

| Case | Backend |
|------|---------|
| Mode A iOS/iPadOS VM/container | `StaticCpu` |
| Mode B + probe.supported | `IosHv` |
| Mode B + probe fail / no host facts | `StaticCpu` |
| Wasm | Pulley (`/wasm/v1`) |
| macOS VM | `Vz` |
| tvOS / watchOS / visionOS | VM/container kinds **forbidden**; HV forbidden |

## Store firewall

Mode A / TestFlight IPA: no private hypervisor ents, no HV symbols, cargo
feature `ios-hv` **off**. Compile against latest iPhoneOS SDK; runtime probe
(`wawona-ios-min-os`).

## Proof devices

- **Required lab:** macOS Apple silicon (`hv_vm_create` + destroy;
  `com.apple.security.hypervisor`). Nested/GHA: skip `HV_UNSUPPORTED`.
- **Not HV proof:** `vphone wawona-jb`, STARDUST, retail iPhone 15+ / iOS 26.
- Do not claim product HV until M1/M2/A16 on ≤16.3.1 boots NixOS.

## Hard rejects

❌ QEMU / UTM / HVF-via-qemu as the product path  
❌ HV in store IPA or `ios-hv` on Mode A  
❌ `IosHv` for wasm  
❌ Parking this on vphone / iOS 26  
❌ Calling macOS HV the shipping macOS VM backend
