# iOS link contract

An undefined symbol at Ld is a failed contract, not a linker surprise.
`scripts/xcode-prebuild.sh` runs `scripts/verify-link-contract.py` on every
Apple app target.

## Membership

Every file xcodegen would compile for that target must be in the target's
Sources phase. A dropped `.m` or `.swift` becomes an undefined ObjC class or
Swift type after the compile. The check runs before Nix.

## Symbols

Every C function the target calls (Relay ABI, and non-weak `extern` uses)
must be present in an archive on that SDK's link line, including
`libwawona.a`. Weak shims and bare declarations are not required. Apple `nm`
cannot read the Rust nightly archive. The check searches the exported name
in the archive bytes.

A stale `.nix-deps` Relay archive, or a backend built from waypipe that does
not export `wwn_waypipe_client_fd`, fails here. Do not stub the symbol.
Rebuild the archive that owns it.
