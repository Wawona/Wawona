# Compilation Guide

Wawona builds with **Nix Flakes**. Xcode 27 opens the committed
`Wawona.xcodeproj` and Android Studio the root Gradle project; what neither
can build (the Rust backend, cross-compiled libraries, generated UniFFI Swift)
comes from Nix through `.deps/`. Layers and recipes:
[2026-nix-build-system.md](2026-nix-build-system.md).

## IDE loop

```bash
# Link .deps/<sdk> for the SDKs you build (Xcode PLATFORM_NAME, or android).
# iphoneos also links watchos for the embedded Watch app.
nix run .#deps -- macosx
nix run .#deps -- iphonesimulator watchsimulator
nix run .#deps -- android

open Wawona.xcodeproj        # schemes Wawona-macOS, Wawona-iOS, Wawona-tvOS, ...
./gradlew :Wawona:assembleDebug   # or open the repo root in Android Studio
```

After a Rust edit, rebuild the working-tree backend for that SDK. It uses the
slice's Nix environment (toolchain, vendored crates, native libraries) and
stages `.build/backend/<sdk>`, which `scripts/xcode-prebuild.sh` links in
place of the Nix backend until the next `nix run .#deps`:

```bash
scripts/build-backend.sh iphonesimulator
```

The prebuild and `scripts/xcode-embed.sh` run on every build (Xcode notes
this) but only copy files. Re-run `nix run .#deps -- <sdk>` after pulling a
change to Nix inputs or `Cargo.lock`.

## Nix products

```bash
nix run .#wawona-macos                   # build + launch
nix build .#wawona-macos-desktop-host    # SIP-off Desktop Replacement host
./scripts/nix-build-low-mem.sh .#wawona-macos   # small machines, see Troubleshooting

nix build .#wawona-ios-app-sim .#wawona-ipados-app-sim
nix build .#wawona-tvos-app-sim .#wawona-watchos-app-sim .#wawona-visionos-app-sim
nix build .#wawona-ios-modeb-tipa        # TrollStore Mode B (vphone, not the Simulator)
nix build .#wawona-android .#wawona-android-aab

nix build .#wawona-macos-backend .#wawona-ios-sim-backend .#wawona-android-backend
```

On Linux, `nix run .#wawona` runs the prebuilt UI wrapper. Its scripts need
LF line endings: a CRLF checkout breaks them (`syntax error near unexpected
token $'in\r'`; issue #164). Keep `.gitattributes` (`*.nix text eol=lf`) and
avoid `core.autocrlf=true`.

`nix run .#nom -- build .#wawona-macos` (or `nom build` inside `nix develop`)
shows build progress. `-L` prints full logs, `--show-trace` evaluation stack
traces.

## FlakeHub Cache (shared org binary cache)

To pull prebuilt Layer-1/`wwn-*` store paths on a laptop (same cache CI uses):

```bash
determinate-nixd login   # once per machine
determinate-nixd status  # Logged in: true
```

Details, limits (forks / anonymous cold rebuild), and CI fragment:
[`flakehub-cache.md`](flakehub-cache.md).

## Requirements

- Apple Silicon Mac on macOS 27, Xcode 27 (SDK 27; older Xcode is refused)
- Nix with flake support
- Android Studio with its bundled JBR 21 for Android
- `TEAM_ID` in `.envrc.local` for device signing (`nix run .#deps` writes
  `.deps/signing.xcconfig` from it)

See [README](../README.md) for environment setup.

## Troubleshooting macOS builds

Weston cursor assets come from `adwaita-cursors`: unpack GNOME's Xcursor
files from the source tarball. `nix build .#wawona-macos` does **not**
build nixpkgs `adwaita-icon-theme`, `librsvg`, Sphinx, or mypy.

A remaining OOM on a tiny laptop is usually some other cold nixpkgs compile
running too many jobs. Cap parallelism:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Full cold compile on a laptop | Not logged into FlakeHub for `wwn-*` slices | `determinate-nixd login` |
| Exit 137 / `Killed: 9` on a small machine | Too many parallel Nix jobs | `./scripts/nix-build-low-mem.sh .#wawona-macos` |

Recommended order for new contributors:

```bash
determinate-nixd login
determinate-nixd status   # Logged in: true
nix build .#wawona-macos
```

On a machine that still OOMs:

```bash
./scripts/nix-build-low-mem.sh .#wawona-macos
```

CI sets `max-jobs` / `cores` in the Nix installer extra-conf, not in flake
`nixConfig` (that setting is untrusted on laptops). Cache details:
[`flakehub-cache.md`](flakehub-cache.md).

## Release beta (TestFlight + Play)

CalVer is `VERSION` (`YY.M.D`). Fastlane lives in this repo. Contributor CI:
[`ci.md`](./ci.md). Secrets: [`maintainers/secrets.md`](./maintainers/secrets.md)
(not for the public site).

```bash
# Tier 0. Docs/maintainers/secrets.md (SecretSpec + pass; sops-nix unlocks GPG)
cargo xtask secrets check                      # verify pass + secretspec
cargo xtask secrets bootstrap-signing                    # one-time match → apple-signing repo
cargo xtask secrets sync                        # pass → GitHub Environment release-beta

nix develop .#release
secretspec check -P local
cargo xtask secrets run -- fastlane ios beta              # match + gym + TestFlight
cargo xtask secrets run -- fastlane android beta          # Play internal (CI smoke)
# Closed Alpha / Open: Draft apps need draft status. Reuse internal versionCode via promote:
PLAY_PROMOTE_INTERNAL=1 PLAY_RELEASE_STATUS=draft \
  cargo xtask secrets run -- fastlane android beta_closed   # → alpha
PLAY_PROMOTE_INTERNAL=1 PLAY_RELEASE_STATUS=draft \
  cargo xtask secrets run -- fastlane android beta_open     # → open (needs production access)
# Fresh AAB: omit PLAY_PROMOTE_INTERNAL (or set WAWONA_AAB_PATH=/path/to.aab)
```

Signed IPAs: `TEAM_ID=… nix build .#wawona-ios-ipa --impure` (also ipados/tvos/watchos/visionos variants).

Android AAB: `nix build .#wawona-android-aab` with `ANDROID_KEYSTORE_*` env vars set.
