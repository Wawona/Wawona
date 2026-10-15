# Tip Wawona app for all testing (hard)

**Every** Appium, agent-device, and local smoke that launches the Wawona host
app must use a **tip build** and a **clean launch**. Never a stale install.

## Required

1. **Build tip** into a test tree (macOS default:
   `/tmp/wawona-macos-tip/DerivedData/Build/Products/Debug/Wawona.app` via
   `scripts/appium/ensure-tip-wawona-macos.sh`). Rebuild when `git HEAD` no
   longer matches the tip stamp, or when `WAWONA_TEST_REBUILD=1`.
2. **Refuse stale paths**: `/Applications/Wawona.app`,
   `~/Applications/Wawona.app`, old `build/DerivedData-macos*`, random
   Xcode DerivedData outside the tip root.
3. **Clean launch every run**: quit any live `Wawona` process, then start the
   tip binary with `WAWONA_RUNTIME` / `XDG_RUNTIME_DIR`. Prove the live argv
   is the tip path (not `/Applications`).
4. Set `WAWONA_APP_PATH` to that tip `.app` before Appium Mac2 or
   `agent-device open`.

Helper: `scripts/lib/require-tip-wawona-app.sh` (`wawona_refuse_stale_app_path`).
Appium catalog: `capture-catalog-gallery.sh` always calls
`ensure-tip-wawona-macos.sh` first.

## Hard rejects

- Launch `/Applications/Wawona.app` (or any store/install copy) for tests
- Reuse yesterday's DerivedData when `git HEAD` moved
- Attach Mac2 / agent-device to a leftover process from a different binary
- `WAWONA_ALLOW_STALE_TEST_APP=1` for Appium catalog or Gate UI
- Claim catalog green on a host that was not tip-built for this HEAD

## Platforms

| Host | Tip build |
|------|-----------|
| macOS | `ensure-tip-wawona-macos.sh` / `Wawona-macOS` Debug under `/tmp/wawona-macos-tip` |
| iOS Simulator | Tip `nix build` / Xcode sim product for current HEAD (same refuse-stale idea) |
| Android | Tip APK/AAB from current HEAD Gradle/nix, not a random old install |

Cursor: `wawona-test-tip-app`. Skill: `wawona-appium`. Related:
`wawona-appium-ui-gh`, `wawona-test-control`, `wawona-calver-today`.
