# Compilation Guide

Product Apple and Android apps build through **Exact bun hosts** plus
`cargo xtask`. There is no committed `Wawona.xcodeproj` and no root Gradle
product project. Darwin builders still need Xcode 27 (SDK, `swiftc`,
`codesign`). Android builders still need the NDK/SDK Exact's host uses.

What Exact cannot build alone (cross-compiled C libraries, vendored crates)
arrives as prebuilt dependency slices in `.deps/`. `cargo xtask` stages
`libwawona` and sets `WAWONA_LINK_ARGS` for Exact's module link.

Nix builds the slices in CI (`deps.yml`) and builds Linux. Layers:
[2026-nix-build-system.md](2026-nix-build-system.md).

## Daily loop

```bash
# Sibling Exact checkout (or EXACT_ROOT=…).
cargo xtask deps get macosx iphonesimulator android src

# Exact Contract chrome + Present (build then launch).
# From Wawona/, `cargo app` / `cargo dev` alias Exact tip macOS
# (same as `cargo xtask run macos`). Cargo shadows a user alias named
# `run`, so do not use plain `cargo run` for the product app.
cargo app
cargo xtask run macos
cargo xtask run ios
# Build only:
cargo xtask build macos
cargo xtask build ios
# Device IPA for Fastlane:
cargo xtask archive ios   # needs EXACT_IDENTITY + EXACT_PROFILE, or unsigned

# Tip for Appium / agent-device
eval "$(WAWONA_TEST_REBUILD=1 cargo xtask tip macos)"
```

### `cargo app` / `cargo dev` vs `cargo build` / `cargo check`

From `Wawona/`, **`cargo app`** and **`cargo dev`** (see `.cargo/config.toml`)
invoke `cargo xtask run macos`: Exact tip build then launch. That is the
product dogfood path (Exact hosts + `libwawona`). iOS sim and other hosts
still need `cargo xtask run <host>`.

Plain `cargo run` is Cargo's built-in (linux-ui bins need `--features linux-ui`).
It does **not** open the Exact product app.

Plain `cargo build` / `cargo check` on the Rust crate need path crates
`./coreutils` and `./waypipe` (symlinks from `cargo xtask deps get src`).
`build.rs` soft-links them when `.deps/src` already exists. If that slice is
missing, Cargo fails with missing `coreutils/Cargo.toml`. Fix:
`cargo xtask deps get src` (or any `deps get` that expands `src`).

Exact dogfood without xtask:

```bash
cd ../exact
EXACT_APP_DIR=apps/wawona bun host/apple/build.mjs --ios wawona-apple --no-install
# Signed store IPA:
EXACT_IDENTITY=… EXACT_PROFILE=… bun host/apple/build.mjs --device wawona-apple --archive /tmp/Wawona.ipa
```

## Ship

Fastlane `ios beta` / `release` call `gym_ipa`, which runs
`cargo xtask archive <target>` (Exact IPA), then ASC asserts
(`assert_no_loose_dylibs!`, `assert_ipa_has_swift_support!`, …) and Pilot /
deliver. Watch companion is skipped (`WAWONA_SKIP_WATCH=1`) until Exact
embeds `--watchos`.

Android Play: `cargo xtask archive android` → Exact AAB → Fastlane upload.

## Every host (`cargo xtask`, not Nix)

```bash
cargo xtask build web
cargo xtask build windows      # cargo check on Darwin; MSVC package on Windows
cargo xtask build linux        # Exact Linux host, headless on macOS
cargo xtask build asteroidos   # host-machine binary
cargo xtask build wearos       # Android Canvas APK with the watch manifest
cargo xtask test all           # every ALL_TARGETS host, then a summary
```

`cargo xtask test all` also builds macos, ios, ipados, tvos, visionos, watchos, and android.

## Requirements

- Apple Silicon Mac on macOS 27, Xcode 27 (SDK 27)
- Sibling Exact checkout with Bun
- Rust from `rust-toolchain.toml`
- Product Exact iOS floor **17.0** (Exact host). See
  [agent-rules/wawona-ios-min-os.md](agent-rules/wawona-ios-min-os.md)
- `TEAM_ID` / match profiles for device archive
- Nix for `--nix` slices and Linux

## Exact Present

`apps/wawona/modules/apple/Present.swift` registers `wayland-present`.
Contract Focus/Start on a running machine mounts it
(`testId="wwn.compositor.surface"`). `libwawona` resolves at runtime when
`WAWONA_LINK_ARGS` linked it.

## Retired

- `Wawona.xcodeproj` / XcodeGen
- Root Gradle / `android/app` Compose product host
- Opening Xcode or Android Studio as the product authoring surface
