# Wayland protocol milestones (Explorer → 100%)

Canonical remaining-work map for bringing every tracked Wayland Explorer
family to **Functional**. Status counts always come from
[`protocol-status.md`](./protocol-status.md) (regenerate with
`cargo xtask gen protocol-status`). Do not hand-count.

Site mirror: https://wawona.io/docs/contributor/protocols/  
(synced from this repo via `wawona.io/scripts/sync-protocol-status.sh`).

Guide: [wayland.app](https://wayland.app/protocols/) (Wayland Explorer).

## Status floor (regenerate before editing)

| Status | Meaning |
|--------|--------|
| Functional | Handles requests, mutates state, sends events |
| Partial | Global registered; some requests handled; incomplete semantics |
| Stub | Global registered; handlers log or no-op |
| Missing | Not registered; tracked Explorer gap |

Portable rule: protocol semantics must not assume Linux. DRM lease advertises
only when a DRM/KMS node is available (capability). Syncobj registers on every
OS under `desktop-protocols`.

## GitHub milestones (Wawona/Wawona)

Create or refresh with `cargo xtask gen protocol-milestones` (requires a valid
`gh` token / `gh auth login`). Titles are stable; numbers are assigned by
GitHub. If `pass` `GH_TOKEN` returns 401, refresh the token before running.

| Phase | Milestone title | Scope |
|-------|-----------------|--------|
| P0 | Wayland protocols: Explorer catalog honesty | Catalog tracks all Explorer families; Missing rows; no Linux-only advertise gates; `docs/protocol-status.md` + site sync |
| P1 | Wayland protocols: close Partials | commit-timing hold-until-target, fifo, gestures, idle-notify, foreign-toplevel list, wlr foreign/virtual-pointer, toplevel icon/tag |
| P2 | Wayland protocols: high-traffic Stubs | session-lock, workspace, data-control, color, screencopy, wlr-output/gamma/power, security-context, tablet, xwayland |
| P3 | Wayland protocols: KDE / Plasma remainder | plasma shell, window management, virtual desktop, screencast, output management/device/order, appmenu, fake-input, … |
| P4 | Wayland protocols: COSMIC + River | All COSMIC + River Missing → Stub → Functional |
| P5 | Wayland protocols: Hyprland + Treeland + Weston | Hyprland, Treeland, Weston/IVI Missing → Functional |
| P6 | Wayland protocols: external vendor shells | GTK shell, Aura, AGL, Mir, XApp, NVIDIA EGLStream as demand requires |
| Proof | Wayland protocols: Kani erroneous-check proofs | Every Functional protocol is in `PROTOCOL_PROOF_OBLIGATIONS`; helpers + Kani in `protocol_proofs.rs`; `build.rs` fails compile on inventory drift; `cargo xtask prove protocol-proofs` fails Verification report |

Issues for protocol work must set `--milestone` to one of the titles above.

## Family ownership

| Family | Origin in catalog | Milestone phase |
|--------|-------------------|-----------------|
| Wayland core | `WaylandCore` | P0 (done when 8/8 Functional; tip-version bumps stay P0 chores) |
| XDG / wayland-protocols | `Xdg` | P1–P2 |
| wlroots | `Wlr` | P1–P2 |
| ext / staging | `Ext` | P1–P2 |
| KDE / Plasma | `Plasma` | P3 |
| COSMIC | `Cosmic` | P4 |
| River | `River` | P4 |
| Hyprland | `Hyprland` | P5 |
| Weston / IVI | `Weston` | P5 |
| Treeland | `Treeland` | P5 |
| External | `External` | P6 |

## Work packages (one family at a time)

Done bar for a package: every interface in that family is **Functional**, with
unit tests, `protocol_matrix` honesty, `PROTOCOL_PROOF_OBLIGATIONS` (+ Kani
helpers when needed), and NixOS `cargo xtask prove protocol-proofs` green.
Portable Rust core only; platform hosts get capability hooks, not a second
protocol stack.

| Package | Milestone | Remaining (live matrix) |
|---------|-----------|-------------------------|
| Core tip versions | P0 chore | **done** (8/8 Functional; tip bumps stay chores) |
| XDG remainder | P1–P2 | **done** (incl. `xdg_session_manager_v1`) |
| wlroots remainder | P1–P2 | **done** (11/11 Functional) |
| ext remainder | P1–P2 | **done** (incl. `xx_*` experimental) |
| Plasma | P3 | **done** (all Plasma catalog rows Functional) |
| COSMIC | P4 | **done** (incl. image-source managers) |
| River | P4 | **done** (9/9 Functional) |
| Hyprland | P5 | **done** (7/7 Functional) |
| Treeland | P5 | **done** (11/11 Functional) |
| Weston/IVI | P5 | **done** (10/10 Functional) |
| External | P6 | **done** (vendor shells + `wl_drm`) |
| Proof close | Proof | **done** (every Functional row has a proof obligation; `cargo xtask prove protocol-proofs` green) |

Live floor: **168 Functional / 0 Partial / 0 Stub / 0 Missing** (regenerate
`docs/protocol-status.md` before citing). Explorer family closure complete.

Serial order was: finish P2 packages before P3; COSMIC then River inside P4;
Hyprland → Treeland → Weston inside P5; External last. New Explorer interfaces
must land as Missing first, then climb Stub → Functional with proofs before
the matching milestone can stay closed.

## Sync checklist (every protocol PR)

1. Update `PROTOCOL_CATALOG` status honestly.
2. `cargo xtask gen protocol-status`
3. `cargo xtask gen protocol-expect` (guest probe expect JSON + sync into
   `repo.wawona.io` `protocol-probe`)
4. `../wawona.io/scripts/sync-protocol-status.sh` (or CI dispatch after master merge)
5. Attach issues/PRs to the matching milestone title above.
6. Proof helpers for new erroneous checks (see Verification report / Kani).

## Related

* [`protocol-status.md`](./protocol-status.md) — generated matrix
* [`PROTOCOLS.md`](./PROTOCOLS.md) — human guide
* [`verification-matrix.md`](./verification-matrix.md) — proof tooling
* `cargo xtask prove protocol-proofs` — fail-closed Kani + inventory
* `cargo xtask gen protocol-milestones` — create/update GitHub milestones
