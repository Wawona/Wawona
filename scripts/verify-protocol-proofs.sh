#!/usr/bin/env bash
# Fail-closed Kani proofs for Wayland protocol erroneous-check helpers.
# Invoked from scripts/verify-formal.sh. Host-only; never linked into store IPA.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/verification-out/protocol-proofs.ndjson}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
fail=0

emit() {
  local severity="${7:-error}"
  cargo xtask report emit --out "$OUT" --tool "$1" --file "$2" --line "${3:-1}" \
    --rule "$4" --failure "$5" --fix "$6" --severity "$severity"
  if [[ "$severity" == "error" ]]; then
    fail=1
  fi
}

MANIFEST="verification/helpers-check/Cargo.toml"

# Unit inventory (sorted obligations, helper examples).
if ! cargo test --manifest-path "$MANIFEST" protocol_proofs -- --nocapture; then
  emit protocol-proofs "src/core/wayland/protocol_proofs.rs" 1 "protocol-proof-unit" \
    "protocol_proofs unit tests failed" \
    "cargo test --manifest-path $MANIFEST protocol_proofs"
fi

# Enumerate Kani harness names from the obligation table (Helpers entries).
mapfile -t HARNESSES < <(perl -0ne 'while (/Helpers\(&\[([^\]]*)\]\)/g) { $n{$_} = 1 for $1 =~ /"([^"]+)"/g } print "$_\n" for sort keys %n' \
  src/core/wayland/protocol_proofs.rs)

if [[ ${#HARNESSES[@]} -eq 0 ]]; then
  emit protocol-proofs "src/core/wayland/protocol_proofs.rs" 1 "no-harnesses" \
    "PROTOCOL_PROOF_OBLIGATIONS lists no Helpers to prove" \
    "add ErroneousChecks::Helpers entries with Kani harnesses"
  cargo xtask report summarize "$OUT" --markdown "$(dirname "$OUT")/protocol-proofs.md" || fail=1
  exit "$fail"
fi

if command -v cargo-kani >/dev/null 2>&1 || cargo kani --version >/dev/null 2>&1; then
  harness_args=()
  for h in "${HARNESSES[@]}"; do
    harness_args+=(--harness "$h")
  done
  if ! cargo kani --manifest-path "$MANIFEST" "${harness_args[@]}" --output-format terse; then
    emit kani "src/core/wayland/protocol_proofs.rs" 1 "protocol-proof-kani" \
      "Kani failed one or more protocol erroneous-check harnesses" \
      "cargo kani --manifest-path $MANIFEST ${harness_args[*]}"
  fi
else
  emit kani "scripts/verify-protocol-proofs.sh" 1 "missing-tool" \
    "cargo-kani is not installed" "install Kani 0.68.0"
fi

cargo xtask report summarize "$OUT" --markdown "$(dirname "$OUT")/protocol-proofs.md" || fail=1
exit "$fail"
