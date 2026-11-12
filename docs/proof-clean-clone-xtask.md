# Clean-clone proof (cargo xtask, no Nix for apps)

Recorded 2026-11-12 on `rust-xtask`. Goal: a fresh checkout builds Apple
simulator and Android apps with `cargo xtask deps get` + `cargo xtask build`,
without invoking Nix for the app link.

## Method

1. Pack existing Nix slices: `cargo xtask deps pack <sdk> .deps/<sdk> /tmp/…tar.zst`.
2. Write `deps.lock` digests; stage archives under `WAWONA_DEPS_MIRROR/<sha256>`.
3. `git clone` to `/tmp/wawona-proof2-clone`, copy `deps.lock`.
4. `WAWONA_DEPS_MIRROR=… cargo xtask deps get …` (no `--nix`).
5. `WAWONA_ALLOW_STALE_CALVER=1 cargo xtask build <target>`.

GHCR publish (`deps push`) was not required for this local mirror proof. CI
`deps.yml` remains the production producer.

## Line counts (tip)

| Metric | Value |
|---|---|
| Tracked `*.py` | 0 |
| `xtask/src` Rust lines | 15129 |
| Tracked `*.sh` | 3 (Mode B / ABI-bound only) |

## Times (clean clone unless noted)

| Step | Result | Wall time |
|---|---|---|
| `deps get` (src + macosx + iphonesimulator + appletvsimulator + watchsimulator) | ok | ~860 s (includes cold xtask compile) |
| `build macos` | **SUCCEEDED** | 835 s |
| `build ios` | **SUCCEEDED** | 1037 s |
| `build tvos` | **SUCCEEDED** | 885 s (after appletvsimulator repack with `slice.json`) |
| `build watchos` | **SUCCEEDED** | ~1230 s |
| `build visionos` | **SUCCEEDED** | 441 s |
| `build android` | see log `/tmp/wawona-proof2-android2.log` | (main tree `.deps/android`) |

## Notes

- Backend refuses a slice directory that lacks `slice.json` (error text now names
  the missing file). A pack taken from a GC'd / partial tree fails closed.
- `WAWONA_DEPS_MIRROR` is the offline stand-in for `ghcr.io/wawona/deps` blob
  pulls (`xtask/src/deps/oci.rs`).
- Exact Phase 6 (AsteroidOS) is tracked separately on `Wawona/exact`
  `platforms/matrix`: headless `hello` agent tree green; Qt/QML image path still open.
