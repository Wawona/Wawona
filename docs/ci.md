# Wawona CI — what runs, where, and why

Branch policy lives in [`.cursor/rules/wawona-branch-workflow.mdc`](../.cursor/rules/wawona-branch-workflow.mdc).
Green-light gate *layers* (L0–L4) live in [`2026-greenlight-gates.md`](./2026-greenlight-gates.md).
Binary cache: [`flakehub-cache.md`](./flakehub-cache.md).

## Branch × workflow

| Workflow | `development` | `master` | Why |
|----------|:-------------:|:--------:|-----|
| **Nix CI** (`nix.yml`) | push + PR | push + PR | L0–L2: verify scripts, cargo/swift tests, **curated** package builds. Required before promote. |
| **Android parity** | push (path filter) + PR | push + PR | Android shell-tool / meson / gradle assemble. |
| **Device GUI e2e** | push (path filter) | push (path filter) | L3: agent-device replays (iOS sim, Android emu, macOS niri/fuzzel). |
| **Nightly full matrix** | tip checked out | — | L4 + slow lanes; always tests **`development` tip** on schedule. |
| **Release Beta** | — | push | TestFlight / Play internal / AppImage betas — release channel only. |
| **Release** | — | tags `v*` | GitHub Release assets. |
| **publish-ios** | — | manual | Legacy TestFlight; prefer Release Beta. |

`main` is accepted as an alias of `master` in a few triggers for legacy remotes.

**Promote rule:** `development` → `master` only when required workflows are green on that tip (Nix CI, Android parity, Device e2e). Release Beta runs *after* promote on `master`.

## FlakeHub Cache (required)

Every Nix-installing job must:

1. `permissions.id-token: write`
2. `DeterminateSystems/nix-installer-action` with `determinate: true`
3. `DeterminateSystems/flakehub-cache-action@v3`

No Magic Nix Cache. No self-hosted Attic. Owner `wwn-*` repos push the same way so Wawona substitutes Layer-1 paths.

## Why the package matrix is curated

Historically `nix.yml` built **every** `packages.<system>` attr (~100+ Darwin × 2 + Linux). That:

- Burned Actions minutes without improving signal
- Flooded FlakeHub with low-value intermediates
- Made “is development green?” unreadable

Push/PR Nix CI now builds only [`.github/ci-package-matrix.json`](../.github/ci-package-matrix.json) (~13 targets): product backends, one nested compositor, shell, graphics validate, Linux AppImage/UI. Full attr enumeration belongs in research / one-off `workflow_dispatch`, not the merge gate.

## Job map (Nix CI)

| Job | Layer | Why |
|-----|-------|-----|
| `prepare-matrix` | L0 | Verify scripts + flake check; emit curated matrix |
| `cargo-test-linux` | L1 | Rust core + linux-ui + protocol-status drift |
| `cargo-test-macos-arm64` | L1 | Native Darwin Rust tests |
| `swift-test-macos-x86_64` | L1 | SwiftUI / model contract tests |
| `build` (matrix) | L2 | Curated `nix build` + FlakeHub push/pull |
| `frontend-syntax-check` | L2-lite | Xcode syntax without full Nix backend |

## Adding a matrix target

1. Confirm `nix build .#packages.<system>.<attr>` works locally.
2. Append to `.github/ci-package-matrix.json` with a one-line `why`.
3. Prefer attrs that **fail closed** on real regressions over “build every lib.”
4. Heavy IPA / full `wawona-ios` / full `wawona-android` APK stay on **device-e2e** / release, not every push.
