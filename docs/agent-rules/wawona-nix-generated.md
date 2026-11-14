# Nix-generated artifacts (flake spirit)

What Nix can emit from inputs is a Nix output, never a git source. Product
Apple/Android apps are Exact bun hosts driven by `cargo xtask`. There is no
committed `Wawona.xcodeproj` or root Gradle product project.

Cursor rule: `wawona-nix-generated`.
Related: `wawona-uniffi-domain`, `wawona-repo-dag`, `docs/compilation.md`.

## Committed source

| File | Edited with |
|---|---|
| Exact `apps/wawona/app.contract`, `app.json`, `modules/apple/` | Exact / editor |
| Wawona `Sources/`, `src/`, `xtask/` | editor; Present may bridge into Exact module |

## Store / gitignore (never commit)

| Artifact | How it appears |
|---|---|
| `.deps/<sdk>` | `cargo xtask deps get <sdk>` |
| `.deps/android` | `cargo xtask deps get android` |
| `.build/backend/<sdk>` (libwawona, UniFFI) | `cargo xtask backend <sdk>` |
| Exact build products under Exact `apps/wawona/.exact/` | `bun host/apple/build.mjs` |
| `result`, `target/`, `.build/` | local builds |

## Hard rejects

- Reintroducing XcodeGen, gradlegen, or a committed product `Wawona.xcodeproj`
- Checking in generated UniFFI Swift/Kotlin under `Sources/`
- A `/nix/store` path in Exact or xtask-generated configs committed to git
- Claiming Android Studio / Xcode as the product authoring surface

## Local

```text
cargo xtask deps get macosx iphonesimulator android
cargo xtask build macos
cargo xtask archive ios
```
