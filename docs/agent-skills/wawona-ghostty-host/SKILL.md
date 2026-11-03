---
name: wawona-ghostty-host
description: Wawona Terminal = UniFFI libghostty-rs + native UI (ToolbarKeys shape). Open when editing GhosttySurface, TerminalSession, apple/Terminal, GuestTerm, or TermGpu retirement.
---

# Wawona Terminal / libghostty-rs

## Shape (ToolbarKeys twin)

**Rust UniFFI** owns the grid (`GhosttySurface` / `TerminalSession`).
**Native UI** paints on every target (AppKit, UIKit, SwiftUI, Watch,
Compose, GTK). Wawona L4 owns Machines chrome, PTY, ToolbarKeys.

| Tree | Role |
|------|------|
| `Wawona/Terminal` `src/` | libghostty-rs UniFFI + optional C |
| `Wawona/Terminal` `apple/Terminal/` | Apple native views |
| `Wawona/Ghostty` | Packaging / flake `wwn-ghostty` + mirrored `apple/` |
| `ToolbarKeys` | Separate UniFFI toolbar |

## Do

- Feed / resize / lines via UniFFI. Hosts draw `lines()` / cells.
- Stage native UI like ToolbarKeys Keyboard (`.nix-deps`).
- iOS floor **13.0**. Static only on Apple-mobile.

## Do not

- GhosttyKit XCFramework.
- Product `.dylib` on Apple-mobile.
- Second VT in SwiftUI Text / Compose Text alone as the engine.
- Zig as product link line.

## Rules

`wawona-platform-targets` §14, `wawona-ios-min-os`, `wawona-uniffi-domain`,
`wawona-rust-first`, `wawona-ios-native-shell`.
