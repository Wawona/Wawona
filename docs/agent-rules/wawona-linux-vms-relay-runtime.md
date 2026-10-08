---
description: NixOS-only VMs. Mode A uses Wawona store runtime only. Mode B adds Wawona Mode B runtime. Not UTM
alwaysApply: true
---

# Linux VMs for Wawona (Relay runtime, NixOS prebuilts)

Wawona does **not** run arbitrary VMs. Machines kind `virtual_machine` is
**Linux only**: **NixOS prebuilts**, OrbStack-style, on **iOS / macOS / Android /
Linux**. tvOS / watchOS / visionOS stay **forbidden** for VM/container kinds.

The engine is **Wawona Relay** (`github.com/Wawona/Relay`, flake input
`wwn-relay`). Not UTM. Guest GUI is Wayland into Wawona
(`wawona-guest-wayland-iland`).

## Runtimes (never mix into the wrong artifact)

| Product | What may run |
|---|---|
| **Mode A** (App Store / TestFlight / Play / store-shaped) | **Only** Wawona’s App Store-compliant runtime: Relay static handlers, WASI via Pulley, jitless VM CPU if any. **No JIT**, no `MAP_JIT`, no Hypervisor.framework, no UTM |
| **Mode B** (TrollStore / Sileo / SIP-off desktop-host / root Android) | That **same** Mode A runtime **plus** Mode B VM path. On iOS/iPadOS, `IosHv` when the probe window matches (`wawona-relay-ios-hypervisor`). Never Mode B in a store IPA/AAB |

Wasm packages stay bytecode (`/wasm/`). Mode B may JIT-execute them where that artifact already allows JIT. Mode A iOS 13-26 must not. Mode A iOS and iPadOS 27+ execute the same bytecode with Wasmer WASIX in a hidden WKWebView (WebKit JIT and JSPI) when WasmerSDK is linked. Mode A must not use Cranelift or MAP_JIT.
Relay Wasm itself ships on **every** Wawona product target, including watchOS,
tvOS, visionOS, and Linux (`wawona-relay-wasm`). VM/container kinds stay
forbidden on watch/tv/vision. Wasm does not.

Mode A speed design, not shipped: offline multi-threaded AOT of the bundled
guest, calling the same StaticCpu helpers, proved by Kani and Verus
refinement (`Relay/docs/ios13-aot-assessment.md`). StaticCpu is the oracle
and the fallback. One semantics. The translator does not ship in the app.
No JIT, no `MAP_JIT`, no Hypervisor.framework. No fastest or cleanest claim
until that doc's measurements exist.

## Destination

**Build in Relay.** No QEMU. No UTM. No TCTI reference CPU. No HVF-via-qemu.
iOS / Play Linux VMs stay **planned** and fail closed until Relay boots NixOS.
Mode B iOS may select native Hypervisor.framework inside the UTM-era window
(see `wawona-relay-ios-hypervisor`). macOS **product** VMs use
Virtualization.framework (macOS HV is lab-only). Linux uses KVM via
cloud-hypervisor or crosvm. Fail closed without `/dev/kvm`. Never call a
leftover QEMU tree the Wawona runtime.

## Required MicroVM and disk behavior

- Relay **must support NixOS MicroVM profiles** as first-class Wawona Machines
  on every target that permits VM machines. A MicroVM uses Relay's CPU, virtio,
  `wwn-iland` userspace DRM/KMS/GBM, and Wawona Wayland path.
- A virtual disk is grow-only while a machine is stopped. Relay owns the size
  validation and resize plan; native UI exposes it as a simple discrete slider.
- The slider never changes a running disk, shrinks a filesystem, or delegates
  sizing logic to SwiftUI, Kotlin, or a shell command.

## Hard rejects

- Windows / macOS / BSD / “any ISO” guests as product Machines
- UTM as the product VM (Spice, CocoaSpice, virgl, UTM ANGLE). GitHub #33 (bundle UTM-SE) closed wontfix
- QEMU / TCTI as a product or temporary VM CPU
- Mode B runtime, JIT, or UTM in App Store / Play artifacts
- One binary with a hidden “enable JIT” toggle for stores
- Claiming App Store approval or "world's fastest" without evidence
- A second Mode A guest CPU. Offline AOT must refine StaticCpu's helpers. No runtime compiler in the store IPA.
- Size-gating wasm off any product target

Canonical: `wawona-guest-wayland-iland`, `wawona-mode-a-b`,
`wawona-ios-mode-b-channels`. Prose:
`docs/agent-rules/wawona-linux-vms-relay-runtime.md`.
