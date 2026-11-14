# Fresh build (hard). Never stale apps

Apple and Android product apps build with **Exact bun hosts** over prebuilt
dependency slices; `cargo xtask` drives Exact and stages `libwawona`. Nix
produces slices in CI, builds Linux, and owns L0/L1. Never launch
`/Applications/Wawona.app` or a stale tip for proof.

Authority: `docs/compilation.md`, `wawona-test-tip-app`, skill `wawona-fresh-build`.

## Before any build or launch

1. Query **wwn-mcp** for the path.
2. Read `docs/compilation.md`. `cargo xtask <verb> --help` names every flag.
3. Ensure sibling Exact checkout (or `EXACT_ROOT`).

## Canonical commands (Wawona checkout root)

| Goal | Command |
|------|---------|
| Dependencies | `cargo xtask deps get macosx iphonesimulator android` |
| Shell build | `cargo xtask build <macos\|ios\|…\|android>` |
| Device IPA | `cargo xtask archive ios` (`EXACT_IDENTITY` + `EXACT_PROFILE`) |
| Tip | `eval "$(WAWONA_TEST_REBUILD=1 cargo xtask tip macos)"` |
| Exact direct | `cd ../exact && bun host/apple/build.mjs --ios wawona-apple` |
| Terminal standalone | `nix run .#terminal` |
| Linux | `nix build .#wawona-linux` on Linux |

## Hard rejects

- `/Applications/Wawona.app` for tests
- Reviving `Wawona.xcodeproj` or root Gradle as the product build
- Vision Pro when the task is macOS/iOS Terminal
- `WAWONA_ALLOW_STALE_TEST_APP=1` for proof claims
