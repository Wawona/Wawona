---
name: wawona-relay-ios-hypervisor
description: Mode B iOS/iPadOS Hypervisor.framework via Relay. Open when editing HV probe, IosHv, store IPA HV firewall, or macOS HV lab.
---

# Relay iOS Hypervisor (pointer)

Open the alwaysApply rule **`wawona-relay-ios-hypervisor`**.

Canonical: `Wawona/docs/relay-ios-hypervisor.md`.

Engine: `Relay` (`wwn-relay`). Not QEMU. Not HVF-via-qemu. Not UTM-as-product.
macOS product VM = Virtualization.framework. macOS HV = lab only.

| Edit | Where |
|------|--------|
| Probe / allowlist / resolve | `Relay/crates/relay-core/src/ios_hv.rs` |
| Start Planned until vCPU | `Relay/crates/relay-vm` |
| C ABI | `relay_probe_ios_hv` |
| Machines trampoline | L4 `Wawona` |

Hard rejects: HV in store IPA; `IosHv` for wasm; parking on vphone / iOS 26;
claiming product HV before a window device boots NixOS.
