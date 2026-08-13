> **Superseded.** Historical. Live Android facts: [`../../2026-SOURCE-OF-TRUTH.md`](../../2026-SOURCE-OF-TRUTH.md). Do not copy to wawona.io.

# Android `__noChroot` Audit

Date: 2026-04-04

## Result

- No Android derivation currently requires `__noChroot`.
- Policy: Android derivations must remain sandboxed; introducing
  `__noChroot = true` in `*android.nix` is treated as a blocker.

## Retained Exceptions (Non-Android)

These remain because they depend on host Xcode/SDK tooling and are outside the
Android output path:

- iOS library/toolchain derivations under `wwn-toolchain/dependencies/libs/*/ios.nix`
- `wwn-toolchain/dependencies/toolchains/xcodeenv/*`
- iOS-only branches in `dependencies/wawona/rust-backend-c2n.nix`

## Enforcement

- CI runs `verify-android-nochroot.py` to fail fast if `__noChroot` appears in
  Android derivations.
