# Wawona Nix Dependencies

This directory is the **integration layer** for building Wawona on Apple, Android, and Linux targets. Cross-compiled libraries, toolchains, and ldflags generators live in upstream `wwn-*` flake inputs (`wwn-toolchain`, `wwn-weston`, `wwn-iland`, …); `flake.nix` injects their store paths into `pkgs` so recipes here never fall back to stale in-tree copies.

## Directory Structure

```
dependencies/
├── README.md                     # This file
├── wawona/                       # App derivations, backends, devshells
│   ├── mobile-platform-deps.nix  # Shared native closure for Apple mobile
│   ├── apple-host-crates.nix     # Shared host-side Rust crate graph
│   ├── rust-backend-c2n.nix      # Per-platform libwawona.a (crate2nix)
│   └── devshells.nix             # `nix develop` shell
├── clients/                      # Wawona shell/tools (integration-only)
├── generators/                   # xcodegen.nix, gradlegen.nix, android-icon helpers
├── gradle-deps.nix               # Gradle dependency mirror for Android Studio
└── smoke-test-lists.nix          # CI smoke targets
```

Canonical upstream locations:

| Concern | Repo / path |
|---------|-------------|
| Apple toolchain, Android SDK config, mobile-base ldflags | `wwn-toolchain` |
| Weston toytoolkit/compositor ldflags, simple-shm | `wwn-weston` |
| iland/ANGLE ldflags | `wwn-iland` |
| Per-lib build recipes (`libs/*`, `toolchains/*`) | respective `wwn-*` inputs via `mergedRegistry` |

## Local dev override

Point flake inputs at sibling checkouts when iterating on toolchain changes:

```nix
wwn-toolchain.url = "path:../wwn-toolchain";
wwn-weston.url = "path:../wwn-weston";
```

Then run `nix flake lock --update-input wwn-toolchain` (and peers) after upstream edits.

## Apple Targets

| OS | Rust backend | Notes |
|----|--------------|-------|
| iOS | `wawona-ios-backend`, `wawona-ios-sim-backend` | Full stack: Weston toytoolkit + compositor (Wayland+DRM), iland, ANGLE |
| iPadOS | `wawona-ipados-backend`, `wawona-ipados-sim-backend` | Same triple as iOS; ipados recipes re-export ios.nix |
| tvOS | `wawona-tvos-backend`, `wawona-tvos-sim-backend` | No iland/ANGLE |
| watchOS | `wawona-watchos-backend`, `wawona-watchos-sim-backend` | No waypipe |
| visionOS | `wawona-visionos-backend`, `wawona-visionos-sim-backend` | Slimmer network stack |
| macOS | `wawona-macos-backend` | Native host build |

## Xcode Prebuild

Xcode targets run `scripts/xcode-prebuild.sh` before linking. It realizes only the backend for the active target **and SDK** (device vs simulator). After warming the store:

```bash
export WAWONA_SKIP_NIX_PREBUILD=1   # Swift/UI iteration
```

See [docs/compilation.md](../docs/compilation.md) for the full contributor workflow.

## Project Generators

```bash
nix run .#xcodegen          # All Apple targets (CI)
nix run .#xcodegen-ios      # iOS + iPadOS only (faster)
nix run .#xcodegen-macos    # macOS only
nix run .#gradlegen         # Android Studio project
```

## Key Concepts

| Directory | Purpose |
|-----------|---------|
| `wawona/` | Final apps, Rust backends, mobile dep factory |
| `clients/` | Wawona-specific shell/tools wrappers |
| `generators/` | Xcode/Gradle project generation (imports ldflags from wwn-* via flake) |
