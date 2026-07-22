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

## Apple Mobile Local Shell (App Store ZSH)

**Wawona is building the first App Store–compliant bundled native zsh on iOS/iPadOS**, paired with upstream Weston `terminal.c`. Start here:

| Document | Description |
|----------|-------------|
| [ios-local-shell/README.md](ios-local-shell/README.md) | **Hub** — vision, doc map, flake outputs, status |
| [ios-local-shell/ARCHITECTURE.md](ios-local-shell/ARCHITECTURE.md) | Process model, data flows, env vars, code anchors |
| [ios-local-shell/APP-STORE-COMPLIANCE.md](ios-local-shell/APP-STORE-COMPLIANCE.md) | Guideline mapping, competitive landscape, enforcement |
| [ios-local-shell/IMPLEMENTATION-ROADMAP.md](ios-local-shell/IMPLEMENTATION-ROADMAP.md) | Phases 0–4, PRs, risks, success criteria |
| [ios-local-shell/WAWONA-PTY-SPEC.md](ios-local-shell/WAWONA-PTY-SPEC.md) | `wwn_pty_*` API specification |
| [ios-local-shell/ROOTFS-AND-ZSH.md](ios-local-shell/ROOTFS-AND-ZSH.md) | Nix packaging, rootfs, `.zshrc`, xcodegen |
| [ios-local-shell/SECURITY-SPAWN-POLICY.md](ios-local-shell/SECURITY-SPAWN-POLICY.md) | Path allowlist, forbidden operations |
| [ios-local-shell/APP-REVIEW-NOTES.md](ios-local-shell/APP-REVIEW-NOTES.md) | Copy for App Store Connect reviewer notes |
| [ios-local-shell/TESTFLIGHT-CHECKLIST.md](ios-local-shell/TESTFLIGHT-CHECKLIST.md) | Pre-release QA checklist |
| [ios-local-shell/WATCHOS-SCOPE.md](ios-local-shell/WATCHOS-SCOPE.md) | watchOS explicitly excluded from local shell v1 |
| [ios-local-shell-spike.md](ios-local-shell-spike.md) | Phase 0 PTY device spike report (fill on hardware) |

---

## Platform & Features

| Document | Description |
|----------|-------------|
| [iland-mode-a-b-desktop.md](iland-mode-a-b-desktop.md) | **Canonical** wwn-iland Mode A vs Mode B, SIP Desktop Replacement, dylib shipping |
| [2026-waypipe.md](2026-waypipe.md) | Waypipe integration (macOS, iOS, Android); SSH transport, streamlocal |
| [2026-Wawona-Android-Audit.md](2026-Wawona-Android-Audit.md) | Android implementation audit and parity checklist |
| [macos-implementation.md](macos-implementation.md) | macOS native implementation, Metal, IOSurface |
| [2026-Liquid-Glass.md](2026-Liquid-Glass.md) | Apple Liquid Glass design (macOS 15 / iOS 26) |

---

## Agent / Cursor rules

| Document | Description |
|----------|-------------|
| [agent-rules/](agent-rules/) | Tracked mirrors of alwaysApply Cursor rules (`.cursor/` is gitignored) |
| [../AGENTS.md](../AGENTS.md) | Agent entrypoint — Mode A/B, FFI, wwn-*, store asymmetry |

---

## Reference

| Document | Description |
|----------|-------------|
| [debugging.md](debugging.md) | Opt-in LLDB via `--debug` (default: no debugger) |
| [2026-LOGGING.md](2026-LOGGING.md) | Logging format convention |
| [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) | Third-party license disclosure |
| [drivers-how-to/](drivers-how-to/README.md) | Graphics driver setup guide (Vulkan, MoltenVK, KosmicKrisp, Android) |

---

## Legacy

| Document | Description |
|----------|-------------|
| [legacy/](legacy/) | Archived docs (2025 archive, protocols) |
