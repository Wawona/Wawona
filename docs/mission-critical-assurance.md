# Mission-critical assurance

Wawona treats verification as evidence about named obligations, not as a claim
that a repository or product is flawless. AI-authored and human-authored changes
have the same gates. A model's explanation, confidence, or self-review is not
evidence.

## Organization baseline

Every Wawona organization repository runs the shared `Wawona org quality`
workflow. It checks changed-file integrity, parses changed data and script files,
checks Rust formatting when Rust changes, inventories dependency locks with
OSV, reviews dependency additions on pull requests, and rejects high-severity
zizmor findings in changed GitHub Actions workflows. Existing vulnerability and
workflow debt stays visible without making the initial organization rollout
unusable; new high-severity dependency additions remain blocked.

GitHub's organization security configuration is attached to all current and
future repositories. It enables the dependency graph, Dependabot alerts,
CodeQL default setup, secret scanning, push protection, validity checks,
non-provider patterns, extended metadata, and private vulnerability reporting.

The shared workflow is a floor. Existing product, package, device, and formal
verification workflows remain mandatory.

## Assurance tiers

| Tier | Change class | Required evidence |
|---|---|---|
| 0 | Prose, metadata, static assets | Organization baseline and review |
| 1 | Build recipes, packaging, catalogs | Tier 0 plus locked evaluation/build and package smoke test |
| 2 | Parsers, protocols, FFI, unsafe code, concurrency | Tier 1 plus property tests or fuzzing, sanitizer or Miri coverage where supported, and ABI/protocol compatibility tests |
| 3 | VM memory, MMU, CPU, virtio, privilege, watchdog, display ownership | Tier 2 plus named mathematical laws, bounded proof against production Rust, an unbounded mathematical model when tractable, and fail-closed runtime validation |

Risk decides the tier, not repository language or change size. A one-line bounds
change can be Tier 3. A large documentation edit can be Tier 0.

## Proof shape

Each Tier 3 obligation must identify:

1. The production function or state transition.
2. Preconditions and postconditions in exact arithmetic or state terms.
3. The bounded harness that calls production code.
4. The unbounded model and its relationship to the production types.
5. Concrete regression and negative tests.
6. What remains unproved.

Kani checks bit-precise bounded behavior of actual Rust. Verus proves unbounded
mathematical models. Tests, fuzzers, Miri, sanitizers, and static analyzers find
different classes of defects. None substitutes for the others.

## Bend-2 and LAWs

Wawona adopts the useful part of the LAWs idea: small named preconditions and
postconditions attached to production helpers, checked by independent proof and
runtime layers.

Wawona does not add a Bend-2-to-C product path. New Wawona logic is Rust, and a
generated C copy would create a second implementation outside Kani, Verus, and
Miri's shared Rust semantics. Miri cannot execute linked C, and Kani does not
prove generated C by calling it through a Rust declaration. C, Objective-C,
JNI, and UniFFI remain thin native UI or ABI glue.

Bend 2.0.40 is installed as a specification tool. Laws and proofs live in
`verification/bend/`. `cargo xtask prove bend` runs `bend PROOF.bend` and
`bend PROOF.bend --verdict` with `BEND_NO_TELEMETRY=1`. The laws cover
`start_machine` / `stop_machine` (`crates/wawona-laws`), the one-level
Machines and Settings route table (`nav_place` in that crate), the non-negative
axis of `clamp_rect`, `normalize_ssh_port`, and the protocol predicates named
in `verification/bend/README.md`. Exact Contract `machinePhase` calls those Rust functions
through `wawona-data` on native hosts. The web executor answers the same
step from `app.ts` because the page does not link the crate. UniFFI
`machine_phase_apply` and `nav_place_apply` are the same functions. The Bend files are
the model of those functions. They are not compiled into any host.

Stage 2 checks critical universal-UI actions through that same bridge.
Contract declares the action and sends a named query. `wawona-laws` is the
Rust transition. `job.bend` is the same transition. `LAWS.bend` states the
requirement and `PROOF.bend` proves the model. Exact `back`, `open`, and
`select` stay the live navigator. `nav_place` answers the route root. Do not
add a second navigation stack in Bend. Native paint, focus delivery, and
pixels stay runtime tests.

Growth order: session phase and route root, then window membership and
focus, dialogs, settings commits, and the compositor calls those helpers
make. A green Bend file proves the named transition. It proves the handler
where the handler's decision is that helper and Kani or Verus covers the
helper.

`verification/bend/laws.lock` is the approval record. An agent may change a
Rust helper and its proof. An agent may not drop, rename, or rewrite a law
unless that lock changes in the same edit. `cargo xtask prove bend` fails
when the lock and `LAWS.bend` disagree. The lane stays explicit until the
runner image has Bend 2.0.40 and Lean. A missing binary is an error on that
lane. It is not a green proof, and it is not yet a Verification report
failure.

Relay is the first Tier 3 implementation. Its page geometry, virtio block span,
and split MMIO address laws are checked by production-code Kani harnesses and
paired Verus models. See `Relay/verification/README.md`.

The org verification contract for Rust, Swift, Kotlin, Nix, and Wawona-owned C
is `docs/verification-matrix.md`. That file is the navigation map: which script
to run, which helper owns a law, pinned error vs warning severity, and how the
gates reduce fragility (one implementation, no deleted bounds checks, NDJSON
findings). The CI check name is **Verification report**. Do not describe a
warning-only research prover as a green gate. Swift and Kotlin mirrors of
`sanitize_ssh_host` stay frozen. Owned C uses `wawona_cproof` helpers. Stubs
are not proved correct by returning zero. Objective-C is outside the C prover
set. Skill: `wawona-formal-verification`.

## Release evidence

Release workflows must preserve source revision, locked dependencies, build
logs, test/proof results, artifact hashes, and platform signing output. Publish
SBOMs and GitHub artifact attestations for release artifacts as those workflows
are migrated. Attestations establish provenance, not correctness.
