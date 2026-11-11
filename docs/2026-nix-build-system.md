# Wawona Nix Build System

What Nix builds in this project, and how its outputs reach the committed
Xcode and Gradle projects without Nix on the developer's machine.

## Overview

Nix builds two things: the native C/C++ libraries of every platform slice,
and the Linux product. Everything an IDE can build itself (the Rust backend,
the apps, archives and wrappers) is Cargo, Xcode and Gradle, driven by
`cargo xtask`.

```
┌──────────────────────────────────────────────────┐
│  Apps: Wawona.xcodeproj, android/ (Gradle)       │
│  cargo xtask build / archive / package           │
├──────────────────────────────────────────────────┤
│  Rust backend: cargo xtask backend <slice>       │
│  rust-toolchain.toml, Cargo.lock, .deps/<slice>  │
├──────────────────────────────────────────────────┤
│  Dependency slices: .#deps-<sdk> (Nix, in CI)    │
│  packed, pushed to ghcr.io/wawona/deps,          │
│  recorded in deps.lock                           │
├──────────────────────────────────────────────────┤
│  Native C/C++ libraries (L0 wwn-toolchain,       │
│  L1 iLand, wwn-* and the repo.wawona.io catalog) │
└──────────────────────────────────────────────────┘
```

Canonical repository DAG: [`wwn-repo-dag.md`](./wwn-repo-dag.md).

## Inputs

See `flake.nix`; do not invent `wwn-*` edges. `wwn-toolchain` is the L0
substrate (cairo, pango, libwayland, openssl, …) and `iland` the L1 graphics
stack (ANGLE, SwiftShader, MoltenVK, KosmicKrisp). Weston, niri, foot,
kmscube, fastfetch and phoon come from one `repo-wawona-io` input
(`registryFragment`). `wwn-zsh`, `wwn-uutils-rs`, `wwn-waypipe`, `wwn-ssh`,
`wwn-relay`, `terminal` and `toolbar-keys` supply the rest. Wawona merges
their registries over `baseRegistry` and never feeds back into them.

The Rust toolchain is `rust-toolchain.toml`. `rust-overlay` reads the same
file, so a Nix build and a checkout compile with one compiler.

## Dependency slices

`dependencies/wawona/deps.nix` makes one output per Xcode `PLATFORM_NAME`
(`.#deps-macosx`, `.#deps-iphonesimulator`, …); the Mode B backend builds
against `iphoneos`. `android-deps.nix` makes `.#deps-android`. A slice holds:

| Path | Consumer |
|---|---|
| `slice.json` | `cargo xtask backend`: the C libraries' include and library paths, rewritten `.pc` files and the pkgconf they need |
| `Wawona.xcconfig` | `WWN_HEADERS_<target>` and `WWN_LDFLAGS_<target>`, included by `src/resources/xcode/wwn-version.xcconfig` |
| `zsh/`, `fastfetch/` | archives `cargo xtask xcode prebuild` privatizes and stages |
| `bundle/` | what `cargo xtask xcode embed` copies into the app |

The deps workflow (`deps.yml`) builds each slice, `cargo xtask deps pack`
makes it relocatable, `deps push` publishes it to GHCR as an OCI artifact and
`deps merge` records its digest in `deps.lock`. `cargo xtask deps get <sdk>`
downloads, verifies and unpacks it into `.deps/<sdk>`; `--nix` builds it
locally instead, which is how a C dependency change is tried before CI.

## Rust backend

`cargo xtask backend <slice>` builds `libwawona` for one slice into
`.build/backend/<slice>`: the triple, deployment minimum and Cargo features
come from `xtask/src/slices.rs`, the C libraries from the slice's
`slice.json`, the crates from `Cargo.lock`. Xcode's prebuild phase and
Gradle's `preBuild` call it, so a Rust edit rebuilds incrementally in
`target/` on the next Run. UniFFI Swift and Kotlin come from the in-workspace
`uniffi-bindgen` in the same step.

`workspace-src.nix` and `cargo xtask workspace` assemble the path crates the
root `Cargo.toml` names (patched waypipe, coreutils, libghostty).

## Apps

The committed `Wawona.xcodeproj` and `android/` project are the only app
projects. `cargo xtask build <target>` runs the target's Xcode scheme or
Gradle task; `archive` makes the release archive and exports it;
`package` makes the Mode B `.tipa` and Sileo debs and the macOS DMG.
Fastlane calls these. CI pins Xcode with `cargo xtask ci select-xcode`
(Xcode 27 only, never "newest installed").

## Nix products

| Command | What it builds |
|---|---|
| `nix build .#deps-<sdk>` | One dependency slice (CI; `deps get --nix` locally) |
| `nix build .#wawona-linux`, `.#wawona-appimage` (on Linux) | The Linux product |
| `nix run .#terminal` | Wawona Terminal standalone |
| `nix develop .#release` | The release shell (fastlane, secretspec) |

There is no Nix derivation for an Apple or Android app.

## Caching

- A native library change rebuilds that library and each slice that holds
  it; CI then publishes only slices whose `narHash` changed.
- A Rust change rebuilds only what Cargo's incremental state says changed.
- Each slice is separate: switching simulator to device fetches the other
  slice, and the first stays in `.deps`.

## File reference

| File | Role |
|---|---|
| `flake.nix` | Inputs, overlays, the slices and the Linux packages |
| `dependencies/wawona/deps.nix`, `android-deps.nix` | Dependency slices |
| `dependencies/wawona/workspace-src.nix` | Cargo workspace assembly for Nix |
| `deps.lock` | Published slice digests |
| `xtask/` | Every build verb (`cargo xtask --help`) |
| `Wawona.xcodeproj/project.xcproj`, `android/app/build.gradle.kts` | The IDE projects |
| `wwn-toolchain/dependencies/libs/*/` | Per-library cross-compilation recipes |
