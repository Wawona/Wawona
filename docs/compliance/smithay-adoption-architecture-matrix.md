# Smithay Adoption Architecture Matrix

This document captures Smithay integration patterns translated into Wawona-specific migration guidance.

## What Was Reviewed

- `inspirational_projects/smithay/src/wayland/mod.rs`
- Wawona protocol registration and state boundaries in `src/core/wayland/*` and `src/core/state/mod.rs`

## Observed Smithay Wiring Pattern

- A single compositor state owns protocol-specific Smithay `*State` objects.
- Smithay delegate macros pair with handler traits to bind protocol dispatch.
- Core shell lifecycle is handler-driven (`CompositorHandler`, `XdgShellHandler`) with explicit configure loops.
- Output state ownership and xdg-output wiring are explicit and centrally managed.

## Adopt / Adapt / Avoid Matrix

- **Adopt**
  - Smithay state/delegate ownership pattern per protocol family.
  - Handler-trait-driven lifecycle wiring for compositor + shell + seat + shm.
  - Per-protocol, explicit state initialization in one registration boundary.

- **Adapt**
  - Keep Wawona profile gate authority (`store-safe`, `store-safe-remote`, `desktop-host`, `full-dev`) as runtime exposure truth.
  - Preserve Wawona platform behavior (mobile-safe policy, store compliance constraints).
  - Preserve Wawona compositor event model (`CompositorEvent`) while replacing protocol internals.

- **Avoid**
  - Monolithic coupling between protocol state and platform UI loop.
  - Implicit protocol exposure without manifest contract coverage.
  - Platform assumptions that reduce cross-platform parity.

## Migration Pitfalls Identified

- Dropping Smithay `*State` instances removes corresponding globals; state lifetime must be compositor-lifetime.
- Mixed custom + Smithay handling for the same interface can double-register globals unless tightly gated.
- Shell configure sequencing (`ack_configure`, popup grab paths) must preserve existing Wawona behavior.
- Linux-only protocols (`drm_lease`, `drm_syncobj`) require explicit compile/runtime branching to keep Apple/Android builds clean.

## Wawona Action Items Derived

- Keep `wayland-protocol-manifest.toml` as strict source-of-truth for interface coverage + profile exposure + compile expectations.
- Keep non-Smithay protocols only with `equivalent = "no-equivalent"` and explicit quarantine notes.
- Use Smithay module wiring under dedicated migration boundaries before replacing existing dispatch entrypoints.
