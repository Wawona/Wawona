---
name: wawona-formal-verification
description: Relay Kani and Verus gate, plus the org verification matrix for Rust, Swift, Kotlin, C, and Nix. Use before VM, compositor, JNI, Nix, or proof-tool changes.
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

## Org matrix

Read `Wawona/docs/verification-matrix.md` before adding a prover or claiming
one runs. Gate: packages calls `verify-all.yml`. The check name is
**Verification report**.

- One law: `sanitize_ssh_host`. Swift and Kotlin copies stay frozen.
- No Dafny, F*, KeY, JML, or Lean product code. No CompCert. No seL4 rewrite.
- Creusot, Prusti, and Flux do not prove `unsafe` or JNI.
- Wawona-owned `.c` is in the matrix. Objective-C is not. Stubs are analyzer-only.
- SHM pool buffers must use `wawona_shm_rect_in_pool` before pointer math.
- CDSChecker is for the `_Atomic` counters via `wawona_count_*`. TSan is for the
  iland presenter mutex.
- Nix floor: parse, alejandra, statix, deadnix, flake metadata + check on every
  org flake (`nix-repo-floor.yml`). Not a product matrix build.
- Failures go through one NDJSON report (`tool`, `file`, `line`, `rule`,
  `failure`, `fix`). Do not leave the developer in raw logs.
- Org-quality OSV has no `continue-on-error`. High and critical advisories fail.
