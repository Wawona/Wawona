# Wawona Terminal / libghostty-vt (Rust)

**One repo:** `github.com/Wawona/Terminal` (flake input `terminal`).

**Wawona Terminal** = UniFFI + C host API over
[`uzaaft/libghostty-rs`](https://github.com/uzaaft/libghostty-rs)
(`libghostty-vt`: safe Rust on Ghostty's extracted VT). Native UI paints cells
(ToolbarKeys shape). Standalone terminal or linked into Wawona L4.

- Rust product API: `GhosttySurface` / `TerminalSession` in `Wawona/Terminal`
- VT engine: `libghostty-vt` (not a homemade `screen.rs` VT)
- Native: `apple/Terminal/`, Compose, GTK, Watch; macOS Metal via
  `GhosttyGpu` / `WWNTermSurface` (in-app) or `apple/Standalone` (dogfood)
- Standalone: `nix run .#terminal` (macOS Metal or Linux GTK)
- VT build: Terminal flake `zig2nix` + `ghostty` `libghostty-vt` (pkg-config,
  feature `nix-ghostty-vt`). Wawona passes the same `ghostty` input into
  `terminal-standalone.nix`. No host zig for the core.
- Not GhosttyKit. Not a second hand-rolled VT under a libghostty name.
- Optional C `ghostty_surface_*` is a bridge into the same engine.

Skill: `wawona-ghostty-host`.
