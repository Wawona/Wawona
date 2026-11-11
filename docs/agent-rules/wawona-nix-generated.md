# Nix-generated artifacts (flake spirit)

What Nix can emit from inputs is a Nix output, never a git source. The Xcode
project and the Gradle build are ordinary committed source that Xcode and
Android Studio open from the repository root.

Cursor rule: `wawona-nix-generated`.
Related: `wawona-uniffi-domain`, `wawona-repo-dag`, `docs/compilation.md`.

## Committed source

| File | Edited with |
|---|---|
| `Wawona.xcodeproj/project.xcproj` (JSON project) and `xcshareddata/` schemes | Xcode, or by hand |
| `settings.gradle.kts`, `build.gradle.kts`, `android/app/` | Android Studio, or by hand |

Sources are synchronized folders: a new file under `Sources/` or `src/` joins
its targets without a project edit. The project names no store path. It reads
the per-SDK slice through `.deps/<sdk>/Wawona.xcconfig`.

## Store / gitignore (never commit)

| Artifact | How it appears |
|---|---|
| `.deps/<sdk>` (C libraries, archives, bundle tree, xcconfig) | `cargo xtask deps get <sdk>` |
| `.deps/android` (jniLibs, assets, `shader_spv.h`) | `cargo xtask deps get android` |
| `.build/backend/<sdk>` (libwawona, UniFFI Swift linked at `.deps/uniffi`) | `cargo xtask backend <sdk>` (working-tree Rust) |
| Wayland `_GEN-*.rs` | rustc / scanner in the backend build |
| `result`, `target/`, `.build/` | local builds |

Bindings: the xtask binary serves `uniffi-bindgen` (UniFFI 0.30, `xtask/src/tools`).
Not `uniffi` `cli` on the Wawona crate.

## Allowed committed generate-and-diff

`docs/protocol-status.md` is a human/CI **contract**. `cargo xtask gen protocol-status`
rewrites it; CI `git diff --exit-code` fails if stale. That is not an app
binary. Do not use it as a pattern for Swift, Kotlin, or project files.

## Hard rejects

- Reintroducing a project generator (XcodeGen, gradlegen) for the app
- Checking in generated UniFFI Swift/Kotlin under `Sources/` or `android/`
- A `/nix/store` or `/store/<hash>` path in `project.xcproj`, an xcconfig in git, or Gradle files
- Committing `.deps/` or `org.gradle.java.home`
- `|| true` on bindgen so a missing binding still "succeeds"
- Copying `.build/backend/*/uniffi` into git "for convenience"

## Local

```text
cargo xtask deps get macosx            # then open Wawona.xcodeproj
cargo xtask deps get iphonesimulator   # adds watchsimulator for the companion
cargo xtask deps get android           # then open the root in Android Studio
cargo xtask backend macosx     # rebuild Rust from the working tree
```
