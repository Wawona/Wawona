# Android `__noChroot` Audit

Date: 2026-04-04

## Result

- No Android derivation currently requires `__noChroot`.
- Policy: Android derivations must remain sandboxed; introducing
  `__noChroot = true` in `*android.nix` is treated as a blocker.

## Retained Exceptions (Non-Android)

These remain because they depend on host Xcode/SDK tooling and are outside the
Android output path:

- iOS library/toolchain derivations under `dependencies/libs/*/ios.nix`
- `dependencies/toolchains/xcodeenv/*`
- iOS-only branches in `dependencies/wawona/rust-backend-c2n.nix`

## Enforcement

- CI runs `verify-android-nochroot.py` to fail fast if `__noChroot` appears in
  Android derivations.
