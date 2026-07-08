# Smithay Adoption Decision (RFC #35 closure)

**Status:** Accepted. Closes [RFC #35 — integrate with Smithay](https://github.com/Wawona/Wawona/issues/35).

This document is the single decision record for how Wawona uses Smithay. It ties
together the two pieces the RFC asked about — the protocol layer and the
backend/wlroots question — and points at the living docs that track ongoing
migration status.

## Decision

1. **Adopt Smithay as the Wayland protocol library.** Wawona builds its
   compositor on Smithay's `wayland-server` / `wayland_frontend` protocol state
   machines rather than a hand-rolled protocol stack. This is exactly the
   `smithay::wayland` framework the RFC recommended and it is the direction we
   are actively migrating toward, protocol family by protocol family.
2. **Do not port wlroots; mirror its protocols natively.** Smithay is a library,
   not a compositor, so we keep native per-platform present backends
   (CAMetalLayer on Apple, `ANativeWindow` on Android, GTK on Linux) instead of
   implementing `smithay::backend` against GBM/DRM/libinput, which do not exist
   on our non-Linux targets. The wlroots protocol families that clients expect
   are implemented natively under `src/core/wayland/wlr/`.

The net effect matches the RFC's intent: Smithay owns protocol correctness; we
own the platform integration Smithay intentionally leaves open.

## Rationale

- **Backend reality (p18 — wlroots).** wlroots is GBM/DRM/libinput-first and
  assumes Linux KMS. Apple platforms have none of these and Android exposes them
  only through restricted NDK surfaces, so porting wlroots would mean
  reimplementing every backend anyway while inheriting a C API that fights App
  Store sandboxing. Full reasoning and the wlroots semantics we deliberately
  mirror are in [`../2026-wlroots-compat.md`](../2026-wlroots-compat.md).
- **Protocol correctness (p12 — protocol status).** Using Smithay's protocol
  state machines shrinks the bug surface versus custom structs/traits, exactly
  as the RFC argued. Advertised globals and per-profile exposure are tracked in
  the generated [`../protocol-status.md`](../protocol-status.md) and enforced in
  CI (`cargo-test-linux`).
- **Memory safety + FFI.** A Rust core with a thin C ABI (`src/ffi`) is easier
  to audit and to expose to Swift/Kotlin than wlroots' C internals.

## Adoption shape

- Per-protocol Smithay `*State` ownership with delegate macros and handler
  traits, wired at one registration boundary. Patterns and pitfalls:
  [`smithay-adoption-architecture-matrix.md`](./smithay-adoption-architecture-matrix.md).
- Interface → Smithay module mapping baseline:
  [`smithay-docs-index.md`](./smithay-docs-index.md).

## Current status and migration ledger

Adoption is incremental, not a big-bang rewrite. The authoritative,
CI-verified state lives in:

- Smithay-backed runtime set, dual-registration blockers, and the reclassify
  queue: [`smithay-feasibility-ledger.md`](./smithay-feasibility-ledger.md).
- Protocols intentionally kept outside Smithay-backed paths (all
  `equivalent = "no-equivalent"`, profile-gated):
  [`non-smithay-survivors.md`](./non-smithay-survivors.md).
- Advertised-globals snapshot per profile:
  [`../protocol-status.md`](../protocol-status.md).

The "All-55 closure rule" in the feasibility ledger requires every
`no-equivalent` interface to resolve to either `true-no-path` (no practical
Smithay owner, or ecosystem-specific) or `architecture-blocked` (Smithay-shaped
target exists but runtime ownership is still custom and stays profile-gated
until cutover). Because that classification is enforced by
`verify-wayland-runtime-ownership.py --strict` and
`verify-wayland-no-equivalent-closure.py`, the remaining migration work is a
tracked, guarded queue rather than an open question — which is why RFC #35 is
closed with this decision rather than left open pending full cutover.
