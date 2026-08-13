# Compilation Guide

Wawona uses **Nix Flakes** for all builds. For the full build pipeline (crate2nix, cross-compilation, layers), see [2026-nix-build-system.md](2026-nix-build-system.md).

## Quick Build

```bash
# macOS app (build + launch)
nix run .#wawona

# iOS Simulator app
nix run .#wawona-ios

# Android app
nix run .#wawona-android
```

## Build Monitoring With `nom`

`nix-output-monitor` is integrated into the flake:

```bash
# Run nom from the flake
nix run .#nom -- build .#wawona-macos

# If you are already in nix develop
nom build .#wawona-macos
nb .#wawona-macos   # alias for `nom build`
```

## Build (without run)

```bash
nix build .#wawona-macos
nix build .#wawona-ios-backend
nix build .#wawona-android-backend
```

## Common Flags

| Flag | Purpose |
|------|---------|
| `-L` | Print full build logs |
| `--show-trace` | Stack trace on Nix evaluation errors |

## Xcode Iteration

The Xcode pre-build phase is **incremental**: it only runs when declared inputs
(`Cargo.lock`, `flake.nix`, `Cargo.toml`, `xcode-prebuild.sh`) have changed.
By default it builds only the **active SDK backend** (device or simulator, not
both), cutting ~50% of Nix work on each rebuild.

```bash
# One-time warm (full iOS, both device and simulator backends)
nix build .#wawona-ios-backend .#wawona-ios-sim-backend
mkdir -p .nix-gcroots && nix build --out-link .nix-gcroots/xcodegen .#xcodegen

# UI-only iteration — no special env needed; prebuild auto-skips when inputs
# are unchanged. For explicit skip (no Nix at all):
export WAWONA_SKIP_NIX_PREBUILD=1

# Release builds that want both device+sim warm in one pass:
export WAWONA_WARM_BOTH_BACKENDS=1

# Skip redundant simulator runtime download during Nix iOS app builds
export WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1

# CI product-build (ios-sim + apple-family) / device-e2e / frontend-syntax set the
# skip flag via `.github/scripts/warm-ios-simulator-sdk.sh` when the requested
# simulator SDK is present (`ios`, `ipados`, `tvos`, `watchos`, `visionos`, or `all`).
# Product `.#wawona-ios` uses `xcodegenIosSimOutputs` (ios-only + simulatorOnly).
# Nix product builds also pass `WAWONA_BACKEND_OUT*` so xcode-prebuild copies
# `libwawona.a` instead of nested-compiling the Rust backend during xcodebuild.
```

After a `Cargo.lock` change, unset `WAWONA_SKIP_NIX_PREBUILD` or rebuild the relevant backend:

```bash
unset WAWONA_SKIP_NIX_PREBUILD
# or: nix build .#wawona-ios-sim-backend
```

Use `nom` / `nb` for cold builds with build visibility. See [2026-nix-build-system.md](2026-nix-build-system.md) for the full pipeline.

## FlakeHub Cache (shared org binary cache)

To pull prebuilt Layer-1/`wwn-*` store paths on a laptop (same cache CI uses):

```bash
determinate-nixd login   # once per machine
determinate-nixd status  # Logged in: true
```

Details, limits (forks / anonymous cold rebuild), and CI fragment:
[`flakehub-cache.md`](flakehub-cache.md).

## Project Generators

```bash
nix run .#xcodegen      # Generate Wawona.xcodeproj (iOS + macOS)
nix run .#xcodegen-ios  # iOS only
nix run .#gradlegen     # Generate ./Wawona-gradle-project for Android Studio
```

## Requirements

- Apple Silicon Mac
- Nix with flake support
- Xcode (for iOS)
- `.envrc` with `TEAM_ID` for iOS signing

See [README](../README.md) for environment setup.

## Release beta (TestFlight + Play)

Wawona v2.5 adds Fastlane automation. See [wwn-mcp/knowledge/wawona/fastlane.md](../../wwn-mcp/knowledge/wawona/fastlane.md).

```bash
# Tier 0 — docs/maintainers/secrets.md (SecretSpec + pass; sops-nix unlocks GPG)
./scripts/setup-release-secrets.sh                      # verify pass + secretspec
./scripts/bootstrap-apple-signing.sh                    # one-time match → apple-signing repo
./scripts/sync-github-secrets.sh                        # pass → GitHub Environment release-beta

nix develop .#release
secretspec check -P local
./scripts/release-env.sh fastlane ios beta              # match + gym + TestFlight
./scripts/release-env.sh fastlane android beta          # Play internal
```

Signed IPAs: `TEAM_ID=… nix build .#wawona-ios-ipa --impure` (also ipados/tvos/watchos/visionos variants).

Android AAB: `nix build .#wawona-android-aab` with `ANDROID_KEYSTORE_*` env vars set.
