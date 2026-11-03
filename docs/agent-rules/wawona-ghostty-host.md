# Wawona Terminal / UniFFI libghostty-rs

**One repo:** `github.com/Wawona/Terminal` (flake input `terminal`).

**Wawona Terminal** = UniFFI Rust grid (**libghostty-rs**) + native UI
(ToolbarKeys shape). Standalone terminal or linked into Wawona L4.

- Rust: `GhosttySurface` / `TerminalSession` in `Wawona/Terminal`
- Native: `apple/Terminal/`, Compose, GTK, Watch
- ToolbarKeys: separate UniFFI where supported
- Not GhosttyKit. Not a second `Wawona/Ghostty` repo. Not Zig product link.
- Optional C `ghostty_*` is not the product contract.

Skill: `wawona-ghostty-host` (alias of Terminal host).
