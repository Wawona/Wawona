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
cargo xtask deps get macosx iphonesimulator android

# Exact Contract chrome + Present NativeView (wayland-present).
cargo xtask build macos
cargo xtask build ios
# Device IPA for Fastlane:
cargo xtask archive ios   # needs EXACT_IDENTITY + EXACT_PROFILE, or unsigned

# Tip for Appium / agent-device
eval "$(WAWONA_TEST_REBUILD=1 cargo xtask tip macos)"
```

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

## Linux

```bash
nix build .#wawona-linux .#wawona-appimage   # on Linux
nix run .#terminal
```

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
