# Wawona Fastlane

Nix builds the artifacts; Fastlane orchestrates signing (match) and uploads (TestFlight / Play).

## TestFlight platforms

`fastlane ios beta` uploads **five** builds to TestFlight:

| Device | Nix output | Bundle ID |
|--------|------------|-----------|
| iPhone | `wawona-ios-ipa` | `com.aspauldingcode.Wawona` |
| iPad | `wawona-ipados-ipa` | `com.aspauldingcode.Wawona` |
| Apple TV | `wawona-tvos-ipa` | `com.aspauldingcode.Wawona` |
| Apple Vision Pro | `wawona-visionos-ipa` | `com.aspauldingcode.Wawona` (iOS appstore profile) |
| Apple Watch | `wawona-watchos-ipa` | `com.aspauldingcode.Wawona.watch` |

**macOS is not uploaded** — the macOS app is distributed outside TestFlight.

TestFlight beta feedback email: `aspauldingcode@gmail.com` (override with `BETA_FEEDBACK_EMAIL`).

External tester auto-distribution is **off** until you create groups in App Store Connect. Set `BETA_TESTFLIGHT_GROUPS=Wawona Beta` (comma-separated) to enable upload → wait for processing → distribute + notify.

## App Store Connect setup

In [App Store Connect](https://appstoreconnect.apple.com), create (or verify) a **Wawona** app with bundle ID `com.aspauldingcode.Wawona` and enable platforms: iOS, tvOS, visionOS. The watch app uses `com.aspauldingcode.Wawona.watch` as a companion to the iOS app.

## Prerequisites

- `nix develop` (provides fastlane, ruby, cocoapods, jdk17)
- `.release-secrets.env` copied from `.release-secrets.env.template` (store keys under `.secrets/` — gitignored)
- `aspauldingcode/apple-signing` populated via `scripts/bootstrap-apple-signing.sh`
- GitHub Environment `release-beta` secrets synced via `scripts/sync-github-secrets.sh --apple-only` (Android/Play when Google verification completes)

See `.release-secrets.env.template` for step-by-step instructions on obtaining each secret value.

## Versioning

Single source of truth: `VERSION` (currently `0.2.4`).

Fastlane reads `WAWONA_VERSION` (optional override; strips a leading `v` from tags) and `WAWONA_BUILD_NUMBER` (defaults to `GITHUB_RUN_NUMBER` in CI, or a timestamp locally). Both are passed into `nix build --impure` so every IPA gets the same marketing version and build number.

Before uploading, Fastlane also calls `deliver` (metadata-only) for **iOS, tvOS, and visionOS** so App Store Connect has a `0.2.4` version row on each platform — fixing the default `1.0` placeholder on tvOS/visionOS.

## Local beta upload

```bash
cd Wawona
source .release-secrets.env
export TEAM_ID WAWONA_VERSION=0.2.4 WAWONA_BUILD_NUMBER=1
nix develop --command bash -lc 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fastlane ios beta'
```

## CI

`.github/workflows/release-beta.yml` runs `fastlane ios beta` (Apple only) via workflow dispatch or tag `v0.2.*`.

Use workflow input `ios beta` for Apple platforms only; `android beta` when Play secrets are ready.
