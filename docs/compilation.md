# Compilation Guide

Wawona uses **Nix Flakes** for all builds. For the full build pipeline (crate2nix, cross-compilation, layers), see [2026-nix-build-system.md](2026-nix-build-system.md).

## Quick Build

```bash
# macOS app (build + launch)
nix run .#wawona
nix run .#wawona-macos

# Low-RAM / OOM (exit 137 on librsvg). See Troubleshooting below.
./scripts/nix-build-low-mem.sh .#wawona-macos

# Store-shaped macOS vs SIP Desktop Replacement host
nix build .#wawona-macos
nix build .#wawona-macos-desktop-host

# Apple family simulators
nix run .#wawona-ios
nix build .#wawona-watchos-app-sim
nix build .#wawona-tvos-sim
nix build .#wawona-visionos-sim

# Android / Linux
nix run .#wawona-android
nix run .#wawona-linux
```

`--rebuild` is not a Nix flag. Use `nix build --rebuild` only if you mean Nix's
`--rebuild` (force rebuild of a derivation). For a clean tree, `nix build` the
attribute again.

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

`xcodebuild` (including `nix run .#wawona-macos`) may print notes that Run
Script phases will run during **every** build because "Based on dependency
analysis" is unchecked. Those are notes, not errors.

`dependencies/generators/xcodegen.nix` sets `basedOnDependencyAnalysis = false`
for several phases on purpose. Xcode cannot skip them from declared inputs and
outputs. The Nix closure, store copies, and Info.plist edits are not a graph
Xcode can track. On `Wawona-macOS` that includes Stamp Build Number, Build
Rust Backend via Nix (`scripts/xcode-prebuild.sh`), Bundle Executables, and
Strip iOS-only keys from Info.plist (#138).

The **script still runs** every time. Cheap when the store is warm: Nix
cache, `WAWONA_BACKEND_OUT*` copy of a realized `libwawona.a`, or
`WAWONA_SKIP_NIX_PREBUILD=1` for UI-only iteration. By default the prebuild
builds only the **active SDK backend** (device or simulator, not both).

```bash
# One-time warm (full iOS, both device and simulator backends)
nix build .#wawona-ios-backend .#wawona-ios-sim-backend
mkdir -p .nix-gcroots && nix build --out-link .nix-gcroots/xcodegen .#xcodegen

# UI-only iteration. Skip Nix entirely (script still runs, then exits):
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

## Troubleshooting macOS builds

A cold `nix build .#wawona-macos` can fail in **nixpkgs** `librsvg` (build
dep of `pkgs.adwaita-icon-theme`, which supplies Weston cursor assets) with
`Killed: 9` and **exit 137**. That is the OOM killer, not a Wawona recipe
bug. Wawona keeps `pkgs.adwaita-icon-theme`.

| Symptom | Cause | Fix |
|---------|-------|-----|
| `librsvg` / `adwaita-icon-theme` / exit 137 | OOM during nixpkgs compile | FlakeHub login, then low-memory build |
| Full cold compile on a laptop | Not logged into FlakeHub | `determinate-nixd login` |
| Still OOM after login | Parallel jobs exceed RAM | `./scripts/nix-build-low-mem.sh .#wawona-macos` |

Recommended order for new contributors:

```bash
determinate-nixd login
determinate-nixd status   # Logged in: true
./scripts/nix-build-low-mem.sh .#wawona-macos
```

Manual equivalent (the helper defaults to these flags):

```bash
nix build .#wawona-macos --option max-jobs 1 --option cores 2 -L
```

If `librsvg` alone keeps failing, build it first with one core:

```bash
nix build 'nixpkgs#librsvg' --option max-jobs 1 --option cores 1 -L
```

Do not lower flake-wide `max-jobs` / `cores` in `flake.nix`. Those stay
`auto` / `0` for CI. Cache details: [`flakehub-cache.md`](flakehub-cache.md).

## Release beta (TestFlight + Play)

CalVer is `VERSION` (`YY.M.D`). Fastlane lives in this repo. Contributor CI:
[`ci.md`](./ci.md). Secrets: [`maintainers/secrets.md`](./maintainers/secrets.md)
(not for the public site).

```bash
# Tier 0. Docs/maintainers/secrets.md (SecretSpec + pass; sops-nix unlocks GPG)
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
