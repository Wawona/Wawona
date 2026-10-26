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
5. After each transport upload, poll the matching App Store Connect `buildUploads`
   record by bundle version, build number, and platform. The lane passes only
   when a new record reaches `COMPLETE`. `FAILED`, a missing record, or timeout
   fails the lane. An `altool` or Fastlane transport success is not acceptance.

Do not archive and upload one target at a time. A later platform failure must
not leave an earlier platform partially submitted.

## CalVer freshness

Keep `VERSION`, `Cargo.toml` `[package].version`, and the `wawona` entry in
`Cargo.lock` equal to the current `America/Los_Angeles` date before running a
fresh product gate or archive. The Xcode prebuild guard fails closed when a
run crosses midnight with yesterday's version. Fix the three version sources
and rerun the gate. Do not use `WAWONA_ALLOW_STALE_CALVER=1` for a fresh tip.

## Watch companion compile failures

The supported store path is `Wawona-iOS` with its Watch companion embedded under
`Watch/`, not a standalone `Wawona-watchOS` upload. Simulator builds are not a
substitute for the device archive. Reproduce without uploading with:

Gate: products builds `.#wawona-watchos-app-device` in the Watch product cell
and also builds the simulator app. The device build runs the embedded Watch
target's `Build Rust Backend via Nix` phase before any iOS archive or ASC upload
can start.

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
