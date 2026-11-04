---
name: wawona-ghostty-host
description: Wawona Terminal grid = Zig libghostty (Wawona/Ghostty, wwn-ghostty). Native chrome only. Open when editing Ghostty surface, GhosttyGpu interim, or Terminal UniFFI.
---

# Ghostty host

## Shape

**Zig libghostty** owns the grid (L3′ `github.com/Wawona/Ghostty`, flake
`wwn-ghostty`). **Native UI** paints chrome around it. Wawona L4 owns Machines,
PTY, ToolbarKeys.

| Tree | Role |
|------|------|
| `Wawona/Ghostty` | Zig static `ghostty_*` (goal: Metal/GL/software) |
| `Wawona/Terminal` | Interim UniFFI over `libghostty-vt` until Metal surface |
| `Terminal/apple/Terminal/GhosttyGpuView` | **Interim** atlas paint (default / `WAWONA_GHOSTTY_GPU`). Do not grow |
| `wwn-ghostty#libghostty-macos-draw-proof` | Link + `ghostty_surface_draw` proof. Not tip (ABI gap) |
| Rootshell `vendor/rootshell` | Reference for iOS Metal embed. Not a product dep |

## Dogfood (Nix only, macOS)

```bash
cd /Users/8amps/Wawona/Wawona
nix run .#terminal --override-input terminal path:/Users/8amps/Wawona/Terminal
# In-app tip:
WAWONA_TEST_REBUILD=1 eval "$(scripts/appium/ensure-tip-wawona-macos.sh)"
```

**Never** Vision Pro / visionOS for Terminal. **Never** `/Applications/Wawona.app`.

## Do

- Query `ghostty-host.md` / rule `wawona-ghostty-host` before paint changes.
- Prefer linking `wwn-ghostty` / full `libghostty.a` for Metal.
- Keep iOS floor **13.0**. Static only on Apple-mobile.

## Do not

- GhosttyKit XCFramework in store IPA.
- Grow TermGpu / GhosttyGpu atlas (UV flips, stamp hacks).
- Second homemade VT.
- Claim Metal Ghostty while atlas still owns paint (`Ghostty/docs/METAL-SURFACE.md`).

## Rules

`wawona-ghostty-host`, `wawona-platform-targets` §14, `wawona-ios-min-os`,
`wawona-nix-fresh-build`, `wawona-rust-first`.
