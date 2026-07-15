# Wawona — Build & CI Optimization

How to keep build/CI time bounded across the Wawona monorepo and the `wwn-*`
port repos. Companion to [`2026-greenlight-gates.md`](./2026-greenlight-gates.md)
and [`2026-universal-client-strategy.md`](./2026-universal-client-strategy.md).

## Local build perf (this M1 MBA)

- **Cargo profiles** (`Cargo.toml`): `release` uses `lto = "thin"`,
  `codegen-units = 1`, `strip = "debuginfo"`; `dev` uses `opt-level = 1` with
  dependencies at `opt-level = 2` (`[profile.dev.package."*"]`) so the smithay/
  wayland hot paths aren't crippled at `-O0` while our crate stays fast to
  iterate. `panic` stays `unwind` (FFI poison recovery uses `catch_unwind`).
- **Incremental**: `nix develop -c cargo build --lib` for the fast inner loop;
  full app builds only when native/plist/entitlement inputs change.
- **Runtime QoS**: Android render thread runs at urgent-display nice; macOS/iOS
  composite on a `USER_INTERACTIVE` queue.

## Shared binary cache (all repos)

**Policy:** org **FlakeHub Cache** (Determinate). No self-hosted Attic/Cachix /
`cache.wawona.io`. Magic Nix Cache is retired in favor of FlakeHub.

Operational runbook: [`flakehub-cache.md`](./flakehub-cache.md).

- CI installs Nix via `DeterminateSystems/nix-installer-action` with
  `determinate: true`, then `DeterminateSystems/flakehub-cache-action@v3`
  (`permissions.id-token: write`). Trusted builders push; runners and logged-in
  laptops pull from `cache.flakehub.com`.
- Cross-repo sharing (Wawona ↔ `wwn-*`): the repo that **owns** the derivation
  builds it in CI (e.g. `wwn-toolchain` substrate, `wwn-weston` archives). Wawona
  substitutes when store hashes match (single nixpkgs lineage via `follows` +
  `verify-nixpkgs-lineage.py`).
- Local: `determinate-nixd login` (or `fh login`). Fork PRs and anonymous
  contributors rebuild cold.

## Per-repo CI dedupe

- **One owner per artifact.** `wwn-toolchain` builds toolchains; `wwn-weston`
  builds Weston + clients; Wawona consumes them via flake inputs and **FlakeHub
  Cache** substitutes. Do not rebuild a sibling's artifact in Wawona CI when the
  hash is already cached.
- **Product binaries once per SHA.** [`product-build.yml`](../.github/workflows/product-build.yml)
  owns `wawona-ios` / `wawona-android` / `wawona-macos` / `wawona-appimage`.
  [`device-gate.yml`](../.github/workflows/device-gate.yml) runs product-build
  then Device e2e with `products_ready`. Release packages DMG/APK/AppImage from
  those GHA artifacts; Release Beta resolves AppImages by SHA when possible.
  Impure IPA/AAB stay publish-only. See [`ci.md`](./ci.md).
- **Curated push/PR matrix.** `nix.yml` builds only
  [`.github/ci-package-matrix.json`](../.github/ci-package-matrix.json)
  (backends / substrate — not full product apps).
- **Branch parity.** `development` and `master` both run Nix CI + Android parity
  + Device gate. Release Beta / Release stay on `master` / tags.
- **Path filters.** `device-gate.yml` / `android-parity.yml` use path filters so
  docs-only changes skip native builds.
- **Fast PR gate vs nightly.**
  - *Push gate* (`nix.yml` + parity + device-gate): curated builds + GUI smoke/fuzzel.
  - *PR:* fuzzel lanes skipped; smoke still runs when device-e2e is invoked.
  - *Nightly:* calls device-gate on **`development` tip**.
- **Reproducibility.** `repro-rebuild` `--rebuild`s backend + workspace-src and
  byte-compares; `verify-no-tar-wildcards.py` bans nondeterministic archives.
  Deterministic outputs are what make FlakeHub Cache safe to trust.

## Sizing rules of thumb

- Keep the base app to core bundled clients only; ship everything else via
  `wwn-apt` (ODR/StoreKit) or waypipe. Smaller base → faster review + install.
- Prefer `--no-link --print-out-paths` in CI scripts to avoid gcroot churn.
