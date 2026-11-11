# iOS link contract

An undefined symbol at Ld is a failed contract, not a linker surprise.

## Membership

`Wawona.xcodeproj/project.xcproj` uses synchronized folders: every source
under a target's folders compiles for that target unless the project lists it
as an exception. Adding a file needs no project edit. Moving a file out of a
folder, or adding an exception, is a project change to review.

## Symbols

Every C function the target calls (Relay ABI, and non-weak `extern` uses)
must be exported by an archive on that SDK's link line, including
`libwawona.a` from `.deps/<sdk>/backend`. The link of each scheme is the
check: build every scheme a change can reach (macOS, the four simulator
schemes, and a device archive through Nix) before claiming it links.

A stale `.deps/<sdk>` slice (`cargo xtask deps get <sdk>` refreshes it), or a
backend built from waypipe that does not export `wwn_waypipe_client_fd`,
fails here. Do not stub the symbol. Rebuild the archive that owns it.
