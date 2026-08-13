# Wawona Nix Build System

How Nix compiles everything in this project, and how crate2nix provides
per-crate caching for the Rust backend.

---

## Overview

Wawona is a cross-platform Wayland compositor. The Rust backend compiles for
**macOS**, **iOS** (device + simulator), and **Android**. The Nix flake
orchestrates every artifact: native C libraries, the Rust backend, Xcode
project generation, and final app bundles.

The build is split into three layers:

```
┌──────────────────────────────────────────────────┐
│  Layer 3: App packaging                          │
│  Xcode project (.xcodeproj), .app bundles,       │
│  Gradle project, simulator automation            │
├──────────────────────────────────────────────────┤
│  Layer 2: Rust backend (crate2nix)               │
│  Per-crate Nix derivations for wawona + waypipe  │
│  Cross-compiled via stdenv.hostPlatform override  │
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
| `crate2nix` | Per-crate Nix from `Cargo.lock` |
| `microvm` | VM machine type (`wwn-vms`) |
| `nix-appimage` | Linux AppImage packaging |
| `wwn-toolchain` | L0 substrate (cairo, pango, wayland, openssl, …) |
| `wwn-iland` | L1 graphics (ANGLE, SwiftShader, MoltenVK, KosmicKrisp) |
| `wwn-kmscube` | L2 GLES/KMS client |
| `wwn-weston` | L3 nested compositor |
| `wwn-niri` | L3′ nested compositor |
| `wwn-zsh`, `wwn-coreutils`, `wwn-foot`, `wwn-neovim`, `wwn-fastfetch`, `wwn-phoon-rs` | Bundled on-device clients |
| `wwn-ssh` | OpenSSH (macOS), libssh2 (Apple mobile), OpenSSH portable (Android) |
| `wwn-waypipe` | Remote Wayland |
| `wwn-anowaW` | Android Desktop / LockScreen bridge |
| `wwn-vms`, `wwn-containers` | VM and container machine types |

`wwn-apt` is **not** a Wawona flake input. Do not document StoreKit `apt install`
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

Wawona keeps only the **integration layer** under `dependencies/`. Library recipes and toolchains live in flake inputs (`wwn-toolchain`, `wwn-weston`, `wwn-iland`, …). `flake.nix` merges their registries and injects store paths into `pkgs`.

```
dependencies/                 # Wawona integration (this repo)
├── wawona/                   # App derivations, Rust backends, devshells
├── generators/               # xcodegen.nix, gradlegen.nix
├── clients/                  # wawona-shell, wawona-tools
└── gradle-deps.nix           # Gradle mirror for Android Studio

wwn-toolchain/                # upstream flake input
├── dependencies/libs/        # Per-library build recipes (ffmpeg, libwayland, …)
├── dependencies/toolchains/  # buildForIOS, buildForMacOS, buildForAndroid
├── dependencies/android/     # sdk-config.nix (canonical Android version pins)
└── dependencies/apple/       # Xcode wrapper + signing helpers

wwn-weston/, wwn-iland/, …    # upstream app ports + ldflags generators
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

- `buildForIOS name entry` — dispatches to `libs/<name>/ios.nix`
- `buildForMacOS name entry` — dispatches to `libs/<name>/macos.nix`
- `buildForAndroid name entry` — dispatches to `libs/<name>/android.nix`

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

Each of these is a standalone Nix derivation. Nix caches them individually —
changing `zstd` does not rebuild `openssl`.

---

## Layer 2: Rust backend with crate2nix

### Why crate2nix?

The previous approach used `buildRustPackage`, which treats the entire Cargo
workspace as a single derivation. Any change to any Rust file or dependency
forced a full rebuild of everything — tens of minutes for a one-line change.

**crate2nix** solves this by generating a separate Nix derivation for every
crate in `Cargo.lock`. Nix's content-addressed store caches each crate
individually. Changing one crate (e.g. `waypipe`) only rebuilds that crate
and its reverse dependencies. Unchanged crates are served from cache.

### The pipeline

```
Cargo.toml + Cargo.lock
        │
        ▼
crate2nix.tools.generatedCargoNix    ← reads Cargo.lock, emits Cargo.nix
        │
        ▼
import Cargo.nix { buildRustCrateForPkgs = ...; }
        │
        ▼
cargoNix.rootCrate.build.override { crateOverrides = ...; features = ...; }
        │
        ▼
Per-crate Nix derivations (each one is a separate /nix/store entry)
        │
        ▼
Final libwawona.a / libwawona_core.so assembled in installPhase
```

### Workspace source assembly (`workspace-src.nix`)

Before crate2nix can run, we need a Cargo workspace that includes both
`wawona` (the root crate) and `waypipe` (an optional in-tree dependency).
`workspace-src.nix` does this:

1. Copies the filtered wawona source
2. Injects pre-patched waypipe source at `./waypipe/`
3. Patches `Cargo.toml` to set `autobins = false` and strip `[[bin]]`
   sections (prevents cross-compilation linker errors for unused binaries)

The waypipe source is patched separately per-platform via
`waypipe-patched-src.nix` + `patch-waypipe-source.sh`. This means changing
the patch script only invalidates the waypipe source derivation, not the
entire Rust build.

### `rust-backend-c2n.nix` in detail

This is the core file. It accepts:

| Parameter      | Type     | Description                                       |
|----------------|----------|---------------------------------------------------|
| `platform`     | string   | `"macos"`, `"ios"`, or `"android"`                |
| `simulator`    | bool     | iOS only: target the simulator                    |
| `workspaceSrc` | drv      | Assembled Cargo workspace (from workspace-src.nix)|
| `nativeDeps`   | attrset  | Pre-built native libraries for the target platform|
| `crate2nix`    | flake    | The crate2nix tools                               |
| `nixpkgs`      | flake    | The nixpkgs source                                |

#### Target triples

| Platform          | Cargo target                 | Linker target                         |
|-------------------|------------------------------|---------------------------------------|
| macOS             | (native, no `--target`)      | —                                     |
| iOS device        | `aarch64-apple-ios`          | `arm64-apple-ios26.0`                 |
| iOS simulator     | `aarch64-apple-ios-sim`      | `arm64-apple-ios26.0-simulator`       |
| Android           | `aarch64-linux-android`      | via NDK linker wrapper                |

#### Cross-compilation strategy

For macOS builds, `buildRustCrate` runs natively — no cross-compilation
needed.

For iOS and Android, we face a fundamental problem: nixpkgs'
`buildRustCrate` uses `stdenv.hostPlatform` to set environment variables
like `TARGET`, `CARGO_CFG_TARGET_OS`, and the `--target` flag for rustc.
When building on macOS, `hostPlatform` is `aarch64-apple-darwin`, so
everything gets compiled for macOS by default.

The solution: **override `stdenv.hostPlatform`** in the cross
`buildRustCrate`. This makes nixpkgs' internal `configure-crate.nix`
correctly set:

- `TARGET=aarch64-apple-ios-sim` (or `aarch64-apple-ios`)
- `CARGO_CFG_TARGET_OS=ios`
- `CARGO_CFG_TARGET_ARCH=aarch64`
- `--target aarch64-apple-ios-sim` passed to rustc

This produces correctly-tagged Mach-O objects from the start (platform 7 for
iOS Simulator, platform 2 for iOS device). No binary patching required.

The override is surgical — we only change the fields that `configure-crate.nix`
and `build-crate.nix` actually read:

```nix
crossHostPlatform = base // {
  config = "aarch64-apple-ios-simulator";
  system = "aarch64-apple-ios-simulator";
  parsed = base.parsed // {
    kernel = base.parsed.kernel // { name = "ios"; };
  };
  rust = {
    rustcTarget    = "aarch64-apple-ios-sim";
    rustcTargetSpec = "aarch64-apple-ios-sim";
    platform       = { arch = "aarch64"; os = "ios"; };
  };
};

crossStdenv = pkgs.stdenv // { hostPlatform = crossHostPlatform; };

crossBRC = pkgs.buildRustCrate.override {
  stdenv = crossStdenv;
  cargo  = pkgs.rustToolchain;
  rustc  = pkgs.rustToolchain;
};
```

#### Dual build: host + cross

Each crate is lazily built twice via `mkCrossBRC`:

```
┌─────────────────────────┐     ┌─────────────────────────┐
│  hostBuild (macOS)      │     │  crossBuild (iOS)       │
│  - proc-macro crates    │     │  - regular crates       │
│  - build script deps    │     │  - extraRustcOpts for   │
│  - rlibs for linking    │     │    native lib paths     │
│    build scripts        │     │  - crossPreConfigure    │
└─────────────────────────┘     └─────────────────────────┘
         │                                │
         └──── hostLib ◄──────────────────┘
               (lazy: only evaluated when referenced)
```

- **Proc-macro crates** (`procMacro = true`): built entirely for the host
  (macOS). Proc-macro dylibs run at compile time on the build machine.
- **Regular crates**: cross-built via `crossBRC`. Their build dependencies
  are swapped to host versions (`.hostLib`) so build scripts can link and
  run on macOS.
- **Laziness**: Nix only evaluates `hostBuild` when `.hostLib` is actually
  referenced. If a crate has no build script and isn't a proc-macro, the
  host build is never computed.

#### cc-rs and the Nix sandbox

Many `-sys` crates (e.g. `libz-sys`, `libssh2-sys`) use the `cc-rs` crate
to compile bundled C code. When `cc-rs` detects an iOS target, it tries to
find the iOS SDK via `xcrun --show-sdk-path`. This fails in the Nix sandbox
because Xcode isn't available.

The workaround uses three environment variables set in `crossPreConfigure`:

```nix
crossPreConfigure = ''
  unset MACOSX_DEPLOYMENT_TARGET
  export IPHONEOS_DEPLOYMENT_TARGET="26.0"
  export CC_aarch64_apple_ios_sim="${rawClang} -target arm64-apple-ios26.0-simulator"
  export CFLAGS_aarch64_apple_ios_sim="-target arm64-apple-ios26.0-simulator -fPIC"
  export CRATE_CC_NO_DEFAULTS="1"
'';
```

- `unset MACOSX_DEPLOYMENT_TARGET` — prevents cc-rs from injecting
  `--target=arm64-apple-macosx`
- `CC_<target>` / `CFLAGS_<target>` — target-specific overrides that cc-rs
  reads; provides clang with the correct `-target` flag
- `CRATE_CC_NO_DEFAULTS=1` — tells cc-rs to skip all default flag detection,
  including the `xcrun` SDK lookup

This works because the C sources bundled in `-sys` crates (zlib, libssh2,
etc.) ship their own headers and don't need system SDK headers.

#### Per-crate overrides

Some crates need extra configuration beyond what `buildRustCrate` provides
automatically. These are specified in `crateOverrides`:

| Crate                    | Override reason                                     |
|--------------------------|-----------------------------------------------------|
| `wawona`                 | Root crate: pkg-config, buildInputs, crateType      |
| `wayland-backend`        | Patches `target_os = "macos"` → `any(macos, ios)`   |
| `wayland-sys`            | pkg-config path for libwayland                      |
| `libssh2-sys`            | C_INCLUDE_PATH for zlib/openssl headers              |
| `openssl-sys`            | OPENSSL_DIR, static linking config                  |
| `waypipe-ffmpeg-wrapper` | pkg-config, rust-bindgen, vulkan-headers includes    |
| `waypipe-lz4-wrapper`    | pkg-config for lz4                                  |
| `waypipe-zstd-wrapper`   | pkg-config for zstd                                 |
| `xkbcommon`              | Platform-conditional xkbcommon library               |

#### Features

| Platform | Enabled features | Why                                                      |
|----------|------------------|----------------------------------------------------------|
| macOS    | (none)           | No waypipe integration in the macOS backend              |
| iOS      | `waypipe-ssh`    | In-process waypipe with static libssh2 (no subprocess)   |
| Android  | `waypipe`        | In-process waypipe                                       |

The `waypipe-ssh` feature enables `waypipe` + `waypipe/with_libssh2`, pulling
in SSH transport support compiled into the static library.

In `src/lib.rs`, `extern crate waypipe;` forces the linker to include
waypipe's symbols in `libwawona.a` even though wawona's Rust code doesn't
directly call them. Without this, rustc's dead code elimination would strip
`waypipe_main` from the archive.

#### Output

The final derivation (`stdenvNoCC.mkDerivation`) assembles:

- `$out/lib/libwawona.a` — static library (iOS, macOS)
- `$out/lib/libwawona_core.so` — shared library (Android, macOS)
- `$out/bin/` — CLI tools (macOS only)
- `$out/uniffi/` — generated Swift bindings (macOS only)

---

## Layer 3: App packaging

### iOS (`dependencies/wawona/ios.nix`)

The iOS app is built in two stages:

1. **Nix build** (`wawona-ios` derivation): compiles Obj-C source files with
   Xcode's clang, links against `libwawona.a` and all native C libraries,
   produces a `.app` bundle.

2. **Simulator automation** (`passthru.automationScript`): generates an Xcode
   project via `xcodegen.nix`, builds it with `xcodebuild` for the iOS
   Simulator, installs the app, and launches it. Pass `--debug` to pause at
   spawn and attach LLDB for crash/freeze debugging.

The automation script is what `nix run .#wawona-ios` invokes.

### Shared Apple wrapper layer (`wwn-toolchain/dependencies/apple/default.nix`)

Apple host assumptions are centralized in the `wwn-toolchain` flake input:

- Host Xcode discovery (`XCODE_APP`, `xcode-select`, newest `/Applications/Xcode*.app`)
- Xcode wrapper command for PATH/DEVELOPER_DIR normalization
- SDK verification helpers (`ensure-ios-sdk`, `ensure-ios-sim-sdk`, `ensure-macos-sdk`)
- Simulator and provisioning scripts exported as flake apps

This replaces scattered Xcode bootstrap logic and gives iOS/macOS one source of truth.

### macOS (`dependencies/wawona/macos.nix`)

Standard `mkDerivation` that compiles Obj-C sources and links against the
macOS Rust backend. Produces a `.app` bundle that `nix run .#wawona` opens
via `open -W`.

### Android (`dependencies/wawona/android.nix`)

Produces an Android project with the NDK-compiled native libraries and Rust
backend. Uses Gradle for the final APK build.

### Xcode project generation (`dependencies/generators/xcodegen.nix`)

Generates a `project.yml` consumed by `xcodegen` to produce
`Wawona.xcodeproj`. The generated project references Nix-built static
libraries and headers from the Nix store. It can optionally include or
exclude the macOS target (`includeMacOSTarget`).

---

## CI Apple runner assumptions

The Darwin workflow (`.github/workflows/nix.yml`) now treats host Xcode as explicit bootstrap state:

- Select highest installed `Xcode*.app` with `sort -V | tail -1`
- Export `XCODE_APP` and run `xcode-select -s "$XCODE_APP"` before Nix builds
- Keep path coupling in CI/bootstrap only; build modules read normalized Apple env from `wwn-toolchain` (`dependencies/apple/`)

---

## Build commands

| Command                              | What it builds                             |
|--------------------------------------|--------------------------------------------|
| `nix run .#wawona`                   | macOS app (build + launch)                 |
| `nix run .#wawona-ios`               | iOS Simulator app (xcodegen + build + run) |
| `nix run .#wawona-android`           | Android app                                |
| `nix build .#wawona-macos-backend`   | Just the macOS Rust static library         |
| `nix build .#wawona-ios-backend`     | Just the iOS device Rust static library    |
| `nix build .#wawona-ios-sim-backend` | Just the iOS sim Rust static library       |
| `nix build .#wawona-android-backend` | Just the Android Rust static/shared lib    |
| `nix run .#xcodegen`                 | Generate Wawona.xcodeproj (iOS + macOS)    |
| `nix run .#xcodegen-ios`             | Generate Wawona.xcodeproj (iOS only)       |
| `nix run .#gradlegen`                | Generate Gradle project for Android        |

---

## Caching behavior

Because every crate is its own Nix derivation:

- **Changing a Rust source file in `src/`** rebuilds only `wawona` (the root
  crate) and the final assembly. All ~120 dependency crates are served from
  `/nix/store` cache.
- **Changing `waypipe` source** rebuilds the waypipe crate and `wawona` (which
  depends on it). Other crates are cached.
- **Changing a native C library** (e.g. bumping zstd) rebuilds only that
  library derivation and any Rust crate that directly links it (e.g.
  `waypipe-zstd-wrapper`, `wawona`).
- **Changing `flake.nix`** or `rust-backend-c2n.nix` may invalidate the
  crate2nix generation step, causing all Rust crates to rebuild.
- **Switching between platforms** (e.g. iOS sim → iOS device) triggers a full
  rebuild because the target triple changes.

---

## File reference

| File                                          | Role                                          |
|-----------------------------------------------|-----------------------------------------------|
| `flake.nix`                                   | Top-level: inputs, overlays, all packages     |
| `dependencies/wawona/rust-backend-c2n.nix`    | crate2nix Rust backend (this doc's focus)     |
| `dependencies/wawona/workspace-src.nix`       | Cargo workspace assembly                      |
| `dependencies/wawona/default.nix`             | Central app entry (ios/macos/android/generators) |
| `dependencies/wawona/ios.nix`                 | iOS app bundle + simulator automation         |
| `dependencies/wawona/macos.nix`               | macOS app bundle                              |
| `dependencies/wawona/android.nix`             | Android project                               |
| `wwn-toolchain/dependencies/toolchains/default.nix` | Platform dispatcher (buildForIOS/macOS/Android) |
| `wwn-toolchain/dependencies/libs/*/`          | Per-library cross-compilation recipes (upstream) |
| `wwn-weston`, `wwn-waypipe`, …                | Patched app ports + platform-specific ldflags   |
| `dependencies/generators/xcodegen.nix`        | Xcode project generator                       |
| `dependencies/generators/gradlegen.nix`       | Gradle project generator                      |
| `Cargo.toml`                                  | Rust workspace manifest                       |
| `src/lib.rs`                                  | Root lib (extern crate waypipe for FFI)       |
