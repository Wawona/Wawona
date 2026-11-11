# Tip Wawona app for all testing (hard)

**Every** Appium, agent-device, and local smoke that launches the Wawona host
app must use a **tip build** and a **clean launch**. Never a stale install.

## Required

1. **Build tip** into a test tree (macOS default:
   `/tmp/wawona-macos-tip/DerivedData/Build/Products/Debug/Wawona.app` via
   `cargo xtask tip macos`). Rebuild when `git HEAD` no
   longer matches the tip stamp, or when `WAWONA_TEST_REBUILD=1`.
   **macOS dogfood (hard):** the tip (or Xcode Run of `Wawona-macOS`).
   Never claim macOS Terminal/Present green from `nix run .#terminal` alone:
   standalone is grid smoke only.
2. **Refuse stale paths**: `/Applications/Wawona.app`,
   `~/Applications/Wawona.app`, old `build/DerivedData-macos*`, random
   Xcode DerivedData outside the tip root. Never `sudo rm` or symlink tip
   into `/Applications`.
3. **Clean launch every run**: quit any live `Wawona` process, then start the
   tip binary with `WAWONA_RUNTIME` / `XDG_RUNTIME_DIR`. Prove the live argv
   is the tip path (not `/Applications`).
4. Set `WAWONA_APP_PATH` to that tip `.app` before Appium Mac2 or
   `agent-device open`.

Check: `cargo xtask tip <platform> --check` (refuses installed copies and stale stamps).
Appium catalog: `cargo xtask appium catalog` always calls
`cargo xtask tip macos` first.

## Hard rejects

- Launch `/Applications/Wawona.app` (or any store/install copy) for tests
- Reuse yesterday's DerivedData when `git HEAD` moved
- Attach Mac2 / agent-device to a leftover process from a different binary
- `WAWONA_ALLOW_STALE_TEST_APP=1` for Appium catalog or Gate UI
- Claim catalog green on a host that was not tip-built for this HEAD

## Platforms

| Host | Tip build |
|------|-----------|
| macOS | `cargo xtask tip macos` / `Wawona-macOS` Debug under `/tmp/wawona-macos-tip` |
| iOS Simulator | Tip `nix build` / Xcode sim product for current HEAD (same refuse-stale idea) |
| Android | Tip APK/AAB from current HEAD Gradle/nix, not a random old install |

Cursor: `wawona-test-tip-app`. Skill: `wawona-appium`. Related:
`wawona-fresh-build` (build commands; never Vision Pro for Terminal),
`wawona-appium-ui-gh`, `wawona-test-control`, `wawona-calver-today`.
