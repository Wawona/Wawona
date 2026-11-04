# Wawona Terminal host (libghostty-rs + UniFFI)

**Product crate:** `github.com/Wawona/Terminal` (flake `terminal`).

**Product grid** = Rust **libghostty-rs** (`libghostty-vt`, Ghostty's stable
VT core) behind UniFFI (`GhosttySurface` / `TerminalSession`). Native UI
owns paint and chrome only (AppKit / UIKit / SwiftUI / SpriteKit / Compose /
GTK). Bytes from the shell backend (`wawona-terminal-shell-backend`),
`wawona-pty`, or Relay `relay_copy_log`.

Canonical RAG: `ghostty-host.md`. Skill: `wawona-ghostty-host`.
Shell backends: `wawona-terminal-shell-backend`.

## Target shape

| Layer | Owns |
|-------|------|
| `Wawona/Terminal` | VT (libghostty-vt), key/mouse encode, selection, render frame, tabs, UniFFI, optional `wwn_term_*` |
| Native hosts | Paint frame with platform text stack; forward keys/IME/pointer; chrome |
| Wawona L4 | Machines Start/Focus/park, Mode A/B shell policy, ToolbarKeys host |
| `ToolbarKeys` | Soft key slots (iOS / iPadOS / visionOS / Android) |

## Shell backends (do not conflate)

| Product | Backend |
|---------|---------|
| macOS, Linux, iOS Mode B, Android Mode B | System login shell on a real pty (Rust spawns) |
| Mode A (store Apple-mobile, Play) | Wawona PTY shell (`wawona_zsh_main` + `wwn_pty`, no fork/exec) |

## Interim paint debt

- Prefer CoreText / Compose / Pango paint from Rust render frames.
- `GhosttyGpuView` Metal atlas and Zig `GhosttySurfaceHost` are **retire
  targets** (plan S12). Do not grow the atlas.
- `github.com/Wawona/Ghostty` is archived (moved to Terminal). Do not add
  new Zig surface product work.

## Hard rejects

- Published GhosttyKit (iOS 17) as a product input
- Product `.dylib` on Apple-mobile
- Homemade VT branded as libghostty
- Hardcoding `/bin/zsh` in hosts instead of the shell resolver
- Vision Pro dogfood for Terminal when the task is macOS
- Claiming Zig Metal surface is the product path

## Credits

Ghostty MIT (Mitchell Hashimoto et al.). libghostty-rs (uzaaft). Rootshell
MIT (Kit Knox) for iOS embed UX ideas only. Do not link Rootshell app.
