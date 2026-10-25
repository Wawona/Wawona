# Apple device archive escaped the green product gate

Date: 2026-10-24

## Impact

Gate: products passed, then the TestFlight workflow failed while archiving the
iOS app with its embedded Watch app. No IPA reached App Store Connect. The
product gate only built simulator products, so it did not cover this signed
device archive path.

## Failure map

| Stage | Evidence | Failure | Fix |
|---|---|---|---|
| Fastlane host environment | Release workflow runs under `nix develop`; the Xcode phase log named `Build Rust Backend via Nix` | The dev shell exports `NIX_BUILD_TOP`, which `xcode-prebuild.sh` treats as proof it is inside a Nix derivation and requires injected library paths. The host release lane did not inject those paths. | `scripts/release-env.sh` clears `NIX_BUILD_TOP` before starting host Fastlane. The Xcode phase can realize its backend through the Nix daemon. |
| Embedded Watch Swift compile | Local signed `Wawona-iOS` archive, `Wawona-watchOS`, `WatchTerminalScreen.swift` lines 332 and 370 | The file declared `wwn_term_string_free` with `@_silgen_name`, while `WatchNativeShell.swift` already declared that same symbol as `WatchShellABI.termStringFree`. Swift reported a function convention mismatch. | Use the shared ABI wrapper from `WatchTerminalScreen` and make the wrapper enum module-internal. |
| Embedded Watch arm64_32 link | Local signed archive linker diagnostics for architecture `arm64_32` | The compatibility slice intentionally omits Nix Rust, PTY, and terminal archives, but Watch Swift still referenced their C ABI symbols. Existing Watch stubs did not define the complete surface. | Add weak fail-closed ABI definitions for this slice in `src/platform/watchos/WWNWatchStubs.c`. The arm64 slice continues to link the real Nix libraries. |
| Store upload ordering | `fastlane ios beta` iterated targets as archive, validate, upload | A later Apple target could fail after an earlier target had already been uploaded. | Archive, export, and validate every selected Apple IPA first. Upload the exact prepared IPA files only after the whole set passes. |

The first blocker was the phase named in the CI report. Fixing it exposed two
additional defects that simulator-only builds had not compiled or linked. The
archive itself is the necessary proof for all three.

## Graph model

| Subject | Relation | Object | Provenance |
|---|---|---|---|
| Gate: products | BUILDS_SIMULATOR_ONLY_FOR | Apple product matrix | `.github/workflows/device-gate.yml` |
| Ship: beta (stores) | RUNS_AFTER_SUCCESS_OF | Gate: products | `.github/workflows/release-beta.yml` |
| Wawona-iOS device archive | EMBEDS_AND_COMPILES | Wawona-watchOS | Generated `Wawona-iOS` scheme |
| Wawona-watchOS arm64_32 | OMITS | Nix Rust, PTY, terminal archives | `dependencies/generators/xcodegen.nix` linker settings |
| Watch Swift bridge | CALLS | C ABI functions | `Sources/WawonaWatch/WatchNativeShell.swift`, `Sources/WawonaApple/Watch/WatchCompositorBridge.swift` |
| `ios beta` lane | PREFLIGHTS_ALL_IPAS_BEFORE | TestFlight upload | `fastlane/Fastfile` |

## Release invariant

Every selected Apple beta target must archive, export, and pass all local IPA
assertions before the first ASC upload. Upload those same verified IPA files.
The iOS archive must include its signed Watch companion. A green simulator
matrix alone is not evidence that the store archive can be uploaded.

Reproduce the iOS plus Watch archive and export without upload with
`CI=true WAWONA_DEBUG_SCHEME=Wawona-iOS fastlane ios debug_export`.
