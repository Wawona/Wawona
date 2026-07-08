# iOS Distribution Ops ([#23](https://github.com/Wawona/Wawona/issues/23) / [#24](https://github.com/Wawona/Wawona/issues/24) / [#27](https://github.com/Wawona/Wawona/issues/27))

Consolidated status for shipping Wawona to Apple beta/App Store channels. Most
of this is already implemented; the residue is App Store Connect data entry and
tester recruitment, which need a human with the developer account.

## #23 — App Store-compliant variant

The store-compliant build is not a separate app; it is the existing app run
under the `store-safe` **protocol profile**, which is enforced end-to-end:

- Profile gating in the Rust core (`src/core/wayland/mod.rs`,
  `src/tests/protocol_matrix.rs`) restricts advertised globals to what App
  Review permits; privileged wlr/virtual-input globals are not exposed.
- No `fork`/`exec`: bundled CLIs dispatch in-process (see
  [`ios-local-shell/SECURITY-SPAWN-POLICY.md`](./ios-local-shell/SECURITY-SPAWN-POLICY.md)).
- Compliance rationale and review notes:
  [`ios-local-shell/APP-STORE-COMPLIANCE.md`](./ios-local-shell/APP-STORE-COMPLIANCE.md),
  [`ios-local-shell/APP-REVIEW-NOTES.md`](./ios-local-shell/APP-REVIEW-NOTES.md).

Status: **implemented and shippable**; the `wawona-ios-ipa` output is the
store-bound artifact uploaded by Fastlane.

## #24 — TestFlight + Fastlane automation

Fully automated. Nix builds signed IPAs; Fastlane handles signing (`match`) and
upload.

- [`fastlane/Fastfile`](../fastlane/Fastfile): `ios beta` uploads iPhone, iPad,
  Apple TV, Apple Vision Pro, and Apple Watch to TestFlight; `ios release`
  submits for App Store review; `sync_version` / `validate_env` support lanes.
- [`.github/workflows/release-beta.yml`](../.github/workflows/release-beta.yml):
  push to `master` (or manual dispatch) runs `fastlane ios beta` on `macos-26`
  with the App Store Connect API key + `match` secrets from the `release-beta`
  GitHub Environment.
- Setup and secrets: [`fastlane/README.md`](../fastlane/README.md) and
  `.release-secrets.env.template`.

Status: **done.** No code work remains; it runs on every green push to master.

## #27 — Beta program

The pipeline supports external testers; the remaining work is
account/relationship, not code:

- [ ] Create the external tester group(s) in App Store Connect, then set
      `BETA_TESTFLIGHT_GROUPS` (comma-separated) so the `beta` lane distributes
      and notifies automatically (currently off until groups exist —
      see `fastlane/README.md`).
- [ ] Recruit testers and collect feedback (feedback email defaults to the
      value in the Fastfile; override with `BETA_FEEDBACK_EMAIL`).
- [ ] Populate App Store metadata/screenshots for public review (the lanes skip
      metadata/screenshots today).

## What needs a human (blockers for full close)

These require the Apple Developer account and cannot be scripted here:

1. App Store Connect app + platform version rows (the Fastfile creates version
   rows via `deliver` metadata-only, but the app record and agreements must
   exist first).
2. External TestFlight group creation + `BETA_TESTFLIGHT_GROUPS` value.
3. Store listing metadata, screenshots, and the actual review submission.
