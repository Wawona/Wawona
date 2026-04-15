# Wawona Software Bloat Audit (2026)

## Scope

This document is a deep architecture and maintainability audit of the current Wawona codebase, focused on:

- Where software bloat exists today.
- Where architecture has drifted from original intent.
- What likely went wrong in migration decisions.
- A concrete staged plan to reduce complexity without destabilizing the compositor.

This is a planning and analysis document only. No code changes are proposed here directly.

## Original Architecture Intent (Baseline)

From `docs/goals.md`, `docs/2026-ARCHITECTURE-STRUCTURE.md`, and `docs/2026-SOURCE-LAYOUT-RULES.md`, the intended architecture is:

- Rust compositor core + FFI as the runtime foundation.
- Native compositor surfaces stay native per host platform (ObjC/AppKit/UIKit/JNI).
- Apple and Android use native UI stacks that mirror machine/settings behavior.
- `Sources/WawonaUI` and `Sources/WawonaModel` are intended as the canonical feature layer.
- `src/platform/macos/ui` is transitional and should not continue growing for new feature ownership.

This architecture is sound. Drift occurred in execution and migration pacing.

## Executive Findings

1. **Dual machine/profile stacks remain active.**
   - Canonical Swift model exists: `MachineProfile` and `MachineProfileStore` in `Sources/WawonaModel/MachineProfile.swift`.
   - Legacy ObjC path remains active: `WWNMachineProfileStore` in `src/platform/macos/ui/Machines/WWNMachineProfileStore.h`.
   - Native bridge still depends on legacy store: `src/platform/macos/WWNCompositorBridge.m` references `WWNMachineProfileStore` for active machine and thumbnail decisions.

2. **Parallel Machines UI stacks still coexist.**
   - Shared UI stack: `Sources/WawonaUI/Machines/` has 7 files.
   - Legacy macOS stack: `src/platform/macos/ui/Machines/` has 10 files.
   - This duplicates surface area for machine list/editor/card behavior and increases change risk.

3. **Settings synchronization indicates persistent dual truth.**
   - `WWNPreferencesManager` still exposes `syncFromCanonicalWawonaPreferences`.
   - This is a migration seam that became semi-permanent and now adds cognitive and bug overhead.

4. **Android build/runtime strategy is robust but still over-complex.**
   - Build and runtime orchestration still span multiple tooling layers (Nix, Gradle, native JNI/runtime wiring).
   - This improves resilience but increases ambiguity around authoritative ownership boundaries.

5. **Android metadata ownership drift exists.**
   - App Gradle config: `minSdk = 28` in `android/app/build.gradle.kts`.
   - Secondary manifest path still declares `<uses-sdk ... minSdkVersion="36">` in `src/platform/android/AndroidManifest.xml`.
   - This mismatch is a migration-debris smell and a policy risk.

6. **Core build files have grown to high-maintenance size.**
   - `dependencies/wawona/android.nix`: 1135 lines.
   - `flake.nix`: 977 lines.
   - `src/ffi/api.rs`: 3230 lines.
   - `src/ffi/types.rs`: 1337 lines.
   - Scale is not inherently bad, but this concentration slows iteration and review quality.

## What Went Wrong (Architecture Drift Analysis)

### 1) Migration completed functionally, not structurally

The cross-platform migration progressed enough to run modern UI flows, but legacy macOS-specific stacks were not fully retired. This left:

- New canonical model/UI in `Sources/*`.
- Old model/UI still wired into compositor bridge/runtime.

Result: both systems must be maintained and reasoned about in parallel.

### 2) Bridge boundary kept legacy data contracts too long

The compositor bridge (`WWNCompositorBridge`) stayed coupled to `WWNMachineProfileStore`, so migration could not cleanly converge on `MachineProfileStore`.

Result: synchronization glue replaced hard ownership transfer.

### 3) Build reliability adaptations accumulated into configuration sprawl

Nix + Gradle integration added compatibility paths and environment switches to keep multiple workflows alive.

Result: resilient local/CI workflows, but unclear happy-path and higher onboarding tax.

### 4) Documentation lagged code shape

Some architecture docs still describe older layouts and assumptions while the tree evolved.

Result: intent and implementation diverged in developer mental models.

## Concrete Bloat Inventory

### A) Duplicate/parallel feature layers

- `Sources/WawonaUI/Machines/` (7 files)
- `src/platform/macos/ui/Machines/` (10 files)
- Duplicate editor views:
  - `Sources/WawonaUI/Machines/MachineEditorView.swift`
  - `Sources/WawonaWatch/MachineEditorView.swift`

### B) Persistent migration seams

- `WWNPreferencesManager.syncFromCanonicalWawonaPreferences` (active synchronization bridge).
- Legacy profile store still authoritative for native bridge behaviors.

### C) Android artifact-path ambiguity

In `android/app/build.gradle.kts`:

- historical Android artifact-path overrides.
- multiple legacy fallback roots.

This is technically useful, but too many active conventions at once.

### D) Large concentration files

- `src/ffi/api.rs` (3230 lines): oversized integration surface.
- `dependencies/wawona/android.nix` (1135 lines): broad orchestration in one file.
- `flake.nix` (977 lines): high global coupling for platform packaging.

## Did We Veer Off Course Too Far?

Short answer: **not irrecoverably**, but yes, we are materially off the intended ownership model.

- The core architecture (Rust + native compositor + platform-native UIs) is still correct.
- The drift is mostly in **ownership convergence** and **migration cleanup debt**, not in fundamental direction.
- If left unchecked, this drift will reduce velocity and increase platform-specific regressions.

## Optimization Plan (No Code Changes Yet)

### P0 - Re-establish single sources of truth (highest leverage)

1. Decide and document canonical runtime store ownership for machine/profile data on Apple platforms.
2. Convert native bridge read paths to one canonical adapter boundary (not dual direct stores).
3. Define one authoritative Android artifact root and one explicit fallback path policy.
4. Resolve Android SDK metadata mismatch by deprecating/removing stale manifest ownership.

Expected effect: largest reduction in hidden behavior divergence.

### P1 - Remove duplicated feature layers

1. Decommission legacy macOS `WWN*` Machines SwiftUI stack once parity checklist is complete.
2. Preserve only minimal native bridge components that cannot live in shared `Sources/*`.
3. Unify editor/form logic across `WawonaUI` and watch where practical.

Expected effect: meaningful code deletion and lower per-feature edit footprint.

### P2 - Reduce concentration and coupling

1. Split `src/ffi/api.rs` into domain modules with stable external ABI boundaries.
2. Split `dependencies/wawona/android.nix` by concern (artifact prep, export, packaging, CI hooks).
3. Add architecture status table in docs mapping "intended owner" vs "current owner" for each subsystem.

Expected effect: better reviewability, lower merge conflict pressure, easier onboarding.

## Proposed Checkpoints and Exit Criteria

### Checkpoint A: Ownership map complete

- Every subsystem has one canonical owner path.
- Deprecated path list is explicit and time-bounded.

### Checkpoint B: Runtime convergence complete

- Native compositor bridge no longer directly depends on legacy machine/profile store for primary machine state.
- Preferences sync bridges are either removed or strictly temporary with removal date.

### Checkpoint C: Build clarity complete

- Android build flow documented as one default path + one fallback.
- Stale Android manifest ownership removed from active build assumptions.

### Checkpoint D: Deletion pass complete

- Legacy `WWN*` machine UI stack removed or reduced to bridge-only minimum.
- Large orchestration files split and documented.

## Risks If We Do Nothing

- Divergent behavior between UI and runtime profile resolution.
- More brittle cross-platform releases due to artifact-path ambiguity.
- Rising cost of feature delivery as every machine/settings change touches multiple stacks.
- Higher chance of regressions when platform-specific fixes are applied to only one of duplicated implementations.

## Bottom Line

Wawona has not failed architecturally. It has accumulated migration debt and duplicated ownership layers while rapidly shipping cross-platform support. The fastest path to major optimization is not rewriting the compositor; it is converging ownership, deleting parallel stacks, and simplifying build-path authority.
