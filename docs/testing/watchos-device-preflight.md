# WatchOS Device Build Preflight

The product gate builds `.#wawona-watchos-app-device` before its simulator app.
This runs the generated Watch target for the device SDK, including the
`Build Rust Backend via Nix` phase and the final Xcode link. It catches
watchOS archive failures before the store upload workflow can start. A
simulator app build alone is not sufficient because product app generators
may omit the device Watch target.

## Failure and repair

On 2026-10-26, Gate: products failed at the iPadOS, visionOS, and watchOS
simulator links with an undefined `_wwn_term_refresh_scrollback_cap` symbol.
The Rust `Term` type had the host pressure refresh method, but the Terminal
revision pinned in `flake.lock` did not export its C ABI symbol. The adjacent
local Terminal checkout was newer and did export it, which made local Cargo
builds conceal the locked source mismatch. Each failure occurred at the final
Xcode link after the Rust backend phase had succeeded.

The Rust backend now provides the missing ABI export behind the
`terminal-pinned-ffi` feature. Every Apple product backend enables that feature
because the same Swift host-pressure hook is used by iOS, iPadOS, tvOS,
visionOS, watchOS, and macOS. Keep it disabled for default Cargo builds. This
avoids a duplicate symbol when the Terminal source already exports the
function. Duplicate zstd library and unavailable `CoreAudioTypes` warnings in
the failing logs were not the cause.

The device archive preflight then exposed a separate `arm64_32` link failure.
That compatibility slice intentionally omits the Nix Rust, PTY, and terminal
archives, but Watch Swift still references their C ABI. `WWNWatchStubs.c` now
provides weak, fail-closed definitions for those references only when
`__LP64__` is absent. They return null, false, or an error value and cannot
start a shell or compositor. LP64 device and simulator slices continue to link
the real libraries. The archive log's list of unresolved symbols, rather than
the earlier Rust backend success, identified the missing coverage.

## Verification

Build `.#wawona-watchos-app-device`, `.#wawona-watchos-app-sim`,
`.#wawona-ipados-app-sim`, and `.#wawona-visionos-app-sim` on the current tip.
The Watch device target validates both the LP64 archive and arm64_32
compatibility link. The simulator targets check the relevant Apple UI and
terminal ABI links. Every listed build must pass before promoting a release
candidate.
