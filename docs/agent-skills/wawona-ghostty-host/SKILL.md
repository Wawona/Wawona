---
name: wawona-ghostty-host
description: Wawona Terminal = UniFFI libghostty-rs + native UI (ToolbarKeys shape). One repo Wawona/Terminal. Open when editing GhosttySurface, TerminalSession, apple/Terminal, or host paint paths.
---

# Wawona Terminal / libghostty-rs

## Shape (ToolbarKeys twin)

**One flake input:** `terminal` → `github.com/Wawona/Terminal`.

**Rust UniFFI (libghostty-rs)** owns the grid (`GhosttySurface` /
`TerminalSession`). **Native UI** paints on every target. Wawona L4 owns
Machines chrome, PTY, ToolbarKeys when bundled. Same repo can ship a
standalone Wawona Terminal app.

| Tree | Role |
|------|------|
| `Wawona/Terminal` `src/` | libghostty-rs UniFFI + optional C |
| `Wawona/Terminal` `apple/Terminal/` | Apple native views |
| `Wawona/Terminal` `android/` | Compose host |
| `ToolbarKeys` | Separate UniFFI toolbar |

## Do

- Feed / resize / lines via UniFFI. Hosts draw `lines()` / cells.
- Stage native UI like ToolbarKeys (`.nix-deps/terminal/Terminal`).
- iOS floor **13.0**. Static only on Apple-mobile.

## Do not

- Second GitHub repo named Ghostty for packaging.
- GhosttyKit XCFramework.
- Product `.dylib` on Apple-mobile.
- Second VT in Swift/Kotlin alone as the engine.
- Zig as product link line.

## Rules

`wawona-platform-targets` §14, `wawona-ios-min-os`, `wawona-uniffi-domain`,
`wawona-rust-first`, `wawona-ios-native-shell`.
