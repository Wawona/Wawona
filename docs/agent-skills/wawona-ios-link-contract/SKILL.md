---
name: wawona-ios-link-contract
description: Apple app links must resolve every called C symbol from the .deps slice. Use when an iOS/xcodebuild link reports undefined symbols, or when editing the Xcode project's target folders.
---

# iOS link contract

Pointer only. Canonical: `Wawona/docs/agent-rules/wawona-ios-link-contract.md`.
Rule: `wawona-ios-link-contract`.

- Membership: synchronized folders. A file under a target's folders compiles unless the project lists it as an exception.
- Symbols: the scheme's own link is the check. Build every scheme a change reaches; refresh a stale slice with `nix run .#deps -- <sdk>`.

Do not stub a missing symbol. Rebuild the archive that owns it. Apple `nm` cannot read the Rust nightly archive.
