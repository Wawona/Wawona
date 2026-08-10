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
| Promote green tip → **`master`** (push) | **Ship: beta (stores)** + **Ship: beta AppImages** (after Gate: products) | TestFlight + Play internal + Linux AppImage workflow artifacts (reused from Gate: products) |
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
| **Ship: beta (stores)** (`release-beta.yml`) | — | push + tags `v*` | Fastlane stores (match+gym). **Does not build AppImages** — see Ship: beta AppImages below |
| **Ship: beta AppImages** (`ship-beta-appimage.yml`) | — | after a green master **Gate: products** (`workflow_run`) | Re-publishes that run's same-SHA `product-appimage-*` as 30-day `wawona-beta-appimage-*` via cross-run `download-artifact` — **no rebuild, no fallback**. Deletes the old master-push double AppImage build (Gate: products + Ship: beta). Keyed on the Gate run's `head_sha` so it never shares release-beta's concurrency group |
| **Ship: GitHub assets** (`release.yml`) | — | tags `v*` (+ `workflow_dispatch`) | GitHub Release: DMG/APK/AppImage from product-build (`macos-app` / `android-apk` / `appimage` only; tip_key `ship-assets-<tag>`); IPA via Fastlane `ios github_ipa` (match+gym, same as Ship: beta). macOS DMG is **Developer ID signed + notarized** |

**macOS DMG layout:** the DMG ships **both** `Wawona.app` (drag → `/Applications`) **and** `WawonaAgent.pkg`. The pkg is a hybrid installer built from the same staged app ([`scripts/macos-launch-agent-pkg.sh`](../scripts/macos-launch-agent-pkg.sh)): its payload installs `/Applications/Wawona.app` and its `postinstall` loads the compositor + menubar LaunchAgents and publishes `WAYLAND_DISPLAY` / `XDG_RUNTIME_DIR`. Default installs for the console user; `sudo WAWONA_INSTALL_USERS=a,b installer -pkg …` targets more accounts. `release.yml` hard-fails if either `Wawona.app` or `WawonaAgent.pkg` is missing before packaging.

**macOS notarization (Gatekeeper):** `release-macos` uses Environment `release-beta` secrets (`DEVELOPER_ID_*_P12_BASE64`, `MATCH_PASSWORD`, `APP_STORE_CONNECT_*`) and [`scripts/macos-sign-and-notarize-dmg.sh`](../scripts/macos-sign-and-notarize-dmg.sh): deep `codesign` with hardened runtime + [`Wawona-macOS-DeveloperID.entitlements`](../src/resources/app-bundle/Wawona-macOS-DeveloperID.entitlements), `productsign` the agent pkg, `hdiutil` UDZO DMG, `notarytool submit --wait`, `stapler staple`. Without this, downloaded apps show “damaged and can’t be opened” (quarantine + ad-hoc/nix signature). Re-ship an existing tag via Actions → **Ship: GitHub assets** → `workflow_dispatch` (`tag=vYY.M.D`, optional `build_ref=development` when the notarize script is not yet on the tagged commit).

**watchOS store shipping:** bare `Wawona-watchOS` archives cannot export `app-store-connect` on Xcode 26. The companion is **embedded into `Wawona-iOS`** under classic `Watch/` (XcodeGen default; App Store Connect expects this layout). Never add standalone watch to `APPLE_BETA_TARGETS`. Gate: products still builds `Wawona-watchOS` for native/sim verification. See [#136](https://github.com/Wawona/Wawona/issues/136).

**IPA export (ITMS-90426):** gym archives only; Fastlane runs `xcodebuild -exportArchive` with an explicit `ExportOptions.plist` (`method: app-store-connect`) because gym 2.232 rewrites custom plists back to deprecated `app-store`.

**Embedded Swift dylib signing, when actually needed (ITMS-90429/90427/90433):** any `Frameworks/lib*.dylib` we embed must be **re-signed with the app's own distribution identity** (`embed_swift_runtime_into_archive!` runs `codesign --preserve-metadata=identifier,entitlements,flags` after copying from the toolchain, with a normal secure timestamp — not `--timestamp=none`, which left these as the only untimestamped signatures in an otherwise fully-timestamped archive) — a straight copy keeps Apple's own toolchain signature and ASC rejects with `ITMS-90433` ("doesn't have the correct code signature"). `SwiftSupport/<platform>/` is the opposite: it must stay **Apple-signed**, so its bytes come fresh from the toolchain via `xcode_swift_lib_source`, never from the (now re-signed) `Frameworks/` copies.

**The actual root cause (settled by the builds 60-120 `buildUploads` record): loose non-Swift dylibs in `Frameworks/`, not SwiftSupport content.** Every iOS upload from build 60 (July, **pre-watch**) through 120 failed with rotating `ITMS-90426`/`90429`/`90433`, while the tvOS/visionOS ipas of the same commits were always `COMPLETE` — including build 119 (textbook ABI-stable iOS+Watch, no SwiftSupport → 90426) and build 120 (full legacy layout: `SwiftSupport/{iphoneos,watchos}` with set-parity and byte-identical Apple-signed copies, verified in the uploaded artifact → still 90429 listing dylibs that were physically present). The one constant, present **only** in the iOS ipa: ANGLE's loose `Payload/Wawona.app/Frameworks/libEGL.dylib` + `libGLESv2.dylib` (the flat `iland dlopen` convenience copies; tvOS never bundles ANGLE, visionOS's embed glob never matched). **App Store bundles must not contain loose (non-framework-wrapped) `.dylib` files under `Frameworks/` (TN2435)** — the only loose dylibs ASC sanctions there are pre-ABI Swift runtime dylibs (`libswift*`), so any other loose dylib flips its Swift Support validator into legacy expectations and produces these errors regardless of SwiftSupport content (same class as tdlib/Flutter's loose `libtdjson.dylib` → 90429 listing `libswift*` names). Fixes: `xcodegen.nix` makes the flat ANGLE copies **simulator-only** (device ships `libEGL.framework`/`libGLESv2.framework` only) and `wwn-iland`'s EGL shim probes the framework-wrapped binaries first (flake input bumped to `d6cf97a`). The canonical accepted shape for every Apple-mobile ipa, watch or not, is ABI-stable: no `SwiftSupport/`, no `Frameworks/libswift*` — only a genuine `SWIFT_BACKDEPLOY_LIB_NAMES` shim below its native-OS floor may ever be embedded (none at our targets). `WAWONA_WATCH_LEGACY_SWIFT_SUPPORT=1` remains as an escape hatch that ships and deeply validates the full legacy layout for watch-bearing ipas (`embed_swift_runtime_into_archive!` populates bundle `Frameworks/` + archive-root `SwiftSupport/` pre-export; exportArchive verifiably propagates it into the ipa) — leave OFF unless a canonical-shape upload is rejected again. Pre-upload, `assert_ipa_has_swift_support!` hard-gates the final ipa's actual zip contents: `assert_no_loose_dylibs!` (TN2435, the real regression guard), then canonical-shape or (hatch on) `assert_legacy_swift_support!` checks. No ipa reaches ASC without passing. After any real upload, poll the ASC `buildUploads` API for the `COMPLETE`/`FAILED` verdict instead of waiting on the rejection email (`altool --validate-app` passes on binaries ASC later rejects — never trust it alone).

**Historical (builds 89-104): bundling the full overlay set everywhere was also wrong.** `embed_swift_runtime_into_archive!` used to treat *every* `/usr/lib/swift/lib*.dylib` reference in `otool -L` as needing embedding on **all** targets and dumped the whole toolchain `swift-5.0/<platform>` dir into `SwiftSupport/` as a fallback — which manufactured content on the watchless tvOS/visionOS IPAs that must not have it, and combined it with signature/zip defects (`--timestamp=none`, append-zip) that kept the watch-bearing uploads failing too (90433 build 89, 90429 build 95, 90426 builds 93/104). The narrow back-deployment whitelist (`SWIFT_BACKDEPLOY_LIB_NAMES` + `swift_backdeploy_needed?`) remains the rule for watchless bundles; the error in 26.8.8's first iteration was extending "embed nothing" to watch-bearing IPAs (builds 110/119 → ITMS-90426). Validate with `fastlane ios debug_export` (`WAWONA_DEBUG_SCHEME=Wawona-iOS`/`Wawona-tvOS`/`Wawona-visionOS`) or the `Ship: beta (stores)` `workflow_dispatch` (`lane: ios debug_export`, `debug_scheme: <scheme>`) — the dispatch uploads the built ipa as a `wawona-debug-export-ipa-<scheme>` workflow artifact for direct inspection; after a real upload, check the ASC `buildUploads` API for the synchronous `COMPLETE`/`FAILED` verdict instead of waiting on the rejection email (`xcrun altool --validate-app` passes on binaries ASC later rejects — never trust it alone).

**tvOS/visionOS export "current platform" mismatch (#138):** exporting `Wawona-tvOS`'s (and `Wawona-visionOS`'s) `.xcarchive` failed with `xcodebuild`: `Provisioning profile "match AppStore com.aspauldingcode.Wawona tvos" has platform "tvOS", which does not match the current platform "iOS"`. Initial theory (stale `xcodebuild`/gym ENV leaking across sequential exports in one Ruby process, the class of bug fastlane ships `xcbuild-safe.sh` for) was **wrong**: it still reproduced in an isolated, single-scheme `fastlane ios debug_export` run. Root cause, found by inspecting a local archive's `Products/Applications/Wawona.app/Info.plist` directly: `src/resources/app-bundle/Info.plist` is shared verbatim (`GENERATE_INFOPLIST_FILE=NO`) across every Apple app target and hardcodes `CFBundleSupportedPlatforms=[iPhoneOS]` + `LSRequiresIPhoneOS=true`. `xcodebuild -exportArchive` reads `CFBundleSupportedPlatforms` — not `DTPlatformName`/`DTSDKName`, both of which were correctly `appletvos`/`xros` — to decide the archive's "current platform", so a tvOS/visionOS archive whose Info.plist still says `iPhoneOS` gets its own (correctly platform-scoped) provisioning profile rejected. Fixed in `dependencies/generators/xcodegen.nix` (`stripIOSOnlyInfoPlistKeysPhase`, a postBuild script deleting those iOS-only keys on the tvOS/macOS/visionOS app targets — the same pattern already used for `Wawona-watchOS`'s "Strip iOS-only keys from Watch Info.plist"). Verified locally end-to-end (archive → embed Swift runtime → export → SwiftSupport inject) for both `Wawona-tvOS` and `Wawona-visionOS` via `fastlane ios debug_export` (`WAWONA_DEBUG_SCHEME=<scheme>`, archive+export only, no upload). The minimal-env `Open3.capture3` export change is kept as a reasonable defensive practice but was not this bug's actual cause.

**`debug_export` must call `setup_ci` (do not skip it):** the first `debug_export` CI run hung for 2h+ at `Signing WawonaUIContracts.framework` with two orphaned `codesign` processes never reaped until the job was cancelled — not a slow cold build. Root cause: the lane omitted `setup_ci if ENV["CI"]` (present in `beta`/`release`), so there was no dedicated non-interactive keychain with a `codesign:` partition list; `codesign` blocked on a private-key ACL prompt that a headless runner can never answer. Every lane that signs on CI must call `setup_ci if ENV["CI"]` before any `build_app`/`gym_ipa`. `apple-beta`/`android-beta` now also carry `timeout-minutes: 90` in `release-beta.yml` so a repeat of this class of hang fails in under 2 hours instead of consuming the full 6h GitHub Actions default and blocking the `release-beta-<ref>` concurrency group.

Removed: **publish-ios** (use Ship: beta `workflow_dispatch`) and standalone **Android parity** (Gradle/meson folded into Gate: packages).

### Gate: products concurrency (tip-only)

Gate: products, Build: products, and Build: GUI smoke share a **branch tip** concurrency key (`development` / `master`), not per-SHA:

- One in-flight Gate: products **per tip**. A newer push cancels the older gate **and** its product + smoke children.
- Cancelled jobs on a superseded SHA are expected — they are not product failures. Promote only cares about a **success** tip Gate: products.
- Skipped product jobs from `only:` filters remain **Skipped** (not Cancelled).

### Why Actions shows dozens of Skipped jobs (and Cancelled ≠ failed)

A green **Gate: products** run lists ~34 **Skipped** jobs. Almost all are the
reusable-workflow fan-out — **intentional**, not races. Do not treat them as
failures or flakiness in review.

| Class | Where | What is skipped | Why |
|-------|-------|-----------------|-----|
| **A1 — `only:` cross-skips** | [`product-build.yml`](../.github/workflows/product-build.yml) | Each of Gate's four product calls (`only: ios-sim\|android-apk\|macos-app\|appimage`) defines all product jobs but runs one family; the other 3–4 families show Skipped (incl. matrix placeholders like `… / ${{ matrix.label }} sim .app`) | Jobs gate on `if: only == 'all' \|\| only == '<job>'` |
| **A2 — `lanes:` cross-skips** | [`device-e2e.yml`](../.github/workflows/device-e2e.yml) | Each GUI-smoke caller (`lanes: ios\|android\|macos\|linux`) skips the other lanes; macOS nested niri/fuzzel is hard-`if: false` (SIGTERM avoidance) | Jobs gate on `inputs.lanes` |
| **A3 — leak `products_ready`** | [`leak-idle-gate.yml`](../.github/workflows/leak-idle-gate.yml) | `Watch: idle memory / Product iOS sim\|Android APK\|macOS app` | Gate passes `products_ready: true`; leak cells download Gate's `product-*` instead of rebuilding — **this is the reuse you want** |

**UI trap:** soft-fail leak cells (`continue-on-error`) can show **red children**
while `Gate: products` is still **success**. The GitHub job conclusion (green after
`continue-on-error`) is not the real leak verdict — read `LEAK_GATE_FAIL targets=…`
/ `verdict.json`. Gate: products stays green regardless.

**Cancelled** (distinct from Skipped) only comes from tip concurrency: a newer
push cancels the older `device-gate-<tip>` / `product-build-<tip>-*` /
`nix-ci-<ref>` run. Expected. The one **wrong** kind of cancel is sharing a
tip_key across unrelated workflows — fixed by keeping `bundled-clients-*`,
`leak-idle-*`, `ship-beta-*`, and `ship-assets-*` off Gate's `product-build-<tip>`
group (anti-pattern #7).

**Harness-only commits must be in the path filter.** Because Gate: products
runs the leak/bundled-clients harness via `products_ready`, edits to
`scripts/leak-idle-gate.sh`, `scripts/bundled-clients-matrix-gate.sh`, or their
`.yml` must be listed in [`device-gate.yml`](../.github/workflows/device-gate.yml)
`on.push.paths` — otherwise they green **Gate: packages** and leave **Gate: products**
on the previous SHA. Until such a path is added, exercise the fix with
`gh workflow run "Gate: products" --ref development`.

## Single-build product pipeline

Pure ship/test binaries are built **once per SHA** by [`product-build.yml`](../.github/workflows/product-build.yml) (**Build: products**):

| Artifact | Attr | Consumers |
|----------|------|-----------|
| `product-ios-sim` | `.#wawona-ios` | Build: GUI smoke, Watch: idle memory |
| `product-android-apk` | `.#wawona-android` | Build: GUI smoke (android-emu downloads it directly — no `wawona-apk` hop), Watch: idle memory, Ship: GitHub assets |
| `product-macos-app` | `.#wawona-macos` | Build: GUI smoke, Watch: idle memory, Ship: GitHub assets (DMG wrap). Mode A only — **must not** ship `libwayland-mac.dylib` |
| `wawona-macos-desktop-host` | `.#wawona-macos-desktop-host` | Developer ID / Desktop Replacement Mode B. Assert dylib present via [`.github/scripts/verify-iland-mode-b-bundle.sh`](../.github/scripts/verify-iland-mode-b-bundle.sh) |
| `product-appimage-<system>` | `.#wawona-appimage` | Ship: beta AppImages (reused cross-run via `workflow_run`, not rebuilt), Ship: GitHub assets |

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

**Runner OS:** all macOS jobs (Apple products, Android APK/AAB, Android Gradle gate, macOS e2e) run on **`macos-26`**. Android needs a macOS host (Linux fails `zsh-android` configure) but not a specific macOS version — Nix supplies the NDK — so it is aligned to `macos-26` rather than pinned to `macos-15`.

FlakeHub caches **Nix store paths** only. It does **not** ship Apple platform SDKs (`iphoneos` / simulator). Keep `warm-ios-simulator-sdk.sh` + host Xcode.

## CI anti-patterns (do not reintroduce)

1. Confusing FlakeHub store cache with Apple SDKs / `apple-sdks.nix`.
2. Unpinned “newest Xcode” (`sort -V \| tail -1`) in workflows.
3. Warming device backend when product needs sim (or the reverse).
4. Expecting FlakeHub to fix crate2nix IFD / eval time — hoist IFDs instead.
5. Serializing iOS GUI smoke behind AppImages/macOS/Android product jobs.
6. Rebuilding products outside `product-build.yml`.
7. Calling `product-build` from Watch: idle memory (or Watch: bundled clients) on the same tip_key as Gate: products — tip concurrency cancels one caller before binaries exist. Push-path idle memory must use `products_ready` from Gate: products; schedule/dispatch use tip_key `leak-idle-*`, and Watch: bundled clients uses `bundled-clients-*` (both isolated from Gate's `product-build-<tip>` group).
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
