# Verification matrix

Decision recorded 2026-10-06. Updated 2026-10-06 for finish gates + Nix floor.
A passing tool is evidence for a named function under named assumptions. It is
not a claim that Wawona, Relay, Weston, Niri, Smithay, SwiftUI, ART, the NDK,
or a flake product attr is proved.

Host verifiers never link into an App Store, TestFlight, or Play binary.

Canonical status lives here. Skills and rules point at this file.

## Running today (wired)

### Relay (`formal-verification.yml`)

- Kani 0.68.0 on `relay-vm`.
- Verus `0.2026.09.27.3cf1832` on `verification/verus/relay_vm_invariants.rs`.
- Miri nightly `2026-09-29`.
- cargo-fuzz 0.13.2: `page_translate` and `vsock_packets`, 60s, request ASan.
- Clippy correctness/suspicious, cargo-deny, locked tests, ARM64 corpus.
- proptest on `ram_span_ok`.
- Loom lifecycle in `verification/loom-lifecycle` (`RUSTFLAGS=--cfg loom`).
- Heavy tools: cargo-fuzz ASan fail-closed; research prover installs warn until pinned.

### Wawona Gate: packages (`verify-all.yml`)

Job display name **Verification report**. Scripts:

| Script | Surface |
|---|---|
| `scripts/verify-formal.sh` | clippy, deny, proptest, Kani, Miri, Loom, Verus (rect + sanitize) |
| `scripts/verify-heavy.sh` | cargo-fuzz ASan 60s + heavy install attempts |
| `scripts/verify-c.sh` | cproof ASan/UBSan, clang-tidy, scan-build, CBMC, Frama-C, Valgrind, MSan, CDSChecker, TSan |
| `scripts/verify-swift.sh` | differential vector, SwiftCheck, strict concurrency, ASan/UBSan/TSan |
| `scripts/verify-kotlin.sh` | Kotest, detekt, lint, SpotBugs, JBMC, JPF |
| `scripts/verify-nix.sh` | parse all `.nix`, alejandra/statix/deadnix on `flake.nix`, flake metadata (full-tree format and `nix flake check` stay in Gate: packages) |

Helpers: `src/core/invariants.rs`, `src/core/generation_counter.rs`,
`src/platform/cproof/wawona_cproof.h`, `verification/ssh_host_vector.tsv`.

### Org floors

- `rust-repo-floor.yml` + per-repo `rust-floor.yml`.
- `nix-repo-floor.yml` + per-repo `nix-floor.yml` on every flake.
- Org-quality OSV: no `continue-on-error`.
- Terminal and ToolbarKeys have `org-quality.yml`.
- agent-device has a Swift sanitize job.

## Branch ruleset

`development` must require the check named **Verification report**.
Promote only with Gate: packages, Verification report, and Gate: products green.

Operator enable (needs valid `gh` auth):

```bash
# scripts/enable-verification-ruleset.sh Wawona/Wawona
```

If `gh` returns 401, the workflow stays wired; the ruleset is not active until
an admin runs that script. That is an explicit blocker, not a silent skip.

## Miri callers

Miri is requested for: `wwn-phoon-rs`, `ToolbarKeys`, `Terminal`, `nixpkgs2wasi`.

| Repo | Status |
|---|---|
| `wwn-phoon-rs` | Miri on via `rust-floor.yml`. First CI red names the blocker here. |
| `ToolbarKeys` | Same. |
| `Terminal` | Same. |
| `nixpkgs2wasi` | Same. |

A silent skip is forbidden. If Miri cannot load a crate, add the exact error
string to this table and keep the job red until fixed or the row is written.

## What a green job is

Workflows are required. A missing binary after an install attempt is an error.
It is not a skip, and it is not a completed proof.

Creusot, Prusti, and Flux see safe Rust only. A green Creusot run does not
extend `Relay/verification/PROOF_OBLIGATIONS.md`.

## One implementation

`sanitize_ssh_host` in `src/domain/validation.rs` owns SSH host rules.
Swift and Kotlin copies stay frozen. Differential tests only.

No Dafny, F*, KeY, JML, or Lean product code. No CompCert. No seL4 rewrite.
No Astrée, Polyspace, Coverity, SonarQube, Helix QAC, VCC.

## Nix

Org-wide floor on every `flake.nix` tree:

- `nix-instantiate --parse` on every `*.nix`
- alejandra `--check`
- statix `check`
- deadnix `-f`
- `nix flake metadata` + `nix flake check`

This is eval, lint, format, and flake checks. Not Gate: packages product
builds. A pass does not prove Weston, the IPA, or guest boot.

Vendored third-party trees need an explicit path allowlist row here. Silent
skip is a red report entry.

## Failure report

Aggregator: `scripts/verification-report.py`. NDJSON fields:
`tool`, `file`, `line`, `rule`, `failure`, `fix`.

## Hard rejects

- Whole-product proof claims
- Soft-skip missing tools
- Mode B / JIT / private API in store IPA
- ACSL that certifies a stub as the compositor
- Growing `input_android.c` into a keymap product
- `continue-on-error` on OSV
