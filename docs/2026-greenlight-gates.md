# Wawona — Green-Light Gates

Definition of "done/working" per platform, wired to concrete CI jobs. A platform
is **green** only when all its gates pass.

**Where jobs run:** see [`ci.md`](./ci.md) (branch × workflow matrix). Required
promote gates run on **`development`** with FlakeHub Cache; `master` gets the
same gates plus Release Beta after promote.

Job names refer to `.github/workflows/nix.yml` unless noted.

## Gate layers

- **L0 Eval** — flake evaluates, profile smoke honest (`verify-*` jobs).
- **L1 Unit** — Rust core + model tests pass (`cargo test`).
- **L2 Build** — platform artifact compiles/links (`build-*` jobs).
- **L3 Functional** — compositor accepts clients and presents frames
  (smoke jobs + agent-device replays).
- **L4 Parity** — UI matches golden baselines (agent-device + `ui_parity_diff.py`).

## Per-platform gates

| Platform | L0 | L1 | L2 | L3 | L4 |
|----------|----|----|----|----|----|
| Rust core | `verify-linux` | `cargo-test-linux`, `cargo-test-macos-arm64` | — | `protocol_matrix` tests | — |
| Linux (x86_64) | `verify-linux` | `cargo-test-linux` (+linux-ui) | `build-linux` | `smoke-linux` | nightly |
| Linux (arm64) | `verify-linux-arm64` | — | `build-linux-arm64` | `smoke-linux-arm64` | nightly |
| macOS (arm64) | `verify-macos-arm64` | `cargo-test-macos-arm64` | `build-macos-arm64` | `smoke-macos-arm64` (compat-matrix + bundled clients) | agent-device (local) |
| macOS (x86_64) | flake check | `swift-test-macos-x86_64` | — | — | — |
| iOS/iPadOS/tvOS/visionOS/watchOS | flake check | `cargo-test-macos-arm64` (shared core) | `*-sim-backend` builds | agent-device replays (local/nightly) | XCUITest (nightly, `p_ci-l3-apple-xcuitest`) |
| Android | — | shared core | `wawona-android` | Compose UI Test (nightly, `p_ci-l3-android-espresso`) | agent-device (device) |

## Determinism / reproducibility gate

`repro-rebuild` builds then `--rebuild`s `wawona-android-backend` and
`wawona-workspace-src-android` and byte-compares. Non-reproducible source churn
fails here. Plus `verify-no-tar-wildcards.py` bans nondeterministic archive
extraction in Nix recipes.

## Protocol honesty gate

`cargo-test-linux` regenerates [`protocol-status.md`](./protocol-status.md) from
the live registry and fails on drift; `protocol_matrix` tests fail if a global is
advertised outside its `ProtocolProfile` policy.

## What "green-light everywhere" means

All L0–L3 gates above green on the **`development`** tip (Nix CI curated matrix +
Android parity + Device e2e), and the nightly full-matrix (L4 parity + graphics
CTS + capability lanes) green against **`development`**. Nightly wiring:
[`ci.md`](./ci.md). Manual functional checklist (being converted to automated
IDs) lives in [`testing/everywhere-matrix.md`](./testing/everywhere-matrix.md).
