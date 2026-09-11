# Nix-generated artifacts (flake spirit)

Reproducible generated files are **Nix outputs**. They are not git sources.

Cursor rule: `wawona-nix-generated`.
Related: `wawona-uniffi-domain`, `wawona-repo-dag`, `docs/2026-nix-build-system.md`.

## Rule

`nix build` / `nix run` produces the app. A clean checkout plus the flake must
be enough. Do not commit a file that Nix can emit bit-for-bit from inputs.

## Store / gitignore (never commit)

| Artifact | How it appears |
|---|---|
| UniFFI Swift / Kotlin | `$rustBackend/uniffi/{swift,kotlin}` |
| `Wawona.xcodeproj` | `nix run .#xcodegen-*` |
| Gradle project / `shader_spv.h` | `gradlegen` |
| Wayland `_GEN-*.rs` | rustc / scanner in the backend build |
| crate2nix `Cargo.nix` | IFD `generatedCargoNix` |
| `result`, `target/`, `.build/` | local eval |

Bindings: `uniffi-bindgen` is `dependencies/generators/uniffi-bindgen.nix`
(host rustPlatform, UniFFI 0.30). Not a crate2nix workspace member. Not
`uniffi` `cli` on the Wawona crate.

## Allowed committed generate-and-diff

`docs/protocol-status.md` is a human/CI **contract**. `scripts/gen-protocol-status.sh`
rewrites it; CI `git diff --exit-code` fails if stale. That is not an app
binary. Do not use it as a pattern for Swift, Kotlin, or Xcode projects.

## Hard rejects

- Checking in generated UniFFI Swift/Kotlin under `Sources/` or `android/`
- Hand-editing a file Nix just wrote
- `|| true` on bindgen so a missing binding still "succeeds"
- Adding `uniffi` `cli` / `uniffi_build` to the Wawona crate2nix graph
- Copying `result/uniffi` into git "for convenience"

## Local

```text
nix build .#uniffi-bindgen
nix build .#wawona-macos-xcode-env   # rust backend; bindings at $out/uniffi
nix run .#xcodegen-macos
```
