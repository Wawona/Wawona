---
name: wawona-store-archive-preflight
description: >-
  Apple store release builds must archive and export every selected device target,
  including the iOS app with its embedded Watch companion, before the first ASC upload.
---

# Apple store archive preflight

Simulator product builds cannot catch every device archive error. In particular,
the Wawona-iOS archive compiles and signs Wawona-watchOS as an embedded app.

## Required release ordering

1. Generate the Xcode project from the current Nix inputs.
2. Archive and export every selected Apple beta target.
3. Run all archive and IPA structure assertions for every exported IPA.
4. Only after all targets pass, upload those exact IPA files to App Store Connect.

Do not archive and upload one target at a time. A later platform failure must
not leave an earlier platform partially submitted.

## Watch companion compile failures

The supported store path is `Wawona-iOS` with its Watch companion embedded under
`Watch/`, not a standalone `Wawona-watchOS` upload. Simulator builds are not a
substitute for the device archive. Reproduce without uploading with:

```sh
CI=true WAWONA_DEBUG_SCHEME=Wawona-iOS fastlane ios debug_export
```

Keep only one Swift declaration for each `@_silgen_name` native symbol in a
target module. If a shared ABI wrapper already declares the function, call that
wrapper rather than redeclaring the symbol at file scope. Duplicate declarations
can produce a Swift function convention mismatch only in the embedded Watch
device compile.

The Watch device archive also builds an `arm64_32` compatibility slice without
linking Nix Rust, PTY, or terminal archives. Any C ABI symbol referenced by
Swift in that slice needs a weak, fail-closed definition in
`src/platform/watchos/WWNWatchStubs.c`. The arm64 device slice must continue to
resolve those APIs from the real Nix archives.

See `docs/ci.md` for release invariants and incident evidence.
