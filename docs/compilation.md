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

## Project Generators

```bash
nix run .#xcodegen      # Generate Wawona.xcodeproj (iOS + macOS)
nix run .#xcodegen-ios  # iOS only
nix run .#gradlegen     # Generate Gradle project for Android
```

## Requirements

- Apple Silicon Mac
- Nix with flake support
- Xcode (for iOS)
- `.envrc` with `TEAM_ID` for iOS signing

See [README](../README.md) for environment setup.
