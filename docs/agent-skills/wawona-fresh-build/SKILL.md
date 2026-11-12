---
name: wawona-fresh-build
description: Fresh Wawona builds. Xcode 27 and Android Studio over prebuilt slices, or cargo xtask from a shell. Use before any tip, dogfood or product launch. Blocks stale /Applications and the wrong simulator.
---

# Fresh build

Open rule `wawona-fresh-build` and `docs/compilation.md`. Query **wwn-mcp**
first. `cargo xtask <verb> --help` names every flag.

## Default commands (Wawona checkout root)

```bash
# Slices once per checkout (a stale one refetches)
cargo xtask deps get macosx iphonesimulator android

# IDEs: open Wawona.xcodeproj (scheme Wawona-macOS, Wawona-iOS, ...) or android/, then Run

# Same projects from a shell
cargo xtask build macos
cargo xtask build ios            # simulator; --device for a phone
cargo xtask build android

# Tip for agent-device / Appium after product edits
eval "$(WAWONA_TEST_REBUILD=1 cargo xtask tip macos)"   # exports WAWONA_APP_PATH

# Wawona Terminal standalone
nix run .#terminal
nix run .#terminal --override-input terminal path:../Terminal
```

## Terminal work

- Target **macOS**, or the iPhone Simulator when the bug is on iOS.
- **Never** start Vision Pro / visionOS for it.
- `nix run .#terminal` for grid dogfood; in-app through the tip.

## Hard rejects

- Stale `/Applications/Wawona.app`
- `/tmp` cargo archive overlays as "shipped"
- The wrong Apple simulator for the bug
- Python anywhere in the build (`cargo xtask verify no-python`)

Rule: `docs/agent-rules/wawona-fresh-build.md`. Tip: `wawona-test-tip-app`.
Ghostty: `wawona-ghostty-host`.
