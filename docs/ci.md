# Wawona CI — what runs, where, and why

Branch policy lives in [`.cursor/rules/wawona-branch-workflow.mdc`](../.cursor/rules/wawona-branch-workflow.mdc).
Green-light gate *layers* (L0–L4) live in [`2026-greenlight-gates.md`](./2026-greenlight-gates.md).
Binary cache: [`flakehub-cache.md`](./flakehub-cache.md).
Build dedupe: [`2026-build-ci-optimization.md`](./2026-build-ci-optimization.md).

## When to beta vs release

| You do… | Runs… | Ships… |
|---------|-------|--------|
| Work / PR on **`development`** | Nix CI, Android parity, **Device gate** (product-build → e2e) | Nothing to stores or GitHub Releases |
| Promote green tip → **`master`** (push) | **Release Beta** | TestFlight + Play internal + Linux AppImage workflow artifacts |
| Tag **`v*`** on a release commit | **Release Beta** *and* **Release** | Store betas + GitHub Release assets |

**Promote rule:** `development` → `master` only when Nix CI + Android parity + Device gate/e2e are green on that tip.

## Branch × workflow

| Workflow | `development` | `master` | Why |
|----------|:-------------:|:--------:|-----|
| **Nix CI** (`nix.yml`) | push + PR | push + PR | L0–L2: verify, cargo/swift tests, **curated** backends (not full product apps) |
| **Android parity** | path filter + PR | push + PR | Gradle assembleDebug + meson/shell gates |
| **Device gate** (`device-gate.yml`) | path filter push | path filter push | Fans out **product-build** by product (`only:`); e2e lanes start per-product (iOS e2e does not wait on AppImages) |
| **Product build** (`product-build.yml`) | via device-gate / Release | via gate / Beta resolve / Release | Sole pure producer: iOS sim `.app`, debug APK, macOS `.app`, AppImages |
| **Device GUI e2e** | via device-gate (`products_ready`) | via gate | Smoke + fuzzel (fuzzel skipped on `pull_request` only) |
| **Nightly full matrix** | tip via device-gate | — | L4 + deep lanes on **`development` tip** |
| **Release Beta** | — | push + tags `v*` | Fastlane stores; AppImages resolved from product-build when possible |
| **Release** | — | tags `v*` | GitHub Release: DMG/APK/AppImage from product-build; IPA impure |

## Single-build product pipeline

Pure ship/test binaries are built **once per SHA** by [`product-build.yml`](../.github/workflows/product-build.yml):

| Artifact | Attr | Consumers |
|----------|------|-----------|
| `product-ios-sim` | `.#wawona-ios` | Device e2e |
| `product-android-apk` | `.#wawona-android` | Device e2e, Release |
| `product-macos-app` | `.#wawona-macos` | Device e2e, Release (DMG wrap) |
| `product-appimage-<system>` | `.#wawona-appimage` | Release Beta, Release |

Helpers: [`.github/scripts/resolve-product-artifacts.sh`](../.github/scripts/resolve-product-artifacts.sh).

Signed IPA/AAB remain **impure** Fastlane/Release steps (secrets); they reuse FlakeHub-warmed pure intermediates.

## FlakeHub Cache (required)

Every Nix-installing job must:

1. `permissions.id-token: write`
2. `DeterminateSystems/nix-installer-action` with `determinate: true`
3. `DeterminateSystems/flakehub-cache-action@v3`

## Why the package matrix is curated

Push/PR Nix CI builds only [`.github/ci-package-matrix.json`](../.github/ci-package-matrix.json): backends, weston/niri/shell, graphics validate, `wawona-linux-ui-bin`. **Not** `wawona-macos` / `wawona-appimage` / full iOS/Android apps — those are **product-build**.

## Job map (Nix CI)

| Job | Layer | Why |
|-----|-------|-----|
| `prepare-matrix` | L0 | Verify scripts + flake check; emit curated matrix |
| `cargo-test-*` / `swift-test-*` | L1 | Language tests |
| `build` (matrix) | L2 | Curated attrs + FlakeHub |
| `frontend-syntax-check` | L2-lite | Xcode syntax without full Nix backend |

## Device e2e speed notes

- Fail-fast: one smoke/fuzzel attempt (no suite retries).
- Device gate fans out product-build by product (`only: ios-sim|…`) so **iOS e2e
  starts when `product-ios-sim` is ready** — it does not wait for AppImages/macOS/Android.
- iOS CI lane: `agent-device-smoke.sh ios-ci` (one prepare for smoke; fuzzel reuses
  warm XCTest derived data; skipped on `pull_request` via `WAWONA_SKIP_FUZZEL`).
- Same-session `prepare ios-runner` + `open` (do not kill prepare daemon before open).
- Fuzzel: required on `development`/`master` **push**; skipped on `pull_request` only.
- XCTest runner cache key includes Xcode version (via `select-xcode.sh` outputs); hit/miss is logged.
- Product iOS sim uses `xcodegenIosSimOutputs` (`simulatorOnly`, ios-only) so project
  gen does not force device/macOS native closures.
