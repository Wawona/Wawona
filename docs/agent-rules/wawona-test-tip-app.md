# Tip Wawona app for all testing (hard)

**Every** Appium, agent-device, simctl screenshot/AX, and local smoke that
launches the Wawona host app must use a **tip build stamped for this HEAD**
and a **clean launch**. Never a stale install. Never a morning
`/tmp/wawona-*-tip` binary after afternoon `Sources/` edits.

## Required (every platform)

1. **Rebuild tip before proof** when any of these are true:
   - `git-HEAD` stamp missing or product tree drifted vs stamp
   - Uncommitted edits under product paths (see below)
   - You just changed UI / Present / Settings / Machines code
   - `WAWONA_TEST_REBUILD=1`
2. **Refuse stale paths**: `/Applications/Wawona.app`,
   `~/Applications/Wawona.app`, random Xcode DerivedData outside the tip
   root. Never `sudo rm` or symlink tip into `/Applications`.
3. **Clean launch every run**: quit live Wawona on that device, install the
   tip `.app`, launch tip binary. Prove live argv / installed bundle is tip.
4. Set `WAWONA_APP_PATH` (and `WAWONA_SIM_UDID` on sims) before Appium /
   `agent-device open` / `simctl io screenshot` used as evidence.

**Binary mtime is not a freshness check.** A 09:48 tip after 13:00 Source
edits is stale even if `/tmp/wawona-tvos-tip/.../Wawona.app` still exists.
Only `tip_root/git-HEAD` + `tip_root/product-FP` (helpers below) count.

### Product paths (invalidate stamp)

`Sources/`, `src/`, `Darwin/`, `Cargo.toml`, `Cargo.lock`, `Package.swift`,
`dependencies/`, `xcodegen.nix`, `flake.nix`, `flake.lock`, `VERSION`.

## Helpers

| Host | Command |
|------|---------|
| macOS | `eval "$(scripts/appium/ensure-tip-wawona-macos.sh)"` |
| tvOS / visionOS / iOS / watchOS sim | `eval "$(scripts/appium/ensure-tip-wawona-apple-sim.sh tvOS)"` (or `visionOS` / `iOS` / `watchOS`) |

Shared refuse + stamp: `scripts/lib/require-tip-wawona-app.sh`
(`wawona_refuse_stale_app_path`, `wawona_tip_stamp_is_fresh`,
`wawona_tip_write_stamp`, `wawona_require_tip_fresh_for_proof`).
Stamp files: `git-HEAD` and `product-FP` (product tree fingerprint including
uncommitted Sources edits).

macOS dogfood still requires `nix run .#xcodegen-macos` then
`xcodebuild -scheme Wawona-macOS` (ensure-tip does this). Never claim
macOS Terminal/Present green from `run-standalone-macos.sh` alone.

## Tip roots

| Host | Tip root | App (Debug) |
|------|----------|-------------|
| macOS | `/tmp/wawona-macos-tip` | `…/Debug/Wawona.app` |
| tvOS | `/tmp/wawona-tvos-tip` | `…/Debug-appletvsimulator/Wawona.app` |
| visionOS | `/tmp/wawona-visionos-tip` | `…/Debug-xrsimulator/Wawona.app` |
| iOS | `/tmp/wawona-ios-tip` | `…/Debug-iphonesimulator/Wawona.app` |
| watchOS | `/tmp/wawona-watchos-tip` | `…/Debug-watchsimulator/Wawona.app` |
| Android | tip APK/AAB from current HEAD Gradle/nix | not a random old install |

## Agent loop (fail closed)

```text
edit Sources/…
→ ensure-tip for that platform (rebuild if stamp stale)
→ simctl install / clean launch tip
→ agent-device open / screenshot / AX
```

Never: edit UI → `simctl install` yesterday's tip → screenshot → "fixed".

## Hard rejects

- Launch `/Applications/Wawona.app` (or any store/install copy) for tests
- Reuse a tip binary when `git-HEAD` / `product-FP` is missing or product paths drifted
- `WAWONA_TIP_SKIP_BUILD=1` while proving a UI fix you just edited
- Attach Mac2 / agent-device to a leftover process from a different binary
- `WAWONA_ALLOW_STALE_TEST_APP=1` for Appium catalog, Gate UI, or clipping /
  toolbar / AX "fixed" claims
- Claim catalog / platform UI green on a host not tip-built for this HEAD
- macOS product claim from standalone Terminal only (no xcodegen/xcodebuild)

Cursor: `wawona-test-tip-app`. Skill: `wawona-test-tip-app` (+ `wawona-appium`
for GH). Related: `wawona-nix-fresh-build`, `wawona-appium-ui-gh`,
`wawona-test-control`, `wawona-calver-today`.
