---
name: wawona-ios-min-os
description: Pointer for iOS 15-27+ min OS on Xcode 27 / SDK 27. One ANGLE, one MoltenVK. Never downgrade the SDK. Open the wawona-ios-min-os rule.
---

# iOS min OS (pointer)

Open rule `wawona-ios-min-os`. Prose:
`Wawona/docs/agent-rules/wawona-ios-min-os.md`.
RAG: `wwn-mcp/knowledge/wawona/ios-min-os.md`.

## When

Editing `IPHONEOS_DEPLOYMENT_TARGET` in `project.xcproj`, ANGLE or MoltenVK
iOS recipes, `@available` / weak-link on iOS, a bundled client recipe
(`apple-mobile.nix`, CMake toolchain, Meson cross file), or the
`xcode-prebuild.sh` privatize step.

## Hard rejects

- An iOS app target below 15.0 (Xcode 27 refuses it) or a flake override of the project's value
- Downgrading the SDK, or linking an archive whose minimum is newer than 15.0
- ObjC compiled without `-miphoneos-version-min` (`CMAKE_OBJC_FLAGS`, Meson `objc_args`)
- More than one ANGLE or one MoltenVK
- Metal/Vulkan capability policy in Swift when Rust can own it
- GhosttyKit, or a product `.dylib` in a store IPA

## Verify

```bash
otool -l Wawona.app/Wawona | grep -A4 LC_BUILD_VERSION   # minos 15.0
cargo xtask artifact ios mode-b <tipa>   # or: mode-a <app>
```
