# Wawona CI — what runs, where, and why

Branch policy lives in [`.cursor/rules/wawona-branch-workflow.mdc`](../.cursor/rules/wawona-branch-workflow.mdc).
Green-light gate *layers* (L0–L4) live in [`2026-greenlight-gates.md`](./2026-greenlight-gates.md).
Binary cache: [`flakehub-cache.md`](./flakehub-cache.md).
Build dedupe: [`2026-build-ci-optimization.md`](./2026-build-ci-optimization.md).
Release secrets (tier 0): [`maintainers/secrets.md`](./maintainers/secrets.md).

## Versioning (CalVer)

Marketing version is **`YY.M.D`** (year · month · day), Apple-style year major
(`26` = 2026). Source of truth: [`VERSION`](../VERSION). Git tags are
`vYY.M.D` (e.g. `v26.8.6`). Same-day re-ships keep the marketing version and
bump **build number** (`WAWONA_BUILD_NUMBER` / `CURRENT_PROJECT_VERSION`) only.
Do not use semver majors for product releases.

## When to beta vs release

| You do… | Runs… | Ships… |
|---------|-------|--------|
| Work / PR on **`development`** | **Gate: packages** + **Gate: products** (build products → GUI smoke) | Nothing to stores or GitHub Releases |
| Promote green tip → **`master`** (push) | **Ship: beta (stores)** | TestFlight + Play internal + Linux AppImage workflow artifacts |
| Tag **`v*`** on a release commit | **Ship: beta (stores)** *and* **Ship: GitHub assets** | Store betas + GitHub Release assets |

**Promote rule:** `development` → `master` only when **Gate: packages** + **Gate: products** are green on that tip.

Workflow display names use a role prefix (`Gate` / `Build` / `Watch` / `Ship`). Filenames stay as before (`nix.yml`, `device-gate.yml`, …).

## Branch × workflow

| Workflow | `development` | `master` | Why |
|----------|:-------------:|:--------:|-----|
| **Gate: packages** (`nix.yml`) | push + PR | push + PR | L0–L2: verify, cargo/swift tests, curated backends; **native path filter** skips Darwin matrix on docs-only tips; Android Gradle/meson path-filtered |
| **Gate: products** (`device-gate.yml`) | path filter push | path filter push | Fans out **Build: products** by product (`only:`); GUI smoke lanes start per-product (iOS does not wait on AppImages) |
| **Build: products** (`product-build.yml`) | via Gate: products / Ship | via gate / Ship: beta (`only: appimage`) / Ship: GitHub assets | Sole pure producer: iOS sim `.app`, debug APK, macOS `.app`, AppImages (callable only) |
| **Build: GUI smoke** (`device-e2e.yml`) | via Gate: products (`products_ready`) | via gate | Smoke + fuzzel (fuzzel skipped on `pull_request` only); callable only |
| **Watch: graphics nightly** (`nightly-full-matrix.yml`) | schedule / dispatch | — | Graphics + protocol drift + Weston/XWayland capability (does **not** re-run Gate: products) |
| **Watch: idle memory** (`leak-idle-gate.yml`) | via Gate: products (`products_ready`) + schedule + dispatch | via Gate: products | Start→60s footprint/PSS plateau on product iOS/Android/macOS; fails with `LEAK_GATE_FAIL targets=…` ([docs/testing/leak-idle-gate.md](./testing/leak-idle-gate.md)). Reuses Gate: products `product-*` artifacts (no duplicate product-build). **Not** a promote blocker (`continue-on-error` on idle-memory jobs inside the reusable workflow; invalid on `uses:` callers) |
| **Watch: bundled clients** (`bundled-clients-matrix.yml`) | schedule + dispatch | — | Every `kBundledClients` id × runnable platforms; `MATRIX_FAIL cells=platform/client,…` ([docs/testing/bundled-clients-matrix-gate.md](./testing/bundled-clients-matrix-gate.md)). **Not** a promote blocker yet |
| **Ship: beta (stores)** (`release-beta.yml`) | — | push + tags `v*` | Fastlane stores (match+gym); owns AppImages via product-build `only: appimage` with `tip_key: ship-beta-<branch>` (must not share Gate: products `product-build-<branch>-appimage` or tip concurrency cancels one caller) |
| **Ship: GitHub assets** (`release.yml`) | — | tags `v*` | GitHub Release: DMG/APK/AppImage from product-build (`macos-app` / `android-apk` / `appimage` only; tip_key `ship-assets-<tag>`); IPA via Fastlane `ios github_ipa` (match+gym, same as Ship: beta) |

**watchOS store shipping:** bare `Wawona-watchOS` archives cannot export `app-store-connect` on Xcode 26. The companion is **embedded into `Wawona-iOS`** under classic `Watch/` (XcodeGen default; App Store Connect expects this layout). Never add standalone watch to `APPLE_BETA_TARGETS`. Gate: products still builds `Wawona-watchOS` for native/sim verification. See [#136](https://github.com/Wawona/Wawona/issues/136).

**IPA export (ITMS-90426):** gym archives only; Fastlane runs `xcodebuild -exportArchive` with an explicit `ExportOptions.plist` (`method: app-store-connect`) because gym 2.232 rewrites custom plists back to deprecated `app-store`. Xcode 26 ABI-stable Swift often omits `SwiftSupport/` and embeds no `libswift*.dylib` — Fastlane then synthesizes `SwiftSupport/<platform>/` from the GM Xcode toolchain (`swift-5.0/iphoneos`, plus `watchos` when a Watch companion is present) and **hard-fails** `assert_ipa_has_swift_support!` if still missing. Do not soft-warn and upload; ASC rejects later by email. Do not re-zip `Payload/` alone.

**Embedded Swift dylib signing (ITMS-90429/90427/90433):** every `Frameworks/libswift*.dylib` we embed must be **re-signed with the app's own distribution identity** (`embed_swift_runtime_into_archive!` runs `codesign --preserve-metadata=identifier,entitlements,flags` after copying from the toolchain) — a straight copy keeps Apple's own toolchain signature and ASC rejects with `ITMS-90433` ("doesn't have the correct code signature"). `SwiftSupport/<platform>/` is the opposite: it must stay **Apple-signed**, so its bytes come fresh from `xcode_swift_5_0_lib_dir`, never from the (now re-signed) `Frameworks/` copies.

**Multi-scheme export in one process (#138):** exporting `Wawona-tvOS`'s `.xcarchive` right after `Wawona-iOS` succeeded in the same `apple_beta_targets.each` loop reproducibly failed with `xcodebuild`: `Provisioning profile "match AppStore com.aspauldingcode.Wawona tvos" has platform "tvOS", which does not match the current platform "iOS"` — stale `xcodebuild`/gym environment state leaking across sequential invocations in one Ruby process (the same class of bug fastlane ships `xcbuild-safe.sh` for). Fixed by running each scheme's `-exportArchive` via `Open3.capture3` with an explicit minimal env (`PATH`/`HOME`/`USER`/`TMPDIR`/`DEVELOPER_DIR` only, `unsetenv_others: true`) instead of Fastlane's `sh`, which just inherits the full process ENV. Repro fast with `fastlane ios debug_export` (`WAWONA_DEBUG_SCHEME=Wawona-tvOS`, archive+export only, no upload).

Removed: **publish-ios** (use Ship: beta `workflow_dispatch`) and standalone **Android parity** (Gradle/meson folded into Gate: packages).

### Gate: products concurrency (tip-only)

Gate: products, Build: products, and Build: GUI smoke share a **branch tip** concurrency key (`development` / `master`), not per-SHA:

- One in-flight Gate: products **per tip**. A newer push cancels the older gate **and** its product + smoke children.
- Cancelled jobs on a superseded SHA are expected — they are not product failures. Promote only cares about a **success** tip Gate: products.
- Skipped product jobs from `only:` filters remain **Skipped** (not Cancelled).

## Single-build product pipeline

Pure ship/test binaries are built **once per SHA** by [`product-build.yml`](../.github/workflows/product-build.yml) (**Build: products**):

| Artifact | Attr | Consumers |
|----------|------|-----------|
| `product-ios-sim` | `.#wawona-ios` | Build: GUI smoke, Watch: idle memory |
| `product-android-apk` | `.#wawona-android` | Build: GUI smoke, Watch: idle memory, Ship: GitHub assets |
| `product-macos-app` | `.#wawona-macos` | Build: GUI smoke, Watch: idle memory, Ship: GitHub assets (DMG wrap). Mode A only — **must not** ship `libwayland-mac.dylib` |
| `wawona-macos-desktop-host` | `.#wawona-macos-desktop-host` | Developer ID / Desktop Replacement Mode B. Assert dylib present via [`.github/scripts/verify-iland-mode-b-bundle.sh`](../.github/scripts/verify-iland-mode-b-bundle.sh) |
| `product-appimage-<system>` | `.#wawona-appimage` | Ship: beta (stores), Ship: GitHub assets |

Helpers: [`.github/scripts/resolve-product-artifacts.sh`](../.github/scripts/resolve-product-artifacts.sh).

Signed IPA/AAB remain **impure** Fastlane/Release steps (secrets; match + gym for Apple IPAs); they reuse FlakeHub-warmed pure intermediates (Rust via `xcode-prebuild.sh`).

## FlakeHub Cache (required)

Every Nix-installing job must:

1. `permissions.id-token: write`
2. `DeterminateSystems/nix-installer-action` with `determinate: true`
3. `DeterminateSystems/flakehub-cache-action@v3`

## Why the package matrix is curated

Push/PR **Gate: packages** builds only [`.github/ci-package-matrix.json`](../.github/ci-package-matrix.json): backends, weston/niri/shell, graphics validate, `wawona-linux-ui-bin`. **Not** `wawona-macos` / `wawona-appimage` / full iOS/Android apps — those are **Build: products**.

## Job map (Gate: packages)

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
5. Serializing iOS GUI smoke behind AppImages/macOS/Android product jobs.
6. Rebuilding products outside `product-build.yml`.
7. Calling `product-build` from Watch: idle memory (or Watch: bundled clients) on the same tip_key as Gate: products — tip concurrency cancels one caller before binaries exist. Push-path idle memory must use `products_ready` from Gate: products; schedule/dispatch use tip_key `leak-idle-*`.
8. Killing agent-device prepare daemon between `prepare` and `open`.
9. Re-planning completed curated-matrix / gate fan-out work.
10. Reintroducing Magic Nix Cache / Attic / Cachix / `cache.wawona.io`.
11. nixpkgs lineage drift across `wwn-*` without `follows` / `verify-nixpkgs-lineage.py`.
12. Leaving `WAWONA_SKIP_NIX_PREBUILD=1` after `Cargo.lock` changes.

## Watch: idle memory

Memory plateau after Machines **Start** (not Instruments MCP — runners cannot use it;
iOS 26 sim Allocations are often empty). See [testing/leak-idle-gate.md](./testing/leak-idle-gate.md).

On product-path pushes, **Gate: products** calls Watch: idle memory with `products_ready: true`
after `product-ios` / `product-android` / `product-macos` succeed (parallel with GUI smoke).
That reuses the same `product-*` artifacts — it must not invoke `product-build` on the
Gate: products tip_key. Nightly schedule / `workflow_dispatch` build under tip_key
`leak-idle-*` so they cannot cancel Gate: products.

```bash
# Local (same script CI runs)
WAWONA_IOS_APP=result-ios/Wawona.app ./scripts/leak-idle-gate.sh ios
WAWONA_ANDROID_APK=dist/Wawona.apk ./scripts/leak-idle-gate.sh android
WAWONA_MACOS_APP=result-macos/Wawona.app ./scripts/leak-idle-gate.sh macos
./scripts/leak-idle-gate.sh summary   # prints LEAK_GATE_FAIL targets=…
```

CI: Actions → **Gate: products** → job `Watch: idle memory` (or standalone **Watch: idle memory**
on schedule/dispatch) → `Leak idle summary` lists failing targets.

## Watch: bundled clients

Every Machines `kBundledClients` option × runnable platforms (nested `weston`/`niri` + demos).

```bash
./scripts/bundled-clients-matrix-gate.sh                 # all platforms
./scripts/bundled-clients-matrix-gate.sh ios android     # subset
WAWONA_MATRIX_CLIENTS="niri,weston" ./scripts/bundled-clients-matrix-gate.sh ios
```

See [testing/bundled-clients-matrix-gate.md](./testing/bundled-clients-matrix-gate.md).
Summary prints `MATRIX_FAIL cells=ios/niri,android/vkcube,…`.

## Build: GUI smoke speed notes

- Fail-fast: one smoke/fuzzel attempt (no suite retries).
- Tip-only concurrency (see above): obsolete SHA gates cancel together; do not
  treat cancelled non-tip Gate: products runs as red for promote.
- Gate: products fans out product-build by product (`only: ios-sim|…`) so **iOS smoke
  starts when `product-ios-sim` is ready** — it does not wait for AppImages/macOS/Android.
- iOS CI lane: `agent-device-smoke.sh ios-ci` (one prepare for smoke; fuzzel reuses
  warm XCTest derived data; skipped on `pull_request` via `WAWONA_SKIP_FUZZEL`).
- **Nested niri/fuzzel** on GHA: iOS/Android lanes are advisory; **macOS nested
  niri is skipped** in Gate: products (runners SIGTERM mid-GUI and fail the job
  even with `continue-on-error`). Run `scripts/niri-fuzzel-smoke-macos.sh` locally
  or via Watch: graphics nightly. Catalog smoke remains hard on the macOS lane.
- Same-session `prepare ios-runner` + `open` (do not kill prepare daemon before open).
- XCTest runner cache key includes Xcode version (via `select-xcode.sh` outputs); hit/miss is logged.
- Product iOS sim uses `xcodegenIosSimOutputs` (`simulatorOnly`, ios-only) so project
  gen does not force device/macOS native closures.
