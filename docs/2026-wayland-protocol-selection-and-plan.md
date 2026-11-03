# Wayland Protocol Status, Next Selection, and Implementation Plan (2026)

> **Superseded for phase tracking.** Live matrix:
> [`protocol-status.md`](./protocol-status.md). Explorer → 100% milestones:
> [`protocol-milestones.md`](./protocol-milestones.md). Site:
> https://wawona.io/docs/contributor/protocols/. Keep the deep-dive below for
> commit-timing design notes only.

## Why this document exists

This is a deep-dive protocol planning document for Wawona.

Goals:

- Measure current protocol support against Wayland Explorer (`wayland.app`) references.
- Quantify what is already supported vs. what is available but not fully integrated.
- Select the most reasonable next protocol to implement now.
- Provide a full execution plan (architecture, milestones, test strategy, risks).

This document does **not** make code changes.

## Sources consulted

- [`wayland.app` protocol index](https://wayland.app/protocols/)
- [`wayland.app` core wayland protocol](https://wayland.app/protocols/wayland)
- [`wayland.app` xdg-shell protocol](https://wayland.app/protocols/xdg-shell)
- [`wayland.app` viewporter protocol](https://wayland.app/protocols/viewporter)
- [`wayland.app` presentation-time protocol](https://wayland.app/protocols/presentation-time)
- Local Wawona protocol registration paths:
  - `src/core/compositor.rs`
  - `src/core/wayland/wayland/mod.rs`
  - `src/core/wayland/xdg/mod.rs`
  - `src/core/wayland/wlr/mod.rs`
  - `src/core/wayland/ext/mod.rs`
  - `src/core/wayland/plasma/mod.rs`

## Current support snapshot

### 1) "Core protocols" support (practical baseline)

Using the common stable baseline from `wayland.app` and ecosystem expectations:

- `wayland` (core): **supported**
- `xdg-shell`: **supported**
- `viewporter`: **supported**
- `presentation-time`: **supported**

Result: **4 / 4 core baseline protocols supported**.

### 2) Current registered protocol breadth in Wawona

Protocol globals are registered from:

- `wayland::register(...)`
- `xdg::register(...)`
- `wlr::register(...)`
- `plasma::register(...)`
- `ext::register(...)`

Current codebase advertises about **67-68 globals** depending on runtime settings (`fullscreen-shell` advertisement toggle) and output count behavior.

## How much can we add right now?

### Immediate additions already scaffolded in-tree

These protocols already have implementation files and register functions, but are not part of the top-level registration path today:

1. `xdg_system_bell_v1` (`src/core/wayland/xdg/xdg_system_bell.rs`)
2. `xdg_toplevel_tag_v1` (`src/core/wayland/xdg/xdg_toplevel_tag.rs`)
3. `wp_commit_timing_manager_v1` (`src/core/wayland/ext/commit_timing.rs`)
4. `wp_color_manager_v1` (`src/core/wayland/ext/color_management.rs`)

These are **addable with medium-to-low integration cost** (especially #1 and #3).

### Additions present as stubs (not production-ready yet)

1. `wp_drm_lease_device_v1` (`src/core/wayland/ext/drm_lease.rs`, TODO register)
2. `wp_linux_drm_syncobj_manager_v1` (`src/core/wayland/ext/linux_drm_syncobj.rs`, TODO register)

These are **not** immediate wins for Apple-focused runtime targets and require substantial backend work.

### Net answer

- **Immediate addable protocols (reasonable now): 4**
- **Heavy addable protocols (longer-term): 2**

## Protocol selected for next implementation

## `wp_commit_timing_manager_v1` (commit-timing-v1)

### Why this one

`wp_commit_timing_v1` is the most reasonable next protocol because it has:

- Existing scaffold + state wiring already in-tree (`commit_timing.rs`).
- Clear product value for smooth frame pacing, video, and remote session responsiveness.
- Lower platform risk than color-management or DRM-centric protocols.
- Mostly compositor-core scheduling work (Rust), not deep per-platform GPU/OS hooks.

### Why not the alternatives first

- `xdg_system_bell_v1`: very low-risk but small impact.
- `wp_color_manager_v1`: higher complexity and color pipeline policy risk.
- `drm-lease` / `linux-drm-syncobj`: Linux-kernel-centric and not near-term Apple priority.

## Deep implementation plan: `wp_commit_timing_v1`

## Target outcome

Wawona should:

1. Correctly advertise `wp_commit_timing_manager_v1`.
2. Accept client target timestamps per-surface.
3. Integrate target timestamps into frame scheduling decisions.
4. Preserve protocol correctness under missed deadlines and surface lifecycle changes.
5. Expose measurable frame pacing improvements for timing-aware clients.

## Scope boundaries

In scope:

- Protocol registration and request handling integration.
- Scheduler consumption of target timestamps.
- Surface-lifecycle cleanup and safety.
- Tests and diagnostics.

Out of scope for this phase:

- Hard real-time guarantees.
- Platform-specific display driver synchronization redesign.
- HDR/color pipeline coupling.

## Implementation phases

### Phase 0: Specification and behavior lock

Deliverables:

- Add a short spec note in docs describing Wawona behavior for:
  - past timestamps
  - far-future timestamps
  - missing timestamp
  - destroyed surface with active timer

Key decision defaults:

- Past target timestamp => commit immediately.
- Near-future target => hold until frame budget allows.
- Excessively far target => cap to configured max defer window.

### Phase 1: Registration and lifecycle correctness

Work:

1. Register `register_commit_timing(...)` from `ext::register(...)`.
2. Ensure one timer lifecycle per-surface is robust under:
   - surface destroy
   - client disconnect
   - role changes
3. Confirm `state.ext.commit_timing.target_times` cleanup in all teardown paths.

Acceptance:

- Protocol appears in advertised globals.
- No stale timing entries after surface/client destruction.

### Phase 2: Scheduler integration

Work:

1. Integrate `CommitTimingState::get_target_ns` / `consume` into frame dispatch path.
2. Add a scheduler gate:
   - if target_ns is in the future within allowed window, defer present.
   - if target_ns elapsed, present on next eligible frame.
3. Keep compositor responsive: no global stalls from one surface timing target.

Acceptance:

- Timing-aware surfaces align better with requested presentation windows.
- Other clients remain unaffected under mixed workloads.

### Phase 3: Telemetry and debugability

Work:

1. Add trace points:
   - target timestamp received
   - defer duration chosen
   - deadline miss amount
2. Add counters:
   - timed commits
   - missed deadlines
   - clamped defers

Acceptance:

- Logs/counters allow tuning without protocol guesswork.

### Phase 4: Test matrix

Unit tests:

- timestamp parse correctness (`tv_sec_hi`, `tv_sec_lo`, `tv_nsec`).
- consume semantics.
- cleanup on destroy/disconnect.

Integration tests:

- mixed surfaces (timed + untimed) under load.
- commit ordering with near-future targets.
- behavior under repeated missed targets.

Manual validation:

- timing-sensitive client (video/player) in nested session.
- remote waypipe session frame pacing spot-check.

## Risk analysis

### Primary risks

1. **Over-deferring** introduces visible latency.
2. **Under-deferring** negates protocol value.
3. **Global coupling bug** causes one client to impact others.

### Mitigations

- enforce per-surface scheduling policy.
- add max defer clamp and fallback immediate path.
- ship with verbose metrics and conservative defaults first.

## Rollout plan

1. Implement behind default-on behavior with safe clamps.
2. Validate in macOS nested sessions first.
3. Validate on iOS/Android host paths where timing requests occur.
4. Expand to broader client compatibility checks.

## Success metrics

- Protocol advertised and exercised by at least one timing-aware client.
- Deadline miss rate decreases in controlled playback scenarios.
- No regressions in untimed client responsiveness.
- No compositor stalls or starvation from timed surfaces.

## Final recommendation

Next protocol to implement: **`wp_commit_timing_manager_v1`**.

Rationale:

- Best value-to-risk ratio in the current codebase.
- Existing partial implementation reduces lead time.
- Improves real user-visible smoothness without requiring heavy platform backend rewrites.
