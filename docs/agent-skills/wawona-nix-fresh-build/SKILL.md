---
name: wawona-nix-fresh-build
description: Fresh Wawona and Wawona Terminal builds via Nix only. Use before any tip, dogfood, or product launch. Blocks stale /Applications and Vision Pro when the task is Terminal.
---

# Nix fresh build

Open rule `wawona-nix-fresh-build` and `docs/compilation.md`. Query **wwn-mcp**
then **nixos** MCP. Do not invent attrs.

## Default commands (Wawona flake root)

```bash
# macOS product
nix run .#wawona-macos
# or package then run result
nix build .#wawona-macos

# Wawona Terminal (standalone Metal/GTK)
nix run .#terminal
nix run .#terminal --override-input terminal path:../Terminal

# Tip for agent-device / Appium (macOS only, after product edits)
WAWONA_TEST_REBUILD=1 eval "$(scripts/appium/ensure-tip-wawona-macos.sh)"
# exports WAWONA_APP_PATH under /tmp/wawona-macos-tip
```

## Terminal work

- Target: **macOS** (or iPhone sim if the bug is iOS).
- **Never** start Vision Pro / visionOS.
- Prefer `nix run .#terminal` for grid dogfood; in-app via tip /
  `nix run .#wawona-macos` after flake/Terminal input is wired.

## Hard rejects

- Stale `/Applications/Wawona.app`
- `/tmp` cargo archive overlays as "shipped"
- Wrong Apple simulator for the bug

Rule: `docs/agent-rules/wawona-nix-fresh-build.md`. Tip: `wawona-test-tip-app`.
Ghostty: `wawona-ghostty-host`.
