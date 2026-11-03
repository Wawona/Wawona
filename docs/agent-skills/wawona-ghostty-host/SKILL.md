---
name: wawona-ghostty-host
description: Wawona Terminal = UniFFI/C over uzaaft/libghostty-rs (Ghostty VT) + native paint. Open when editing GhosttySurface, TerminalSession, GhosttyGpu, or GuestTerm. Standalone: nix run .#terminal.
---

# Wawona Terminal / libghostty-vt

## Shape (ToolbarKeys twin)

**Rust** owns the grid via [`uzaaft/libghostty-rs`](https://github.com/uzaaft/libghostty-rs)
(`libghostty-vt` → Ghostty VT archive). UniFFI (`GhosttySurface` /
`TerminalSession`) and C `ghostty_surface_*` wrap that engine.
**Native UI** paints on every target (AppKit Metal, UIKit/SwiftUI, Watch,
Compose, GTK). Wawona L4 owns Machines chrome, PTY, ToolbarKeys.

| Tree | Role |
|------|------|
| `Wawona/Terminal` `src/` | UniFFI + C over `libghostty-vt` |
| `Wawona/Terminal` `apple/Terminal/` | Apple UniFFI line paint (iOS family) |
| `Wawona/Terminal` `apple/Standalone/` | macOS Metal standalone host |
| `Wawona/Terminal` `src/bin/wawona-terminal.rs` | Linux GTK standalone |
| Wawona `GhosttyGpu` / `WWNTermSurface` | In-app macOS Metal paint |

## Standalone dogfood

```bash
# From Wawona (uses flake input `terminal`)
nix run .#terminal
# Local sibling Terminal tree:
nix run .#terminal --override-input terminal path:../Terminal

# From Terminal repo itself
nix run .#terminal
./scripts/run-standalone-macos.sh   # after scripts/build-static.sh macos
```

macOS: AppKit + Metal. Linux: GTK + `TerminalSession` UniFFI.

**Nix owns Zig.** Terminal flake pulls `zig2nix` (Zig 0.17) + `ghostty`
(`libghostty-vt` + `.dev`). Rust links via `pkg-config` and feature
`nix-ghostty-vt`. Do not ad-hoc host `zig` / `cargo` for the VT core.
Wawona `.#terminal` reuses `Terminal/nix/package.nix` + flake input
`ghostty` (same commit as Terminal).

## Do

- Feed / resize / lines via UniFFI or C into the same VT worker.
- Stage native UI like ToolbarKeys Keyboard (`.nix-deps`).
- iOS floor **13.0**. Static only on Apple-mobile.
- Real `libghostty-vt.a` from Ghostty (via libghostty-vt-sys).

## Do not

- GhosttyKit XCFramework.
- Product `.dylib` on Apple-mobile.
- Homemade VT branded as libghostty.
- Second VT in SwiftUI Text / Compose Text alone as the engine.
- Ship empty stub viewports.

## Rules

`wawona-platform-targets` §14, `wawona-ios-min-os`, `wawona-uniffi-domain`,
`wawona-rust-first`, `wawona-ios-native-shell`.
