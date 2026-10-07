#!/usr/bin/env bash
# Swift differential vector, strict concurrency on the two small targets, sanitizers.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/verification-out/swift.ndjson}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
REPORT="$ROOT/scripts/verification-report.py"
fail=0

emit() {
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line 1 \
    --rule "$3" --failure "$4" --fix "$5"
  fail=1
}

if ! swift test --filter SSHHostVectorTests; then
  emit swift-test "Tests/WawonaUIContractsTests/SSHHostVectorTests.swift" "swift-testing" \
    "Swift SSH host differential or SwiftCheck failed" \
    "swift test --filter SSHHostVectorTests"
fi

if ! swift build --target WawonaModel --target WawonaUIContracts \
  -Xswiftc -strict-concurrency=complete; then
  emit swift-concurrency "Package.swift" "strict-concurrency" \
    "WawonaModel or WawonaUIContracts failed strict concurrency" \
    "swift build --target WawonaModel --target WawonaUIContracts -Xswiftc -strict-concurrency=complete"
fi

for san in address undefined thread; do
  if ! swift test --sanitize="$san" --filter SSHHostVectorTests; then
    emit "swift-$san" "Tests/WawonaUIContractsTests/SSHHostVectorTests.swift" "sanitize" \
      "swift test --sanitize=$san failed" \
      "swift test --sanitize=$san --filter SSHHostVectorTests"
  fi
done

python3 "$REPORT" summarize "$OUT" --markdown "$(dirname "$OUT")/swift.md" || fail=1
exit "$fail"
