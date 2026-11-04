---
name: wawona-ghostty-host
description: Wawona Terminal = Rust libghostty-rs + UniFFI + native UI (Wawona/Terminal). Open when editing Terminal VT, paint hosts, shell backend, or retiring GhosttyGpu/Zig surface.
---

# Wawona Terminal host

## Shape

**Rust** `github.com/Wawona/Terminal` (flake `terminal`) on **libghostty-rs**
(`libghostty-vt`). **UniFFI** to Swift/Kotlin. **Native UI** paints.
Shell backend is separate (`wawona-terminal-shell-backend`).

| Tree | Role |
|------|------|
| `Wawona/Terminal` | Product: VT, encode, selection, frame, tabs, UniFFI |
| `Terminal/apple/Terminal` | SwiftUI / AppKit / UIKit paint + input |
| `GhosttyGpuView` / `GhosttySurfaceHost` | Interim retire targets. Do not grow |
| `ToolbarKeys` | Soft keys where supported |
| Rootshell `vendor/rootshell` | UX reference only. Not a product dep |

## Dogfood (Nix only, macOS)

```bash
cd /Users/8amps/Wawona/Wawona
nix run .#terminal --override-input terminal path:/Users/8amps/Wawona/Terminal
# In-app tip:
WAWONA_TEST_REBUILD=1 eval "$(scripts/appium/ensure-tip-wawona-macos.sh)"
```

**Never** Vision Pro / visionOS for Terminal unless the task is visionOS.
**Never** `/Applications/Wawona.app`.

## Do

- Query `ghostty-host.md` / rule `wawona-ghostty-host` before paint changes.
- Keep iOS floor **13.0**. Static only on Apple-mobile.
- System shell vs Wawona PTY via Rust resolver. Never hardcode in hosts.

## Do not

- GhosttyKit XCFramework in store IPA.
- Grow TermGpu / GhosttyGpu atlas.
- Second homemade VT.
- New Zig `ghostty_surface_*` product work (`Wawona/Ghostty` archived).

## Rules

`wawona-ghostty-host`, `wawona-terminal-shell-backend`,
`wawona-platform-targets` §14, `wawona-ios-min-os`,
`wawona-nix-fresh-build`, `wawona-rust-first`.
