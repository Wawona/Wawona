# iOS min OS vs latest SDK (11.0, SDK never downgrades)

Wawona iOS (phone and iPad) must run on **iOS 11 through current**, compiled
**only** against the **latest** iPhoneOS SDK. Today that SDK is **26**. When
iOS 27 ships, the SDK becomes 27. The SDK is never pinned backward to match
an old OS.

Apple skipped iOS 19-25. Versions in full consideration: 11, 12, 13, 14, 15,
16, 17, 18, 26, and 27 when that SDK exists.

This applies to **App Store Mode A**, **TrollStore `.tipa`**, and **Sileo
jailbreak** products. Mode B engines still never enter the store IPA
(`wawona-ios-mode-b-channels`).

Current product: iOS 26 only. Older iOS is unfinished work (`planned`), not
unsupported.

Cursor rule: `wawona-ios-min-os`.
Skill: `wawona-ios-min-os`.
RAG: `wwn-mcp/knowledge/wawona/ios-min-os.md`.
GitHub milestone: [`iOS 11-27 (latest SDK, ANGLE + MoltenVK)`](https://github.com/Wawona/Wawona/milestone/4).
Tracker: [`#178`](https://github.com/Wawona/Wawona/issues/178). Product issues live in
`Wawona/Wawona`; there is no `Wawona/issues` repository.

## Two knobs (never conflate)

| Knob | Value | Where |
|---|---|---|
| SDK / sysroot | Latest only (`iPhoneOS26.sdk` now) | Nix Apple toolchain, xcodebuild, ANGLE GN, MoltenVK |
| Deployment target / min OS | **11.0** | One Wawona-owned `deploymentTarget`. Mach-O minos |

Wawona chooses the min OS. ANGLE, MoltenVK, and other deps do not.

## One binary, one ANGLE, one MoltenVK

```text
ONE Wawona iOS build
  ├── ONE ANGLE (Metal). iOS 11 compatibility is a Wawona patch
  └── ONE MoltenVK (Metal). iOS 11-14 compatibility is a Wawona patch

Runtime MTLDevice caps decide GLES/Vulkan features.
```

Not four ANGLE versions. Not four MoltenVK versions.

iOS GLES is ANGLE(Metal). iOS Vulkan is MoltenVK(Metal). Do not add extra
translation hops.

## Upstream floors (why patches exist)

| Component | Upstream floor | Wawona |
|---|---|---|
| ANGLE Metal | iOS 12+ | Patch restores iOS 11 |
| MoltenVK 1.4.2+ | iOS 15+ | Patch restores iOS 11-14 |
| Metal itself | Present on iOS 11+ arm64 | Present on every version in scope |

Current L1 iOS recipes still unpack **prebuilts** (XCSoar ANGLE; Khronos
MoltenVK 1.4.1 `MoltenVK-all.tar`). Those cannot carry Wawona min-OS patches.
The iOS 11 path **source-builds** both in `wwn-iland` and applies a thin
patch queue.

## Nix owns the toolchain (not a CMake product root)

L0 `wwn-toolchain` `dependencies/apple/default.nix` is the single
`deploymentTarget` (today default `"17.0"`; this work moves it to `"11.0"`).
L1 ANGLE GN / MoltenVK CMake consume that plus the latest SDK.

Study UTM/SDL/Godot/Dolphin/VLC for *ideas* (one toolchain config, deps inherit
min OS, static MoltenVK). Do **not** replace the Nix flake with a UTM-style
`cmake/toolchains/WawonaApple.cmake` product root. Do **not** adopt UTM's VM
display stack.

## Runtime caps, not scattered OS version checks

Rust owns the capability policy (`WWNMetalCapabilities` or equivalent).
ObjC/Metal is a trampoline that fills it from `MTLDevice`.

Ask Metal what the device can do. Missing Metal feature: do not advertise
the matching Vulkan/GLES cap. Do not fake it.

`@available(iOS 15.0, *)` is for **API existence** when compiling against the
new SDK. It is not a substitute for the capability struct.

## App Store Connect vs Mach-O

Clang can emit minos 11.0 against SDK 26. Apple's Xcode 26 App Store Connect
table currently lists iOS 15-26 as the supported upload range. Treat that as
a **separate investigation**, not a reason to drop iOS 11-14 from TrollStore
or Sileo, and not a reason to compile against an old SDK.

## Channels

Same min-OS source for:

- App Store / TestFlight Mode A
- TrollStore `.tipa`
- Sileo rootless/rootful

Store IPA still has no JIT, no IOMFB SPI, no jailbreak copy.

## Where to edit

| Change | Repo |
|---|---|
| Single `deploymentTarget` / latest SDK | `wwn-toolchain` |
| ANGLE / MoltenVK recipes and patches | `wwn-iland` |
| `@available`, weak-link, Swift/ObjC/Rust guards | `Wawona` |
| This rule / RAG | `Wawona` + `wwn-mcp` |

iPadOS shares this iOS min. tvOS, watchOS, and visionOS are **not** this
rule (those keep their own mins).

## Hard rejects

- Downgrade `iphoneos` SDK / `-isysroot` to "help" iOS 11
- Multiple ANGLE or MoltenVK artifacts per iOS version
- Letting a dep recipe set its own `IPHONEOS_DEPLOYMENT_TARGET`
- Permanent heavily diverged ANGLE/MoltenVK forks (use patch queues on a
  pinned upstream commit)
- Replacing Nix with a CMake/Xcode-only dependency forest
- Putting Metal/Vulkan cap policy in ObjC when Rust can own it
- Shipping Mode B / JIT / IOMFB in the store IPA
- Treating iOS 11-14 as out of scope for TrollStore or Sileo because ASC
  upload range is 15+
