---
name: wawona-test-tip-app
description: >-
  Tip-build + clean-launch Wawona before Appium, agent-device, or sim
  screenshot/AX. Covers macOS and Apple sims (tvOS/visionOS/iOS/watchOS).
  Never reuse a morning tip after Sources edits. Open before any UI proof.
---

# Tip Wawona app (all platforms)

Canonical rule: `docs/agent-rules/wawona-test-tip-app.md` (AlwaysApply
`wawona-test-tip-app`).

## Before any UI proof

```bash
# macOS
eval "$(scripts/appium/ensure-tip-wawona-macos.sh)"

# Apple Simulator (tvOS | visionOS | iOS | watchOS)
eval "$(scripts/appium/ensure-tip-wawona-apple-sim.sh tvOS)"
# exports WAWONA_APP_PATH WAWONA_SIM_UDID WAWONA_TIP_PLATFORM
xcrun simctl install "$WAWONA_SIM_UDID" "$WAWONA_APP_PATH"
```

Force rebuild: `WAWONA_TEST_REBUILD=1`.

## Freshness gate

```bash
source scripts/lib/require-tip-wawona-app.sh
wawona_require_tip_fresh_for_proof /tmp/wawona-tvos-tip   # or macos/ios/…
```

Stamps: `tip_root/git-HEAD` + `tip_root/product-FP`. Mtime of `.app` is not enough.

## Hard rejects

- Screenshot / AX / "fixed" without fresh `git-HEAD` + `product-FP`
- `WAWONA_TIP_SKIP_BUILD=1` after editing `Sources/` for the bug under test
- `/Applications/Wawona.app` or foreign DerivedData
- `WAWONA_ALLOW_STALE_TEST_APP=1` for Gate / catalog / clipping claims

## Related

`wawona-appium`, `wawona-nix-fresh-build`, `wawona-test-control`,
`wawona-agent-device`.
