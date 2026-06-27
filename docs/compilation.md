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

For day-to-day Swift/UI work in Xcode, warm the Nix store once, then skip the pre-build phase on subsequent builds.

```bash
# One-time warm (full iOS, both device and simulator backends)
nix build .#wawona-ios-backend .#wawona-ios-sim-backend
mkdir -p .nix-gcroots && nix build --out-link .nix-gcroots/xcodegen .#xcodegen

# UI-only iteration (after warm store)
export WAWONA_SKIP_NIX_PREBUILD=1

# Skip redundant simulator runtime download during Nix iOS app builds
export WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1
```

After a `Cargo.lock` change, unset `WAWONA_SKIP_NIX_PREBUILD` or rebuild the relevant backend:

```bash
unset WAWONA_SKIP_NIX_PREBUILD
# or: nix build .#wawona-ios-sim-backend
```

Use `nom` / `nb` for cold builds with build visibility. See [2026-nix-build-system.md](2026-nix-build-system.md) for the full pipeline.

## Project Generators

```bash
nix run .#xcodegen      # Generate Wawona.xcodeproj (iOS + macOS)
nix run .#xcodegen-ios  # iOS only
nix run .#gradlegen     # Generate Android Studio project at ./Wawona-gradle-project
nix run .#wawona-wearos # Build and run WearOS flow
```

## Requirements

- Apple Silicon Mac
- Nix with flake support
- Xcode (for iOS)
- `.envrc` with `TEAM_ID` for iOS signing

See [README](../README.md) for environment setup.
