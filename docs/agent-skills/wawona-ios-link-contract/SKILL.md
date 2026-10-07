---
name: wawona-ios-link-contract
description: Fail Apple app builds before compile when a source file or called C symbol is missing from the link. Use when an iOS/xcodebuild link reports undefined symbols, or when editing xcode-prebuild or the Xcode project sources.
---

# iOS link contract

Pointer only. Canonical: `Wawona/docs/agent-rules/wawona-ios-link-contract.md`.
Rule: `wawona-ios-link-contract`.

`scripts/xcode-prebuild.sh` runs `scripts/verify-link-contract.py`.

- `membership` before Nix. xcodegen's source globs must all be in the target Sources phase.
- `symbols` after `libwawona.a` is copied. Called C symbols must be exported by an archive on that SDK link line.

Do not stub a missing symbol. Rebuild the archive that owns it. Apple `nm` cannot read the Rust nightly archive.
