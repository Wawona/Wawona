# Ghostty host (Zig libghostty L3′)

**L3′ repo:** `github.com/Wawona/Ghostty` (flake input `wwn-ghostty`).

**Product grid** = Zig **libghostty** (`ghostty_*`). Native UI owns chrome
only (windows, sheets, ToolbarKeys, Machines Start). Bytes from `wawona-pty`
or Relay `relay_copy_log`.

Canonical RAG: `ghostty-host.md`. Skill: `wawona-ghostty-host`.

## Target shape

| Layer | Owns |
|-------|------|
| `Wawona/Ghostty` | VT, font atlas, resize, GPU/software draw, `ghostty_*` C ABI |
| Wawona L4 | Start/Focus/park, PTY/session, ToolbarKeys host |
| `ToolbarKeys` | Soft key slots |
| `Wawona/Terminal` | Interim UniFFI over `libghostty-vt` + host paint until Metal surface links |

## Interim (today)

- VT: upstream `libghostty-vt` via flake `ghostty` + `Terminal` (`GhosttySurface`).
- Paint: `Terminal/apple/Terminal/GhosttyGpuView` (interim atlas, staged into
  Wawona). **Forbidden to grow.** Plan:
  retire after Zig Metal surface green (`Ghostty/docs/METAL-SURFACE.md`).
- `wwn-ghostty#libghostty-macos` **fails closed** until Darwin attaches
  GhosttyLib install (probe: `#libghostty-macos-probe`). Terminal
  `libghostty.a` alias of `libwawona_terminal.a` is not Metal.
- Prefer plan: paint via Zig Ghostty surface, not atlas stamp.

## Hard rejects

- Published GhosttyKit (iOS 17) as a product input
- Product `.dylib` on Apple-mobile
- Homemade VT branded as libghostty
- Rewriting libghostty to Rust while Zig triples emit objects
- Claiming Metal libghostty ships while GhosttyGpu still paints
- Vision Pro dogfood for Terminal when the task is macOS

## Credits

Ghostty MIT (Mitchell Hashimoto et al.). Rootshell MIT (Kit Knox) for iOS
embed starting point. Port into `Wawona/Ghostty`; do not link Rootshell app.
