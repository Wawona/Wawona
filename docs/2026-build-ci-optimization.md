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

- CI installs Nix via `DeterminateSystems/nix-installer-action`, which provides
  the Magic Nix Cache (GitHub-Actions-scoped) automatically — no secrets needed.
- For cross-repo sharing (Wawona ↔ `wwn-*`), publish heavy derivations
  (toolchains, Weston/ANGLE/Vulkan archives, per-client ports) to a shared
  substituter so a client rebuilds only when *its* source changes:
  - Recommended: an Attic (or Cachix) cache keyed per store path.
  - Push from the repo that *owns* the derivation (e.g. `wwn-weston` pushes
    weston artifacts); Wawona and siblings pull as a substituter.
  - Add the cache URL + public key to each repo's `nix.conf`
    (`extra-substituters`, `extra-trusted-public-keys`).

## Per-repo CI dedupe

- **One owner per artifact.** `wwn-toolchain` builds toolchains; `wwn-weston`
  builds Weston + clients; Wawona consumes them via flake inputs. Do not rebuild
  a sibling's artifact in Wawona CI — pull it from cache.
- **Path filters.** Workflows use `on.push/pull_request.paths` (see
  `android-parity.yml`) so a docs-only change doesn't trigger native builds.
- **Fast PR gate vs nightly.**
  - *PR gate* (`nix.yml`): flake eval, `cargo test` (Linux + macOS), platform
    builds, reproducibility gate, protocol-status drift, macOS compat smoke.
  - *Nightly* (`nightly-full-matrix.yml`): graphics CTS, cross-platform UI
    parity, nested-Weston/XWayland capability lane — the slow/flaky deep gates.
- **Reproducibility.** `repro-rebuild` `--rebuild`s backend + workspace-src and
  byte-compares; `verify-no-tar-wildcards.py` bans nondeterministic archives.
  Deterministic outputs are what make the shared cache safe to trust.

## Sizing rules of thumb

- Keep the base app to core bundled clients only; ship everything else via
  `wwn-apt` (ODR/StoreKit) or waypipe. Smaller base → faster review + install.
- Prefer `--no-link --print-out-paths` in CI scripts to avoid gcroot churn.
