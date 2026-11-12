# Compilation Guide

Xcode 27 opens the committed `Wawona.xcodeproj` and Android Studio the
`android/` Gradle project. What neither can build (cross-compiled C
libraries, the Rust toolchain's vendored crates, generated UniFFI Swift)
arrives as prebuilt dependency slices in `.deps/`. `cargo xtask` drives the
rest from a shell: the Rust backend, builds, tests, archives and the Mode B
and DMG wrappers. There is no Python and no project generator.

Nix builds the slices in CI (`deps.yml` publishes them to GHCR and records
them in `deps.lock`) and builds Linux. It is not needed to build the Apple or
Android apps. Layers and recipes: [2026-nix-build-system.md](2026-nix-build-system.md).

## IDE loop

```bash
# Fetch .deps/<sdk> for the SDKs you build (Xcode PLATFORM_NAME, or android).
# iphoneos also fetches watchos for the embedded Watch app.
cargo xtask deps get macosx iphonesimulator android

open Wawona.xcodeproj        # schemes Wawona-macOS, Wawona-iOS, Wawona-tvOS, ...
# or open android/ in Android Studio (Gradle JDK: its bundled JBR 21)
```

Xcode's prebuild phase runs `cargo xtask xcode prebuild`, which builds the
working-tree Rust backend for the target's SDK into `.build/backend/<sdk>`
and links it; the embed phase runs `cargo xtask xcode embed`. Gradle's
`preBuild` does the same for Android. A Rust edit needs nothing else: press
Run. To build a backend alone:

```bash
cargo xtask backend iphonesimulator
```

A slice older than `deps.lock` (after a pull that changed Nix inputs) is
fetched again by the next `deps get`. Without network access to GHCR, or for
a slice `deps.lock` does not list yet, `cargo xtask deps get <sdk> --nix`
builds it locally with Nix.

## From a shell

```bash
cargo xtask build macos              # ios, ipados, ios-modeb, tvos, visionos, watchos, android
cargo xtask build ios --device --sign  # TEAM_ID signs device builds
cargo xtask test rust                # ios (XCTest on a simulator), android (unit tests)
cargo xtask archive ios --export app-store-connect
cargo xtask archive android          # release AAB
cargo xtask package ios-mode-b       # TrollStore .tipa + rootless and rootful Sileo debs
cargo xtask package dmg --notarize   # drag-install macOS DMG
cargo xtask install                  # Release build into /Applications with agents and helper
eval "$(cargo xtask tip macos)"      # tip app for agent-device and Appium
```

`cargo xtask <verb> --help` names every flag; `cargo xtask verify --list`
names the repository gates.

## Linux and the Nix products

```bash
nix build .#wawona-linux .#wawona-appimage   # on Linux
nix run .#terminal                   # Wawona Terminal standalone
nix run .#nom -- build .#wawona-linux   # with build progress
```

On Linux, `nix run .#wawona` runs the prebuilt UI wrapper. Its scripts need
LF line endings: a CRLF checkout breaks them (`syntax error near unexpected
token $'in\r'`; issue #164). Keep `.gitattributes` (`*.nix text eol=lf`) and
avoid `core.autocrlf=true`.

## FlakeHub Cache (shared org binary cache)

To pull prebuilt Layer-1/`wwn-*` store paths when building slices with
`--nix` or building Linux (same cache CI uses):

```bash
determinate-nixd login   # once per machine
determinate-nixd status  # Logged in: true
```

Details, limits (forks / anonymous cold rebuild), and CI fragment:
[`flakehub-cache.md`](flakehub-cache.md). A cold `--nix` build that dies
with exit 137 on a small machine is too many parallel jobs: pass
`--option max-jobs 2 --option cores 4` through `NIX_CONFIG`.

## Requirements

- Apple Silicon Mac on macOS 27, Xcode 27 (SDK 27; older Xcode is refused)
- Rust from `rust-toolchain.toml` (rustup installs it on first `cargo`)
- Android Studio with its bundled JBR 21 for Android
- `TEAM_ID` in `.envrc.local` for device signing (`deps get` writes
  `.deps/signing.xcconfig` from it)
- Nix only for `--nix` slices, Linux and the release shell

See [README](../README.md) for environment setup.

## Release beta (TestFlight + Play)

CalVer is `VERSION` (`YY.M.D`). Fastlane lives in this repo and calls
`cargo xtask archive`. Contributor CI: [`ci.md`](./ci.md). Secrets:
[`maintainers/secrets.md`](./maintainers/secrets.md) (not for the public site).

```bash
# Tier 0. Docs/maintainers/secrets.md (SecretSpec + pass; sops-nix unlocks GPG)
cargo xtask secrets check                      # verify pass + secretspec
cargo xtask secrets bootstrap-signing          # one-time match → apple-signing repo
cargo xtask secrets sync                       # pass → GitHub Environment release-beta

nix develop .#release
secretspec check -P local
cargo xtask secrets run -- fastlane ios beta              # match + archive + TestFlight
cargo xtask secrets run -- fastlane android beta          # Play internal (CI smoke)
# Closed Alpha / Open: Draft apps need draft status. Reuse internal versionCode via promote:
PLAY_PROMOTE_INTERNAL=1 PLAY_RELEASE_STATUS=draft \
  cargo xtask secrets run -- fastlane android beta_closed   # → alpha
PLAY_PROMOTE_INTERNAL=1 PLAY_RELEASE_STATUS=draft \
  cargo xtask secrets run -- fastlane android beta_open     # → open (needs production access)
# Fresh AAB: omit PLAY_PROMOTE_INTERNAL (or set WAWONA_AAB_PATH=/path/to.aab)
```

Signed Android AABs need the `ANDROID_KEYSTORE_*` variables
(`cargo xtask secrets run -- cargo xtask archive android`).
