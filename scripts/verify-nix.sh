#!/usr/bin/env bash
# Nix floor: parse, alejandra, statix, deadnix, flake metadata + check.
# Not a product matrix build.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/verification-out/nix.ndjson}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
REPORT="$ROOT/scripts/verification-report.py"
fail=0

emit() {
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line "${3:-1}" \
    --rule "$4" --failure "$5" --fix "$6"
  fail=1
}

NIX_FILES=()
while IFS= read -r -d '' f; do
  NIX_FILES+=("$f")
done < <(find . -name '*.nix' \
  -not -path './.git/*' \
  -not -path './result*' \
  -not -path './.direnv/*' \
  -not -path './target/*' \
  -not -path './android/.gradle/*' \
  -print0)

for f in "${NIX_FILES[@]:-}"; do
  [[ -n "$f" ]] || continue
  if ! nix-instantiate --parse "$f" >/dev/null 2>/tmp/nix-parse.err; then
    emit nix-parse "$f" 1 "parse" \
      "$(tr '\n' ' ' </tmp/nix-parse.err)" \
      "nix-instantiate --parse $f"
  fi
done

# Pin tools from nixpkgs when available.
run_tool() {
  local attr="$1"
  local name="$2"
  local args="$3"
  if command -v "$name" >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    if ! $name $args; then
      emit "$name" "flake.nix" 1 "$name" "$name failed" "$name $args"
    fi
    return
  fi
  if command -v nix >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    if ! nix shell "nixpkgs#$attr" -c $name $args; then
      emit "$name" "flake.nix" 1 "$name" \
        "nixpkgs#$attr $name failed" \
        "nix shell nixpkgs#$attr -c $name $args"
    fi
    return
  fi
  emit "$name" "scripts/verify-nix.sh" 1 "missing-tool" \
    "$name and nix are missing" "install Nix and nixpkgs#$attr"
}

run_tool alejandra alejandra "--check ."
run_tool statix statix "check ."
run_tool deadnix deadnix "-f ."

if [[ -f flake.nix ]]; then
  if ! nix flake metadata --json >/tmp/flake-meta.json 2>/tmp/flake-meta.err; then
    emit flake-metadata "flake.nix" 1 "metadata" \
      "$(tr '\n' ' ' </tmp/flake-meta.err)" \
      "nix flake metadata --json"
  fi
  if [[ -x ./.github/scripts/nix-retry.sh ]]; then
    if ! ./.github/scripts/nix-retry.sh nix flake check --print-build-logs; then
      emit flake-check "flake.nix" 1 "check" \
        "nix flake check failed" \
        "./.github/scripts/nix-retry.sh nix flake check --print-build-logs"
    fi
  else
    if ! nix flake check --print-build-logs; then
      emit flake-check "flake.nix" 1 "check" \
        "nix flake check failed" "nix flake check --print-build-logs"
    fi
  fi
fi

# nix-unit only when suites exist.
if find . -path '*/tests/*.nix' -print -quit 2>/dev/null | grep -q .; then
  run_tool nix-unit nix-unit "."
fi

python3 "$REPORT" summarize "$OUT" --markdown "$(dirname "$OUT")/nix.md" || fail=1
exit "$fail"
