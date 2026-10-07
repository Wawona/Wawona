---
name: wawona-formal-verification
description: Org Verification report and Relay Kani/Verus. Navigate matrix, run scripts, keep one helper implementation, reduce fragility. Use before VM, compositor, JNI, Nix, or proof-tool changes.
---

# Formal verification and Verification report

Canonical status and navigation: `Wawona/docs/verification-matrix.md`.
Rule: `wawona-mission-critical-assurance`. Do not claim whole-product proof.

## Navigate in one minute

```text
Matrix (what runs / severity)     → docs/verification-matrix.md
Relay Tier-3 obligations          → Relay/verification/PROOF_OBLIGATIONS.md
CI check name                     → Verification report (verify-all.yml)
Local surface                     → bash scripts/verify-<name>.sh out.ndjson
Findings                          → NDJSON via scripts/verification-report.py
```

| Change | Helper / vector | Script |
|---|---|---|
| Rect clamp, generation counter | `src/core/invariants.rs` | `verify-formal.sh`, `verify-heavy.sh` |
| SSH host policy | `src/domain/validation.rs` + `verification/ssh_host_vector.tsv` | `verify-swift.sh`, `verify-kotlin.sh` |
| C bounds / atomics | `src/platform/cproof/wawona_cproof.h` | `verify-c.sh` |
| Relay VM / MMU | production helpers + Verus models | `Relay/scripts/verify-formal.sh` |
| Flake parse | all `*.nix` | `verify-nix.sh` |

## Fragility and optimization

- **One implementation.** Factor pure helpers. Point Kani, fuzz, CBMC, and
  differentials at those helpers. Do not "optimize" by deleting checks or
  forking a second Swift/Kotlin/C policy.
- **Pinned vs warn.** Error severity fails the job. Warnings (unpinned research
  provers, Frama-C on Ubuntu 24.04, AGP 9 SpotBugs) stay visible in the report
  but do not pretend to be green proofs.
- **Host only.** Verifiers never ship in store IPA/AAB.
- **NDJSON.** Every failure is `tool`, `file`, `line`, `rule`, `failure`,
  `fix` (+ `severity`). Do not leave agents in raw log soup.

## Relay (Tier 3)

- Kani 0.68.0 on production Rust helpers (`#[cfg(kani)]`).
- Verus 0.2026.09.27.3cf1832 models in `Relay/verification/verus/`.
- Run `Relay/scripts/verify-formal.sh`. Both must pass for the stamp.
- Prefer `Relay/scripts/verified-cargo.sh`. Runner rejects stale digests.
- Loom lifecycle: `verification/loom-lifecycle` with `RUSTFLAGS=--cfg loom`.
- Miri and sanitizers are dynamic checks, not mathematical proof.

## Wawona Verification report

Workflow: `.github/workflows/verify-all.yml` (name Verification).
Required check: job **Verification report**.

```bash
bash scripts/verify-formal.sh verification-out/formal.ndjson
bash scripts/verify-heavy.sh verification-out/heavy.ndjson
bash scripts/verify-c.sh verification-out/c.ndjson
bash scripts/verify-swift.sh verification-out/swift.ndjson
bash scripts/verify-kotlin.sh verification-out/kotlin.ndjson
bash scripts/verify-nix.sh verification-out/nix.ndjson
python3 scripts/verification-report.py summarize verification-out --markdown verification-out/report.md
```

Fuzz targets live under `fuzz/` and depend on `verification/helpers-check`
(not the full compositor link).

Ruleset enable (pass-wrapped `gh`; unset stale `GH_TOKEN`):

```bash
scripts/enable-verification-ruleset.sh Wawona/Wawona
```

## Hard rejects

- Whole-VM or whole-app "proved" claims
- Soft-skip of a pinned required tool
- Second sanitize/clamp/keycode implementation
- Bend-2-generated C product logic
- Dafny, F*, KeY, JML, Lean, CompCert, seL4 rewrite as product code
- ACSL that certifies a stub as the compositor
- Calling research-prover warnings a completed proof
