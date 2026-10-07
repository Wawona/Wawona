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

Relay is the first Tier 3 implementation. Its page geometry, virtio block span,
and split MMIO address laws are checked by production-code Kani harnesses and
paired Verus models. See `Relay/verification/README.md`.

The org verification contract for Rust, Swift, Kotlin, and Wawona-owned C is
`docs/verification-matrix.md`. That file lists what already runs and what is
required but not wired. Do not describe an unwired tool as a green gate.
Swift and Kotlin mirrors of `sanitize_ssh_host` stay frozen. Owned C gets the
tools that can see that file. Stubs are not proved correct by returning zero.
Objective-C is outside the C prover set.

## Release evidence

Release workflows must preserve source revision, locked dependencies, build
logs, test/proof results, artifact hashes, and platform signing output. Publish
SBOMs and GitHub artifact attestations for release artifacts as those workflows
are migrated. Attestations establish provenance, not correctness.
