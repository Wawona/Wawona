# Clean-clone proof (cargo xtask, no Nix on PATH)

Recorded 2026-11-11 on the `rust-xtask` worktree. Prebuilt slices via
`WAWONA_DEPS_MIRROR` (stands in for GHCR until `deps.yml` publishes).

## Setup

```bash
# Pack once from existing Nix-built .deps (CI / --nix path)
cargo xtask deps pack <sdk> .deps/<sdk> target/wawona-pack/archives/<sdk>.tar.zst
WAWONA_DEPS_MIRROR=~/.cache/wawona-deps-mirror \
  cargo xtask deps push <sdk> target/wawona-pack/archives/<sdk>.tar.zst --nar sha256-local-<sdk>

# Fresh get without nix on PATH
export PATH="$HOME/.cargo/bin:/usr/bin:/bin"
export WAWONA_DEPS_MIRROR=~/.cache/wawona-deps-mirror
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cargo xtask deps get macosx iphonesimulator android
```

## Times

| Step | Seconds | Notes |
|------|---------|-------|
| Pack src | 9 | 0 store paths |
| Pack macosx | 136 | 67 store paths, 73 MB zst |
| Pack android | 428 | 35 store paths, 85 MB |
| Pack iphonesimulator | 356 | 23 store paths, 64 MB |
| Pack watchsimulator | 239 | 17 store paths, 55 MB |
| Pack appletvsimulator | ~570 | 63 MB zst |
| Pack xrsimulator | 280 | 59 MB zst |
| Clean `deps get` (5 slices) | 30 | mirror, no `/nix` on PATH |
| `cargo xtask build macos` | 1176 | Debug, CODE_SIGNING off |
| `cargo xtask build ios` | ~2301 | includes Watch companion embed |
| `cargo xtask build android` | 206 | after `@SLICE@` expand (Gradle + CMake) |
| `cargo xtask build watchos` | 262 | watchsimulator slice |
| `cargo xtask build tvos` | 1203 | appletvsimulator slice |
| `cargo xtask build visionos` | 617 | xrsimulator slice |
| Warm `cargo xtask backend macosx` | ~1–3 | incremental after first |

## Products

- `.build/xcode/macos/…/Wawona.app`
- `.build/xcode/ios/…/Wawona.app` (+ Watch companion)
- `.build/xcode/tvos/…/Wawona.app`
- `.build/xcode/watchos/…/Wawona.app`
- `.build/xcode/visionos/…/Wawona.app`
- `android/app/build/outputs/apk/debug/Wawona-debug.apk` (~88 MB)

## Line counts (this tip)

| Surface | Count |
|---------|-------|
| Tracked `*.py` | 0 |
| Tracked `scripts/**/*.sh` | 0 |
| Tracked `.github/scripts/*.sh` | 0 |
| `xtask/**/*.rs` | ~15,161 |

Plan baseline to replace: ~7,913 Python lines, ~14,931 shell lines.

## Host xtask under Xcode

`env -i` for the run-script `cargo build` of xtask must pass
`DEVELOPER_DIR`, macOS `SDKROOT`, and `MACOSX_DEPLOYMENT_TARGET`. Without
them, host crates (`zstd-sys`, `ring`) fail with `string.h` not found when
Xcode’s mobile `SDKROOT` would otherwise leak, or when the environment is
empty.

## Android `@SLICE@`

Packed `wawona.properties` keeps `@SLICE@/store/…`. Expand at:

1. `cargo xtask deps get` after unpack (`expand_slice_placeholders`)
2. Gradle load of `wawona.properties` (`android/app/build.gradle.kts`)
3. CMake `string(REPLACE "@SLICE@" "${WAWONA_DEPS}" …)` in
   `android/app/src/main/cpp/CMakeLists.txt`

Without that, NDK clang looks under `android/app/src/main/cpp/@SLICE@/…`
and fails on `iosurface_compat.h`.

## Slices in `deps.lock` (mirror)

`src`, `macosx`, `iphonesimulator`, `appletvsimulator`, `watchsimulator`,
`xrsimulator`, `android`.
