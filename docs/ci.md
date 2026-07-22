# Wawona CI — what runs, where, and why

Branch policy lives in [`.cursor/rules/wawona-branch-workflow.mdc`](../.cursor/rules/wawona-branch-workflow.mdc).
Green-light gate *layers* (L0–L4) live in [`2026-greenlight-gates.md`](./2026-greenlight-gates.md).
Binary cache: [`flakehub-cache.md`](./flakehub-cache.md).
Build dedupe: [`2026-build-ci-optimization.md`](./2026-build-ci-optimization.md).
Release secrets (tier 0): [`maintainers/secrets.md`](./maintainers/secrets.md).

## When to beta vs release

| You do… | Runs… | Ships… |
|---------|-------|--------|
| Work / PR on **`development`** | **Nix CI** + **Device gate** (product-build → e2e) | Nothing to stores or GitHub Releases |
| Promote green tip → **`master`** (push) | **Release Beta** | TestFlight + Play internal + Linux AppImage workflow artifacts |
| Tag **`v*`** on a release commit | **Release Beta** *and* **Release** | Store betas + GitHub Release assets |

**Promote rule:** `development` → `master` only when **Nix CI** + **Device gate** are green on that tip.

## Branch × workflow

| Workflow | `development` | `master` | Why |
|----------|:-------------:|:--------:|-----|
| **Nix CI** (`nix.yml`) | push + PR | push + PR | L0–L2: verify, cargo/swift tests, curated backends; **native path filter** skips Darwin matrix on docs-only tips; Android Gradle/meson path-filtered |
| **Device gate** (`device-gate.yml`) | path filter push | path filter push | Fans out **product-build** by product (`only:`); e2e lanes start per-product (iOS e2e does not wait on AppImages) |
| **Product build** (`product-build.yml`) | via device-gate / Release | via gate / Release Beta (`only: appimage`) / Release | Sole pure producer: iOS sim `.app`, debug APK, macOS `.app`, AppImages (callable only) |
| **Device GUI e2e** | via device-gate (`products_ready`) | via gate | Smoke + fuzzel (fuzzel skipped on `pull_request` only); callable only |
| **Nightly full matrix** | schedule / dispatch | — | Graphics + protocol drift + Weston/XWayland capability (does **not** re-run Device gate) |
| **Leak idle gate** (`leak-idle-gate.yml`) | path filter push + schedule + dispatch | — | Start→60s footprint/PSS plateau on product iOS/Android/macOS; fails with `LEAK_GATE_FAIL targets=…` ([docs/testing/leak-idle-gate.md](./testing/leak-idle-gate.md)). **Not** a promote blocker yet |
| **Bundled clients matrix** (`bundled-clients-matrix.yml`) | schedule + dispatch | — | Every `kBundledClients` id × runnable platforms; `MATRIX_FAIL cells=platform/client,…` ([docs/testing/bundled-clients-matrix-gate.md](./testing/bundled-clients-matrix-gate.md)). **Not** a promote blocker yet |
| **Release Beta** | — | push + tags `v*` | Fastlane stores (match+gym); owns AppImages via product-build `only: appimage` |
| **Release** | — | tags `v*` | GitHub Release: DMG/APK/AppImage from product-build; IPA impure |

Removed: **publish-ios** (use Release Beta `workflow_dispatch`) and standalone **Android parity** (Gradle/meson folded into Nix CI).

### Device gate concurrency (tip-only)

Device gate, product-build, and Device GUI e2e share a **branch tip** concurrency key (`development` / `master`), not per-SHA:

- One in-flight Device gate **per tip**. A newer push cancels the older gate **and** its product + e2e children.
- Cancelled jobs on a superseded SHA are expected — they are not product failures. Promote only cares about a **success** tip Device gate.
- Skipped product jobs from `only:` filters remain **Skipped** (not Cancelled).

## Single-build product pipeline

Pure ship/test binaries are built **once per SHA** by [`product-build.yml`](../.github/workflows/product-build.yml):

| Artifact | Attr | Consumers |
|----------|------|-----------|
| `product-ios-sim` | `.#wawona-ios` | Device e2e, Leak idle gate |
| `product-android-apk` | `.#wawona-android` | Device e2e, Leak idle gate, Release |
| `product-macos-app` | `.#wawona-macos` | Device e2e, Leak idle gate, Release (DMG wrap). Mode A only — **must not** ship `libwayland-mac.dylib` |
| `wawona-macos-desktop-host` | `.#wawona-macos-desktop-host` | Developer ID / Desktop Replacement Mode B. Assert dylib present via [`.github/scripts/verify-iland-mode-b-bundle.sh`](../.github/scripts/verify-iland-mode-b-bundle.sh) |
| `product-appimage-<system>` | `.#wawona-appimage` | Release Beta, Release |

Helpers: [`.github/scripts/resolve-product-artifacts.sh`](../.github/scripts/resolve-product-artifacts.sh).

Signed IPA/AAB remain **impure** Fastlane/Release steps (secrets; match + gym for Apple IPAs); they reuse FlakeHub-warmed pure intermediates (Rust via `xcode-prebuild.sh`).

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
| `ci-scope` | L0 | Path filter: `native` vs docs-only |
| `prepare-matrix` | L0 | Verify scripts + flake check; emit curated matrix (always) |
| `cargo-test-*` / `swift-test-*` | L1 | Language tests (Darwin jobs skip when `native=false`) |
| `build` (matrix) | L2 | Curated attrs + FlakeHub (Darwin cells skip when `native=false`) |
| `frontend-syntax-check` | L2-lite | Xcode syntax without full Nix backend (skipped when docs-only) |
| `android-gradle-gate` | L2 (path filter) | Gradle `assembleDebug` + meson/shell |

`workflow_dispatch` always runs the full Darwin surface.

## Host Xcode pin (impure Apple builds)

Runners use [`.github/scripts/select-xcode.sh`](../.github/scripts/select-xcode.sh) — **pinned**, not “newest”.

| | |
|--|--|
| Default pin | `/Applications/Xcode_26.6.0.app` (macos-26 image) |
| Override | `WAWONA_XCODE_APP` or `WAWONA_XCODE_VERSION` |
| Missing pin | Fail closed (lists installed `Xcode*.app`) |

**Bump procedure:** update `DEFAULT_XCODE_APP` in `select-xcode.sh` in a reviewed PR after confirming the GHA image ships that app. Expect impure weston/backend/product hash churn + XCTest cache misses — that is intentional.

FlakeHub caches **Nix store paths** only. It does **not** ship Apple platform SDKs (`iphoneos` / simulator). Keep `warm-ios-simulator-sdk.sh` + host Xcode.

## CI anti-patterns (do not reintroduce)

1. Confusing FlakeHub store cache with Apple SDKs / `apple-sdks.nix`.
2. Unpinned “newest Xcode” (`sort -V \| tail -1`) in workflows.
3. Warming device backend when product needs sim (or the reverse).
4. Expecting FlakeHub to fix crate2nix IFD / eval time — hoist IFDs instead.
5. Serializing iOS e2e behind AppImages/macOS/Android product jobs.
6. Rebuilding products outside `product-build.yml`.
7. Killing agent-device prepare daemon between `prepare` and `open`.
8. Re-planning completed curated-matrix / gate fan-out work.
9. Reintroducing Magic Nix Cache / Attic / Cachix / `cache.wawona.io`.
10. nixpkgs lineage drift across `wwn-*` without `follows` / `verify-nixpkgs-lineage.py`.
11. Leaving `WAWONA_SKIP_NIX_PREBUILD=1` after `Cargo.lock` changes.

## Leak idle gate

Memory plateau after Machines **Start** (not Instruments MCP — runners cannot use it;
iOS 26 sim Allocations are often empty). See [testing/leak-idle-gate.md](./testing/leak-idle-gate.md).

```bash
# Local (same script CI runs)
WAWONA_IOS_APP=result-ios/Wawona.app ./scripts/leak-idle-gate.sh ios
WAWONA_ANDROID_APK=dist/Wawona.apk ./scripts/leak-idle-gate.sh android
WAWONA_MACOS_APP=result-macos/Wawona.app ./scripts/leak-idle-gate.sh macos
./scripts/leak-idle-gate.sh summary   # prints LEAK_GATE_FAIL targets=…
```

CI: Actions → **Leak idle gate** → job `Leak idle summary` step summary lists failing targets.

## Bundled clients matrix

Every Machines `kBundledClients` option × runnable platforms (nested `weston`/`niri` + demos).

```bash
./scripts/bundled-clients-matrix-gate.sh                 # all platforms
./scripts/bundled-clients-matrix-gate.sh ios android     # subset
WAWONA_MATRIX_CLIENTS="niri,weston" ./scripts/bundled-clients-matrix-gate.sh ios
```

See [testing/bundled-clients-matrix-gate.md](./testing/bundled-clients-matrix-gate.md).
Summary prints `MATRIX_FAIL cells=ios/niri,android/vkcube,…`.

## Device e2e speed notes

- Fail-fast: one smoke/fuzzel attempt (no suite retries).
- Tip-only concurrency (see above): obsolete SHA gates cancel together; do not
  treat cancelled non-tip Device gate runs as red for promote.
- Device gate fans out product-build by product (`only: ios-sim|…`) so **iOS e2e
  starts when `product-ios-sim` is ready** — it does not wait for AppImages/macOS/Android.
- iOS CI lane: `agent-device-smoke.sh ios-ci` (one prepare for smoke; fuzzel reuses
  warm XCTest derived data; skipped on `pull_request` via `WAWONA_SKIP_FUZZEL`).
- Same-session `prepare ios-runner` + `open` (do not kill prepare daemon before open).
- Fuzzel: required on `development`/`master` **push**; skipped on `pull_request` only.
- XCTest runner cache key includes Xcode version (via `select-xcode.sh` outputs); hit/miss is logged.
- Product iOS sim uses `xcodegenIosSimOutputs` (`simulatorOnly`, ios-only) so project
  gen does not force device/macOS native closures.
