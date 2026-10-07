#!/usr/bin/env bash
# Manual Ghostty GTK popup verification on macOS Wawona.
# Run while Ghostty (container/waypipe) is visible. Right-click the CSD
# titlebar 3 times; click away between each. Watch for popup_done in logs.
set -euo pipefail

ART="${ART:-$(cd "$(dirname "$0")/.." && pwd)/.agent-device/test-artifacts}"
mkdir -p "$ART"
LOG="$ART/popup-manual-test.log"

echo "Logging Wawona popup events to $LOG"
echo "1. Focus Ghostty in Wawona"
echo "2. Right-click titlebar -> menu opens"
echo "3. Click terminal body to dismiss"
echo "4. Repeat steps 2-3 two more times"
echo ""

log stream --predicate 'process == "Wawona"' --style compact 2>/dev/null | tee "$LOG" &
LOGPID=$!
trap 'kill "$LOGPID" 2>/dev/null || true' EXIT

echo "Waiting 90s for manual clicks..."
sleep 90

echo ""
echo "--- popup log summary ---"
rg -i 'Popup create|Popup dismissed|popup_done|Sending xdg_popup' "$LOG" || echo "(no popup lines captured)"
