---
name: wawona-ios-min-os
description: Pointer for iOS 13-27+ min OS vs latest SDK. One ANGLE, one MoltenVK. Never downgrade iPhoneOS SDK. Open the wawona-ios-min-os rule.
---

# iOS min OS (pointer)

Open rule `wawona-ios-min-os`. Prose:
`Wawona/docs/agent-rules/wawona-ios-min-os.md`.
RAG: `wwn-mcp/knowledge/wawona/ios-min-os.md`.
Tracker: https://github.com/Wawona/Wawona/milestone/4 (meta #178).

## When

Editing `IPHONEOS_DEPLOYMENT_TARGET`, Apple `deploymentTarget`, ANGLE iOS,
MoltenVK iOS, `xcodegen.nix` iOS min, or `@available` / weak-link on iOS.

## Hard rejects (one line)

- Do not pin or downgrade the iPhoneOS SDK to match iOS 13
- Do not ship four ANGLE or four MoltenVK versions
- Do not let a dep recipe pick its own min OS. xcodegen iOS floor and the ANGLE plist fallback are 13.0, not 17.0. Tipa call site stays 14.0
- Do not compile Apple-mobile ObjC without the iOS 13 `-miphoneos-version-min`. SDK-default `.m` emits `_objc_release_xN` and dyld aborts on iOS 13-15. `ld -r` for iOS archives uses `IPHONEOS_DEPLOYMENT_TARGET`, never 17.0
- Do not replace Nix with a UTM-style CMake product root
- Do not put Metal/Vulkan cap policy in Swift when Rust can own it
- Do not restore iOS 11 or 12 ANGLE, EGL, GLES, Vulkan, or MoltenVK patches. Floor is 13.0. EGL is ANGLE(Metal). Vulkan is MoltenVK(Metal)
- Do not drop TrollStore / Sileo iOS 13-14 because ASC upload range is 15+
- Do not add extra GLES translation hops on iOS (ANGLE Metal is the path)
- Do not raise the iOS floor above 13.0 to link a newer dependency, and do not ship a product `.dylib` in an App Store IPA (static `.a` only; Apple `libswift*` is the exception)

Query `wwn-mcp` first (`where_to_edit` ANGLE/MoltenVK → `wwn-iland`;
`IPHONEOS_DEPLOYMENT_TARGET` → `wwn-toolchain`).

## iOS 13 shared UI checkpoint (2026-09-30)

`WawonaUI` compiles and links for `arm64-apple-ios13.0` with SDK 26.5.
Use XcodeDefault's Swift and pass the iPhoneOS path with both `--sdk` and
`-Xlinker -syslibroot -Xlinker PATH`. The separately installed Swift toolchain
linked host runtime paths despite `--sdk`; setting global SDKROOT to iPhoneOS
also breaks the macOS package manifest. Do not accept those warning-bearing links.
Host Swift package tests: 40 passed before the final tab-menu/lifecycle cleanup;
rerun after that cleanup. These are package checks, not full app/device proof.
Compatibility helpers live in `Sources/WawonaUI/Compatibility`; iOS 13 retains
machine cards, settings controls, file selection and client preview overview.
Older overview uses a stack; move/close-other actions remain in context menus.
Native task/onChange APIs remain selected where available. Full app linking,
representative-device UI tests, embedded-library minima and dependency pin
propagation remain open. Pure guest AOT is still a proposal, not implemented.

## Product compile and binary-floor repair (2026-09-30)

The complete unsigned iOS device app now compiles and links through
XcodeBuildMCP with SDK 26.5 and deployment target 13.0, including its watch
companion. Latest host UI tests: 40 passed. This first link used old renderer
pins and is not accepted as an iOS 13 artifact: embedded ANGLE plists claimed
13.0 while their Mach-O binaries require 16.0 / SDK 18.5. Inspect binaries.
The Mode A artifact gate now checks all embedded iOS slices and consumes otool
output fully to avoid SIGPIPE under pipefail. It rejects that old artifact.
Updated published graphics/toolchain pins; explicitly evaluate local Relay,
wwn-toolchain floor changes and static-renderer changes for current-source proof.
Device SwiftShader remains excluded by mobile-platform-deps and the existing
store firewall. The old simulator static SwiftShader release contains only its
Vulkan frontend and fails an actual link probe for Reactor/device/decoder
symbols. Source repair must merge the built target dependency archives and
namespace Vulkan entry points beside MoltenVK before accepting a new prebuilt.
Current-source renderer/app rebuilds remain pending; physical operation and
signed distribution are unverified. Map: docs/ios13-product-build-map.md.

### Current-source build isolation and archive tooling (2026-10-01)

Device iOS projects use a device-only dependency profile that retains native
phone, iPad and watch bundles. Simulator builds retain their own full profile;
physical-device evaluation need not force unrelated simulator/platform recipes.
Rebuilt ANGLE archives: all 501 object records are iOS 13.0 / SDK 26.5.
Rebuilt MoltenVK archive load-command record: iOS 13.0 / SDK 26.5. Final current
app and signed device operation remain pending.
SwiftShader source compiled all 1222 steps, then implicit xcrun selected an
unavailable macOS SDK during archive merge. Set DEVELOPER_DIR from find-xcode
and pass the target SDK explicitly to libtool and nm. The install repair is
under rebuild; complete static link proof remains required before acceptance.

### Native archive identity, ABI isolation and Lua closure (2026-10-01)

Current-source app linking exposed three packaging issues beyond UI compilation.
Client ld -r privatization stamped iOS 17.0 / SDK 17.0. It now honors the iOS
deployment setting and uses the actual SDK version; a real zsh archive proof
passed 13.0 / SDK 26.5. Generated prebuild scripts pass selected device or
simulator archive paths directly, preserving local source identity instead of
re-evaluating published inputs from the staged project. Invalid provided paths
fail. Neovim link flags no longer silently drop an unrealized native archive.

ANGLE's Metal-only build still includes 623 Volk Vulkan pointer globals.
MoltenVK function definitions replaced their data storage during linking.
Namespace those globals and references inside ANGLE; real archive proof found
zero public Vulkan globals and all 623 private definitions. The rebuilt source
package passed its new no-public-Vulkan-symbol gate.

Neovim lacked 84 Lua symbols because its collector recognized only modern
LC_BUILD_VERSION. An SDK 26.5 object compiled for iOS 11 reproduces the legacy
LC_VERSION_MIN_IPHONEOS record. Accept recognized legacy records only for the
matching target platform, consume complete otool output, and require real
lua_newstate and luaL_newstate definitions in the final native archive. Fixture
checks accept iOS device objects and reject simulator/macOS for device assembly.
The repaired local Neovim source is explicitly included in the consumer build.

SwiftShader source package and real provider-entrypoint link passed at iOS 13.0
/ SDK 26.5. Use required-entrypoint plus ordinary static archive resolution;
whole-archive loading also pulls unused LLVM disassembler objects with unrelated
undefined RTTI symbols. Full simulator runtime remains pending. Device products
continue to exclude SwiftShader. Overall complete app acceptance, physical
operation, authenticated guest readiness and real imported frames remain open.


## Complete current-source app and driver evidence (2026-10-01)

Complete unsigned phone/watch app now builds and passes Mode A, iOS 13 binary
floors and graphics bundle gates. Native Lua closure and private ANGLE Volk
storage fixes are linked, with zero newer-floor or Vulkan collision warnings.
Guest staging must honor optional initrd: direct-root manifests use null;
declared initrd remains mandatory and unsupported paths reject.
Shared environment help names SwiftShader without linking it. Use driver-owned
SwiftShader Device / SwiftShader driver / SwiftShaderUUID identifiers surviving
stripping, rather than arbitrary prose. A real linked provider probe still
fails the device gate. Signed device operation and VM completion remain open.
Evidence: Wawona/docs/ios13-product-build-map.md and .artifacts/relay-build.


## Native arm64 Simulator artifact evidence (2026-10-01)

SDK26.5 clang stamps a minimal arm64 iOS13 Simulator executable with
IOSSIMULATOR/min14.0. The complete phone/watch Simulator app matches: phone
main/model/UIContracts14.0, watch10.0, all SDK26.5. This does not change the
physical iOS13.0 floor. verify-ios-modeb-artifacts.sh --mode-a-simulator checks
platform7/arm64/floor14; --mode-a still checks device platform2/floor13.
Cross-platform negative tests reject both mismatches.
Simulator SwiftShader may be a real static ICD. Bundle gate requires all three
strong prefixed Vulkan entry points in the same binary plus driver-owned
identifiers. Device products still exclude it; no rendering claim from symbols.
Installing an immutable Nix-store app failed EACCES. Copy the complete bundle
to a writable artifact directory with ditto, change only permissions, then
install through agent-device preserving app data. Never omit bundled clients.
Evidence: simulator-guests-deployment.json, simulator-guests-*-gate-final.log,
device-*-gate-regression.log, and .artifacts/relay-build in Wawona.

Unsigned Simulator runtime integrity: CopySwiftLibs can leave an empty
Frameworks/libswift_Concurrency.dylib despite BUILD SUCCEEDED. The Mode A
artifact gate must reject empty/non-Mach-O dylibs before inspecting minima.
Standalone Apple swift-stdlib-tool repairs the measured unsigned Simulator
copy; retain its real arm64 slice/load commands. Do not patch signed/archive
outputs after signing. Runtime receipt: simulator-real-swift-runtime-gate.log.
A successful agent-device Start tap is not boot evidence: verify disk/session/
console progress. Fresh Stage1 QA saved/reopened 768 MiB/9 GiB; Start currently
has no observed effect. New launch error reporting awaits a full app rebuild.

Native VM profile reload cycle: serialize previously recreated empty
bundledAppID/useBundledApp fields that loadProfiles removed. Broadcasting Save
then schedules endless migration/reload. Keep native ABI serialization consistent
with its loader and publish only changed parsed values (not JSON key order).
Actual QA VM prefs showed empty ID/false flags. Runtime regression still needed.
Unconditional final Apple-copy + native slice extraction yielded a genuine
557440-byte runtime in the Nix Simulator app; conditional repair hooks did not.
Do not infer final-library integrity from hook execution or BUILD SUCCEEDED.
