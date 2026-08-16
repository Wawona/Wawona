# wwn-vms — Mode A / Mode B implementation plan

Canonical product split: [Wawona `docs/mode-a-b.md`](https://github.com/Wawona/Wawona/blob/development/docs/mode-a-b.md).
Mirror: keep this file in sync with `Wawona/docs/vms-mode-a-b.md`.

## Goal

One Machines kind `virtual_machine`, **different backends per platform**, plus
Mode A vs Mode B on the iOS family:

| Platform | Mode A engine | Mode B / privileged |
|----------|---------------|---------------------|
| **macOS** | `Virtualization.framework` (not MAS) | Same + SIP desktop-host paths |
| **iOS / iPadOS** | UTM-SE–class **jitless** QEMU-TCTI | **JIT** UTM in Sileo Mode B IPA |
| **Android** | QEMU TCG (± AVF/KVM when available) | Root/privileged paths as designed |
| **Linux** | Host/QEMU profiles (TBD) | N/A |

Shared: Machines schema, guest artifacts, vsock + waypipe GUI, capability gates.
**Do not** assume the iOS interpreter path on macOS/Android or vice versa.

Containers are separate (`wwn-containers`): macOS Apple Containerization work is
in flight elsewhere — Wawona integration waits on that merge; do not block VMs
or Wasm packages on it.

## Shared substrate (both modes)

- Machine profile schema (`virtual_machine`)
- Guest image selection / NixOS guest artifacts (data)
- vsock + waypipe GUI path into Wawona
- Capability gate API: `VmEngineKind = .interpreterJitless | .jitEnabled`
- Unit tests against the interface, not a single binary

## Mode A implementation

1. Link / embed only TCTI (UTM-SE model) sources from `dependencies/vms/utm/`
   paths used for store builds.
2. CI: assert **no** JIT entitlements, no `MAP_JIT`, no Hypervisor on iOS store
   schemes; symbol/string scan for jailbreak/JIT engage UI = fail.
3. Performance: document TCTI ceiling; tune guest size (existing README levers).
4. Optional ODR/downloadable UTM-SE payload (see Wawona #33) — still jitless data.

## Mode B implementation

1. Separate product flavor / scheme: `Wawona-iOS-ModeB` (name TBD) **not**
   submitted to ASC.
2. Enable JIT UTM path (same family as jailbreak UTM / TrollStore JIT).
3. `repo.wawona.io` CI: build Mode B IPA → Sileo package automatically.
4. Mode B may use unsandboxed shell alongside VMs (product Mode B shell); VM
   engine must not be the only Mode B feature.
5. Website documents JIT; store IPA never mentions it.

## Never

- Ship Mode B engine inside App Store IPA “behind a toggle.”
- Pretend jitless and JIT are the same binary with an env var.
- Enable VM machine kind on tvOS/watchOS/visionOS (forbidden).

## Phases

| Phase | Work |
|-------|------|
| 1 | Engine interface + Mode A TCTI stub→real boot on device |
| 2 | Mode B JIT engine behind Mode-B-only target |
| 3 | repo.wawona.io auto Mode B IPA + Sileo metadata |
| 4 | e2e: Mode A guest waypipe; Mode B JIT guest waypipe |

## Success

- Store IPA boots a guest **without** JIT and passes App Store review notes.
- Sileo Mode B IPA boots the same profile class **with** JIT.
- Single Machines UI codepath; engine selected by build flavor / capability.
