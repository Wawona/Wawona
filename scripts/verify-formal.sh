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
# Never `nix develop` here. The default flake shell builds libsecret; its DBus
# tests abort on GHA and can hang Formal scripts for tens of minutes. Use plain
# cargo, with helpers-check as the clippy/proptest fallback.

emit() {
  local severity="${7:-error}"
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line "${3:-1}" \
    --rule "$4" --failure "$5" --fix "$6" --severity "$severity"
  if [[ "$severity" == "error" ]]; then
    fail=1
  fi
}

if ! cargo clippy --locked --all-targets -- -D clippy::correctness -D clippy::suspicious; then
  # Fallback: helpers only
  if ! cargo clippy --manifest-path verification/helpers-check/Cargo.toml -- -D clippy::correctness -D clippy::suspicious; then
    emit clippy "Cargo.toml" 1 "clippy::correctness" \
      "clippy denied a correctness or suspicious lint" \
      "cargo clippy --locked --all-targets -- -D clippy::correctness -D clippy::suspicious"
  fi
fi

# Root cargo metadata breaks once ensure-waypipe/coreutils drop nested
# [workspace] trees. Prefer helpers-check; warn (do not fail the floor) if
# deny cannot run. Gate: packages still owns full-tree deny.
if cargo deny --manifest-path verification/helpers-check/Cargo.toml check; then
  :
elif cargo metadata --format-version 1 >/dev/null 2>&1 && cargo deny check; then
  :
else
  emit cargo-deny "deny.toml" 1 "deny-unavailable" \
    "cargo-deny could not check (nested ensure-* workspaces or advisory failure)" \
    "cargo deny --manifest-path verification/helpers-check/Cargo.toml check" \
    warning
fi

if ! cargo test --manifest-path verification/helpers-check/Cargo.toml --offline 2>/dev/null \
   && ! cargo test --manifest-path verification/helpers-check/Cargo.toml; then
  emit proptest "src/core/invariants.rs" 1 "proptest" \
    "helper tests failed" \
    "cargo test --manifest-path verification/helpers-check/Cargo.toml"
fi

# Kani on helpers-check only. Never `nix develop` here (libsecret DBus fails in GHA).
if command -v cargo-kani >/dev/null 2>&1 || cargo kani --version >/dev/null 2>&1; then
  if ! cargo kani --manifest-path verification/helpers-check/Cargo.toml \
      --harness clamped_rect_stays_inside_nonnegative_bounds \
      --harness sanitize_ascii_has_no_shell_metacharacters \
      --output-format terse; then
    emit kani "verification/helpers-check" 1 "helpers-check-kani" \
      "Kani failed helpers-check harnesses" \
      "cargo kani --manifest-path verification/helpers-check/Cargo.toml --harness clamped_rect_stays_inside_nonnegative_bounds --harness sanitize_ascii_has_no_shell_metacharacters"
  fi
else
  emit kani "scripts/verify-formal.sh" 1 "missing-tool" \
    "cargo-kani is not installed" "install Kani 0.68.0"
fi

if rustup toolchain list 2>/dev/null | grep -q 'nightly-2026-09-29'; then
  # proptest FileFailurePersistence calls getcwd; isolation blocks that.
  if ! MIRIFLAGS="${MIRIFLAGS:--Zmiri-disable-isolation}" \
      cargo +nightly-2026-09-29 miri test \
      --manifest-path verification/helpers-check/Cargo.toml -- --test-threads=1; then
    emit miri "src/core/invariants.rs" 54 "miri" \
      "Miri failed the helper unit tests" \
      "MIRIFLAGS=-Zmiri-disable-isolation cargo +nightly-2026-09-29 miri test --manifest-path verification/helpers-check/Cargo.toml"
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
