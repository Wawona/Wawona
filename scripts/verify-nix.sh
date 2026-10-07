#!/usr/bin/env bash
# Nix floor: parse every .nix, format-check flake.nix, flake metadata.
# Full-tree alejandra/statix/deadnix and nix flake check stay out of this gate:
# Wawona's product matrix is Gate: packages. Format the whole tree separately.
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

run_tool() {
  local attr="$1"
  local name="$2"
  shift 2
  if command -v "$name" >/dev/null 2>&1; then
    if ! "$name" "$@"; then
      emit "$name" "flake.nix" 1 "$name" "$name failed" "$name $*"
    fi
    return
  fi
  if command -v nix >/dev/null 2>&1; then
    if ! nix shell "nixpkgs#$attr" -c "$name" "$@"; then
      emit "$name" "flake.nix" 1 "$name" \
        "nixpkgs#$attr $name failed" \
        "nix shell nixpkgs#$attr -c $name $*"
    fi
    return
  fi
  emit "$name" "scripts/verify-nix.sh" 1 "missing-tool" \
    "$name and nix are missing" "install Nix and nixpkgs#$attr"
}

# Format-check the flake entry only. statix/deadnix findings on the large
# input graph are recorded but do not fail this floor (repeated follows keys
# are a flake style debt tracked outside Verification report).
if [[ -f flake.nix ]]; then
  run_tool alejandra alejandra --check flake.nix

  if command -v nix >/dev/null 2>&1; then
    if ! nix shell nixpkgs#statix -c statix check flake.nix >/tmp/statix.out 2>&1; then
      python3 "$REPORT" emit --out "$OUT" --tool statix --file flake.nix --line 1 \
        --rule statix --severity warning \
        --failure "$(tr '\n' ' ' </tmp/statix.out | head -c 400)" \
        --fix "nix shell nixpkgs#statix -c statix check flake.nix"
    fi
    if ! nix shell nixpkgs#deadnix -c deadnix -f flake.nix >/tmp/deadnix.out 2>&1; then
      python3 "$REPORT" emit --out "$OUT" --tool deadnix --file flake.nix --line 1 \
        --rule deadnix --severity warning \
        --failure "$(tr '\n' ' ' </tmp/deadnix.out | head -c 400)" \
        --fix "nix shell nixpkgs#deadnix -c deadnix -f flake.nix"
    fi
  fi

  if ! nix flake metadata --json >/tmp/flake-meta.json 2>/tmp/flake-meta.err; then
    emit flake-metadata "flake.nix" 1 "metadata" \
      "$(tr '\n' ' ' </tmp/flake-meta.err)" \
      "nix flake metadata --json"
  fi
fi

python3 "$REPORT" summarize "$OUT" --markdown "$(dirname "$OUT")/nix.md" || fail=1
exit "$fail"
