# iOS minimum OS and latest SDK

User decision, 2026-11-10: Wawona builds with Xcode 27 and SDK 27 only.
Xcode 27 accepts iOS deployment targets from **15.0**, so every Wawona
iOS/iPadOS app (App Store, TestFlight, Sileo `.deb`, TrollStore `.tipa`,
simulator) targets 15.0. iOS 13 and 14 can no longer be built and are not
supported. This supersedes the 2026-09-30 13.0 policy and older skill text.

Use the latest installed iPhoneOS SDK. When a newer SDK is available,
validate it and use it. Never downgrade the SDK to reach an older minimum.
"15 through 27+" is a compatibility objective, not proof that untested or
future systems work.

## Build contract

- `Wawona.xcodeproj/project.xcproj` sets `IPHONEOS_DEPLOYMENT_TARGET = 15.0`.
  Nix products inherit it; no flake attribute overrides it.
- `scripts/xcode-prebuild.sh` `ld -r` takes `IPHONEOS_DEPLOYMENT_TARGET`.
  Do not hardcode a version.
- L0 `wwn-toolchain/dependencies/apple/default.nix` still builds dependency
  archives at 13.0. An archive with an older minimum links into a 15.0 app;
  one with a newer minimum than 15.0 must not be linked.
- tvOS, watchOS, visionOS and macOS retain their own deployment targets.
- Local dependency changes require an updated published pin or explicit local
  input override before a consumer can claim to have built those changes.

C flags and Meson `c_args` do not apply to `.m` / `.mm`. CMake must set
`CMAKE_OBJC_FLAGS` / `CMAKE_OBJCXX_FLAGS` with the same
`-miphoneos-version-min` as C. Meson cross files must set `objc_args` /
`objcpp_args` the same way. Without that, clang targets the iPhoneOS SDK.
It emits `_objc_release_xN`, which `libobjc` does not provide before iOS
16, and dyld aborts on iOS 15. Check:
`wwn-toolchain/.github/scripts/verify-apple-objc-deployment.py`.

## Renderer and UI

Use one native static ANGLE/Metal and one native static MoltenVK/Metal set.
EGL and GLES go through ANGLE to Metal. Vulkan goes through MoltenVK to Metal.
Runtime Metal feature policy stays in Rust. Swift in `Sources/WawonaApple`
fills capabilities and bridges native APIs. No Objective-C product classes.

SwiftUI APIs added after iOS 15 still need guarded use or a functional
backport (`WawonaBackport`). Machine creation, per-machine RAM and storage
settings, launch and lifecycle must work on the supported range.

## Distribution channels

All iOS binaries target 15.0. App Store Mode A stays no Cranelift, no
`MAP_JIT`, no Hypervisor, no private Metal/IOMFB APIs, and no QEMU. iOS 27+
Mode A Wasm may use Wasmer WASIX in WebKit. TrollStore and Sileo retain their
separate installation and entitlement contracts. A deployment target does not
extend TrollStore's installer window or the iOS Hypervisor window.
`.github/scripts/verify-ios-modeb-artifacts.sh` requires 15.0 on the tipa and
Sileo executables.

Compile success, device operation, App Store processing and review are
separate gates. Do not describe the whole range or store acceptance as
verified without evidence for the actual artifact.

## Verification

Audit linked Mach-O load commands and embedded framework minima in final
artifacts. Exercise machine creation, settings, guest launch, graphics, input
and background/resume on representative iPhone/iPad releases and hardware.
Record failures explicitly.

## Ownership

Toolchain: `wwn-toolchain`. Graphics recipes: `iLand`. App and UI: `Wawona`.
Relay stays Rust and uses the floor supplied by its consuming toolchain.

## App Store linkage

App Store and TestFlight IPAs do not ship a product `.dylib`. Link static
archives. Apple's `libswift*` / SwiftSupport is the store exception. macOS
Desktop Mode B `libwayland-mac.dylib` stays in `.#wawona-macos-desktop-host`
only. Do not rewrite `LC_BUILD_VERSION` to change an archive's minimum.

Wawona Terminal grid is **libghostty-rs** from `github.com/Wawona/Terminal`
(flake `terminal`), a static archive. UniFFI is the product contract. Never
link published GhosttyKit (iOS 17). Never ship a product Terminal `.dylib` in
store IPA. Shell backends: `wawona-terminal-shell-backend`. Rule:
`wawona-ghostty-host`.
