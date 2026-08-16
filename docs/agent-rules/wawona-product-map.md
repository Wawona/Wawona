# Wawona product map (do not conflate)

These are **separate** products. Mixing them in code, docs, UI, or packaging is a bug.

| Product | What it is | Not |
|---|---|---|
| **Wawona Swinging Bridge** (formerly **anowaW**) | Cocoa / Android / (future UIKit) apps → **Wayland clients**, local or over **waypipe-rs** to Linux (resize, placement, HID) | Desktop/LockScreen; MediaProjection-as-desktop |
| **Desktop + LockScreen replacement** | Host DE / greeter (machine picker). macOS + Android planned; iOS/iPadOS jailbreak via `repo.wawona.io` only | Swinging Bridge; Linux; store Apple-mobile |
| **`wwn-vms`** | Machines kind `virtual_machine` | Wasm packages; local shell; Swinging Bridge |
| **`wwn-containers`** | Machines kind `container` (OCI) | Wasm packages; Desktop |
| **Wawona Runtime + `wpm`** (`wwn-wasm`) | WASI P1/P2 **`.wasm` packages** for optional software | OCI containers; `.deb`; Mach-O modules (`wwn-apt` retired) |

Canonical prose: `Wawona/docs/mode-a-b.md`, `swinging-bridge.md`, `iland-mode-a-b-desktop.md`, `vms-containers.md`, `wasm-package-manager.md`. Site: wawona.io `/docs/…`.

## Mode A vs Mode B (product-wide)

| | **Mode A** | **Mode B** |
|---|---|---|
| Who | App Store / TestFlight / Play / store-shaped | Jailbreak iOS/iPadOS; SIP partial/off macOS; root Android |
| Ship | Store IPA/AAB; notarized macOS | `repo.wawona.io` Sileo `.deb` + **Mode B IPA**; desktop-host macOS — **never** in store |
| Copy | Never mention jailbreak / JIT pitch in store UI | Website + repo may document Mode B |

**Always design A and B together** for VMs, containers, Desktop, Swinging Bridge. **Never** ship Mode B into App Store / Play artifacts.

### Swinging Bridge

- Repo: `Wawona/Wawona-Swinging-Bridge` (flake `wwn-swinging-bridge`; legacy ABI/Nix `anowaw_*` OK temporarily).
- Status: planned; **neither Mode A nor Mode B implemented**.
- macOS + Android: Mode A + Mode B planned. **iOS/iPadOS: Mode B only** (forbidden in store IPA).
- Helps Desktop later (e.g. Android home = Wawona, apps still Wayland surfaces in niri) — home path is still Desktop, not Swinging Bridge.

### Desktop / LockScreen

- macOS: Mode A present path = iland userspace; Mode B = SIP-gated `libwayland-mac.dylib` in `.#wawona-macos-desktop-host` only.
- Android: Default Home + LockScreen APIs (planned); no root required for baseline.
- App Store Apple-mobile: **forbidden** in-app; never jailbreak strings in store IPA.

### VMs / containers

- Platforms: planned on macOS, iOS, iPadOS, Android, Linux. **Forbidden** on tvOS, watchOS, visionOS.
- iOS Mode A: UTM-SE–class **jitless**. iOS Mode B: JIT UTM via Mode B IPA.
- Backends differ by OS (macOS Virtualization/Apple Container ≠ iOS UTM ≠ Android QEMU). Do not force one engine.
- Not the same as on-device `wwn-zsh` shell or Wasm packages.

### Wawona Runtime packages (`wpm` / WASI) — Mode A forever

- **Wawona Runtime is always App Store / Play compliant.** There is **no Mode B flavor of the Runtime**.
- Packages are **bytecode data** (`.wasm`), not unsigned Mach-O/`dlopen`, not `.deb`.
- Dual channel on `repo.wawona.io`:
  - `/wasm/` — Mode A (store binaries may use)
  - `/jailbreak/` — Mode B APT only (store binaries must **never** touch)
- Do not put `.deb` and `.wasm` in one index. Do not auto-discover jailbreak from `wpm`.

## Hard rejects

❌ Call Swinging Bridge “Desktop” or “LockScreen”  
❌ Ship Mode B / JIT / jailbreak engage in store IPA/AAB  
❌ Treat Wasm packages as containers/VMs (or vice versa)  
❌ Put graphics/Desktop/Swinging Bridge ownership into `wwn-toolchain` (L0 substrate only)  
❌ Document Runtime as needing Mode B for package install  
