# iOS link contract

An undefined symbol at Ld is a failed contract, not a linker surprise.

## Membership

Exact Apple hosts assemble the product `.app` / IPA. Sources that Exact
modules and `libwawona` export must resolve on that link line. There is no
committed `Wawona.xcodeproj` synchronized-folder membership.

## Symbols

Every C function the Exact iOS target calls (Relay ABI, non-weak `extern`)
must be exported by an archive on that SDK's link line, including
`libwawona.a` from `.build/backend/<sdk>` via `WAWONA_LINK_ARGS`. Exact's
`bun host/apple/build.mjs` link is the check: build every target a change
reaches before claiming it links.

A stale `.deps/<sdk>` slice (`cargo xtask deps get <sdk>`), or a backend that
does not export a required symbol, fails here. Do not stub the symbol.
Rebuild the archive that owns it.

Canonical: Exact cutover + `docs/compilation.md`.
