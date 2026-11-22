# Android upgrade guardrails

Product Android builds go through Exact (`cargo xtask build|archive android`).
Root `android/app/build.gradle.kts` is deleted.

## Pins

Keep Exact `host/android` NDK / compileSdk / targetSdk aligned with
`wwn-toolchain` sdk-config (`.#wwnSdkConfigPath`). CI
`setup-xtask` installs the Exact NDK pin (or `ANDROID_NDK_VERSION`).

Checklist when bumping Android SDK / NDK:

- [ ] Exact `host/android/app/build.gradle.kts` (or equivalent) matches sdk-config
- [ ] `cargo xtask deps get android` + `cargo xtask build android` locally
- [ ] Fastlane / Play AAB path still finds the Exact output under
  `exact/host/android/app/build/…`

## Hard rejects

- Reviving root Gradle as the product host
- Claiming Android Studio on a deleted `android/app` tree is the ship path
