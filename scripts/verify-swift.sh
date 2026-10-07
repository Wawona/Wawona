#!/usr/bin/env bash
# Swift differential vector, strict concurrency on contracts, sanitizers.
# Uses verification/swift-ssh-vector so WawonaUI (needs WawonaApple) is not linked.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/verification-out/swift.ndjson}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
REPORT="$ROOT/scripts/verification-report.py"
fail=0
VECTOR_PKG="$ROOT/verification/swift-ssh-vector"

emit() {
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line 1 \
    --rule "$3" --failure "$4" --fix "$5"
  fail=1
}

if ! (cd "$VECTOR_PKG" && swift test --filter SSHHostVectorTests); then
  emit swift-test "Tests/WawonaUIContractsTests/SSHHostVectorTests.swift" "swift-testing" \
    "Swift SSH host differential failed" \
    "cd verification/swift-ssh-vector && swift test --filter SSHHostVectorTests"
fi

if ! swift build --package-path "$VECTOR_PKG" --target WawonaUIContracts \
  -Xswiftc -strict-concurrency=complete; then
  emit swift-concurrency "Sources/WawonaUIContracts" "strict-concurrency" \
    "WawonaUIContracts failed strict concurrency" \
    "swift build --package-path verification/swift-ssh-vector --target WawonaUIContracts -Xswiftc -strict-concurrency=complete"
fi

for san in address undefined thread; do
  if ! (cd "$VECTOR_PKG" && swift test --sanitize="$san" --filter SSHHostVectorTests); then
    emit "swift-$san" "Tests/WawonaUIContractsTests/SSHHostVectorTests.swift" "sanitize" \
      "swift test --sanitize=$san failed" \
      "cd verification/swift-ssh-vector && swift test --sanitize=$san --filter SSHHostVectorTests"
  fi
done

python3 "$REPORT" summarize "$OUT" --markdown "$(dirname "$OUT")/swift.md" || fail=1
exit "$fail"
