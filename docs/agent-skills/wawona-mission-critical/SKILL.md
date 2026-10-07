---
name: wawona-mission-critical
description: Assurance tiers and evidence gates for critical Wawona changes, including AI-authored work, proofs, fuzzing, sanitizers, dependency security, and release provenance.
---

# Mission-critical Wawona changes

Read `docs/mission-critical-assurance.md` before changing VM memory, MMU, CPU,
virtio, privilege, watchdog, display ownership, unsafe/FFI, protocol parsers, or
release gates.

- AI output is untrusted input. Same review and evidence as human code.
- Pick Tier 0-3 by failure impact, not diff size.
- Tier 3 needs named laws tied to production Rust, Kani bounded proof, a Verus
  unbounded model when tractable, negative tests, and an explicit unproved list.
- Use fuzzing, Miri, sanitizers, and static analysis for their own defect classes.
  Do not describe them as mathematical proof.
- Do not claim a repository, VM, or product is flawless.
- Do not add Bend-2-generated C product logic. Preserve Rust-first and one
  production implementation. Adopt LAWs as Rust contracts and proof obligations.
- Every repo keeps the shared org-quality workflow. Product-specific gates add
  coverage; they do not replace the baseline.
- Language tools and what is actually wired: `docs/verification-matrix.md`.
  Do not claim a missing-tool red as a completed proof. Org-quality OSV already
  fails closed (no `continue-on-error`).
