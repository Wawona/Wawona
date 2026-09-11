#!/usr/bin/env bash
# Cheap Gate: packages check for the iOS Mode B contract.
# Does not prove IOMFB or MAP_JIT. Xcode Simulator is not that proof.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCANNER="$ROOT/.github/scripts/verify-ios-modeb-artifacts.sh"
REPLAY="$ROOT/.agent-device/wawona-ios-vphone-smoke.ad"
SMOKE="$ROOT/scripts/agent-device-smoke.sh"

fail() {
  echo "iOS Mode B CI contract failed: $*" >&2
  exit 1
}

[[ -f "$SCANNER" ]] || fail "missing scanner $SCANNER"
[[ -f "$REPLAY" ]] || fail "missing vphone replay $REPLAY"
[[ -f "$SMOKE" ]] || fail "missing smoke driver $SMOKE"

grep -q 'context device=vphone wawona-jb' "$REPLAY" ||
  fail "replay must pin device vphone wawona-jb"
grep -q 'packages tipa open-jit com.aspauldingcode.Wawona.ModeB' "$REPLAY" ||
  fail "replay must open-jit the Mode B bundle first"
grep -q 'open com.aspauldingcode.Wawona.ModeB' "$REPLAY" ||
  fail "replay must open the Mode B bundle"
grep -q 'test-artifacts/modeb-ios/' "$REPLAY" ||
  fail "replay must store screenshots under modeb-ios/"
grep -q 'vphone)' "$SMOKE" ||
  fail "agent-device-smoke.sh must expose a vphone lane"

usage="$(bash "$SCANNER" 2>&1 || true)"
grep -q -- '--mode-a' <<<"$usage" || fail "scanner usage must mention --mode-a"
grep -q -- '--mode-b' <<<"$usage" || fail "scanner usage must mention --mode-b"
grep -q -- '--iteration' <<<"$usage" || fail "scanner usage must mention --iteration"

if [[ -n "${WAWONA_MODEA_APP:-}" ]]; then
  "$SCANNER" --mode-a "$WAWONA_MODEA_APP"
fi
if [[ -n "${WAWONA_MODEB_TIPA:-}" ]]; then
  "$SCANNER" --mode-b "$WAWONA_MODEB_TIPA"
fi

echo "iOS Mode B CI contract OK"
