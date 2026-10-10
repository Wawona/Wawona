# CalVer must be today (fail closed)

Wawona marketing version is CalVer `YY.M.D` (no zero-pad), e.g. `26.10.10`.

When building product artifacts (Xcode, tipa, IPA, nix product packages)
while iterating with AI, **VERSION must equal today's date** in
`America/Los_Angeles`. Stale CalVer fails the build by default.

## Required files

| File | Field |
|---|---|
| `VERSION` | `YY.M.D` |
| `Cargo.toml` `[package].version` | same |
| `Cargo.lock` `name = "wawona"` version | same |

## Gate

`.github/scripts/verify-calver-today.sh`

Wired into:

- `scripts/xcode-prebuild.sh` (every Xcode target)
- `.#wawona-ios-modeb-tipa` / `.#wawona-ios-modeb-tipa-slim` packaging

## Agent loop

1. Before build: if `VERSION` ≠ today → bump `VERSION` + `Cargo.toml` +
   `Cargo.lock`, commit on `development`.
2. Never ship yesterday's CalVer as a fresh tipa/IPA from an AI session.
3. Escape only for intentional rebuild of a past tip:
   `WAWONA_ALLOW_STALE_CALVER=1`.

## Hard rejects

- Building tipa/IPA/Xcode while `VERSION` is an older day
- Soft-warn and continue
- Inventing `0.1.0` or non-CalVer marketing versions
