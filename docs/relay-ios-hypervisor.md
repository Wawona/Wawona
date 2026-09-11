# Relay iOS Hypervisor (Mode B)

Canonical plan for **native** `Hypervisor.framework` on Mode B iOS / iPadOS
Wawona. Engine: [`github.com/Wawona/Relay`](https://github.com/Wawona/Relay)
(flake `wwn-relay`). Guest GUI stays vsock + waypipe into Wawona (iland).

This is **not** UTM. **Not** QEMU. **Not** HVF-via-qemu (`-accel hvf`).
macOS product VMs stay **Virtualization.framework**. macOS HV is a **lab
harness** for the shared Relay FFI only.

Status: **planned**. Probe + resolve land in Relay. vCPU / NixOS-on-HV boot
is not claimed until a window device boots NixOS. Operator has no HV-enabled
iOS device today. Lab and CI prove on **macOS Apple silicon**.

Related: [`vms-containers.md`](./vms-containers.md), [`mode-a-b.md`](./mode-a-b.md),
rule `wawona-relay-ios-hypervisor`, skill `wawona-relay-ios-hypervisor`.
Tracking: milestone **Relay iOS Hypervisor (Mode B)** on `Wawona/Wawona` and
`Wawona/Relay`.

---

## Mode A vs Mode B (no Settings toggle)

Mode A vs Mode B is **which binary was installed**. Relay auto-detects.

| Artifact | VM / container backend | Wasm |
|----------|------------------------|------|
| Mode A store / TestFlight IPA | `StaticCpu` only. Never HV | Pulley (`/wasm/v1`) |
| Mode B tipa / Sileo | `IosHv` when probe says yes; else `StaticCpu` | Pulley. MAP_JIT wasm is not Hypervisor.framework |
| macOS product | `Vz` always | Cranelift / Pulley per product |

HV applies to **VM and container-in-VM only**. Never select `IosHv` for wasm.

---

## UTM compatibility window (verify; do not copy QEMU)

Apple shipped kernel HV on iOS / iPadOS **14.0 through 16.3.1**. **16.4+**
removed it. Jailbreak does **not** restore HV on 16.4+. TrollStore is enough
for the entitlement class UTM uses. Public product SoCs match UTM 4.4.5:
**M1, M2, A16** only. **A12Z** is hardware-capable and **not** a public
Wawona target.

### Public device / OS matrix

| Device family | SoC | OS window | Relay Mode B HV |
|---------------|-----|-----------|-----------------|
| iPad Pro 11" 3rd / 12.9" 5th | M1 | 14.5–16.3.1 | planned when device exists |
| iPad Air 5th | M1 | 15.4–16.3.1 | planned when device exists |
| iPad Pro 11" 4th / 12.9" 6th | M2 | 16.1–16.3.1 | planned when device exists |
| iPhone 14 Pro / Pro Max | A16 | 16.0–16.3.1 | planned when device exists |
| A12Z iPad Pro | A12Z | ≤16.3.1 | **not public** (`soc-not-public`) |
| iPhone 14 / A15 and older public phones | A15… | any | **no** (`soc-unknown`) |
| Any device | any | **16.4+** | **no** (`os-too-new`) |
| M3 / M4 / M5 iPad, iPhone 15+ | newer | shipped after window | **no** |

Code allowlist: `Relay/crates/relay-core/src/ios_hv.rs` (`public_hv_target`,
`IOS_HV_OS_CEILING`).

### SoC capability vs public support

| SoC | Hardware virt class | Public Wawona HV |
|-----|---------------------|------------------|
| A12Z | Capable | No |
| M1 / M2 / A16 | Capable | Yes inside OS window |
| A15 and below (public phones) | No | No |
| A17+ / M3+ on iOS | Often capable silicon | No (OS past 16.3.1) |

---

## Auto-detect (Relay owns it)

Inputs:

1. Artifact class (`ModeA` vs `ModeB`)
2. `hw.machine` + `kern.osproductversion` (live on `target_os=ios`, or
   injected `IosHvHost` in tests)
3. Kernel trap when cargo feature `ios-hv` is on (Mode B only):
   `HV_CALL_VM_GET_CAPABILITIES` via `svc 0x80`. `HV_UNSUPPORTED` means
   kernel has no HV. Store IPA must keep `ios-hv` **off**
4. Optional private hypervisor entitlement fact

Resolve (`resolve_ios_linux_vm`):

```text
Mode A                              → StaticCpu
Mode B + probe.supported            → IosHv
Mode B + probe fail / no facts      → StaticCpu
Wasm (any)                          → Pulley
macOS VM                            → Vz (never IosHv)
tvOS / watchOS / visionOS           → Forbidden (kinds), not HV
```

C ABI: `relay_probe_ios_hv` in `wawona_relay.h`. UI never picks a hypervisor.

`start()` for `IosHv` currently returns `Planned` ("vCPU is not implemented
yet"). That is correct until a window device boots NixOS.

---

## Store / TestFlight firewall

Forbidden in Mode A IPA:

- `com.apple.private.hypervisor` / private hypervisor entitlements
- Hypervisor.framework symbols linked into the store slice
- Cargo feature `ios-hv`
- Any Settings or in-app Mode A→B HV switch

Compile against the **latest** iPhoneOS SDK. Weak-link / runtime probe.
Min OS remains 11.0 (`wawona-ios-min-os`). HV availability is a **runtime**
window, not a deployment-target floor.

---

## macOS HV lab (not the shipping macOS VM)

| Item | Rule |
|------|------|
| Product macOS VM | `Virtualization.framework` only |
| Lab | `hv_vm_create` + destroy on Apple silicon. Entitlement `com.apple.security.hypervisor` |
| Not enough | `com.apple.security.virtualization` (VZ) alone |
| Nested / GHA | Skip on `HV_UNSUPPORTED`. Do not fail the suite |
| UTM macOS | `jb_has_hypervisor()` is unconditional true. Wawona must actually create a VM |

macOS lab proves the **shared FFI and entitlement story**. It does **not**
claim iOS product HV.

---

## Proof devices (do / do not)

| Device | Role |
|--------|------|
| macOS Apple silicon | Required HV lab / CI for `hv_vm_create` |
| M1 / M2 iPad or iPhone 14 Pro on ≤16.3.1 | Future product NixOS-on-HV proof |
| `vphone wawona-jb` | Mode B tipa / IOMFB / open-jit. **Not** HV (iOS 26, no HV kernel) |
| STARDUST / retail iPhone 15+ / iOS 26 | **Not** HV proof |

---

## Hard rejects

- QEMU, TCTI, UTM as the product VM, Spice / CocoaSpice / virgl
- HVF-via-qemu as “Hypervisor support”
- Settings HV toggle or Mode A binary that can flip to HV
- Selecting `IosHv` for wasm
- Claiming HV available before a window device boots NixOS
- Parking this milestone on vphone or iOS 26 hardware

## Code map

| Piece | Path |
|-------|------|
| Probe / allowlist | `Relay/crates/relay-core/src/ios_hv.rs` |
| Backend enum | `RelayBackend::IosHv` |
| Resolve | `resolve_ios_linux_vm` in `relay-core` |
| Start fail-closed | `relay-vm` `start_ios_hv` → `Planned` |
| C ABI | `relay_probe_ios_hv` |
| Feature | `ios-hv` (default off) |
