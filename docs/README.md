# Wawona Documentation

> **Wawona** is a native Wayland compositor for macOS, iOS, and Android. This folder contains technical documentation for architecture, build, and platform integration.

---

## Core Documentation

| Document | Description |
|----------|-------------|
| [usage.md](usage.md) | Weston, waypipe, native commands — run `nix run .#weston`, `.#weston-terminal`, remote apps |
| [settings.md](settings.md) | All Wawona Settings (Display, Graphics, Input, Waypipe, SSH) for macOS, iOS, Android |
| [2026-ARCHITECTURE-STRUCTURE.md](2026-ARCHITECTURE-STRUCTURE.md) | Project layout, FFI flow, Wayland protocol status, platform architecture |
| [2026-nix-build-system.md](2026-nix-build-system.md) | Nix build pipeline, crate2nix, cross-compilation |
| [2026-COMPOSITOR-COMPARISON-AND-ROADMAP.md](2026-COMPOSITOR-COMPARISON-AND-ROADMAP.md) | Wawona vs Weston/Hyprland/Wayoa; protocol gaps and roadmap |

---

## Platform & Features

| Document | Description |
|----------|-------------|
| [2026-waypipe.md](2026-waypipe.md) | Waypipe integration (macOS, iOS, Android); SSH transport, streamlocal |
| [2026-Wawona-Android-Audit.md](2026-Wawona-Android-Audit.md) | Android implementation audit and parity checklist |
| [macos-implementation.md](macos-implementation.md) | macOS native implementation, Metal, IOSurface |
| [2026-Liquid-Glass.md](2026-Liquid-Glass.md) | Apple Liquid Glass design (macOS 15 / iOS 26) |

---

## Reference

| Document | Description |
|----------|-------------|
| [debugging.md](debugging.md) | Attach LLDB with `--debug` (macOS, iOS, Android) |
| [2026-LOGGING.md](2026-LOGGING.md) | Logging format convention |
| [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) | Third-party license disclosure |
| [drivers-how-to/](drivers-how-to/README.md) | Graphics driver setup guide (Vulkan, MoltenVK, KosmicKrisp, Android) |

---

## Legacy

| Document | Description |
|----------|-------------|
| [legacy/](legacy/) | Archived docs (2025 archive, protocols) |
