# Apple store archive preflight

Apple beta release workflow must archive, export, and validate every selected
device IPA before its first App Store Connect upload. Upload the same validated
IPA files. Do not interleave archive and upload per target.

Simulator product gates do not validate the signed iOS device archive or its
embedded Watch app. `Wawona-iOS` must compile `Wawona-watchOS` as its companion
under `Watch/`. Reproduce the device path with
`CI=true WAWONA_DEBUG_SCHEME=Wawona-iOS fastlane ios debug_export`.

The arm64_32 compatibility slice intentionally has no Nix Rust, PTY, or
terminal libraries. Swift-referenced C ABI symbols in that slice require weak,
fail-closed Watch stubs. The arm64 slice must still link the real libraries.

See `docs/agent-skills/wawona-store-archive-preflight/SKILL.md` and `docs/ci.md`.
