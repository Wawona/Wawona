# Bend 2 laws (specification only)

Bend 2.0.40 checks these files. The compositor does not compile them.

| File | Role |
|---|---|
| `job.bend` | Models of the Rust helpers below |
| `LAWS.bend` | Requirements. Review edits here on their own |
| `laws.lock` | Approval record. A dropped, renamed, or rewritten law fails `prove bend` until this file changes in the same edit |
| `PROOF.bend` | Proofs that those requirements hold for the models |

| Law group | Rust helper |
|---|---|
| Start and Stop | `crates/wawona-laws` `machine_phase` |
| Keyboard eligibility (close removes the id, select refuses a missing id, close clears that focus) | `crates/wawona-laws` `focus` |
| Machines / Settings back, open, select | `crates/wawona-laws` `nav_place` |
| Damage rect stays inside its limit | `src/core/invariants.rs` `clamp_rect` (non-negative axis) |
| SSH port 1..=65535 or fallback | `src/domain/sanitize_ssh_host.rs` `normalize_ssh_port` |
| Generation step, gamma length, fractional scale floor, idle remove, commit hold, duplicate reject, oneshot, fifo, power/tearing bit, alpha mode, content hint, cursor, single pixel, viewport size | `src/core/generation_counter.rs`, `src/core/wayland/protocol_proofs.rs` |
| Exact writes, pin/sort/tag flip, waypipe remote, blank save, hidden section | `crates/wawona-laws` `ui` |
| Alpha factor, empty DRM lease, export/shortcut absent, fractional source without dest | `job.bend` `factor_ok`, `lease_empty`, `absent`, `frac_reject` |

`crates/wawona-laws` `coverage` fails if an `app.contract` action, a `PROTOCOL_CATALOG` interface, or an erroneous-check helper has no row. Interfaces with `ErroneousChecks::None` are no-client-error. Viewport out-of-buffer and xdg anchor negatives are `kani` (Bend `Nat` has no negative). The same laws cover every `ALL_TARGETS` host. visionOS, tvOS, and watchOS `exact_ui` stay `planned`.

```bash
export PATH="$HOME/.bend/bin:$HOME/.elan/bin:$PATH"
export BEND_NO_TELEMETRY=1
cargo xtask prove bend
```

`cargo xtask prove bend` runs `bend PROOF.bend` and `bend PROOF.bend --verdict`.
`--verdict` needs Lean v4.34.0 (`leanprover/lean4:v4.34.0` via elan). The
checker alone is not the kernel verdict.
It refuses a `.c` file in this directory. Bend's C, JS, and native backends
are not product targets.

`nav_place` follows the one-level nesting in `exact/apps/wawona/app.contract`.
Settings is a cover over the Machines catalog. Back from Settings returns to
Machines.
Exact calls these Rust functions later through the data seam.

The clamp laws are the non-negative axis (`x`, span, and limit are `Nat`).
Negative inputs stay on the Kani harness in `clamp_rect`. String cleanup for
SSH hosts stays on `verification/ssh_host_vector.tsv`. Concurrent bumps stay
on the Loom counter. Fractional scale's law is the floor of 120. A concrete
`100 * 120 / 100` reduction runs the Bend kernel out of fuel, so that numeral
is not a separate law.

Rust tests for these helpers: `cargo test --manifest-path verification/helpers-check/Cargo.toml`.
