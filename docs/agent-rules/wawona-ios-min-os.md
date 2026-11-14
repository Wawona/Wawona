# iOS minimum OS and latest SDK

## Exact product floor (2026-11-14 cutover)

The **shipping** Apple-mobile binary is Exact `apps/wawona` assembled by
`bun host/apple/build.mjs` / `cargo xtask archive ios`. Exact
`host.ios.minimumOS` is **17.0**. Product IPA / TestFlight / App Store
therefore floors at **iOS 17.0**. Bundle id stays `com.aspauldingcode.Wawona`
(Exact `app.json`).

Rust backend slices (`xtask/src/slices.rs`) and L0 archives may still compile
at a lower Mach-O min so they link into Exact; they must not raise the Exact
host floor.

## Legacy dual-run note

Before Exact product ship, SwiftUI dual-run apps targeted **15.0** against the
iPhoneOS 27 SDK. That floor applied to `Wawona.xcodeproj` (deleted). Do not
revive a 15.0 Xcode product project to "support iOS 15".

## Build contract

- Exact `apps/wawona/app.json` `host.ios.minimumOS` = `17.0`.
- `cargo xtask deps get` / `backend` stage `.deps` + `.build/backend` for Exact
  `WAWONA_LINK_ARGS`.
- Use the latest installed iPhoneOS SDK (Xcode 27). Never downgrade the SDK.
- tvOS, watchOS, visionOS and macOS retain Exact host deployment targets.
- Mode B tipa/deb: Exact or `cargo xtask package` over Exact device build; ldid
  on the Exact `.app`. Document `Depends: firmware (>= 17.0)` when packaging.

## Renderer and UI

One native static ANGLE/Metal and one MoltenVK/Metal set when linked.
Present is Exact `wayland-present` NativeView (`modules/apple/Present.swift`)
plus `libwawona` when linked. No Objective-C product classes.

## Distribution channels

Exact IPA is Mode A store path. TrollStore / Sileo Mode B remain separate
artifacts from `cargo xtask package`, never mixed into ASC uploads.

## Verification

Audit Exact IPA load commands and ASC asserts (`assert_no_loose_dylibs!`,
`assert_ipa_has_swift_support!`). Exercise Machines Start → Present surface
(`wwn.compositor.surface`) on iOS 17+ simulators/devices.

## Ownership

Toolchain: `wwn-toolchain`. Graphics: `iLand`. Chrome: Exact. Glue: Wawona
`cargo xtask` + Present module. Relay stays Rust.
