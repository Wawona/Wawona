# Mission-critical assurance

Canonical policy: `Wawona/docs/mission-critical-assurance.md`.
Tool matrix and navigation: `Wawona/docs/verification-matrix.md`.
Skill: `wawona-formal-verification`.

AI-authored changes have the same review, proof, test, security, and provenance
requirements as human changes. Model confidence is not evidence.

Use risk tiers. VM memory, MMU, CPU, virtio, privilege, watchdog, and display
ownership changes are Tier 3. They require named obligations tied to production
Rust, bounded proof, an unbounded model when tractable, negative tests, and an
explicit statement of what remains unproved.

Do not introduce Bend-2-generated C product logic. It violates Rust-first and
creates a second semantics that Kani, Verus, and Miri do not jointly cover.

Stage 2 UI laws use one bridge: Contract action, `wawona-laws` transition,
Bend model of that transition. Exact `back` / `open` / `select` stay the
live navigator. Do not add a second Bend navigation stack. Agents may edit
helpers and proofs. Agents may not drop, rename, or rewrite a law in
`LAWS.bend` unless `verification/bend/laws.lock` changes in the same edit.
`wawona-laws` `coverage` must name every `app.contract` action, every catalog
interface, and every erroneous-check helper. `ErroneousChecks::None` is
no-client-error. Negative-integer checks stay `kani`.

Org verification contract: `docs/verification-matrix.md`. The CI check name is
**Verification report** (`verify-all.yml`). Pinned tools fail closed (`severity:
error`). Unpinned research provers and Ubuntu-missing analyzers warn until a
pinned path exists. Do not claim a warning row is a completed proof.

`sanitize_ssh_host` owns SSH host rules. Swift and Kotlin mirrors stay frozen.
Factor clamp / keycode / SHM bounds into `invariants` / `wawona_cproof` helpers.
Do not ship Dafny, F*, KeY, JML, or Lean as product code. CompCert is not the
product compiler. A seL4-style rewrite is not this product. Objective-C is
outside the C prover set. Stubs are analyzer-only. `pool_create_buffer` needs
`wawona_shm_rect_in_pool` before any proof calls it safe. CDSChecker is for the
`_Atomic` counters in `android_jni.c`. ThreadSanitizer is for the iland
presenter mutex.

A green verifier covers the named function only. Findings use one record:
tool, file, line, rule, failure, fix (and severity).
