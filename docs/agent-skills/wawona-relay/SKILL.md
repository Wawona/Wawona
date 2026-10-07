---
name: wawona-relay
description: Wawona Relay is the only VM, container-in-VM, and Mode A WASI engine. Use when editing Linux guests, OCI, wasm runtime, flake input wwn-relay, or dropping QEMU/UTM.
---

# Wawona Relay (pointer)

Repo: `github.com/Wawona/Relay` (`development`). Flake input: **`wwn-relay`**. Layer **L3′**. Wawona calls one API (`wawona_relay.h`) for:

- `virtual_machine`: Linux / NixOS prebuilts only. Mode A speed design is offline multi-threaded AOT of the bundled guest, one StaticCpu semantics, Kani/Verus refinement. Not shipped. StaticCpu is the oracle and the fallback. No JIT, no `MAP_JIT`, no Hypervisor.framework in the store IPA. No fastest or cleanest claim until `Relay/docs/ios13-aot-assessment.md` is measured.
- `container`: OCI unpack, then the **same** Linux VM backend
- WASI / `wpm`: Mode A bytecode (`/wasm/v1`) only. iOS and iPadOS through OS 26 execute with Pulley. OS 27 Mode A uses Wasmer WASIX in a hidden WKWebView when `WWN_WASMER_IOS27` links WasmerSDK. Otherwise Pulley. No Cranelift or MAP_JIT in the store IPA. macOS and Linux stay Wasmtime Cranelift. Fuel stays on. One burst is 2e9 instructions (`fuel_budget`), refilled after a Wayland `socket_recv` that returns bytes. 25e6 traps `chess-wawona` during the first SHM frame after `toplevel configure 0x0`. Do not turn fuel off.
- Machines kind `wasm`: Start is `wasm <file|package>` (same as native shell).
  Native machines keep the `wawona-wasm` client. Do not strip `bundledAppID`
  when loading a `wasm` profile.
- Android product `wawona-wasm` is header-only today (empty `lib/`). Link
  `-lwawona_wasm` only when `libwawona_wasm.a` exists. Weak JNI
  `wawona_wasm_run` stays null until Relay ships that archive. Do not toast
  ProcessBuilder "not bundled" for type wasm.

## Rules to open

- `wawona-linux-vms-relay-runtime`
- `wawona-guest-wayland-iland`
- `wawona-relay-wasm`
- `wawona-repo-dag`
- `wawona-product-map`
- `wawona-mode-a-b` / `wawona-ios-mode-b-channels`

Canonical prose: `Wawona/docs/agent-rules/wawona-linux-vms-relay-runtime.md`, `Relay/README.md`.
Completion scorecard (not harness counts): `Relay/docs/static-cpu-completion-plan.md`
2026-10-06. Completely complete iOS Mode A VM is **0%**. Twelve-gate ~48%.
iOS `vm` stays planned. Remaining work follows **Shortest calendar path** in
that file: 4 KiB SHM import first, no second smoke, no guest rebuild, no
16 KiB/AOT/ISA/STARDUST until the frame hash.

## Rust + crate2nix (required)

Relay product logic is **Rust**. C/ObjC/Swift/JNI is only thin ABI or Apple framework trampolines (`wawona_relay.h`, eventual VZ ObjC bridge). Do not grow Swift/C engines, spikes as product paths, or new `buildRustPackage` monoliths. Nix builds of Relay crates must use **crate2nix** for per-crate `/nix/store` derivations (same granularity as L4 `rust-backend-c2n.nix`): 1. Pin: `crate2nix.follows = "wwn-toolchain/crate2nix"` (L0 owns the tip). 2. Build: `crate2nix.tools.${system}.generatedCargoNix` over the Relay
   workspace / `Cargo.lock`, then per-crate `build` / staticlib assemble.
3. Hard reject: new Relay recipes that only wrap `rustPlatform.buildRustPackage`
   for the whole workspace (one change rebuilds everything).
Open debt: migrate `recipes/relay-staticlib.nix` (Apple mobile / Android) and `import/wasm/**/*.nix` off `buildRustPackage`. Replace Swift `wawona-vz-run` (`WawonaLinuxVZ.swift`) with a Rust Virtualization.framework launcher (thin ObjC only if the ABI forces it). Host macOS/Linux `wawona-relay` already uses `recipes/relay-crate2nix.nix`. Guest OCI virtiofs needs a rebuilt `wawona-nixos-guest-*` image (VIRTIO_FS + crun + `wawona-container` unit).

## Case-insensitive Determinate builder

Determinate's native Linux builder exposes the macOS Nix store through VirtioFS. Relay guest artifacts must handle Nix case-hack names:

- Use the minimal scripted initrd. Disable default modules, suppress `ext2`,
  and request only `virtio_mmio`, `virtio_blk`, `virtio_console`,
  `vmw_vsock_virtio_transport`, and `ext4`.
- Reject any `~nix~case~hack~N` path found in the completed initrd.
- Build the ext4 image from the physical store tree, then rename case-hacked
  directory entries inside the image with `debugfs`. Never materialize the
  decoded tree on the case-insensitive host.
- Do not add `virtio_vsock`. That is not a Linux module name.

Implementation: `Relay/import/vms/dependencies/vms/mobile/{guest,guest-artifacts}.nix`. Direct Image boot must build `manifest.json` command_line from `cfg.boot.kernelParams`; it does not pass through the NixOS bootloader. Do not duplicate a shorter hard-coded command line in `guest-artifacts.nix`. For StaticCpu boot diagnosis use `nokaslr` plus `earlycon=pl011,mmio32,0x09000000`, and report both virtual and translated physical PC. Place a relocatable ARM64 Image at a 2 MiB aligned base plus the header's `text_offset`; a hard-coded `0x80000` load corrupts execution when a new kernel reports zero text offset. Decode `LDAR` and `STLR` before the broader exclusive-load/store masks. Misclassifying `STLRB` as `STXR` silently drops Linux spinlock unlocks and deadlocks `console_sem` before PL011 output. Keep guest RAM at the conventional `0x40000000` base so GIC, PL011, and virtio-mmio remain outside Linux RAM. Place the initrd after the ARM64 header's `image_size`, not after the shorter Image file, or kernel BSS clearing corrupts the archive. StaticCpu timer expiry must surface as the DT-selected GIC PPI (virtual 27, physical 30), not as a private interpreter interrupt. For the boot-proof guest use `boot.initrd.compressor = "cat"`: plain `newc` cpio keeps optional zstd decoder coverage out of the stage-1 critical path. The 4 KiB bundle is boot-proven through macOS Virtualization.framework `wawona-vz-run`: stage 1, stage 2, automatic login, and guest Wayland service start. Relay Rust `start_vz` now owns artifact verification, persistent writable disk state, launcher lifecycle, console
capture, readiness, Wayland endpoint, restart, and stop.
VZ lifecycle details:

- APFS `clonefile` preserves the read-only Nix store mode. Add owner write
  permission to the cloned rootfs before attaching it, or VZ rejects the
  storage attachment.
- Do not scrape ANSI-formatted systemd `Started` lines. The guest
  `ExecStartPost` writes `WAWONA_RELAY_READY=1` to `hvc0`; Rust waits for that
  exact readiness contract.
- A stable machine ID selects persistent disk state. A second live start is
  rejected. A dead process may be recovered and restarted on that same disk.
- Release guest starts require a trusted Ed25519 manifest signature. Unsigned
  bundles require an explicit development-only resource flag.
- Guest kernels are Linux 7.2 or newer (`linuxPackages_latest` / `linux_latest`).
- A 16 KiB page guest needs a real `ARM64_16K_PAGES` kernel. Do not relabel a
  4 KiB Image. On Determinate's native Linux builder, start from the NixOS
  `linux_latest` config, flip to 16 KiB pages, disable large unused trees
  (USB/SOUND/MEDIA/WLAN/DRM/…), disable `DEBUG_INFO` / DWARF, skip
  `dtbs_install`, and force `# CONFIG_OF is not set` after every
  `olddefconfig` (Apple VZ is ACPI; OF rebuilds every arm64 DTB). Then purge
  loadable modules (`=m` → unset) and force Relay builtins only (`EXT4`,
  virtio blk/console/net/mmio/pci, `VIRTIO_VSOCKETS`, `ACPI`, `PCI`, …) with
  `MODULES=y` so initrd can read `modules.builtin`. Slim `postInstall`: do not
  copy gdb `constants.py` or a full `$dev` source tree (`GDB_SCRIPTS` is off).
  Cap `NIX_BUILD_CORES` (builder is 1 vCPU). A raw defconfig / fat module tree
  fills scratch (`No space left on device` while compiling `net/dsa` or linking
  `vmlinux.o`). A too-thin `allnoconfig` Image under VZ shows empty `hvc0` and
  readiness timeout. `MODULES=n` fails initrd with `Required modules: ext4`.
  Do not leave `relay-vm-state*/**/wayland.sock` under the flake `path:.` tree:
  Nix cannot copy unix sockets.

## StaticCpu boot and verification

Use `relay-vm` example `static_differential` before adding more speculative
opcode handlers. Its versioned JSONL checkpoints include GPR/SIMD, exception
and timer state, plus guest dirty-page hashes. Cumulative SHA-256 makes the
first mismatch monotonic for binary search. Native AArch64 or QEMU may produce
the reference trace only as outside-product development tooling. Never bundle
that reference engine or plugin. Narrow the interval to one instruction, then
add a minimized regression test. Contract: `Relay/docs/static-cpu-differential.md`.
Linux virtio-console RX buffers remain device-owned while host input is empty.
Completing them with length zero causes Linux recycle/notify IRQ storms. Virtio
block requests may scatter across descriptors whose boundaries cross sectors.
Validate full request, bounds, and guest memory before mutating disk or RAM.
LDTR/STTR stage-1 translation failure is normal Linux uaccess. Enter EL1
synchronous data-abort vector with ELR_EL1, SPSR_EL1, ESR_EL1, FAR_EL1, DAIF,
and WnR set. Never terminate host interpreter for a user page fault.
Stage-1 data translation must enforce terminal PTE AP permissions. In
particular, an EL0 write to AP=11 is a permission fault, not a successful host
memory write. Bypassing that fault defeats Linux fork COW and silently corrupts
glibc/bash stacks. Preserve translation-vs-permission DFSC in ESR_EL1.
Kani and Verus must pass before Relay VM Rust executes. Skill
`wawona-formal-verification`.

## Backends (Relay picks them)
| Host | VM | Container | Wasm |
|------|----|-----------|------|
| macOS Apple silicon | VZ | OCI on VZ | Cranelift |
| Linux AppImage | KVM (cloud-hypervisor / crosvm). Fail closed without `/dev/kvm` | OCI on that VM | Cranelift |
| iOS / iPadOS Mode A | static CPU (planned) | OCI on that VM | Pulley through OS 26. OS 27+: Wasmer WASIX in WebKit when WasmerSDK is linked |
| iOS / iPadOS Mode B | `IosHv` when probe window matches; else static. Not HVF-via-qemu | OCI on that VM | same /wasm/v1. Pulley |
| Android Play | static CPU (planned). No AVF | OCI-in-VM. No proot | Pulley (Mode A) |
| Android Mode B | AVF lab | OCI-in-VM. No proot | Cranelift |
| visionOS | static CPU (planned) | OCI on that VM | Pulley |
| tvOS / watchOS | forbidden | forbidden | Pulley (required) |

Mode A vs Mode B is **which binary was installed**. Not a Settings toggle.

## Hard rejects

- QEMU, TCTI, HVF-via-qemu, `qemu-*.framework`
- UTM / Spice / CocoaSpice / virgl
- Host Docker, runc-on-host, proot
- Edit target `wwn-vms` / `wwn-containers` / `wwn-wasm` for new work
- AVF in Play. Termux debs as a Relay backend
- "Faster than UTM" or "world's fastest" copy
- New Relay product logic in Swift/C (headers / thin trampolines only)
- New monolithic `buildRustPackage` for the Relay workspace (use crate2nix)
- Hypervisor.framework / `ios-hv` in Mode A store IPA
- Selecting `IosHv` for wasm
- Calling macOS HV the shipping macOS VM backend (product is VZ)

Mode B iOS HV window: rule/skill `wawona-relay-ios-hypervisor`,
`Wawona/docs/relay-ios-hypervisor.md`. Distinguish **forbidden HVF-via-qemu**
from **Relay native Hypervisor.framework** on the Mode B SoC/OS window.

## Where to edit

| Change | Repo |
|--------|------|
| Backend table, C ABI, flake `registryFragment` | `Wawona/Relay` |
| Machines trampoline (`WWNRelay`) | L4 `Wawona` |
| Guest GUI / iland present | `wwn-iland` + L4. Never UTM display |


Cross-page scalar/SIMD memory accesses must translate every virtual fragment:
adjacent virtual pages may map discontiguous physical frames. Validate both
fragments before split stores so second-page permissions fault without partial
writes. Native SIMD tests cover every split for 4/16 KiB mappings.
16 KiB Linux needs TGran16=1 (TGran4=0, TGran64=15) and TxSZ-derived starting
levels per TTBR. Measured TCR_EL1=0x045000757551b510 has T0SZ=16 (four-level
48-bit low half), T1SZ=17 (three-level 47-bit high half). Mask canonical high
bits before initial lookup. Hardcoded four-level walks cause PC=0x200 loops.
Differential traces are untrusted evidence: recompute state/chain hashes and
reject empty/malformed/reordered checkpoints. `instructions` counts interpreter
steps, including synchronous exception entries; it is not retirement. No
full-system reference adapter ships yet. Self-replay proves determinism only.
`static_smoke` must reject loader errors, panics and interpreter failures even
while a thread stays alive. Acceptance: `Relay/docs/static-cpu-acceptance.md`.
`cpu/native_reference.rs` runs fixed, statically assembled AArch64 instructions;
no guest bytes execute and no executable memory is generated. FP tests restore
host FPCR/FPSR/NZCV and compare guest results plus exceptions. Coverage includes:
UMOV/SMOV, DUP, INS, MOVI/MVNI/ORR/BIC/FMOV immediates, precision and integer FP
conversions, scalar FP arithmetic/comparisons, vector ADD/SUB/comparisons,
pairwise reductions, bitwise/unary byte operations, widening shifts, EXT, XTN.
Modified immediates cover all 16,128 valid encodings with three destination
patterns; scalar FP immediates cover 512 encodings; INS covers 370 lane forms.
Use non-inlined const-generic helpers for large corpora: macro-expanded debug
stack frames overflowed in the initial exhaustive immediate test.
Software FP uses pinned pure-Rust rustc_apfloat 0.2.3 with ARM-specific NaN
priority, FZ/DN, rounding and status. APFloat omits OVERFLOW on directed
saturation: native tests caught it; exact S/D→Quad widening and wider-range
evaluation recover ARM's flag. Native tests also caught old host-float casts
and compares losing FPSR flags. Never restore those shortcuts. Arithmetic
samples include normal/subnormal rounding boundaries. Formal obligations cover
named invariants, not the entire FP library or CPU.
Measured boot: 4 KiB direct-root reaches NixOS Stage 2 activation; 16 KiB
PL011/nokaslr diagnostic reaches real systemd-udevd startup. Neither establishes
systemd target, authenticated readiness or Wayland. Latest full suite at this
checkpoint: 166 VM tests, 3 smoke tests, 11 Kani harnesses, 8 Verus obligations.
iOS aarch64 cargo check passes; portable arithmetic and reserved-encoding
regressions pass Miri. Native assembly cases are excluded under Miri/non-AArch64.

## 2026-09-30 completion audit and fetch boundary

Plan: `Relay/docs/static-cpu-completion-plan.md`. Keep Relay slim: one Rust
engine, shared memory/virtqueue mechanisms, thin ABI glue. Proof tools, native
references, fuzz corpora and diagnostics stay outside the product artifact.
One of nine boot gates is not 11% engineering completion.
Instruction fetch used EL1 read translation even at EL0. It now shares the
production walker with explicit fetch/read/write access, leaf/table XN, table
AP, WXN and EL1 rejection of EL0-writable executable mappings. Typed walk faults
preserve syndrome levels; bad configuration is not a fabricated guest abort.
Shared data/instruction abort entry saves EL1 SP0 correctly. Kani permission
harnesses check production helpers; the Verus Boolean model is not a full MMU
refinement proof. AF, descriptor legality and canonical-address coverage remain.
Full-system reference adapter still absent. GIC is simplified; StaticCpu bus
still lacks rng/net/vsock/fs. Current vsock queue is not guest virtio-vsock and
only bounds individual packets. Local proof stamp is not release attestation.
OCI digest checks exist, but bounded extraction, symlink-safe confinement,
immutable validation-to-use, publisher trust and identity handling need work.
Do not count native ARM corpus as run on x86 CI. New ARM64 workflow checks corpus
presence; expanded Miri script covers portable fetch/FP/block/reserved tests.
Native tests caught FRINT{N,P,M,Z,A,X,I} missing; all 14 scalar S/D forms now
match results/status under all guest controls. Only FRINTX adds IXC. Scalar
integer CMEQ/CMGT/CMGE/CMHI/CMHS/CMTST and zero forms reuse vector lane logic.
Measured word 0x5ee09bff is integer CMEQ D31,D31,#0, not FP compare.
Direct-root guest skipped stage 1 prerequisites: /proc/cmdline and /dev/fd
failed in Stage 2. Bootstrap now sources NixOS `earlyMountScript` before init
and creates fd/stdin/stdout/stderr links. Rebuild artifacts and verify boot;
editing the recipe does not change existing result symlinks. Old 16 KiB idle
PCs resolve to timer/nohz/context-tracking functions, not proof of readiness.


### 2026-09-30 shared SIMD families and AF faults

Both rebuilt direct-root 4 KiB and 16 KiB guests finish activation, set up
`/etc`, and start real systemd PID 1. Target readiness still unproved.
SADDW 0x0ebe13ff triggered all 48 signed/unsigned long/wide add/sub forms.
LD1 0x4c40a825 triggered 192 consecutive LD1/ST1 native forms. SHL
0x4f2c5621 triggered all 11 non-saturating immediate-shift families, with
264 native boundary forms. LD1 lane 0x0d40041f triggered 720 lane and 96
replicate forms. Static native asm only; never execute supplied instruction
bytes. Shared 64-byte RAM path preflights split writes; register wrap and
all page splits have portable regressions. Lane loads preserve all other
bits even with Q=0; replicate Q=0 clears the upper half.
HAFDBS remains unadvertised. AF=0 leaf causes access-flag fault before
permissions, with actual walk level, without mutating descriptor or target
memory. Fixtures must explicitly set AF when testing unrelated permissions.
Miri table tests use explicit host page size: macOS getpagesize FFI is not
supported by Miri, not a demonstrated product UB.
Kani shift kernel covers valid width/shift domains, lane bounds and exact
zero/full-width edge identities, not full ARM decoder equivalence. Fragment
proof bounds now 1..=64 bytes. Source stamp includes gate/build configuration;
verify-formal compares pre/post hashes and refuses a changed tree. Runner
stub tests validate gate behavior, never stand in for actual Kani/Verus.

### EL1 hardware reference and boot wait (2026-09-30)

Relay `verification/el1` provides a standalone macOS Hypervisor.framework fixed
micro-guest oracle; never link it into the app. 29 cases on each 4/16 KiB granule
produce 58 recorded observations, compared portably against StaticCpu (also Miri).
Native evidence drove fixes for SVC ESR.IL, EL1 SP0 vector/stack entry, IRQ DAIF,
invalid level-3 block descriptors, ERET SPSel/stack-bank restoration and timer
ISTATUS independent of IMASK. ERET must validate mode before changing state.
Fresh hardware comparison: `scripts/verify-el1-reference.sh`; fixture updates
invalidate proof stamps and require formal gates again. Each case uses a fresh
VM to avoid stale translations after host-side page-table changes. This bounded
oracle does not establish full Linux or ISA equivalence.
Debug 4 KiB systemd boot waits after hostname/timezone setup. Hung-task output
shows PID1 closing inotify in fsnotify_wait_marks_destroyed and its cleanup worker
waiting in synchronize_srcu. Root cause unresolved; do not call this readiness.

### SRCU needs self-SGIs even with one vCPU (2026-09-30)

A one-vCPU Linux guest still uses GICv2 software interrupts for irq_work.
The exact 7.2.3 guest's gic_ipi_send_mask writes GICD_SGIR at distributor+0xf00
with TargetListFilter=2 for self delivery. Discarding distributor writes stranded
SRCU grace-period work. Relay now routes SGIR explicit CPU-0 and self targets;
other-CPU-only/reserved filters do not deliver. Kani covers bit extraction and
routing; Verus covers the routing model, not full GIC state/liveness.
The optional `kernel-probe` feature and `static_kernel_probe` example provide
bounded RAM-only observations without device-read or fault side effects. Default
app builds exclude them. See Relay/docs/static-cpu-differential.md. Before the
SGIR fix, a 3-billion-instruction trace saw a grace-period request but no worker;
afterward srcu_irq_work/process_srcu/srcu_invoke_callbacks first execute at
761463790/761468973/761470469 instructions. This proves that callback path resumed,
not whole guest readiness. Never infer lost IRQs from IAR=1023 counts alone.

### Measured reductions and table lookup (2026-09-30)

After SGIR repair, both page sizes passed the SRCU wait and reached UMAXV
`0x2e30a800`, then in-place TBL `0x4e1c03ff`. Shared integer reductions cover
35 native forms (ADDV, S/UADDLV, S/UMAXV, S/UMINV). The Kani contract checks
exact sums modulo output width and min/max membership/order with an independent
i128 interpretation for arbitrary valid vector inputs, plus arithmetic safety.
TBL/TBX shares one 1..4-register byte lookup (16 native forms); capture source,
indices and old destination before writing, wrap V31 to V0, and clear Q0 upper
bits even for TBX. Kani proves exact byte selection and out-of-range behavior;
native cases cover wrapping/aliasing, and Miri checks portable boundaries.
These are lane-kernel proofs, not full decoder or whole-ISA equivalence.

### Saturation and scalar ADDP (2026-09-30)

Service startup exposed scalar ADDP `0x5ef1bb3f` (16 KiB) and UQSUB
`0x6efd2f9c` (4 KiB). ADDP Dd,Vn.2D uses modulo-u64 addition and clears upper
bits. SQADD/UQADD/SQSUB/UQSUB share one i128 clamping kernel across 44 native
scalar/vector forms. FPSR.QC is sticky and set when any active lane saturates;
other flags stay unchanged. Kani proves exact clamping/indication for all valid
lane inputs. Do not treat scalar Q=0 patterns as reserved saturation encodings:
they overlap scalar FP encodings (including FCSEL). Match the correct classes.

### Interleaved transfers and high-lane FMOV (2026-09-30)

Measured service-stage gaps: 4 KiB `0x4c40843e` LD2 V30.8H/V31.8H;
16 KiB `0x9eaf0060` FMOV V0.D[1],X3. LD/ST2..4 share the existing
64-byte transfer/preflight path: byte mapping interleaves element-sized chunks,
with register wrap and all writeback forms. Added 126 fixed native forms; every
page split and fault-atomic stores cover both granules. Kani proves byte mapping
bounded and invertible (19 total harnesses; 10 Verus checks). High-lane FMOV
preserves low 64 bits, uses XZR semantics, and has native/portable comparisons.
No new runtime dependencies. VM tests: 211; workspace: 261. iOS 11 release
staticlib builds. Whole target/readiness acceptance still requires guest boots
and device wiring; these scoped tests are not whole-CPU proofs.

### Console ownership and service diagnostics (2026-09-30)

Console RX kicks used to be overwritten by TX; receive exhaustion also returned
empty buffers. Keep a notification bit per virtqueue, retain waiting RX, drain
TX independently, and clear a kick only after its ring is empty. Validate all
chain directions/RAM spans before payload effects; fixed 4 KiB scratch removes
guest-length allocations. Used length is device-written bytes (TX=0). Bounded
output keeps its tail without temporarily allocating the full incoming span.
Portable tests cover delayed RX/TX, malformed second descriptors, u32::MAX
lengths and chunk boundaries. Gates: 264 workspace tests, 19 Kani, 10 Verus,
20 Miri suites, Clippy correctness/suspicious and iOS 11 release staticlib pass.
Miri cannot call Darwin getpagesize: portable tests use allocate_on_host with an
explicit host granule; do not weaken production host-page detection.
Both granules stayed live for 480 wall seconds after interleaved/FMOV fixes.
No required-target/readiness claim follows. For service errors, temporary
development manifests add systemd.default_standard_output=journal+console,
systemd.default_standard_error=journal+console and
systemd.journald.forward_to_console=1. This revealed 16 KiB firewall failure:
iptables: Failed to initialize nft: Protocol not supported. Its kernel recipe
explicitly disabled NETFILTER. Retain the firewall and build its dependencies;
IP_NF_MATCH_RPFILTER/IP6_NF_MATCH_RPFILTER also depend on their IP_NF_IPTABLES/
IP6_NF_IPTABLES menus, even with NFT_COMPAT. Kernel build/boot validation pending.

## 2026-09-30 guest reference and identity corrections

OCI image config uses `User` (legacy `user` accepted). Explicit numeric UID:GID
must survive conversion; reject malformed/reserved IDs, names and UID-only
identities until confined account lookup exists. Missing Entrypoint/Cmd is an
error, never an invented readiness shell. Validate process config before
clearing an existing materialization destination.
The same 4 KiB kernel/rootfs starts nsncd under native VZ; StaticCpu emits
SIGSEGV at address -48. This is an unresolved interpreter/guest divergence,
not proof of its cause. A later StaticCpu stop measured UMAX V29.4S,V29.4S,V31.4S;
shared elementwise/pairwise min/max now has native forms and an exact lane lemma.
Native reference exposed guest Wayland unit permission errors: an unprivileged
service cannot mkdir /run/user/1000 or redirect directly to /dev/hvc0. Use an
owned RuntimeDirectory and journal+console. Type=exec plus MAINPID liveness
prevents the observed marker after failed exec. That marker remains only a
transport-start hint, not authenticated readiness or a frame assertion.
Native VZ with the repaired 4 KiB unit starts the session successfully. VZ's
ACPI/PCI topology differs from StaticCpu MMIO; this is a coarse guest-health
reference, not whole-system conformance. A direct-root image can be referenced
with an empty newc initrd and hvc0 console; omit the StaticCpu PL011 earlycon.

## 2026-09-30 leading counts and nested display

Measured vector CLZ 0x6ea04b7b now shares one CLZ/CLS lane implementation.
All 12 legal vector forms match fixed native assembly; alias/zero/sign-boundary
and reserved-width tests pass. Kani proves counted prefix and first differing
bit for arbitrary lanes. Gates now pass 270 workspace tests (218 VM), 21 Kani,
10 Verus, 23 Miri suites, Clippy correctness/suspicious and iOS release build.
These counts are scoped evidence, never a whole-product completion percentage.
The mobile Cage session must use WLR_BACKENDS=wayland and WLR_WL_OUTPUTS=1
when launched through waypipe. Headless draws into a guest-only output and
cannot provide the parent surface for Wawona. Recipe corrected; full host-frame
validation remains open. Keep nested guest configuration distinct from native
bundled compositor backend preferences.

## 2026-09-30 nsncd stack fault and waypipe direction

The signal probe captured nsncd SIGSEGV at user PC 0xb787459bb824, with X29=0.
Pinned nsncd-1.5.2 (wyariv... store path) maps it to ELF offset 0x3b824:
STUR Q0,[X29,#-48], in slog_async AsyncCoreBuilder::build_no_guard. The preceding
callee at 0x350e4 aligns its stack using AND SP,X9,#-128 (0x9279e13f).
StaticCpu's logical-immediate decoder discarded Rd=31 for all operations;
AND/ORR/EOR instead target SP/WSP, while ANDS targets ZR. Failure to allocate
that stack frame overwrote saved caller registers. Route only non-flag-setting
logical immediates through set_x_or_sp. Keep Rn=31 as ZR in every form.
The compact frame regression reproduces this save/align/write/restore sequence.
A later full boot confirms nsncd startup; desktop acceptance remains open.
Native VZ with nested Cage now fails honestly without a host compositor,
instead of running invisibly headless. Pinned waypipe 0.11.0 manpage says the
server connects to the client; guest --vsock -s1024 server dials host CID2.
Relay start_vz currently supplies --vsock-connect/--listen-unix, also dialing
the guest. Correct listener/forward direction and host waypipe-client startup
ordering together. Do not restore headless or accept a startup marker as a frame.

## 2026-09-30 OCI archive regression and settings gap

A temporary-fixture regression reproduced outside-root writes through an
existing layer symlink. Use real-directory ancestor checks for archive paths
and opaque whiteouts, plus tar Entry::unpack_in for confined extraction and
hardlink validation. Apply whiteouts in a first streaming pass before additions:
OCI whiteouts only hide lower-layer resources. Reject empty/dot basenames.
Tests cover escape writes/deletions, hardlinks, dangling symlink replacement,
and late whiteouts preserving same-layer files. No new dependency or expanded
layer buffer. Concurrent filesystem replacement and atomic publication remain
unproven; internal symlink ancestors currently reject conservatively.
The active shared Sources/WawonaUI settings already contain memory/storage
sliders and guest-page selection; WWNVirtualMachineEditorSection is legacy.
Sources/WawonaApple/Runners/RelayRunner.swift sends memory_mb/disk_gib/max_disk_gib. RelaySpec now retains these;
StaticCpu and VZ apply RAM and disk limits. App-owned machine disks publish
without replacement, hold an exclusive advisory lock, grow only, and flush
writes before virtio completion. This is not a crash-consistency or race proof.
Shared UI labels storage, prevents configured-size shrink, and shows automatic
connection instead of a nonfunctional port field. Swift package WawonaUI builds;
actual iOS app/device settings validation remains open. Guest root stays
ext4 on whole-disk /dev/vda. autoResize is set, but scripted stage 1 never
applies x-systemd.growfs to that already-mounted root. wawona-grow-root runs
resize2fs after remount. Do not convert the disk to btrfs or Disko. Disks
stay grow-only while stopped. RAM (256 MiB through 64 GiB) is independent of
the disk file and may go up or down between boots. The legacy iOS 11 UI path
still needs separate coverage.

## 2026-09-30 conditional FP and persistence validation

Full 4 KiB boot after the SP fix starts nsncd successfully. Next measured stop
is FCCMP D0,D31,#0,EQ (0x1e7f0400). FCCMP/FCCMPE share the integer-bit FP
comparison helper; false conditions install immediate NZCV without FP effects.
Native tests across all 16 conditions caught scalar integer ADD/SUB's broad
Q=0 mask overlapping FCCMP HI. Require Q=1 for scalar integer forms.
Storage validation adds production-helper Kani and a separate Verus extent
lemma; neither proves host filesystem durability. Gates pass: 281 workspace
tests (225 VM), 22 Kani, 11 Verus, 26 Miri suites, Clippy and iOS release.
16 KiB kernel/firewall guest build completed; nested-session image refreshed.
Host vsock direction/readiness and full desktop frame remain open.

## Real vsock/native waypipe (2026-10-01)
FMADD812,032/pairwise-long3,360 native comparisons pass. Vsock16flows/64KiB;
modular4KiB needs vmw_vsock_virtio_transport. Both guests send16+28 realbytes.
Rust worker uses upstream handler/owned duplicate/per-call argv; no WAYLAND_SOCKET theft.
Delayed stop retains handle/exclusive disk clone; canonical linked-runtime header.
Phone/watch links real Weston/Niri/Relay/native FD entry, phone13/SDK26.5.
Native editor: physical768MiB/9GiB.2MiB log;309tests/26Kani/15Verus/33Miri checkpoint.
Physical4KiB reaches Multi-User; stops indexed FMUL0x4fda93bd at1185760ms.
Indexed S/D fix:9216native/312tests/26Kani/15Verus pass;35 strict Miri pass.
Mobile guest --no-gpu SHM images built; fresh900s boots stay live, miss required target.
Both hvc0 jobs precede slow coldplug; measure udev before device/clock changes. Host Metal/iland required.
CPU/native join share2s; pending retains registry/disk.319tests/26Kani/15Verus/37Miri pass;21vectorFRINT forms match190848native cases. New app pending.
Simulator/iPad recipes must pass both guest paths; verify images. Build selector: --arg simulator true.
Logs start relaunches: beforeboot. Fill timeout may apply; snapshot before retry.
Sheet swipes inside AXbounds. No auth/frame/distribution claim. Map: Relay/docs/static-cpu-completion-plan.md.
Simulator resume: profile migration loop resolved on real app; saved rename still
stale until reopen. Snapshot native mutable profile values in card UI; build and
runtime proof required. New Start truncates boot trace, so zero console is not
VM status. Oct2 fresh QA reboots saved768MiB/9GiB into real stage2 with journal
recovery. No target/auth/frame/guest-data claim. Host319/Kani26/Verus15 rerun pass.
Oct2 Simulator real host Cage window stays blank, Foot exposes FCVTN0x0e616bff.
Four S/D vector precision forms reuse narrow_double/widen_single; alias/lane/
flags covered by70272native comparisons.322tests/26Kani/15Verus pass; Miri/app
pending. Half formats remain unadvertised. Native storage field must be slider
with GiB value + endpoints4..64 (existing capacity is edit minimum). Shared
slider alone does not prove deployed native editor UI. Native last-tab Close
left blank host after CPU exit; return-to-Machines still needs runtime proof.
Vector precision current gates:322tests/26Kani/15Verus/38strictMiri, Clippy and
explicitiOS13release library pass. Last-tab Close callback was not verified;
after attempted tap, tab disappeared while guest already exited, host stayed
blank. Preserve that distinction when diagnosing return-to-Machines.

## User NixOS configuration

Mobile `guest.nix` evaluates separate user `configuration.nix` and Wawona
`relay.nix`. Relay enables flakes/nix-command and exports nixosModules.relay.
User `wawona.relay.sessionCommand` is an argv list passed through escapeShellArgs.
Rust owns editor templates/highlights. Save is not guest rebuild: transfer,
flake.lock, authenticated apply/rollback and generation-aware restart remain
required. UniFFI profile maps use HashMap; BTreeMap fails app compilation.


Unsigned iOS Swift runtime packaging: device library may already be thin;
lipo -thin rejects it. swift-stdlib-tool compressed output can become empty
in final Nix store artifact. Rewrite thin decoded bytes through cat into a
fresh file, thin fat inputs with lipo, then move into place. Final artifact
gates must still reject empty/wrong-platform/high-minimum libraries.
Verified full iOS13 physical and arm64 Simulator bundle floors/graphics.
Signed-device and distribution proof remain separate.


Disk-owned generation boot (2026-10-02): new mobile images seed system-1-link,
system profile, and /init; manifests use init=/init. Actual 4K/16K image links
and stage2 boots verified. Existing disks need migration; bundled kernel/initrd
compatibility and guest rebuild/apply/rollback remain open. Fresh326 tests,
26 Kani/15 Verus pass. Both600s probes live but no required Multi-User target:
udev pending, OCI bundle mount/dependency fails, no auth/frame. See
Relay/docs/static-cpu-completion-plan.md and stable-generation-* receipts.
Phone editor AX snapshot can crash Apple's XCTAutomationSession; use screenshot
and observed point actions, verify resulting screen. Successful swipe reports
alone do not prove scrolling. Latest attempt cancelled, no disk growth claimed.


Nix editor templates must live inside relay-core: real crate2nix compilation
omits external include_str assets. Canonical files now in relay-core/templates,
flake export follows them, legacy templates/nixos-guest is a directory symlink.
Full coldplug priority is block,tty,net,input,module,tpmrm via asDropin; preserve
--type=all, inherited units/rules/timeouts. Actual image drop-ins verified;
1200s runtime acceptance pending. See static-cpu-completion-plan.md.


Service traces exec59164/11042 finished 1200s exit0. systemd "Startup finished"
means the job queue is empty, not "Reached target Multi-User System". That
line was absent on both page sizes. shadow login LOGIN_TIMEOUT 60s exits during
pam_systemd while user@1000 is still inside its own deadline, then
session-N.scope fails result resources (no PIDs). dhcpcd waitip has no
virtio-net. relay.nix sets LOGIN_TIMEOUT 0 and disables dhcpcd. Deadlines of
remaining services stay.

Rebuilt images qrkhvnr0 (4 KiB) and x6p6wnhk (16 KiB): login timeout, scope
resources, and dhcpcd timeout are gone. systemd.log_target=console plus fbcon
taking /dev/console hides the last status line. Without that flag, journal
forward shows both page sizes reach Multi-User: 4 KiB at guest 487.507676,
16 KiB at 406.996742, after "Started Wawona mobile Wayland session".
OCI no-share failure and 16 KiB bpf-restrict-fs ESRCH remain. 16-byte vsock
payload is not authentication or a frame.
