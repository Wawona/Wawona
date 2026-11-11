# Fresh build (hard). Never stale apps

Apple and Android apps build with **Xcode 27 and Android Studio** over
prebuilt dependency slices; `cargo xtask` drives the same projects from a
shell. Nix produces those slices in CI, builds Linux, and owns L0/L1. An
agent that launches `/Applications/Wawona.app`, overlays `/tmp` archives, or
boots the wrong simulator produces false evidence. Authority:
`docs/compilation.md`, `wawona-test-tip-app`, skill `wawona-fresh-build`.

## Before any build or launch

1. Query **wwn-mcp** (`search_docs` / `where_to_edit`) for the path.
2. Read `docs/compilation.md`. `cargo xtask <verb> --help` names every flag.

## Canonical commands (Wawona checkout root)

| Goal | Command |
|------|---------|
| Dependencies for the IDEs | `cargo xtask deps get macosx iphonesimulator android` (a missing or stale slice refetches) |
| Xcode | open `Wawona.xcodeproj`, pick a `Wawona-*` scheme, Run. The prebuild phase builds the Rust backend |
| Android Studio | open `android/`, Run. Gradle `preBuild` builds the Rust backend |
| Shell build of the same project | `cargo xtask build <macos\|ios\|ipados\|ios-modeb\|tvos\|visionos\|watchos\|android>` (`--device`, `--release`) |
| Tests | `cargo xtask test <target>` |
| Release | `cargo xtask archive <target> --export app-store-connect`, `cargo xtask package dmg\|ios-mode-b` |
| Install to this Mac | `cargo xtask install` (Release build, launch agents, Mode B helper, CLI wrappers) |
| Tip for Appium / agent-device | `eval "$(WAWONA_TEST_REBUILD=1 cargo xtask tip macos)"` (or `ios`, `tvos`, `visionos`, `watchos`) |
| Wawona Terminal standalone | `nix run .#terminal` (`--override-input terminal path:../Terminal` for a local tree) |
| Linux | `nix build .#wawona-linux` on Linux |
| Slices from source (no cache) | `cargo xtask deps get <sdk> --nix` |

A source edit needs a rebuild. `cargo xtask tip` rebuilds when its stamp
(`git-HEAD` plus the product fingerprint) differs from the tree; a matching
stamp on a binary whose libraries you patched by hand is still **stale**.

## Match the device to the task (hard)

Boot **only** the platform under test.

| Task | Allowed run target |
|------|--------------------|
| Wawona Terminal / Ghostty / macOS host UI | macOS tip or `nix run .#terminal` |
| iOS phone Terminal | iPhone Simulator or device |
| visionOS feature work | visionOS Simulator, **only then** |

Booting Vision Pro or aiming `xcodebuild` / XcodeBuildMCP at visionOS while
the bug is on macOS or iOS is forbidden. A visionOS launch proves nothing
about Terminal.

## Hard rejects

- `/Applications/Wawona.app`, `~/Applications`, foreign DerivedData
- Host `cargo build` + `llvm-objcopy` merges of `libwawona_terminal.a` as the
  ship path, or `/tmp/*-target/release/*.a` as the product archive
- `WAWONA_ALLOW_STALE_TEST_APP=1` for a proof claim
- A project generator (XcodeGen, gradlegen) or a Nix app derivation for an
  Apple or Android product
- Guessing a command instead of reading `docs/compilation.md` or `--help`

## Checklist (every host UI turn)

```text
[ ] wwn-mcp queried for the build path
[ ] rebuilt after the source change (IDE Run, cargo xtask build, or tip --rebuild)
[ ] WAWONA_APP_PATH is the tip, not /Applications
[ ] No Vision Pro unless the task is visionOS
```

Cursor: `wawona-fresh-build` (alwaysApply). Skill: `wawona-fresh-build`.
Related: `wawona-test-tip-app`, `wawona-local-before-ci`, `wawona-ghostty-host`,
`wawona-no-python`.
