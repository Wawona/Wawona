#!/usr/bin/env bash
# Install a TrollStore Mode B tipa on vphone (or SSH guest).
# Official and slim tipas stay guest-free until Relay frames. Leftover
# 5.7 G zips still exist on some guests. Helper 176 is disk-full
# (Failed to create dir …/Frameworks). Check df before trollstorehelper.
#
#   scripts/install-ios-modeb-tipa.sh --slim path/to/Wawona-YY.M.D-iOS-arm64.tipa
#   scripts/install-ios-modeb-tipa.sh --official path/to/Wawona-YY.M.D-iOS-arm64.tipa
#
# Not App Store. Never Ship: beta / TestFlight.
# SSH: same as vphone-jb-lab (sshpass + alpine). Never interactive askpass.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib/vphone-ensure-guest.sh
source "$HERE/lib/vphone-ensure-guest.sh"

DEVICE="${WAWONA_VPHONE_DEVICE:-vphone wawona-jb}"
BUNDLE="com.aspauldingcode.Wawona.ModeB"
HELPER="/var/jb/Applications/TrollStoreLite.app/trollstorehelper"
GUEST_TIPA_DIR="/var/mobile/Documents/agent-device/tipa"
# Root + alpine: mobile password auth fails on this research guest.
export WAWONA_VPHONE_INSTALL_SSH_USER="${WAWONA_VPHONE_INSTALL_SSH_USER:-root}"
PROFILE="${WAWONA_VPHONE_PROFILE:-$ROOT/.agent-device/vphone-wawona-jb.json}"
# agent-device daemon resolves relative paths against its own cwd (often $HOME).
STAGE_DIR="${WAWONA_MODEB_STAGE_DIR:-$HOME/.agent-device/test-artifacts/modeb-ios}"

usage() {
  echo "usage: $0 --slim|--official Wawona-YY.M.D-iOS-arm64.tipa" >&2
  exit 2
}

abspath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
    return
  fi
  python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$p"
}

[[ $# -eq 2 ]] || usage
kind="$1"
tipa_in="$2"
[[ "$kind" == "--slim" || "$kind" == "--official" ]] || usage
[[ -f "$tipa_in" ]] || {
  echo "tipa not found: $tipa_in" >&2
  exit 1
}
tipa="$(abspath "$tipa_in")"

mkdir -p "$STAGE_DIR"
staged="$STAGE_DIR/$(basename "$tipa")"
if [[ "$tipa" != "$staged" ]]; then
  cp -f "$tipa" "$staged"
  tipa="$staged"
fi
echo "staged tipa: $tipa"

need_kb=$((1024 * 1024))

guest_ip() {
  if [[ -n "${WAWONA_VPHONE_SSH_HOST:-}" ]]; then
    echo "${WAWONA_VPHONE_SSH_HOST}"
    return
  fi
  if [[ -f "$PROFILE" ]]; then
    python3 - "$PROFILE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get("sshHost") or data.get("host") or data.get("ip") or "")
PY
    return
  fi
  echo ""
}

HOST="$(guest_ip)"
[[ -n "$HOST" ]] || {
  echo "guest SSH host unknown. Update $PROFILE or WAWONA_VPHONE_SSH_HOST." >&2
  exit 1
}

echo "== Mode B tipa install ($kind) on $HOST =="
echo "tipa: $tipa"

free_kb="$(vphone_ssh "$HOST" '/bin/df -k /var/containers' | awk 'NR==2 {print $4}')"
echo "guest /var/containers free_kb=$free_kb need_kb=$need_kb"
if [[ -z "$free_kb" || "$free_kb" -lt "$need_kb" ]]; then
  echo "refusing install: not enough free space (helper 176 / Frameworks mkdir)." >&2
  echo "uninstall the previous Mode B app, delete leftover tipas under $GUEST_TIPA_DIR, then retry." >&2
  vphone_ssh "$HOST" "df -h /var /var/containers /var/mobile; ls -lh $GUEST_TIPA_DIR 2>/dev/null || true"
  exit 176
fi

echo "== killing competing IOMFB owners =="
vphone_ssh "$HOST" 'killall WawonaModeBDemo WawonaIomfbSmoke WawonaIomfbMetal 2>/dev/null || true'

if [[ "$kind" == "--official" ]]; then
  echo "== uninstall previous Mode B app before expand =="
  vphone_ssh "$HOST" "echo alpine | sudo -S '$HELPER' uninstall '$BUNDLE' 2>/dev/null || true"
  vphone_ssh "$HOST" "rm -rf $GUEST_TIPA_DIR/*.tipa"
fi

installed_via_agent=0
if command -v agent-device >/dev/null 2>&1; then
  echo "== agent-device packages tipa install (absolute path) =="
  if agent-device packages tipa install "$tipa" --verify --device "$DEVICE"; then
    installed_via_agent=1
  else
    echo "agent-device packages tipa install failed; falling back to helper SSH" >&2
  fi
fi

if [[ "$installed_via_agent" -eq 0 ]]; then
  remote="$GUEST_TIPA_DIR/$(basename "$tipa")"
  echo "== SSH push + trollstorehelper install force custom =="
  vphone_ssh_put "$HOST" "$remote" "$tipa"
  vphone_ssh "$HOST" "echo alpine | sudo -S '$HELPER' install force custom '$remote'"
fi

app_path="$(vphone_ssh "$HOST" "find /var/containers/Bundle/Application -name Wawona.app -print -quit")"
[[ -n "$app_path" ]] || {
  echo "install finished but Wawona.app is missing under /var/containers" >&2
  exit 1
}
echo "installed: $app_path"

echo "== launch ${BUNDLE} (uicache, uiopen, SB bounce if needed) =="
vphone_ssh_script "$HOST" <<EOF
set -e
killall WawonaIomfbSmoke WawonaIomfbMetal WawonaModeBDemo 2>/dev/null || true
uicache -p $(printf '%q' "$app_path") || true
uiopen --app Wawona || uiopen --bundleid ${BUNDLE} || true
sleep 3
alive() { ps aux | grep -F 'Wawona.app/Wawona' | grep -v grep >/dev/null 2>&1; }
if ! alive; then
  echo 'uiopen missed; bouncing SpringBoard' >&2
  killall -9 SpringBoard 2>/dev/null || true
  sleep 8
  uiopen --app Wawona || uiopen --bundleid ${BUNDLE} || true
  sleep 4
fi
ps aux | grep -F 'Wawona.app/Wawona' | grep -v grep || {
  echo 'Wawona Mode B process still missing after launch' >&2
  exit 1
}
EOF

if command -v agent-device >/dev/null 2>&1; then
  echo "== tipa open-jit =="
  agent-device packages tipa open-jit "$BUNDLE" --device "$DEVICE" || true
fi
echo "Mode B tipa install OK"
