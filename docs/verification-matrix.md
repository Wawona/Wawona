# Verification matrix

Decision recorded 2026-10-06. Updated 2026-10-07 for shipped Verification
report gates, severity policy, and agent navigation.

A passing tool is evidence for a **named function** under **named assumptions**.
It is not a claim that Wawona, Relay, Weston, Niri, Smithay, SwiftUI, ART, the
NDK, or a flake product attr is proved.

Host verifiers never link into an App Store, TestFlight, or Play binary.

Canonical status lives here. Skills and rules point at this file.

## Why this exists (fragility and optimization)

Verification is how Wawona keeps a large multi-language tree from rotting into
untyped shortcuts:

| Pressure | What the gates force |
|---|---|
| Duplicate policy (SSH host, rect clamp, keycode OK) | One Rust (or cproof) owner. Swift/Kotlin stay frozen differentials. |
| "Optimize" by deleting bounds checks | Kani / Verus / CBMC / cproof helpers reject the shortcut. |
| JNI / SHM pointer math | `wawona_shm_rect_in_pool` and `wawona_copy_capped` before use. |
| Racey counters / presenter | Loom, CDSChecker, TSan on the named sites. |
| Silent CI skip | Missing pinned tool is a finding. Unpinned research provers warn. |
| Flake eval rot | Parse every `.nix`. Format-check `flake.nix`. Metadata must load. |

**Code optimization** means keep hot paths, but move proof-facing logic into
small pure helpers (`src/core/invariants.rs`, `src/platform/cproof/`). Do not
inline a second copy in Swift, Kotlin, or a "faster" C fork. Fuzz and Kani
point at the same helpers product code calls.

**Reduce fragility** means fail closed on the production-critical surface
(formal Rust, clamp fuzz, SSH vector, Gradle tests, nix parse) and record
honest warnings for tools that are not yet pinned on Ubuntu 24.04 GHA.

## How to navigate (agents and humans)

```text
1. Read this file (status + severity).
2. Skill: wawona-formal-verification (how to run / what not to claim).
3. Rule: wawona-mission-critical-assurance (tiers + AI parity).
4. Change code in the helper the gate already names.
5. Local: bash scripts/verify-<surface>.sh verification-out/<surface>.ndjson
6. CI: workflow Verification (verify-all.yml), check name "Verification report".
7. Failures: one NDJSON row per finding (tool, file, line, rule, failure, fix).
```

| You are changing… | Open first | Local script |
|---|---|---|
| Relay VM / MMU / virtio | `Relay/verification/PROOF_OBLIGATIONS.md` | `Relay/scripts/verify-formal.sh` |
| Clamp / sanitize / generation counter | `src/core/invariants.rs` | `scripts/verify-formal.sh` |
| Owned C helpers / JNI bounds | `src/platform/cproof/wawona_cproof.h` | `scripts/verify-c.sh` |
| SSH host string policy | `src/domain/validation.rs` + `verification/ssh_host_vector.tsv` | `verify-swift.sh` / `verify-kotlin.sh` |
| Android MachineInputSanitizer | Kotlin + `verification/kotlin/SanitizeHarness.java` | `scripts/verify-kotlin.sh` |
| Flake / `.nix` parse | `flake.nix` | `scripts/verify-nix.sh` |
| Org small Rust flake | `rust-repo-floor.yml` | cargo clippy/deny/test |
| Org small Nix flake | `nix-repo-floor.yml` | parse + floor |

Operator ruleset (needs wrapped `gh` via pass; unset a stale `GH_TOKEN`):

```bash
# scripts/enable-verification-ruleset.sh Wawona/Wawona
```

OrganizationAdmin may bypass so the workflow that produces the check can land.
Do not leave enforcement disabled after bootstrap.

## Severity policy (2026-10-07)

| Class | Severity | Job exits non-zero? |
|---|---|---|
| Pinned tools that must run (Kani, Verus, Miri, cargo-fuzz ASan, SSH vector, Gradle test/detekt/lint, nix parse, flake metadata, cproof ASan/CBMC/tidy) | `error` | Yes |
| Unpinned research installs (Rudra, MIRAI, Prusti, Creusot, Flux, Aeneas, Haybale) | `warning` | No (until a pinned GHA path exists) |
| Not on Ubuntu 24.04 apt (Frama-C, KLEE, CPA) | `warning` | No |
| CDSChecker missing until a pinned GHA install | `warning` | No |
| SpotBugs on AGP 9 (BaseExtension removed) | `warning` | No |
| JBMC / JPF missing on runner | `warning` | No |
| flake.nix statix/deadnix style debt (repeated follows keys) | `warning` | No |

`scripts/verification-report.py summarize` fails only on `severity: error`.
Silent skip of a **pinned** tool is still forbidden.

## Running today (wired)

### Relay (`formal-verification.yml`)

- Kani 0.68.0 on `relay-vm`.
- Verus `0.2026.09.27.3cf1832` on `verification/verus/relay_vm_invariants.rs`.
- Miri nightly `2026-09-29`.
- cargo-fuzz 0.13.2: `page_translate` and `vsock_packets`, 60s, prefer ASan.
- Clippy correctness/suspicious, cargo-deny, locked tests, ARM64 corpus.
- proptest on `ram_span_ok`.
- Loom lifecycle in `verification/loom-lifecycle` (`RUSTFLAGS=--cfg loom`).
- Heavy research prover installs: warn until pinned.

### Wawona (`verify-all.yml`, workflow name Verification)

Push and PR on `development` / `master`. Final job name **Verification report**
(required ruleset check).

| Script | Surface |
|---|---|
| `scripts/verify-formal.sh` | clippy, deny, proptest, Kani, Miri, Loom, Verus (rect + sanitize) |
| `scripts/verify-heavy.sh` | cargo-fuzz ASan 60s (helpers-check); research installs warn |
| `scripts/verify-c.sh` | cproof ASan/UBSan, clang-tidy (cert/bugprone on cproof TU), scan-build, CBMC, Valgrind, MSan, CDSChecker harness when installed, TSan; Frama-C/KLEE/CPA/CDSChecker warn if missing |
| `scripts/verify-swift.sh` | SSH vector (Swift Testing), strict concurrency, ASan/UBSan/TSan |
| `scripts/verify-kotlin.sh` | Kotest, detekt, lint; SpotBugs/JBMC/JPF warn if unwired/missing |
| `scripts/verify-nix.sh` | parse all `.nix`, alejandra on `flake.nix`, flake metadata; full-tree format and `nix flake check` stay in Gate: packages |

Helpers: `src/core/invariants.rs`, `src/core/generation_counter.rs`,
`src/platform/cproof/wawona_cproof.h`, `verification/ssh_host_vector.tsv`,
`fuzz/` → `verification/helpers-check` (not the full compositor crate).

Reusable floors (other flakes call these; job names are **not**
"Verification report"):

- `.github/workflows/nix-repo-floor.yml` (job Nix floor)
- `.github/workflows/rust-repo-floor.yml` (job Rust floor)
- Wawona path-filtered `nix-floor.yml` wraps the nix reusable workflow

### Org floors

- Per-repo `rust-floor.yml` / `nix-floor.yml` where wired.
- Org-quality OSV: no `continue-on-error`.
- Terminal and ToolbarKeys have `org-quality.yml`.
- agent-device has a Swift sanitize job.

## Branch ruleset

`development` requires the check named **Verification report**.
Promote only with Gate: packages, Verification report, and Gate: products green.

Auth: use the pass-wrapped `gh` from nix-darwin (unset a bad agent `GH_TOKEN`).
See `scripts/enable-verification-ruleset.sh` (OrganizationAdmin bypass allowed).

## Miri callers

Miri is requested for: `wwn-phoon-rs`, `ToolbarKeys`, `Terminal`.

| Repo | Status |
|---|---|
| `wwn-phoon-rs` | Miri on via `rust-floor.yml`. First CI red names the blocker here. |
| `ToolbarKeys` | Same. |
| `Terminal` | Same. |

A silent skip is forbidden. If Miri cannot load a crate, add the exact error
string to this table and keep the job red until fixed or the row is written.

## What a green job is

A green **Verification report** means every child job succeeded and the
aggregator saw no `severity: error` rows. Warnings may still appear in the
markdown summary. A green row is not a whole-product proof.

Creusot, Prusti, and Flux see safe Rust only. A green Creusot run does not
extend `Relay/verification/PROOF_OBLIGATIONS.md`.

## One implementation

`sanitize_ssh_host` in `src/domain/validation.rs` owns SSH host rules.
Swift and Kotlin copies stay frozen. Differential tests only.

No Dafny, F*, KeY, JML, or Lean product code. No CompCert. No seL4 rewrite.
No Astrée, Polyspace, Coverity, SonarQube, Helix QAC, VCC.

## Nix

On **Wawona** (`scripts/verify-nix.sh`):

- `nix-instantiate --parse` on every `*.nix` (error if broken)
- alejandra `--check flake.nix` (error)
- statix / deadnix on `flake.nix` (warning until follows-key style is cleaned)
- `nix flake metadata` (error)
- Full-tree format and `nix flake check` remain Gate: packages work

On **other org flakes** (`nix-repo-floor.yml`): parse + format + flake check
as that reusable workflow implements.

Vendored third-party trees need an explicit path allowlist row here. Silent
skip is a red report entry.

## Failure report

Aggregator: `scripts/verification-report.py`. NDJSON fields:
`tool`, `file`, `line`, `rule`, `failure`, `fix`, `severity`.

## Hard rejects

- Whole-product proof claims
- Soft-skip of a **pinned** required tool
- Mode B / JIT / private API in store IPA
- ACSL that certifies a stub as the compositor
- Growing `input_android.c` into a keymap product
- `continue-on-error` on OSV
- Second copy of clamp / sanitize / keycode policy outside the named helper
- Claiming research provers (Rudra, MIRAI, …) are green gates while they only warn
