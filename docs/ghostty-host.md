# Wawona Terminal host

Product crate: `github.com/Wawona/Terminal` (flake `terminal`).

One terminal grid for the local shell, SSH, and the Relay guest console, on
macOS, iOS, iPadOS, tvOS, watchOS, visionOS, Android, and Linux.

**Engine:** Rust **libghostty-rs** (`libghostty-vt`, Ghostty VT core) with
UniFFI (`GhosttySurface` / `TerminalSession`). Optional C ABI: `wwn_term_*`.

**Paint:** native per platform (AppKit/UIKit/SwiftUI CoreText, SpriteKit on
watchOS, Compose on Android, GTK/Pango on Linux). Hosts paint a Rust render
frame and forward input. They do not decide bytes, selection, or shell.

**Shell backends** (rule `wawona-terminal-shell-backend`):

- macOS, Linux, iOS Mode B, Android Mode B: system login shell on a real pty
- Mode A store/Play: Wawona PTY shell (`wawona_zsh_main` + `wwn_pty`)

Bytes also come from Relay `relay_copy_log` / SSH when attached.

**Retire:** Zig `GhosttySurfaceHost` / `ghostty_surface_*` product path and
the `GhosttyGpuView` atlas (plan S12). `github.com/Wawona/Ghostty` is
archived (moved to Terminal). Do not grow the atlas.

libghostty / Ghostty VT is Ghostty. Copyright (c) 2024 Mitchell Hashimoto,
Ghostty contributors. MIT. https://github.com/ghostty-org/ghostty

libghostty-rs: https://github.com/uzaaft/libghostty-rs

iOS embed UX ideas from Rootshell. Copyright (c) 2026 Rootshell LLC, Kit
Knox. MIT. iOS / iPadOS: static archive, deployment target 13.0. No product
`.dylib`. Published GhosttyKit (minimum OS 17) is not an input.

Toolbar keys are `ToolbarKeys`, not this repo. Relay stays the VM engine.
