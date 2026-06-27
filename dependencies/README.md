# Wawona Nix Dependencies

This directory contains the Nix infrastructure for building Wawona on Apple, Android, and Linux targets.

## Directory Structure

```
dependencies/
├── README.md                     # This file
├── toolchains/                   # Cross-compilation (buildForIOS, buildForMacOS, …)
├── wawona/                       # App derivations, backends, devshells
│   ├── mobile-platform-deps.nix  # Shared native closure for Apple mobile
│   ├── apple-host-crates.nix     # Shared host-side Rust crate graph
│   ├── rust-backend-c2n.nix      # Per-platform libwawona.a (crate2nix)
│   └── devshells.nix             # `nix develop` shell
├── libs/                         # Cross-compiled C libraries
├── clients/                      # Weston compositor, foot, …
│   └── weston/                   # toytoolkit + compositor-apple-mobile.nix
├── platforms/                    # Per-OS build dispatchers (ios, ipados, …)
├── generators/                   # xcodegen.nix, gradlegen.nix, ldflags helpers
└── utils/                        # Xcode wrapper helpers
```

## Apple Targets

| OS | Rust backend | Notes |
|----|--------------|-------|
| iOS | `wawona-ios-backend`, `wawona-ios-sim-backend` | Full stack: Weston, compositor, iland, ANGLE |
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
| `toolchains/` | Cross-compiles C libraries per platform |
| `wawona/` | Final apps, Rust backends, mobile dep factory |
| `libs/` | Low-level C libraries |
| `clients/weston/` | Weston toytoolkit + compositor archives |
| `generators/` | Xcode/Gradle project generation |
| `platforms/` | Routes dependency names to per-lib recipes |
