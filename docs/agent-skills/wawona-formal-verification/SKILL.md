---
name: wawona-formal-verification
description: Mandatory Kani and Verus gate for Wawona Relay VM Rust. Use before building, testing, or executing Relay VM code and when changing page, virtio, MMU, CPU, or FFI invariants.
---

# Wawona Relay formal verification

Relay VM Rust uses both tools. Neither substitutes for tests.

- Kani 0.68.0 checks actual production Rust helpers with bit-precise bounded
  model checking. Harnesses live beside code under `#[cfg(kani)]`.
- Verus 0.2026.09.27.3cf1832 proves unbounded mathematical models in
  `Relay/verification/verus/`.
- Run `Relay/scripts/verify-formal.sh`. Both must pass.
- Execute Cargo tests/examples/binaries only after current proof stamp exists.
  `Relay/.cargo/config.toml` routes execution through
  `scripts/verified-runner.sh`, rejecting missing or stale source digest.
- Prefer `Relay/scripts/verified-cargo.sh <cargo args...>`.
- CI has separate mandatory Kani and Verus jobs.
- Host verifiers never enter mobile app artifacts. Product Rust checked by
  Kani remains exact code linked there.
- No duplicate verified implementation. Factor pure production helpers, point
  Kani at them, and pair Verus mathematical model by named invariant.
- Do not claim whole-VM proof. State exact harnesses and proof obligations.
- Treat LAWs as named Rust preconditions and postconditions tied to production
  helpers. Do not add a Bend-2-to-C product implementation.
- Miri and sanitizers are independent dynamic checks. Miri does not execute
  linked C, and neither is a mathematical proof.

Initial coverage: 4/16 KiB arena round-up, virtio block request bounds, and
split virtio MMIO 64-bit queue address assembly.
