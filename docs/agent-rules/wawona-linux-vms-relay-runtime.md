# Linux VMs for Wawona (Relay runtime, NixOS prebuilts)

Wawona does **not** run arbitrary VMs. Machines kind `virtual_machine` is
**Linux only**: **NixOS prebuilts**, OrbStack-style, on **iOS / macOS / Android /
Linux**. tvOS / watchOS / visionOS stay **forbidden** for VM/container kinds.

The engine is **Wawona’s**, not UTM. Guest GUI is Wayland into Wawona
(`wawona-guest-wayland-iland`).

## Runtimes (never mix into the wrong artifact)

| Product | What may run |
|---|---|
| **Mode A** (App Store / TestFlight / Play / store-shaped) | **Only** Wawona’s App Store-compliant runtime: Relay static handlers, WASI via Pulley, jitless VM CPU if any. **No JIT**, no `MAP_JIT`, no HVF, no UTM |
| **Mode B** (TrollStore / Sileo / SIP-off desktop-host / root Android) | That **same** Mode A runtime **plus** Wawona’s Mode B runtime (JIT VM CPU allowed). Never Mode B in a store IPA/AAB |

Wasm packages stay bytecode (`/wasm/`). Mode B may JIT-execute them; Mode A must not.
Relay Wasm itself ships on **every** Wawona product target, including watchOS,
tvOS, visionOS, and Linux (`wawona-relay-wasm`). VM/container kinds stay
forbidden on watch/tv/vision. Wasm does not.

## Destination

**Build toward Relay.** No QEMU. No UTM. No TCTI reference CPU. iOS / Play
Linux VMs stay **planned** and fail closed until Relay’s own CPU can boot
NixOS. macOS may use Virtualization.framework. Linux may use KVM via
cloud-hypervisor or crosvm. Never call a leftover QEMU tree the Wawona runtime.

## Hard rejects

- Windows / macOS / BSD / “any ISO” guests as product Machines
- UTM as the product VM (Spice, CocoaSpice, virgl, UTM ANGLE)
- QEMU / TCTI as a product or temporary VM CPU
- Mode B runtime, JIT, or UTM in App Store / Play artifacts
- One binary with a hidden “enable JIT” toggle for stores
- Claiming App Store approval or “world’s fastest” without evidence
- Size-gating wasm off any product target

Canonical: `wawona-guest-wayland-iland`, `wawona-mode-a-b`,
`wawona-ios-mode-b-channels`. Cursor:
`.cursor/rules/wawona-linux-vms-relay-runtime.mdc`.
