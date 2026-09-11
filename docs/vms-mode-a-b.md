# wwn-vms. Mode A / Mode B

Canonical product split: [Wawona `docs/mode-a-b.md`](mode-a-b.md).
Engine: Wawona Relay (`wwn-relay`). Not QEMU. Not UTM.

## Goal

One Machines kind `virtual_machine`. Linux / NixOS prebuilts only. Guest GUI
is Wayland into Wawona (`wawona-guest-wayland-iland`).

| Platform | Mode A engine | Mode B / privileged |
|----------|---------------|---------------------|
| **macOS** | Virtualization.framework via Relay | Same plus desktop-host paths |
| **iOS / iPadOS** | Relay static / jitless CPU. Planned. Fail closed | Same Relay plus Mode B JIT CPU. Planned. Fail closed |
| **Android** | Relay static CPU. Planned. Fail closed | Root / privileged Relay. Planned |
| **Linux** | KVM via cloud-hypervisor or crosvm. Fail closed without `/dev/kvm` | N/A |
| **tvOS / watchOS / visionOS** | Forbidden | Forbidden |

Shared: Machines schema, NixOS guest artifacts, vsock + waypipe GUI, capability
gates. Engine is selected by which binary was installed, not a Settings toggle.

## Never

- QEMU, TCTI, UTM, Spice, virgl, or `wwn-qemu-run` as the product CPU
- Ship Mode B engine inside an App Store IPA behind a toggle
- Enable VM machine kind on tvOS / watchOS / visionOS
- Document VM frames as done before Relay boots NixOS on that artifact

## Success (not reached on iOS yet)

- Store IPA boots a NixOS guest through Relay without JIT
- TrollStore Mode B tipa boots the same profile class through Relay with the
  Mode B CPU
- Official `.#wawona-ios-modeb-tipa` ships guests only after Relay frames
