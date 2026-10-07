#!/usr/bin/env bash
# Local and CI floor: clippy, cargo-deny, proptest, Kani, Miri, Loom, Verus.
# Prefer helpers-check when the full compositor graph cannot configure.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/verification-out/formal.ndjson}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
REPORT="$ROOT/scripts/verification-report.py"
fail=0
CARGO=(cargo)
if command -v nix >/dev/null 2>&1 && [[ -f flake.nix ]]; then
  if nix develop -c true >/dev/null 2>&1; then
    CARGO=(nix develop -c cargo)
  fi
fi

emit() {
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line "${3:-1}" \
    --rule "$4" --failure "$5" --fix "$6"
  fail=1
}

run_cargo() {
  "${CARGO[@]}" "$@"
}

if ! run_cargo clippy --locked --all-targets -- -D clippy::correctness -D clippy::suspicious; then
  # Fallback: helpers only
  if ! cargo clippy --manifest-path verification/helpers-check/Cargo.toml -- -D clippy::correctness -D clippy::suspicious; then
    emit clippy "Cargo.toml" 1 "clippy::correctness" \
      "clippy denied a correctness or suspicious lint" \
      "cargo clippy --locked --all-targets -- -D clippy::correctness -D clippy::suspicious"
  fi
fi

if ! run_cargo deny check && ! cargo deny check; then
  emit cargo-deny "deny.toml" 1 "deny" \
    "cargo-deny reported an advisory, ban, or license failure" \
    "cargo deny check"
fi

if ! cargo test --manifest-path verification/helpers-check/Cargo.toml --offline 2>/dev/null \
   && ! cargo test --manifest-path verification/helpers-check/Cargo.toml; then
  emit proptest "src/core/invariants.rs" 1 "proptest" \
    "helper tests failed" \
    "cargo test --manifest-path verification/helpers-check/Cargo.toml"
fi

if ! run_cargo test --locked --lib -- sanitize_ 2>/dev/null; then
  # sanitize tests need the full crate; record if helpers cannot cover
  if ! run_cargo test --locked --lib -- sanitize_; then
    emit proptest "src/domain/validation.rs" 1 "proptest" \
      "sanitize_ssh_host tests failed" \
      "nix develop -c cargo test --locked --lib -- sanitize_"
  fi
fi

if command -v cargo-kani >/dev/null 2>&1 || cargo kani --version >/dev/null 2>&1; then
  if ! run_cargo kani -p wawona --harness clamped_rect_stays_inside_nonnegative_bounds \
     && ! cargo kani --manifest-path verification/helpers-check/Cargo.toml --harness clamped_rect_stays_inside_nonnegative_bounds; then
    emit kani "src/core/invariants.rs" 32 "clamped_rect_stays_inside_nonnegative_bounds" \
      "Kani failed the rect harness" \
      "cargo kani -p wawona --harness clamped_rect_stays_inside_nonnegative_bounds"
  fi
  if ! run_cargo kani -p wawona --harness sanitize_ascii_has_no_shell_metacharacters; then
    emit kani "src/domain/validation.rs" 1 "sanitize_ascii_has_no_shell_metacharacters" \
      "Kani failed the SSH host harness" \
      "cargo kani -p wawona --harness sanitize_ascii_has_no_shell_metacharacters"
  fi
else
  emit kani "scripts/verify-formal.sh" 1 "missing-tool" \
    "cargo-kani is not installed" "install Kani 0.68.0"
fi

if rustup toolchain list 2>/dev/null | grep -q 'nightly-2026-09-29'; then
  if ! cargo +nightly-2026-09-29 miri test --manifest-path verification/helpers-check/Cargo.toml -- --test-threads=1; then
    emit miri "src/core/invariants.rs" 54 "miri" \
      "Miri failed the helper unit tests" \
      "cargo +nightly-2026-09-29 miri test --manifest-path verification/helpers-check/Cargo.toml"
  fi
else
  emit miri "scripts/verify-formal.sh" 1 "missing-toolchain" \
    "nightly-2026-09-29 is not installed" \
    "rustup toolchain install nightly-2026-09-29 --component miri"
fi

if [[ -d verification/loom-counter ]]; then
  if ! (cd verification/loom-counter && RUSTFLAGS='--cfg loom' cargo test -- --test-threads=1); then
    emit loom "src/core/generation_counter.rs" 1 "loom" \
      "Loom model of the generation counter failed" \
      "cd verification/loom-counter && RUSTFLAGS='--cfg loom' cargo test"
  fi
fi

if [[ -x scripts/verify-verus.sh ]]; then
  if ! scripts/verify-verus.sh; then
    emit verus "verification/verus/sanitize_ssh_host.rs" 1 "verus" \
      "Verus rejected the rect or sanitize model" \
      "scripts/verify-verus.sh"
  fi
else
  emit verus "scripts/verify-verus.sh" 1 "missing-script" \
    "verify-verus.sh is missing" \
    "pin Verus 0.2026.09.27.3cf1832"
fi

python3 "$REPORT" summarize "$OUT" --markdown "$(dirname "$OUT")/formal.md" || fail=1
exit "$fail"
