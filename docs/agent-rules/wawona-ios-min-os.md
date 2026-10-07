# iOS minimum OS and latest SDK

User decision, 2026-09-30: every Wawona iOS/iPadOS product and its dependencies
compile with deployment target **13.0**. iOS 11 and 12 are no longer supported.
This supersedes the earlier iOS 11 policy, including older skill text.

Use the latest installed iPhoneOS SDK (26.5 verified locally on this date).
When a newer SDK is available, validate it and use it. Never downgrade the SDK
to match the minimum OS. “13 through 27+” is a compatibility objective, not
proof that untested or future systems work.

## Build contract

- L0 `wwn-toolchain/dependencies/apple/default.nix` owns the default floor.
- Its xcode environment and shared Apple-mobile recipes inherit 13.0.
- Wawona's product overlay explicitly passes 13.0 when using a pinned L0 input.
- Rust backends, generated Xcode projects, Swift packages, app archives and
  embedded frameworks must agree. Inspect Mach-O minos in final artifacts.
- tvOS, watchOS, visionOS and macOS retain their own deployment targets.
- Local dependency changes require an updated published pin or explicit local
  input override before a consumer can claim to have built those changes.

## Renderer and UI

Use one native static ANGLE/Metal and one native static MoltenVK/Metal set.
Keep compatibility required by iOS 13/14; remove 11/12-only branches only after
checking they are not also needed by supported systems. Runtime Metal feature
policy stays in Rust. Swift in `Sources/WawonaApple` fills capabilities and
bridges native APIs. No Objective-C product classes.

SwiftUI exists at the new floor, but APIs added after iOS 13 still need guarded
use or a functional backport. Lowering Package.swift or Xcode settings alone
is not proof that the UI compiles or works. Machine creation, per-machine RAM
and storage settings, launch and lifecycle must work on the supported range.

## Distribution channels

All iOS binaries target 13.0. App Store Mode A stays no Cranelift, no `MAP_JIT`, no Hypervisor, no private Metal/IOMFB APIs, and no QEMU. iOS 27+ Mode A Wasm may use Wasmer WASIX in WebKit. TrollStore and Sileo retain their
separate installation and entitlement contracts. A 13.0 deployment target
does not extend TrollStore's installer window or the iOS Hypervisor window.

Compile success, device operation, App Store processing and review are separate
gates. Do not describe the whole range or store acceptance as verified without
evidence for the actual artifact. Keep the SDK current in every channel.

## Verification

Compile dependencies, Rust static libraries, Swift modules and final apps with
13.0. Audit linked Mach-O load commands and embedded framework minima. Exercise
machine creation, settings, guest launch, graphics, input and background/resume
on representative iPhone/iPad releases and hardware. Record failures explicitly.

## Ownership

Toolchain: `wwn-toolchain`. Graphics recipes: `wwn-iland`. App and UI: `Wawona`.
Relay stays Rust and uses the same floor supplied by its consuming toolchain.
Reference: `Wawona/docs/agent-rules/wawona-ios-min-os.md`.

## App Store linkage

The floor stays **13.0** on the latest iPhoneOS SDK (26 now, 27 when that SDK
is installed). A dependency built for a newer minimum does not raise Wawona.
Do not link a published kit whose minimum OS is newer than 13.0, and do not rewrite
`LC_BUILD_VERSION` to pretend it is 13.0.

App Store and TestFlight IPAs do not ship a product `.dylib`. Link static
archives. Apple's `libswift*` / SwiftSupport is the store exception. macOS
Desktop Mode B `libwayland-mac.dylib` stays in `.#wawona-macos-desktop-host`
only.

Ghostty is not a Wawona input. Do not link libghostty or GhosttyKit.
