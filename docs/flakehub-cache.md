# FlakeHub Cache (Wawona org shared binary cache)

Wawona uses **Determinate FlakeHub Cache** (`https://cache.flakehub.com`) as the
org-wide Nix binary cache. There is **no** self-hosted Attic/Cachix or
`cache.wawona.io`.

Companion: [`2026-build-ci-optimization.md`](./2026-build-ci-optimization.md).
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
| Fork PRs | No FlakeHub Cache auth — rebuild cold |
| Laptop push | Not allowed — only trusted CI builders push |

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

Do **not** use `DeterminateSystems/magic-nix-cache-action` for new work — it is
GHA-scoped only and superseded here by FlakeHub Cache.

## Measuring hit rate

After landing cache wiring on `development` / `main`:

1. Open a green **Nix CI** run → build job logs → search for `cache.flakehub.com`
   / substitute messages.
2. Compare wall-clock of the build matrix job before vs after a warm cache
   (same attrs, unchanged flake inputs).
3. On a laptop with a clean-ish store, time `nix build` of a known substrate
   attr twice (first may still compile; second / peer machine should substitute).

FlakeHub does **not** reduce Nix **eval** / crate2nix IFD cost — see issue #68
Phases 3–4 for that work.

## Issue #68

Tracking issue [#68](https://github.com/Wawona/Wawona/issues/68) cache policy now matches this doc:
FlakeHub Cache in; Magic Nix Cache retired; no self-hosted Attic/Cachix.

## Baseline wall-time (pre–FlakeHub wiring)

Sample from Nix CI run `28757935270` (2026-07-05, `master`, overall ~29 min
wall, several jobs failed — use only as a rough pre-cache reference):

| Job class | Approx window |
|-----------|----------------|
| Sample successful cargo test (macOS arm64) | ~29 min (`23:02`–`23:32`) |
| Sample successful cargo test (Linux) | ~12 min (`23:02`–`23:14`) |

After FlakeHub is warm on green `main`/`development` builds:

1. Re-run the same attrs and compare matrix job durations.
2. Grep logs for `cache.flakehub.com` / substitute hits.
3. Only then resume #68 **4.1** (curated PR matrix) and **3.1** (IFD hoist) —
   those are eval/matrix work, not cache wiring.
