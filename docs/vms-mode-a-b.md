# wwn-vms. Mode A / Mode B implementation plan

Canonical product split: [Wawona `docs/mode-a-b.md`](https://github.com/Wawona/Wawona/blob/development/docs/mode-a-b.md).
iOS channels: [wawona-ios-mode-b-channels](https://github.com/Wawona/Wawona/blob/development/docs/agent-rules/wawona-ios-mode-b-channels.md).
Mirror: keep this file in sync with `wwn-vms/docs/MODE-A-B.md`.

## Goal

One Machines kind `virtual_machine`, **different backends per platform**, plus
Mode A vs Mode B on the iOS family:

| Platform | Mode A engine | Mode B / privileged |
|----------|---------------|---------------------|
| **macOS** | QEMU + HVF (`Hypervisor.framework`) | Same (macOS not App Store constrained) |
| **iOS / iPadOS** | **jitless** QEMU-TCTI (`-accel tcg`, UTM SE) | **JIT** QEMU/UTM via **TrollStore** and/or **Sileo** Mode B IPA |
| **Android** | QEMU + KVM when present, else TCG+JIT | Root/privileged paths as designed |
| **Linux** | Host/QEMU profiles (TBD) | N/A |

### iOS QEMU: interpreter vs JIT

```text
App Store / TestFlight  →  TCTI / TCG interpreter only. No MAP_JIT.
TrollStore sideload     →  Mode B IPA flavor with JIT (VMs; containers share engine).
Sileo (jailbreak)       →  Same JIT engine + Desktop/LockScreen/Swinging Bridge product.
```

Shared: Machines schema, guest artifacts, vsock + waypipe GUI, capability gates.
**Do not** assume the iOS interpreter path on macOS/Android or vice versa.

Containers are separate (`wwn-containers`): macOS Apple Containerization work is
in flight elsewhere. Wawona integration waits on that merge; do not block VMs
or Wasm packages on it.

## Shared substrate (both modes)

- Machine profile schema (`virtual_machine`)
- Guest image selection / NixOS guest artifacts (data)
- vsock + waypipe GUI path into Wawona
- Capability gate API: `VmEngineKind = .interpreterJitless | .jitEnabled`
- Unit tests against the interface, not a single binary
- Rust helper: `wwn-vms` `crates/wwn-vms-engine` (`Tcti` vs `TcgJit`)

## Mode A implementation

1. Link / embed only TCTI (UTM-SE model) sources from `dependencies/vms/utm/`
   paths used for store builds. Force `-accel tcg` (see `WWNMobileVmEngine`).
2. CI: assert **no** JIT entitlements, no `MAP_JIT`, no Hypervisor on iOS store
   schemes; symbol/string scan for jailbreak/JIT/TrollStore/Sileo engage UI = fail.
3. Performance: document TCTI ceiling; tune guest size (existing README levers).
4. Optional ODR/downloadable UTM-SE payload (see Wawona #33). Still jitless data.

## Mode B implementation

1. Separate product flavor / scheme: `Wawona-iOS-ModeB` (name TBD) **not**
   submitted to ASC.
2. Enable JIT UTM/QEMU path (TrollStore entitlement and/or jailbreak).
3. `repo.wawona.io` CI: build Mode B IPA → Sileo package automatically.
4. Website documents TrollStore (JIT) and Sileo (full Mode B). Store IPA never mentions either.
5. Sileo product also ships Desktop / LockScreen / Swinging Bridge Mode B (not a VM-only IPA).

## Never

- Ship Mode B engine inside App Store IPA “behind a toggle.”
- Pretend jitless and JIT are the same binary with an env var.
- Enable VM machine kind on tvOS/watchOS (forbidden).
- Document TrollStore as providing Desktop/LockScreen/Swinging Bridge by itself.

## Phases

| Phase | Work |
|-------|------|
| 1 | Engine interface + Mode A TCTI stub→real boot on device |
| 2 | Mode B JIT engine behind Mode-B-only target (TrollStore + Sileo) |
| 3 | repo.wawona.io auto Mode B IPA + Sileo metadata |
| 4 | e2e: Mode A guest waypipe; Mode B JIT guest waypipe |

## Success

- Store IPA boots a guest **without** JIT and passes App Store review notes.
- TrollStore / Sileo Mode B IPA boots the same profile class **with** JIT.
- Single Machines UI codepath; engine selected by build flavor / capability.
