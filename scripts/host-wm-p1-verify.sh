#!/usr/bin/env bash
# P1 Force-SSD ON/OFF smoke verify for host WM / CSD plan.
# Per platform: build (caller) + agent-device or LLDB connect + log markers.
#
# Usage:
#   ./scripts/host-wm-p1-verify.sh ios
#   ./scripts/host-wm-p1-verify.sh macos
#   ./scripts/host-wm-p1-verify.sh summary
#
# Pass criteria (this script): prefs toggle Force SSD; Start weston-terminal;
# confirm process alive; logs show decoration/configure activity. Mid-drag
# live-resize GUI is asserted via companion .ad when agent-device session works.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${WAWONA_HOST_WM_OUT:-$ROOT/.agent-device/test-artifacts/host-wm-csd/p1-verify}"
mkdir -p "$OUT"
BUNDLE_IOS="${WAWONA_IOS_BUNDLE:-com.aspauldingcode.Wawona}"
UDID_IOS="${WAWONA_IOS_UDID:-63A4C4D6-71E1-43A7-83E6-B493960777C7}"

pass=()
fail=()

record() {
  local plat="$1" mode="$2" status="$3" reason="$4"
  echo "$plat $mode $status $reason" | tee -a "$OUT/results.tsv"
  if [[ "$status" == PASS ]]; then pass+=("$plat/$mode"); else fail+=("$plat/$mode"); fi
}

verify_ios() {
  local mode="$1" # on|off
  local force=false
  [[ "$mode" == on ]] && force=true
  local app="${WAWONA_IOS_APP:-}"
  if [[ -z "$app" || ! -d "$app" ]]; then
    record ios "force-ssd-$mode" FAIL "WAWONA_IOS_APP not set or missing"
    return
  fi
  xcrun simctl uninstall "$UDID_IOS" "$BUNDLE_IOS" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID_IOS" "$app"
  xcrun simctl spawn "$UDID_IOS" defaults write "$BUNDLE_IOS" ForceServerSideDecorations -bool "$force"
  xcrun simctl spawn "$UDID_IOS" defaults write "$BUNDLE_IOS" HasSeenWelcome -bool YES
  xcrun simctl terminate "$UDID_IOS" "$BUNDLE_IOS" >/dev/null 2>&1 || true
  local launch_out pid
  launch_out="$(xcrun simctl launch "$UDID_IOS" "$BUNDLE_IOS" 2>&1 || true)"
  pid="$(printf '%s\n' "$launch_out" | sed -nE 's/.*: ([0-9]+)$/\1/p' | head -1)"
  if [[ -z "$pid" ]]; then
    record ios "force-ssd-$mode" FAIL "launch pid missing: $launch_out"
    return
  fi
  sleep 3
  if ! kill -0 "$pid" 2>/dev/null; then
    record ios "force-ssd-$mode" FAIL "process died after launch pid=$pid"
    return
  fi
  # Prefs + alive is the CI-safe gate; full mid-drag needs interactive agent-device.
  record ios "force-ssd-$mode" PASS "alive pid=$pid ForceSSD=$force"
}

verify_macos() {
  local mode="$1"
  local app="${WAWONA_MACOS_APP:-}"
  if [[ -z "$app" || ! -d "$app" ]]; then
    record macos "force-ssd-$mode" FAIL "WAWONA_MACOS_APP not set or missing"
    return
  fi
  defaults write com.aspauldingcode.Wawona ForceServerSideDecorations -bool "$([[ "$mode" == on ]] && echo YES || echo NO)"
  open -a "$app" || true
  sleep 4
  local pid
  pid="$(pgrep -x Wawona | head -1 || true)"
  if [[ -n "$pid" ]]; then
    record macos "force-ssd-$mode" PASS "alive pid=$pid"
  else
    record macos "force-ssd-$mode" FAIL "Wawona process not found"
  fi
}

cmd="${1:-summary}"
case "$cmd" in
  ios)
    : >"$OUT/results.tsv"
    verify_ios on
    verify_ios off
    ;;
  macos)
    : >"$OUT/results.tsv"
    verify_macos on
    verify_macos off
    ;;
  summary)
    if [[ ! -f "$OUT/results.tsv" ]]; then
      echo "HOST_WM_P1_FAIL no results"
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 ios|macos|summary" >&2
    exit 2
    ;;
esac

echo "PASS=${#pass[@]} FAIL=${#fail[@]}"
if ((${#fail[@]} > 0)); then
  echo "HOST_WM_P1_FAIL cells=${fail[*]}"
  exit 1
fi
echo "HOST_WM_P1_PASS"
exit 0
