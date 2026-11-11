# Wawona Nix Build System

How Nix compiles everything in this project and feeds the committed Xcode
and Gradle projects.

---

## Overview

Wawona is a cross-platform Wayland compositor. The Rust backend compiles for
**macOS**, **iOS** (device + simulator), and **Android**. The Nix flake
orchestrates every artifact: native C libraries, the Rust backend, the
`.deps` slices the IDE projects read, and final app bundles.

The build is split into three layers:

```
┌──────────────────────────────────────────────────┐
│  Layer 3: App packaging                          │
│  Committed Xcode + Gradle projects over .deps,   │
│  .app / .ipa / .apk bundles                      │
├──────────────────────────────────────────────────┤
│  Layer 2: Rust backend                           │
│  One Cargo build per slice (backend.nix and      │
│  scripts/build-backend.sh)                       │
├──────────────────────────────────────────────────┤
│  Layer 1: Native C/C++ libraries                 │
│  libwayland, xkbcommon, ffmpeg, zstd, lz4,       │
│  openssl, libssh2, mbedtls, zlib, etc.           │
│  Built per-platform in wwn-toolchain / wwn-*     │
└──────────────────────────────────────────────────┘
```

---

## Entry point: `flake.nix`

The flake defines all inputs, overlays, and packages.

### Inputs

Current flake inputs (see `flake.nix`; do not invent extra `wwn-*` edges):

| Input | Layer / role |
|-------|----------------|
| `nixpkgs` | Base package set (unstable) |
| `rust-overlay` | `rust-bin` with Apple/Android targets |
| `crate2nix` | Followed by `wwn-toolchain` and Relay (not Wawona's backend) |
| `microvm` | VM machine type (`wwn-vms`) |
| `nix-appimage` | Linux AppImage packaging |
| `wwn-toolchain` | L0 substrate (cairo, pango, wayland, openssl, …) |
| `iLand` | L1 graphics (ANGLE, SwiftShader, MoltenVK, KosmicKrisp) |
| `wwn-kmscube` | L2 GLES/KMS client |
| `wwn-weston` | L3 nested compositor |
| `wwn-niri` | L3′ nested compositor |
| `wwn-ssh` | OpenSSH (macOS), libssh2 (Apple mobile), OpenSSH portable (Android) |
| `wwn-waypipe` | Remote Wayland |
| `wwn-Wawona Swinging Bridge` | Android Desktop / LockScreen bridge |
| `wwn-vms`, `wwn-containers` | VM and container machine types |

`wwn-apt` was **removed**. Do not document StoreKit `apt install` as a delivery
path; use Wawona Runtime Wasm packages ([`wasm-wasi.md`](./wasm-wasi.md)).
as shipping. Canonical DAG: [`wwn-repo-dag.md`](./wwn-repo-dag.md).

### Rust toolchain overlay

The `rust-overlay` input is used to create a single `rustToolchain` attribute
that includes cross-compilation targets:

```nix
rustToolchain = super.rust-bin.stable.latest.default.override {
  targets = [
    "aarch64-apple-ios"
    "aarch64-apple-ios-sim"
    "aarch64-linux-android"
  ];
};
```

This toolchain is injected into `buildRustCrate` via `.override { cargo = ...; rustc = ...; }`.

### Source filtering (`srcFor`)

`srcFor` creates a filtered source tree containing only what Cargo needs:
`Cargo.toml`, `Cargo.lock`, `VERSION`, `build.rs`, `src/`, `protocols/`,
`scripts/`, `include/`. Everything under `dependencies/` (Nix modules) is
excluded since those are injected separately as Nix derivations.

---

## Layer 1: Native C/C++ libraries

### Directory structure

Wawona keeps only the **integration layer** under `dependencies/`. Library recipes and toolchains live in flake inputs (`wwn-toolchain`, `wwn-weston`, `iLand`, …). `flake.nix` merges their registries and injects store paths into `pkgs`.

```
dependencies/                 # Wawona integration (this repo)
├── wawona/                   # App derivations, Rust backends, devshells
├── generators/               # uniffi-bindgen, Android icons
├── clients/                  # wawona-shell, wawona-tools
└── gradle-deps.nix           # Gradle mirror for Android Studio

wwn-toolchain/                # upstream flake input
├── dependencies/libs/        # Per-library build recipes (ffmpeg, libwayland, …)
├── dependencies/toolchains/  # buildForIOS, buildForMacOS, buildForAndroid
├── dependencies/android/     # sdk-config.nix (canonical Android version pins)
└── dependencies/apple/       # Xcode wrapper + signing helpers

wwn-weston/, iLand/, …    # upstream app ports + ldflags generators
```

For local development against sibling checkouts:

```nix
wwn-toolchain.url = "path:../wwn-toolchain";
```

### How native libraries are built

Each library has per-platform `.nix` files in the upstream `wwn-*` repos (e.g. `wwn-toolchain/dependencies/libs/lz4/ios.nix`). These
are standard `pkgs.stdenv.mkDerivation` recipes that cross-compile the C/C++
source for the target platform. For iOS, they use Xcode's clang with
`-miphoneos-version-min=26.0` and the appropriate `-target` triple. For
Android, they use the NDK toolchain.

`wwn-toolchain.lib.mkToolchains` acts as a dispatcher. It
exports three main functions:

- `buildForIOS name entry`. Dispatches to `libs/<name>/ios.nix`
- `buildForMacOS name entry`. Dispatches to `libs/<name>/macos.nix`
- `buildForAndroid name entry`. Dispatches to `libs/<name>/android.nix`

If no library-specific recipe exists, it falls back to the generic builder in
`platforms/<platform>.nix`.

In `flake.nix`, the toolchains are instantiated once:

```nix
toolchains = mkWawonaToolchains { inherit pkgs androidSDK wawonaSrc; };
```

Then individual libraries are passed as `nativeDeps` to the Rust backend:

```nix
nativeDeps = {
  xkbcommon  = toolchains.ios.xkbcommon;
  libffi     = toolchains.ios.libffi;
  libwayland = toolchains.ios.libwayland;
  zstd       = toolchains.ios.zstd;
  lz4        = toolchains.ios.lz4;
  zlib       = toolchains.buildForIOS "zlib" { simulator = true; };
  openssl    = toolchains.buildForIOS "openssl" { simulator = true; };
  # ...
};
```

Each of these is a standalone Nix derivation. Nix caches them individually -
changing `zstd` does not rebuild `openssl`.

---

## Layer 2: Rust backend

`dependencies/wawona/backend.nix` builds `libwawona` for one slice (an Xcode
`PLATFORM_NAME`, `iphoneos-modeb`, `android` or `linux`). It is one
derivation per slice that runs `scripts/build-backend.sh`: the crates come
from `Cargo.lock` through `rustPlatform.importCargoLock`, the native libraries
from `nativeDeps`, and the target triple, deployment floor and features from
the slice. The derivation also writes the script's environment to `$out/env`.

`nix run .#deps -- <slice>` links that output into `.deps/<slice>/backend`, so
the same script run in a checkout builds the working tree with the same
toolchain, vendored crates and native libraries, incrementally in `target/`,
and stages `.build/backend/<slice>` for Xcode or Gradle:

```
Cargo.lock ── importCargoLock ──┐
nativeDeps (Layer 1) ───────────┼─► backend.nix ─► $out/lib/libwawona.a + $out/env
slice (triple, floor, features) ┘          │
                                           ▼
             nix run .#deps ─► .deps/<slice>/backend ─► scripts/build-backend.sh
                                                       ─► .build/backend/<slice>
```

`workspace-src.nix` assembles the Cargo workspace the derivation builds: the
filtered Wawona source with the patched waypipe source injected at
`./waypipe/` and `[[bin]]` sections stripped, so cross builds do not link
unused binaries.

---

## Layer 3: App packaging

The committed `Wawona.xcodeproj` and root Gradle project are the only app
projects; Nix products build them as an IDE does.

- **Apple** (`dependencies/wawona/ios.nix`, `macos.nix`): links the slice
  `deps.nix` makes for the SDK into `.deps`, then runs `xcodebuild` on the
  target's scheme. `scripts/xcode-prebuild.sh` stages `libwawona.a`, zsh and
  fastfetch; `scripts/xcode-embed.sh` copies the slice's `bundle/`. Signing
  comes from `TEAM_ID` or the match profiles in `fastlane/`.
- **Android** (`dependencies/wawona/android.nix`): runs the root Gradle
  project offline over `android-deps.nix` (jniLibs, assets, `shader_spv.h`)
  with `-Pwawona.maven=` pointing at the Nix Maven mirror.

Host Xcode is state outside Nix. `wwn-toolchain/dependencies/apple/` exports
the Xcode wrapper and SDK checks; CI pins the app with
`cargo xtask ci select-xcode` (Xcode 27 only, never "newest installed").

---

## Build commands

| Command | What it builds |
|---|---|
| `nix run .#deps -- <sdk>...` | Links `.deps/<sdk>` for the IDE projects |
| `nix run .#wawona-macos` | macOS app (build + launch) |
| `nix build .#wawona-<ios,ipados,tvos,watchos,visionos>-app-sim` | Simulator apps |
| `nix build .#wawona-ios-ipa` (and other platforms' `-ipa`) | Signed store IPAs |
| `nix run .#wawona-ios-trollstore` / `.#wawona-ios-jailbreak` | Mode B tipa / Sileo `.deb` on vphone |
| `nix build .#wawona-android` / `.#wawona-android-aab` | APK / AAB |
| `nix build .#wawona-<platform>[-sim]-backend` | One slice's Rust static library |

---

## Caching behavior

- A Rust source change rebuilds the slice's backend derivation; locally,
  `scripts/build-backend.sh` rebuilds only what Cargo's incremental state
  says changed.
- A native library change rebuilds that library, then each backend that
  links it.
- Each slice is its own derivation: switching iOS simulator to device builds
  the other slice, and the first stays cached.

---

## File reference

| File | Role |
|---|---|
| `flake.nix` | Inputs, overlays, packages, the `deps` app |
| `dependencies/wawona/backend.nix` | Rust backend per slice |
| `scripts/build-backend.sh` | The backend build, in Nix and in a checkout |
| `dependencies/wawona/deps.nix` | Apple slices behind `.deps/<sdk>` |
| `dependencies/wawona/android-deps.nix` | Android slice behind `.deps/android` |
| `dependencies/wawona/workspace-src.nix` | Cargo workspace assembly |
| `dependencies/wawona/ios.nix`, `macos.nix`, `android.nix` | Product builds of the committed projects |
| `Wawona.xcodeproj/project.xcproj`, `settings.gradle.kts` | The IDE projects |
| `wwn-toolchain/dependencies/libs/*/` | Per-library cross-compilation recipes |
