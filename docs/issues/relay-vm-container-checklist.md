# Relay VM and Container Completion Checklist

## Current score

- Complete: 14/64
- Partial: 5/64
- Not started: 45/64

Completed means verified by source and a passing local test or artifact build.
Partial means a boundary or proof exists, but not the end-to-end product result.

## Product and policy

- [x] Relay is the sole runtime boundary for Wawona WASM, VMs, and containers.
- [x] New Relay product logic is Rust; native UI layers stay ABI and presentation glue.
- [x] Mode A mobile VM and container policy selects static CPU only.
- [x] Mode B does not claim JIT until a real JIT executor exists.
- [x] VM/container exclusion for watchOS and tvOS is policy-tested.
- [x] Publish the supported-target matrix, including visionOS VM/container exclusion
      (`docs/relay-ios-hypervisor.md`, site platforms / vms-containers).
- [x] Mode B iOS Hypervisor.framework probe + `RelayBackend::IosHv` resolve
      (unit-tested). vCPU / NixOS-on-HV still planned.
- [ ] macOS HV lab: `hv_vm_create` + destroy with `com.apple.security.hypervisor`.
- [ ] Define versioned Machine profile schema for VM and container-in-VM.
- [ ] Define guest artifact trust, integrity, and update policy.

## Guest images and memory

- [x] Validate 4 KiB and 16 KiB guest page-size choices.
- [x] Select the host page size automatically when a profile does not override it.
- [ ] Produce NixOS 4 KiB kernel/initrd/rootfs artifacts.
- [ ] Produce NixOS 16 KiB kernel/initrd/rootfs artifacts.
- [ ] Add a signed guest manifest with page size, sizes, hashes, and compatibility metadata.
- [x] Validate manifest hashes before guest load.
- [x] Implement page-size-aware guest physical memory allocation.
- [ ] Implement guest page tables, address translation, permissions, and faults.
- [ ] Implement deterministic low-memory and out-of-address-space behavior.
- [ ] Test both page sizes through guest image loading and kernel boot.

## Static AArch64 CPU

- [x] Run a static iOS AArch64 proof ELF without dynamic native-code generation.
- [x] Correctly preserve x16 while evaluating conditional branches.
- [ ] Define CPU feature contract and supported AArch64 instruction baseline.
- [ ] Implement exception levels and Linux boot entry state.
- [ ] Implement interrupts, timers, and virtual GIC.
- [ ] Implement MMU/TLB behavior needed by Linux.
- [ ] Implement SMP startup or explicitly ship an initial uniprocessor profile.
- [ ] Add instruction, exception, MMU, and device conformance tests.
- [ ] Add deterministic record/replay and crash diagnostics.

## Virtual hardware and Linux boot

- [ ] Implement virtio-mmio transport in Relay.
- [ ] Implement virtio block for immutable base and writable overlay disks.
- [ ] Implement virtio console and capture boot log in Wawona Machines.
- [ ] Implement virtio net with App Store-safe host networking.
- [ ] Implement vsock for host-to-guest services.
- [ ] Implement entropy, clock, reset, and poweroff devices.
- [x] Load kernel, initrd, DTB, and command line from the manifest.
- [ ] Boot NixOS to a verified login or service-ready state on macOS.
- [ ] Boot NixOS in the iOS Simulator.
- [ ] Boot NixOS on physical iPhone/iPad hardware.
- [ ] Gracefully stop, restart, snapshot, and recover a VM.

## Guest display and input

- [x] Present a Relay proof frame through the iOS frame bridge.
- [ ] Define the Relay guest display ABI and damage protocol.
- [ ] Implement guest Wayland transport through vsock/waypipe/iland.
- [ ] Forward host keyboard, pointer, touch, clipboard, and resize correctly.
- [ ] Test a real guest Wayland client with Multi-Touch enabled.
- [ ] Test suspend/resume and background/foreground rendering behavior.

## OCI containers inside NixOS

- [x] Route container profiles through the same Relay VM backend policy.
- [ ] Implement OCI layout and manifest validation in Relay.
- [ ] Verify image config, layers, whiteouts, and platform selection.
- [ ] Deliver OCI image data to the guest through an explicit Relay device/service.
- [ ] Implement guest-side OCI create, start, stop, logs, and delete.
- [ ] Implement container filesystem isolation, namespaces, cgroups, and mounts in guest NixOS.
- [ ] Implement container networking through the guest VM network stack.
- [ ] Run a standards-conforming OCI smoke container on macOS.
- [ ] Run the same OCI smoke container in iOS Simulator.
- [ ] Run the same OCI smoke container on a physical device.
- [ ] Prove container output and Wayland frames return through the VM boundary.

## Wawona Machines integration

- [ ] Create, import, run, stop, and recover NixOS MicroVM profiles through Relay.
- [ ] Expose Relay's stopped-only, grow-only disk plan as a discrete native UI slider.
- [ ] Expose NixOS VM creation, import, start, stop, logs, and recovery in every supported UI.
- [ ] Expose container-in-VM lifecycle and logs in every supported UI.
- [ ] Generate Swift and Kotlin bindings from the Rust Relay domain with UniFFI.
- [ ] Keep SwiftUI, ObjC, and Kotlin free of VM business logic.
- [ ] Persist machine state, disk overlays, and guest artifacts safely.
- [ ] Support backup, restore, migration, and quota reporting.
- [ ] Add accessible status, errors, and progress identifiers for UI automation.

## App Store compliance and packaging

- [x] Build the Relay iOS static archive locally.
- [ ] Embed the Relay archive/framework in the Mode A iOS app.
- [ ] Verify IPA contains no QEMU, UTM, MAP_JIT, Cranelift mobile codegen, private API, or dynamic-code path.
- [ ] Add repeatable compliance scanner to CI.
- [ ] Separate, label, sign, and verify optional TrollStore/Sileo Mode B artifacts.
- [ ] Never ship a hidden JIT switch inside an App Store artifact.
- [ ] Complete App Store review evidence and claims review.

## Tests, devices, CI, and performance

- [x] Relay workspace unit suite passes locally: 13 tests.
- [ ] Add integration tests for guest manifests, disk overlays, boot protocol, virtio, and OCI.
- [ ] Add NixOS boot test on macOS before mobile integration.
- [ ] Add iOS Simulator build, install, launch, and VM boot test.
- [ ] Add physical-device install, launch, VM boot, and OCI test with agent-device evidence.
- [ ] Require Multi-Touch for Wayland guest client interaction tests.
- [ ] Run Instruments traces for CPU, memory, energy, frame time, and launch time.
- [ ] Add GitHub Actions jobs for unit, integration, compliance, artifact, simulator, and device lanes.
- [ ] Upload logs, screenshots, traces, guest manifests, and benchmark results from CI.
- [ ] Define peer-reviewed benchmark methodology and fixed workload matrix.
- [ ] Measure Relay against permitted reference systems on comparable hardware.
- [ ] Publish only reproducible performance claims; do not claim fastest before evidence.

## Completion gate

- [ ] A signed Mode A build boots a verified NixOS guest and runs an OCI workload on physical iOS hardware with no dynamic native-code generation.
- [ ] All required tests, compliance scans, CI jobs, device evidence, and benchmarks are green and archived.
