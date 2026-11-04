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
- Paint: `Terminal/apple/Terminal/GhosttySurfaceHost` (Zig
  `ghostty_surface_draw` on tip dogfood; else `GhosttyGpuView` atlas
  fallback). **Forbidden to grow the atlas.**
- `wwn-ghostty#libghostty-macos` ships GhosttyLib static; draw proof:
  `#libghostty-macos-draw-proof`. Rust VT is `wwn_term_*`; Zig keeps
  `ghostty_surface_*`. Stage: `scripts/stage-libghostty-macos.sh`.
- Tip default-on: `ensure-tip-wawona-macos.sh` sets
  `WAWONA_LINK_LIBGHOSTTY=1` (opt out `=0`), stages archive when missing,
  writes `.build/wwn-libghostty-link.xcconfig`, and passes `-force_load`
  on the `xcodebuild` CLI. Prebuild auto-links when the staged archive
  exists even if the env flag is unset. Bridge compile flag is
  `wwn_ghostty_host_config.h` in `DERIVED_FILE_DIR`, not
  `GCC_PREPROCESSOR_DEFINITIONS` from that xcconfig.
- GhosttyGpu retired from tip default path (still fallback). Product nix
  package Zig-by-default is later. PTY unify (Machines feed → Zig) open.

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
