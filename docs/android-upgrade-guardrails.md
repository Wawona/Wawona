# Android SDK/NDK Upgrade Guardrails

This checklist is mandatory for any change that touches Android version pins or
toolchain selection logic.

## Scope Triggers

Treat a PR as an Android upgrade PR when any of the following files change:

- `dependencies/android/sdk-config.nix`
- `android/app/build.gradle.kts`
- `dependencies/toolchains/android.nix`
- `dependencies/toolchains/android-cmake.nix`
- `.github/scripts/verify-android-config.py`

## Pre-upgrade Checklist

- [ ] Confirm target change set (SDK, NDK, build-tools, CMake/toolchain behavior).
- [ ] Update `dependencies/android/sdk-config.nix`.
- [ ] Keep `android/app/build.gradle.kts` values aligned to sdk-config.
- [ ] Run `python3 ./.github/scripts/verify-android-config.py`.
- [ ] Run `python3 ./.github/scripts/ci-failure-baseline.py --limit 11`.

## Platform Smoke Validation

All four host platforms must complete smoke gates before merge:

- [ ] `linux-x86_64`
- [ ] `linux-arm64`
- [ ] `darwin-arm64`
- [ ] `darwin-x86_64`

Required smoke outputs:

- Android backend (`wawona-android-backend`)
- Darwin Android path (`wawona-android` and `gradlegen`)

## Blocker Signatures

The following signatures are release blockers for upgrade PRs:

- `toolchain_path_missing`
- `neon_builtin_mismatch`
- `gradle_daemon`
- `gradle_oom`

## Acceptance Criteria

Upgrade is accepted only when all are true:

1. `verify-android-config.py` passes on CI prepare jobs.
2. Baseline artifact (`ci-failure-baseline.md` + `.json`) is produced.
3. Blocker threshold job reports zero blocker signatures on the current run.
4. No new High-severity Android signature appears in the 10-run comparison
   window after merge.
