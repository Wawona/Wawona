# FlakeHub Cache (Wawona org shared binary cache)

Wawona uses **Determinate FlakeHub Cache** (`https://cache.flakehub.com`) as the
org-wide Nix binary cache. There is **no** self-hosted Attic/Cachix or
`cache.wawona.io`.

Companion: [`flakehub-registry.md`](./flakehub-registry.md) (versioned flake
refs. **not** this cache), [`2026-build-ci-optimization.md`](./2026-build-ci-optimization.md),
[`ci.md`](./ci.md) (branch × workflow + curated matrix).
Upstream docs: [FlakeHub Cache](https://docs.determinate.systems/flakehub/cache).

## What it does

- **CI push:** `DeterminateSystems/flakehub-cache-action@v3` on trusted GitHub
  Actions runners uploads store paths after builds (OIDC via `id-token: write`).
- **CI / laptop pull:** same cache; developers authenticate with Determinate Nix.
- **Cross-repo:** `wwn-toolchain`, `wwn-weston`, and other `wwn-*` owners populate
  paths; Wawona substitutes when derivation hashes match (single nixpkgs lineage).

## Local developer setup

1. Use **Determinate Nix** (the org standard; CI already sets `determinate: true`).
2. Log in once:

   ```bash
   determinate-nixd login
   # or: fh login
   ```

3. Confirm:

   ```bash
   determinate-nixd status
   # Logged in: true
   ```

4. Build something that owner CI has already produced (example after a green
   `wwn-toolchain` push):

   ```bash
   cd ~/Wawona/wwn-toolchain
   nix build .#packages.aarch64-darwin.xkbcommon-ios -L
   ```

   Look for substitute / download activity from `cache.flakehub.com` instead of a
   full cold compile when the hash is already cached.

## Limits

| Case | Behavior |
|------|----------|
| Org member, logged in | Pull FlakeHub Cache slices for flakes you can access |
| Anonymous / no login | Cold rebuild (`cache.nixos.org` only) |
| Fork PRs | No FlakeHub Cache auth. Rebuild cold |
| Laptop push | Not allowed. Only trusted CI builders push |

## CI fragment (every Nix-building job)

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: actions/checkout@v4
  - uses: DeterminateSystems/nix-installer-action@v22  # or @main on wwn-*
    with:
      determinate: true
  - uses: DeterminateSystems/flakehub-cache-action@v3
  - run: nix build …
```

Do **not** use `DeterminateSystems/magic-nix-cache-action` for new work. It is
GHA-scoped only and superseded here by FlakeHub Cache.

## Measuring hit rate

After landing cache wiring on `development` / `main`:

1. Open a green **Gate: packages** or **Build: products** run → build job logs → search for
   `cache.flakehub.com` / substitute messages.
2. Compare wall-clock of the build matrix / product-build job before vs after a
   warm cache (same attrs, unchanged flake inputs).
3. On a warm tip, Gate: products GUI smoke should **download** `product-*` artifacts
   (seconds) rather than recompile `wawona-ios` / `wawona-android` / `wawona-macos`.
4. On a laptop with a clean-ish store, time `nix build` of a known substrate
   attr twice (first may still compile; second / peer machine should substitute).

FlakeHub does **not** reduce Nix **eval** / crate2nix IFD cost, and it does
**not** ship Apple platform SDKs. Runner speedups for those:

- Pin host Xcode ([`select-xcode.sh`](../.github/scripts/select-xcode.sh); see [`ci.md`](./ci.md))
- Warm host simulator SDKs before Apple `xcodebuild` ([`warm-ios-simulator-sdk.sh`](../.github/scripts/warm-ios-simulator-sdk.sh) on ios-sim, apple-family, and frontend-syntax)
- Path-filter Darwin Gate: packages cells on docs-only tips
- Hoist `generatedCargoNix` per `workspace-src-*` (ios / macos / watchos)
- `nixConfig` / CI `max-jobs` + `cores`

L2 `build` jobs append a FlakeHub hit probe to the step summary (`nix path-info`
+ `cache.flakehub.com`). Treat “likely” as a hint. Same-job local builds can
false-positive.

## Issue #68

Tracking issue [#68](https://github.com/Wawona/Wawona/issues/68): FlakeHub Cache
in; Magic Nix Cache retired; curated matrix landed
([`ci-package-matrix.json`](../.github/ci-package-matrix.json)); Xcode pin and
simulator-SDK warm scripts are in. Remaining wins are FlakeHub hit rate, path
filters, IFD hoist, and runner cores. **not** `apple-sdks.nix` / packaged
Apple frameworks as a product sysroot.
