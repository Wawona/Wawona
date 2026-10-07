#!/usr/bin/env bash
# Heavy host tools. cargo-fuzz ASan is fail-closed. Research provers record
# install blockers as warnings until a pinned CI install path exists.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/verification-out/heavy.ndjson}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
REPORT="$ROOT/scripts/verification-report.py"
fail=0

emit() {
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line 1 \
    --rule "missing-or-failed" --failure "$3" --fix "$4"
  fail=1
}

emit_warn() {
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line 1 \
    --rule "missing-or-failed" --severity warning --failure "$3" --fix "$4"
}

attempt_install() {
  local name="$1"
  local cmd="$2"
  local file="$3"
  local fix="$4"
  local mode="${5:-error}"
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  if eval "$cmd"; then
    return 0
  fi
  if [[ "$mode" == warning ]]; then
    emit_warn "$name" "$file" \
      "$name install failed or binary missing after install attempt" \
      "$fix"
  else
    emit "$name" "$file" \
      "$name install failed or binary missing after install attempt" \
      "$fix"
  fi
  return 1
}

if ! command -v cargo-fuzz >/dev/null 2>&1; then
  attempt_install cargo-fuzz \
    "cargo +nightly install cargo-fuzz --version 0.13.2 --locked" \
    "fuzz/fuzz_targets/clamp_rect.rs" \
    "cargo +nightly install cargo-fuzz --version 0.13.2 --locked"
fi

if command -v cargo-fuzz >/dev/null 2>&1 && [[ -f fuzz/Cargo.toml ]]; then
  if ! RUSTFLAGS='-Zsanitizer=address' cargo +nightly fuzz run clamp_rect -- \
      -max_total_time=60 -use_value_profile=1 2>/tmp/fuzz-clamp.err; then
    if ! cargo +nightly fuzz run clamp_rect -- -max_total_time=60 -s address 2>>/tmp/fuzz-clamp.err; then
      emit cargo-fuzz "fuzz/fuzz_targets/clamp_rect.rs" \
        "clamp_rect fuzz failed: $(tail -n 3 /tmp/fuzz-clamp.err | tr '\n' ' ')" \
        "cargo +nightly fuzz run clamp_rect -- -max_total_time=60 -s address"
    fi
  fi
fi

# Research tools: install attempt; warn on missing (no pinned GHA path yet).
attempt_install rudra \
  "cargo install rudra --locked 2>/tmp/rudra-install.err" \
  "Cargo.toml" \
  "cargo install rudra --locked; blocker: $(tail -n 2 /tmp/rudra-install.err 2>/dev/null | tr '\n' ' ')" \
  warning
attempt_install mirai-driver \
  "cargo install mirai --locked 2>/tmp/mirai-install.err" \
  "Cargo.toml" \
  "install MIRAI; blocker: $(tail -n 2 /tmp/mirai-install.err 2>/dev/null | tr '\n' ' ')" \
  warning
attempt_install prusti-rustc \
  "cargo install prusti-helper --locked 2>/tmp/prusti-install.err || true; false" \
  "src/core/invariants.rs" \
  "install Prusti for clamp_rect; see matrix blocker if cargo install fails" \
  warning
attempt_install cargo-creusot \
  "cargo install creusot --locked 2>/tmp/creusot-install.err" \
  "src/core/invariants.rs" \
  "install Creusot. Safe Rust only. blocker: $(tail -n 2 /tmp/creusot-install.err 2>/dev/null | tr '\n' ' ')" \
  warning
attempt_install flux \
  "cargo install flux --locked 2>/tmp/flux-install.err" \
  "src/core/invariants.rs" \
  "install Flux for clamp_rect; blocker: $(tail -n 2 /tmp/flux-install.err 2>/dev/null | tr '\n' ' ')" \
  warning
attempt_install aeneas \
  "cargo install aeneas --locked 2>/tmp/aeneas-install.err" \
  "src/core/invariants.rs" \
  "install Aeneas and Lean-check clamp_rect; blocker: $(tail -n 2 /tmp/aeneas-install.err 2>/dev/null | tr '\n' ' ')" \
  warning
attempt_install haybale \
  "cargo install haybale --locked 2>/tmp/haybale-install.err" \
  "src/core/invariants.rs" \
  "Haybale on helper bitcode; blocker: $(tail -n 2 /tmp/haybale-install.err 2>/dev/null | tr '\n' ' ')" \
  warning

python3 "$REPORT" summarize "$OUT" --markdown "$(dirname "$OUT")/heavy.md" || fail=1
exit "$fail"
