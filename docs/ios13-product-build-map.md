# iOS 13 product build repair map

SDK: 26.5. Deployment minimum remains 13.0. Package tests omit the active
`!SWIFT_PACKAGE` product views; acceptance requires the complete device app.

| Family | Repair | State |
| --- | --- | --- |
| Source staging | Exclude local build/cache trees, keep fixup checks | Repaired; project generation passes |
| Navigation | Backport sidebar toggle and editor routes without replacing product models | Product compile passed |
| Owned observable state | Retain and observe drafts/view models on iOS 13 | Product compile passed |
| Focus | Isolate newer focus API | Product compile passed |
| Grids/toolbars | Preserve cards and actions with older presentation APIs | Product compile passed |
| Styling/modifiers | Share availability helpers | Product compile passed |
| App link | Complete iOS device app through XcodeBuildMCP | Passed with SDK 26.5 / min 13.0; unsigned |
| Dependency pins | Published graphics/toolchain updates plus explicit local Relay/static-renderer inputs | Current-source complete phone/watch app build passed; unsigned |
| Simulator static renderer closure | Flatten target dependencies, namespace Vulkan ABI, require real provider entrypoint | Source package and real entrypoint link passed, iOS 13.0 / SDK 26.5; full simulator app pending |
| Embedded dependency floors | Inspect actual Mach-O records, not just Info.plist | Current ANGLE and MoltenVK records verified 13.0 / SDK 26.5; complete bundle floor gate passed |
| Client relink floors | Use iOS deployment setting and actual SDK version | Real zsh relink proof passed 13.0 / SDK 26.5; old app clients stamped 17.0 |
| Native client source identity | Pass generated project archives directly to prebuild | Implemented for Apple mobile device/simulator profiles; complete build passed |
| Neovim Lua closure | Recognize legacy iOS records, enforce exact platform and real Lua definitions | Rebuilt real Lua closure; complete app link passed |
| ANGLE Vulkan isolation | Namespace internal Volk pointer globals beside MoltenVK functions | Real archive proof: 0 public Vulkan globals, 623 private definitions; source package rebuild pending |

## Initial measured errors

```text
Sources/WawonaUI/WawonaMainWindowView.swift:138:43: error: 'NavigationSplitViewVisibility' is only available in iOS 16.0 or newer
src/platform/macos/ui/Machines/WWNContainerHubSearchView.swift:13:18: error: 'dismiss' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachineEditorView.swift:20:18: error: 'dismiss' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachineEditorView.swift:22:4: error: 'StateObject' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachineEditorView.swift:24:35: error: 'NavigationPath' is only available in iOS 16.0 or newer
src/platform/macos/ui/Machines/WWNMachineEditorView.swift:475:18: error: 'dismiss' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachineTags.swift:189:18: error: 'dismiss' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachineTags.swift:23:38: error: 'mint' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachineTags.swift:23:45: error: 'teal' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachineTags.swift:24:13: error: 'indigo' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachineTags.swift:24:38: error: 'brown' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:17:4: error: 'StateObject' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:25:4: error: 'FocusState' is only available in iOS 15.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:260:4: error: 'ToolbarContentBuilder' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:261:45: error: 'ToolbarContent' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:281:4: error: 'ToolbarContentBuilder' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:282:51: error: 'ToolbarContent' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:445:4: error: 'ToolbarContentBuilder' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:446:42: error: 'ToolbarContent' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:625:39: error: 'GridItem' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNMachinesGridView.swift:677:52: error: 'GridItem' is only available in iOS 14.0 or newer
src/platform/macos/ui/Machines/WWNWasmCatalogSearchView.swift:8:18: error: 'dismiss' is only available in iOS 15.0 or newer
```

## Verified progress

- Latest host package test run: 40 passed after product compatibility repairs.
- Complete device build passed, including the embedded watch application.
- Main executable, WawonaModel, and WawonaUIContracts: iOS 13.0 / SDK 26.5.
- Old ANGLE framework plists said 13.0, but their binaries require 16.0.
  This artifact is not accepted as an iOS 13 product.
- Updated published wwn-iland and wwn-toolchain pins. The current-source build
  explicitly evaluates local Relay and local static SwiftShader recipe changes;
  unpublished changes are not represented as a published pin.
- Current-source ANGLE static archives passed object-level inspection: all 501
  objects use iOS 13.0 and SDK 26.5. Final app inspection remains pending.
- The device-only generated project retains native phone/iPad/watch bundles
  while avoiding unrelated simulator/platform rebuilds. Simulator projects
  retain their own complete dependency profiles.
- SwiftShader compiled all 1222 steps, then failed at archive installation
  because implicit `xcrun` selected unavailable macOS SDK tools. The recipe
  now sets the discovered Xcode developer directory and requests its target
  SDK explicitly for both archive merge and symbol inspection. Rebuild pending.
- Physical-device operation and signed distribution remain unverified.

## Current-source link findings (2026-10-01)

The first current-source product link failed with 84 unresolved Lua symbols.
Neovim's dependency collector recognized only LC_BUILD_VERSION and discarded
PUC Lua objects carrying LC_VERSION_MIN_IPHONEOS. A real SDK 26.5 object
compiled for iOS 11 reproduced that legacy record. The collector now accepts
that record only for the matching device platform, consumes complete otool
output, and requires lua_newstate and luaL_newstate definitions. The local
consumer recipe explicitly includes the repaired Neovim source.

The same link reported client archives relinked for iOS 17.0 / SDK 17.0, and
ANGLE Vulkan pointer storage replaced by MoltenVK function definitions. Real
archive proofs verify the corrected relink and all 623 Volk pointer renames.
The generated prebuild now receives actual selected native archive paths,
rather than re-evaluating published inputs from its staged source tree.

SwiftShader source packaging completed. A real entrypoint probe links at
iOS 13.0 / SDK 26.5 using normal static archive resolution. Whole-archive
forcing unnecessarily pulls unreferenced LLVM disassembler members, so the
simulator link now requires the namespaced provider entrypoint explicitly
and resolves its reachable closure. Physical-device products still exclude
SwiftShader. This probe establishes link closure, not rendered guest frames.

## Current-source accepted build (2026-10-01)

Complete unsigned iOS app and embedded watch build passed. Artifact:
`/nix/store/4iygqyhcdngr9rwsyi5v1f017lgmya86-Wawona/Wawona.app`.
Mode A firewall, embedded iOS 13 dependency floors and graphics policy passed.
Build log has zero newer-iOS link warnings and zero ANGLE Vulkan data/function
collisions. Durable logs: `.artifacts/relay-build/`.

Guest staging follows the existing manifest contract: direct-root guests with
`initrd: null` require Image, rootfs.img and manifest.json; a declared initrd
must exist. Fixtures reject missing declared initrd and unsupported paths.
No synthetic initrd or runtime trust-policy changes were introduced.

Shared environment help mentions SwiftShader even in software-only watch
frameworks. The graphics gate now checks driver-owned runtime identifiers,
which survive stripping, instead of arbitrary help prose. The complete device
app passes, while a real linked SwiftShader provider probe is rejected.
Physical operation, signed distribution and full VM acceptance remain open.

Exact current app copy signed with matching installed development identities
and phone/watch profiles; strict deep signature verification passed. STARDUST
installation is blocked by kAMDMobileImageMounterDeviceLocked, before app
installation. No installed data was removed. Fresh selected Relay host suites:
273 passed; 22 Kani harnesses and 11 Verus checks passed. The separate storage
restart/growth tests also passed. These are host checks, not device lifecycle.

The remaining WASI suites pass (6 tests), plus all 3 static-smoke regressions.
Fresh host total across core/VM/OCI/FFI/WASI/bench and smoke example: 282 passed.
Real native Weston, Niri, Relay VM and Relay WASI entrypoints are present in
the signed main executable; main and shared framework records remain 13.0 /
SDK 26.5. Boot logs for fresh 4/16 KiB runs are being recorded durably.

## Fresh VM diagnostics after the accepted app build

Both granules expose a /dev/hvc0 systemd device timeout. The 4 KiB guest
remains live for 600 host seconds without reaching required readiness.
The 16 KiB run fails honestly after 9,859,432,448 steps at scalar double
FMADD D0,D0,D14,D0 (0x1f4e0000). An instruction regression reproduces the
unsupported failure before the repair. The earlier signed app predates this
new CPU repair and must be rebuilt before claiming current-device acceptance.

A bounded development-only 4 KiB kernel probe records actual wait sites and
SRCU callback execution. It is excluded from product defaults and is not a
full-system hardware equivalence trace. Boot logs/configs/symbols are saved
in .artifacts/relay-build; no required readiness/frame assertions were relaxed.

## Fused-instruction repair acceptance

Complete rebuilt app: /nix/store/awkhiinj43ih6brc4rarn7hbji0fy287-Wawona/Wawona.app.
The fused-fix app links successfully; its signed phone/watch copy passes strict
verification. New 16 KiB boot passes the old instruction failure, starts the
wawona user session and reports Multi-User System. Required graphics service
still fails: waypipe vsock connect returns ENODEV and Cage receives no host
wl_compositor. A legacy console READY hint appears even after those failures;
it is explicitly not authenticated readiness or a frame. Native VZ still
uses that legacy hint, an additional failure-closed transport requirement.

Current checks: 287 workspace/all-targets tests, 22 Kani harnesses, 11 Verus
checks, two targeted strict-provenance Miri suites (3 FP tests + 1 CPU test),
formatting and Clippy correctness/suspicious checks passed. Formal scope is
unchanged; fused FP is covered by native comparisons and dynamic tests.

The signed fused-fix artifact also passes Mode A, graphics and iOS 13 binary
floor gates. New 16 KiB run remains live for 900 host seconds with no further
unsupported-instruction stop, but missing vsock/guest graphics still prevent
acceptance. The continuous implementation goal remains active.

## Virtio-vsock work in progress

New wire codec validates the fixed 44-byte little-endian header and bounded
payload lengths before allocation. Unknown packet types remain visible for
the transport's required reset response. Modular stream credit uses checked
subtraction rather than underflow. Fixed Linux-UAPI fixture and wrap/boundary
tests pass, as does strict-provenance Miri. New scoped totals: 23 Kani harnesses
and 12 Verus checks pass. These prove the window arithmetic only; codec and
credit helpers are groundwork for real MMIO/host-stream integration, not a
working guest transport, authentication or frame. The original unused
loopback queue is still present until the real implementation replaces it.
Devices rechecked: STARDUST disconnected; other phone/watch unavailable.

## Virtio-vsock device wiring (2026-10-01)

Both fused-fix 900s traces reach Multi-User and the user manager. Required
Wayland units still fail; hvc0 and optional OCI mount failures remain. Legacy
console READY text is not authenticated readiness. The guest post-start script
now stops on a failed kill check and emits only TRANSPORT_STARTED. Native VZ
console readiness remains an open security/acceptance gap.

StaticCpu now exposes real virtio-vsock device 19 at 0x0a002000, guest CID 3,
three queues and SPI 36/GIC 68. RX/TX use shared split-ring validation, whole
chain preflight and bounded packet allocation. RX kicks survive empty output;
TX progresses within a total budget while RX is absent. The device polls real
nonblocking Unix stream pairs; host CID 2 accepts guest-initiated connections
on port 1024. Product API take_vsock_connection hands off actual host streams.
Status reset drops flows and queued bytes. Flow limit 16, listener limit 8,
per-flow pending window 64 KiB, outgoing limit 256 packets/1 MiB.

Forward-count advancement is validated independently of peer buf_alloc before
modular credit arithmetic. The previous unchecked interpretation of the wire
helper could accept a forged advance with a u32::MAX peer allocation. Kani
checks the actual update helper; the Verus model covers arithmetic only.
Sources reserve peer credit before queuing host bytes; half-close drains guest
payload before closing the host write half. Guest RAM faults cause no partial
RX payload effects. CPU boundary polling prevents host data from depending on
guest MMIO writes.

Direct iOS waypipe --socket-fds still enters unreachable match arms in the
bundled source. Use its real Unix listener path for the host bridge rather
than inventing FD support. No host waypipe client, authenticated readiness or
imported guest frame has been accepted yet. The --vsock-probe smoke option
only records real guest connection/payload evidence. Its output is explicitly
not an authentication or frame result. Stateful fuzz target vsock_packets is
development-only. Fresh checks and boot evidence are under .artifacts/relay-build.

### Fresh scoped evidence
297 workspace/all-targets tests pass (238 VM), 24 Kani harnesses and 13 Verus
checks pass. Seven vsock-related strict-provenance Miri tests pass. The
ASan/libFuzzer stateful packet-sequence target completes 452,538 runs in 46s
with no findings (six initial seeds; capped input length 131,072). This is
a short fuzz campaign, not exhaustive state or concurrency validation.
Clippy correctness/suspicious and workspace formatting pass. The 31 configured
Miri suites have not all been rerun for this checkpoint; only the seven related
tests above were freshly executed.

Fresh 900s 4 KiB and 16 KiB vsock-probe boots are running against prior guest
images. A full current iOS product build refreshes the guest scripts and app.
Neither a guest transport payload, an unauthenticated marker, nor these tests
is a graphics or release acceptance result. Logs live under
Wawona/.artifacts/relay-build/{host-tests-vsock-final,miri-vsock-device,
fuzz-vsock-device,current-build-vsock,guest-4k-vsock,guest-16k-vsock}.log.

### Current app build/signing result
Full current phone/watch build passes: /nix/store/c1baycz9zwmfqr1x1fpwm0yr56ncjm68-Wawona.
Main phone and embedded Model/UIContracts are platform iOS, min13.0/SDK26.5.
Watch fat binaries carry watchOS10.0 arm64_32 and watchOS26.0 arm64 slices.
No newer-iOS link warning is present. Mode A absence and graphics policy gates
pass before and after signing. The isolated signed-device-vsock/Wawona.app
passes strict deep codesign verification. Physical installation was attempted
and rejected before install by DDI mount: kAMDMobileImageMounterDeviceLocked.
STARDUST is paired/available but requires its passcode. No physical runtime
or distribution acceptance is inferred.

Build still warns about duplicate cube-HUD symbols, wpm_main, demo main and
rust_eh_personality across native archives. ANGLE Volk collisions are absent;
these remaining unrelated ownership/toolchain warnings stay mapped for repair.
Diagnostics: deployment-vsock.json, app-build-vsock.log, sign-device-vsock.log,
signed-vsock-{mode-a,graphics}-gate.log, device-install-vsock.{json,log}.

## First real guest vsock bytes and pairwise-long repair (2026-10-01)

The 16 KiB 900s vsock probe establishes a genuine guest CID3 connection to
host CID2 port1024 and reads the first 16 guest waypipe bytes. This is transport
evidence only: the diagnostic does not reply as waypipe, authenticate readiness
or import a frame. The same run stops after 9,985,236,992 instructions at
0x6e202800, disassembled by the Apple toolchain as UADDLP V0.8H,V0.16B.
The 4 KiB run stays live for900s and reaches Multi-User, but guest waypipe
reports ECONNRESET without a host accepted-stream observation. Do not assume
the 16 KiB transport result applies to 4 KiB.

SADDLP/UADDLP/SADALP/UADALP now share pairwise_long_lane. Source widths8/16/32
widen exactly; optional accumulation wraps in twice that width. Snapshot Rn
and prior Rd for aliases; Q0 clears upper64; size3 fails without register/PC
mutation; flags are unchanged. Native comparison executes 48 fixed register
forms (24 arrangements times aliased/separate operands), 70 samples each:3,360
comparisons. The measured alias has a portable regression. Kani checks actual
helper against independent i128 arithmetic; Verus models signed bounds and
modular accumulation. Neither proves the whole decoder/CPU.

Fresh checkpoint: 299 workspace/all-targets tests (240 VM), 25 Kani harnesses,
14 Verus checks pass. Pairwise regression passes strict-provenance Miri. Latest
iOS13/SDK26.5 relay-ffi release library compiles. Previously signed full vsock
app predates this CPU repair; a fresh full-app link is still required.
Bounded first128 header tracing is kernel-probe-only, excluded from default
product. Fresh 4 KiB/16 KiB probes running under this source will diagnose the
reset and verify progress after UADDLP; target/frame acceptance stays open.

## Pairwise CPU and explicit guest module build (2026-10-01)

Current full app: /nix/store/1cwvnpnncz67bnq5ihz3vs1arsg65mv9-Wawona.
Phone main/Model/UIContracts min13.0 SDK26.5. Watch arm64_32 min10.0,
arm64 min26.0, SDK26.5. Native Weston/Niri/Relay symbols remain linked.
Isolated signed-device-pairwise/Wawona.app passes deep strict development signing
and store graphics policy gates. Physical install still awaits unlocked STARDUST.
Includes pairwise-long CPU repair and explicit 4KiB virtio-vsock module load;
new guest traffic, auth/readiness/frame and distribution acceptance remain open.
Evidence: deployment-pairwise.json, app-build-pairwise.log,
sign-device-pairwise.log, signed-pairwise-graphics-gate.log.

## Native waypipe FD ownership and physical editor (2026-10-01)
StaticCpu now transfers its real vsock receiver to a Rust native waypipe worker.
The upstream client entry borrows the FD, duplicates it, connects to the real
host Wayland display and calls upstream handle_client_conn. Explicit per-call
arguments replace process-global argv: concurrent native launches otherwise
race. Do not consume another client's process-global WAYLAND_SOCKET.
Stop joins CPU/device first, then waits up to2s for the native entry. A delayed
entry retains its handle and cloned exclusive disk file until a retry succeeds;
never detach it, release its writable disk or claim shutdown prematurely.
Quoted local wawona_relay.h shadowed the linked runtime header. Stage the
canonical ABI header from that runtime package before generating the project.
Full phone/watch app links both relay_start_host_waypipe and wwn_waypipe_client_fd,
alongside real Weston/Niri. Phone main/framework floors13.0, SDK26.5.
308 host tests (249 VM),26 Kani,15 Verus and full33 strict Miri suites pass.
Native FD/reconnect/EOF/delayed-stop tests are host tests, outside Miri/formal scope.
Exact signed app installed and launches on unlocked STARDUST. Agent-device runner
needs G6EJA4DJKW signing team, not its default unavailable2S799L9W4M. Use supported
AGENT_DEVICE_IOS_TEAM_ID/AGENT_DEVICE_IOS_BUNDLE_ID in a dedicated daemon state.
Physical native VM editor lacked RAM/storage despite shared UI controls. Native
schema bindings are added, fresh full build/save-reopen verification pending.
No authenticated readiness/imported guest frame or distribution acceptance yet.

## Physical native VM settings and boot evidence (2026-10-01)
The actual physical app used WWNVirtualMachineEditorSection, which exposed only
Backend. Shared MachineEditorView RAM/disk controls were not that active UI.
Add native dictionary bindings preserving unknown vmSettings; use existing
WWNEditorNumberField across targets. SwiftUI Stepper is unavailable on tvOS.
Read stored properties only after all Swift draft fields initialize; use a local
initialVMSettings snapshot to seed immutable disk-growth lower bound.
Full phone/watch app /nix/store/bw7nva8fnfv90k07vk1g48knw42g2fna-Wawona links,
signs, installs and launches. Physical QA create/save/reopen retains768MiB/9GiB;
read-back identifies FE02CE81-DB08-4508-97C4-6C06381989C1 and real9GiB rootfs.img.
No guest boot/frame accepted: active process displays a black surface. Do not
interpret it as a crash or readiness. Effective Multi-Touch still unverified.
agent-device logs start on physical iOS relaunches the app: start capture before
starting a guest. Fill may timeout after applying text; snapshot before retrying.
Expand half-screen sheets using the observed grabber rect, then swipe within the
observed scroll bounds. Full-screen scroll-up can begin outside the sheet.
New Rust per-machine console.log records console and periodic elapsed/PC/count
samples, stops at2MiB, drains on CPU stop/error, and never asserts readiness.
Host disk-cap/console-reset test passes.309 tests (250 VM),26 Kani/15 Verus pass.
Fresh full33 strict Miri suites pass. Diagnostics app /nix/store/vvrnj8vr5p7f084kjcsbiy5pwnnszv9s-Wawona builds, signs, installs and passes signed graphics/ModeA floors.
Physical4KiB trace confirms Linux entry,196608pages/768MiB and real PC/instruction
progress (204472320 instructions/20192ms). Subsequent physical trace shows writable ext4 root,
/wawona-init PID1 and NixOS Stage2. Required systemd target/frame remain open. QA restart started21:57:27UTC. Read
physical-4k-boot-trace-first.log; never infer graphics from a live black surface.

## Verified shutdown and current Simulator artifact (2026-10-01)
Fresh316 workspace/all-targets tests (257VM),26 Kani/15 Verus, full36 strict
Miri suites and Clippy correctness/suspicious pass, with existing Clippy warnings.
Formal digest7d6e5eb197c0591e29fcd5d0ecdef702a27fe78219043712070a39873de477e7.
The added real registry test proves a pending CPU retains the handle and disk
lock, forbids concurrent disk growth, then allows retry/reopen/growth with the
same persisted test bytes. This is host lifecycle evidence, not app/guest data
acceptance. Pure thread retention/panic tests run under strict Miri; native
UnixStream/foreign-entry checks remain host concurrency tests. iOS13 relay-ffi
release compilation passes. Full new bounded-Stop app linking remains pending.
Evidence:host-tests-bounded-shutdown-final.log, miri-bounded-shutdown.log,
clippy-bounded-shutdown-final.log, ios13-bounded-shutdown-library.log.

Full Simulator phone/watch app build exec77494 finished exit0. Exact output
/nix/store/naglmk381ys88llg9ccvsc2wzvm7qzvl-Wawona/Wawona.app includes both fresh
Image/rootfs/manifest sets and real Weston/Niri/Relay/native host-waypipe symbols.
It predates bounded Stop. Current Simulator phone main/Model/UIContracts floor
14.0, watch companion/frameworks10.0, all SDK26.5. A minimal SDK26.5 clang link
requesting arm64-apple-ios13.0-simulator also stamps14.0. Scoped
--mode-a-simulator checks platform7/native arm64/floor14.0; device --mode-a keeps
platform2/floor13.0. The wrong-platform Simulator is rejected by the device gate.
Simulator SwiftShader is the real namespaced static source provider. Graphics
gate requires its three public entry points plus driver-owned identifiers when
no dylib exists. Device exclusion is unchanged. Both real artifacts pass their
scoped gates; the real device bundle is rejected as a Simulator without its ICD.
Deployment records:simulator-guests-deployment.json; compile probe:
simulator-floor-probe.log. Simulator bundle matrices still need runtime evidence.

Nix-store install returned EACCES. A complete writable ditto copy at
.artifacts/relay-build/simulator-fmul-shm/Wawona.app installs via agent-device and
launches; no uninstall or profile clear. Default profile remains; new QA is
55BBF8D8-AF7A-4C9D-8801-A36237C03895, Relay Simulator QA 4K. Native create/save/
reopen retains768MiB/9GiB. Persisted globals confirm TouchInputType Multi-Touch
and TouchPointerEmulation false. Actual boot trace confirms805306368 memory
bytes and9663676416 backing-disk bytes. Current real Simulator boot is live;
no imported frame/authentication/Stop/grow/restart/guest-data claim yet. Card
subtitle incorrectly hardcodes Relay VZ; launch actually uses StaticCpu.
Simulator data root:
/Users/8amps/Library/Developer/CoreSimulator/Devices/AA38C3A4-C022-41DB-8960-4050F3DE014B/data/Containers/Data/Application/10FA414C-5675-4A98-AC34-38717587B90A
Boot console under Library/Application Support/Wawona/relay-state/machines/<id>/console.log.

Both1200s diagnostic probes finished exit0 with no unsupported instruction/panic.
16KiB reaches Multi-User System and sends real16-byte vsock payload; the diagnostic
never replies as waypipe or authenticates a frame.4KiB has not reached required
target. hvc0 is actually queued by udev only at365.445s/273.589s respectively,
after device/getty timeout.16KiB udev READY=1 is203.367s;4KiB238.353s. These are
measured delayed discovery, not proof of a broken console model. Capture queue/
worker completion and direct-root stage1 omission before changing device/time.


## Measured vector rounding and stage1 discovery (2026-10-01)

Simulator QA4K saved/reopened768MiB/9GiB and actually booted with those values.
Its direct-root guest stopped at937227ms/11341254656instructions on
0x2e218bff(FRINTA V31.2S,V31.2S), not a timeout or app crash.
Evidence: simulator-4k-fatal-vector-round-trace.log. A portable aliased/inactive
sNaN regression reproduced failure before repair. Vector FRINT N/P/M/Z/A/X/I
now reuses the existing unsigned lane and software integral-rounding kernels
for21 S/D forms, snapshots sources, clears Q0 upper bits, accumulates FPSR and
rejects reserved Q0/D.190848 native comparisons and319workspace/260VM tests
pass;26Kani/15Verus and all37strict Miri suites pass. Clippy correctness/
suspicious and explicit iOS13 relay-ffi release compilation pass. Formal digest
6e3c2470a9d4d631d7a4cdd4da10c970bcbe2301b239a83ed6b26a2cd3e2a6cf.
Existing lane proof/model covers selection/bounds, not decoder/FP refinement.

Complete bounded-Stop/label Simulator app built: x90idc4lk2w1fvaz4vraa68md00gwgcy-
Wawona, scoped ModeA/graphics gates pass. It predates vector-rounding repair.
New full vector-rounding app builds via exec94787; no final-artifact claim yet.
Real unchanged initrd probes exec71036/92681 run1200s; their executable/source
version is pinned by real-stage1-launch-provenance.json.16KiB processes hvc0
in stage1 then reaches Multi-User but still times out its device/getty job.
Stage1 alone is insufficient. Pinned NixOS stage-1.nix omits99-systemd.rules;
upstream's serial-console rule tags hvc0 for systemd. New guest recipes bundle
the real initrd/hash, hand off to the actual NixOS stage2 path, reject cpio
case-hack paths and copy exactly the upstream console rule in scripted stage1.
NixOS MCP queried; internal extraUdevRulesCommands is absent from public index
but present in pinned module. Use config.systemd.package for rules, not
pkgs.udev(which is only minimal libs); initial build exposed that output error,
corrected. Both new images building(exec78291); service/guest-frame acceptance
remains pending. No deadline/unit reduction. Auth/OCI/devices/distribution open.


## Current verified artifacts and live jobs (2026-10-01)

Vector-rounding Simulator app built(exit0):
/nix/store/9ksfzz1c130ljnn5ip4ix0484dh80iqi-Wawona/Wawona.app.
ModeA platform7/floor14 and real static graphics gates pass. Not installed yet.
Both new stage1/console-tag guest bundles built(exit0), every kernel/initrd/
rootfs byte count and SHA256 verified, cpio case-hack paths absent, exact upstream
non-remove serial-console tagging rule present. guest-stage1-console-evidence.json.
4KiB:/nix/store/i98b3zprqnlzmbvgqhara9yariv32ypb-wawona-mobile-guest-artifacts,
16KiB:/nix/store/k06nc5y75cvh2jlbnd27lc6i5li55i3m-wawona-mobile-guest-artifacts.
Earlier real-initrd-only probes finished1200s(exit0);16KiB reaches Multi-User
but hvc0/getty fails;4KiB startsPID1 but does not reach requiredtarget.
Fresh exact recipe probes exec13675(4KiB)/9706(16KiB),1200s, now use current
vector-rounding CPU and no udev-debug override; observe actual guest streams
only. Logs guest-4k-stage1-console.log/guest-16k-stage1-console.log.
Full Simulator build including these new guest images remains live exec1286;
logcurrent-build-simulator-stage1-console.log,outlinkcurrent-app-simulator-stage1-console.
Installed Simulator app remains old FMUL/SHM/exit version; actualCPU halted at
measuredFRINTA. Preserve existing QA profile/disk. New initrd command uses new
NixOS toplevel path; an existing disk may retain old closures. For next runtime
acceptance use a fresh QA machine; do not reseed/delete the old disk. Explicit
guest-version pin/migration and preservation across app upgrades remain open.
Storage.open currently keeps an existing disk without base-image-version binding;
this source inspection is not a measured failed migration.
All319tests/26Kani/15Verus/37Miri,Clippy correctness/suspicious and iOS13release
library checks have terminalsuccess. No authentic readiness/frame acceptance.

### Simulator profile and Swift runtime integrity (2026-10-01)

The stage1/tagged-guest Simulator app installed successfully. A fresh QA
profile saved and reopened with 768 MiB RAM and 9 GiB storage. All three
profiles survived relaunch. The previous 9 GiB disk kept its exact SHA256
across installation (simulator-stage1-install-preservation.json). This proves
host disk preservation, not guest application data or restart acceptance.

Save left the Machines list stale until relaunch. Native profile persistence
now broadcasts the existing profiles-changed notification to all models.
Start taps on the fresh VM produced no new disk or visible transition. Native
launch failures now have a visible error alert and a diagnostic log; the full
Simulator rebuild is pending. Do not claim a VM is running from a successful
automation tap.

Xcode's built-in CopySwiftLibs produced a zero-byte libswift_Concurrency.dylib
in both measured Simulator and older physical-device artifacts. The previous
deployment-floor loop silently skipped it. The artifact gate now rejects
empty or non-Mach-O embedded dylibs. The original Simulator app fails this
stronger gate; a separate unsigned copy with the real Apple arm64 runtime
passes. The standalone Apple swift-stdlib-tool restores the real library even
when its destination starts empty. The unsigned iOS Simulator recipe applies
that copy and retains the actual arm64 slice. Signed/archive products are not
modified by this workaround; exact signing/export repair remains open. The
underlying built-in copier failure is not yet explained.

Both exact 1200-second guest probes finished without unsupported-instruction
failure. Both start the hvc0 serial getty with the upstream console tag. Both show
60-second login retries; the 16 KiB trace eventually reaches a genuine wawona
shell prompt, while the 4 KiB trace has no shell prompt. Neither trace proves
the required Multi-User target, authenticated readiness, or an imported guest
frame. An OCI bundle
mount failure is also visible. Preserve these failures as acceptance debt.

### Profile reload loop and final runtime packaging (2026-10-01)

The launch-error/notification app compiled and linked. Its raw Nix bundle still
failed the stronger gate because its Swift concurrency library was empty.
A separate unsigned install copy with the genuine Apple arm64 runtime passed
both Mode A and graphics checks and was installed. Simulator data moved to
073FFAFE-A187-4EDE-8881-CBC94761E369; all three profiles and Multi-Touch settings
were present. No fresh QA boot files were created. Automation later hung while
waiting for this app to idle, then failed to launch its runner. The runner was
reinstalled through agent-device and the app closed; no VM boot was interrupted.

Source and actual stored profiles reveal a reload cycle: serialize always
recreated bundledAppID="" and useBundledApp=false for VM profiles; loadProfiles
removed those keys and saved; the new change notification scheduled another
reload. The native persistence adapter now writes those fields only for native
and Wasm profiles, and compares parsed saved values before publishing an
unchanged save. Runtime proof of Save/reopen/Start awaits the full rebuild;
do not claim the UI loop is resolved from source inspection alone.

Conditional Swift repairs in buildPhase and postFixup did not produce valid
final libraries. An unconditional final Apple-copy plus arm64 extraction and
integrity assertion did. The completed Nix app at
/nix/store/qqwg07m7fidhl6zvkjj97k97kma58gcf-Wawona/Wawona.app has the real
557440-byte arm64 library and passes the stronger Mode A dependency gate.
The reason earlier conditional checks skipped the repair remains unexplained.
Signed/archive products are outside this unsigned Simulator workaround.
