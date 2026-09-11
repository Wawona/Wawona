#!/usr/bin/env bash
# Install a Sileo / Procursus Mode B .deb on vphone (or SSH guest).
#
#   scripts/install-ios-modeb-deb.sh --rootless path/to/Wawona-YY.M.D-iOS-arm64-rootless.deb
#   scripts/install-ios-modeb-deb.sh --rootful  path/to/Wawona-YY.M.D-iOS-arm64-rootful.deb
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
export WAWONA_VPHONE_INSTALL_SSH_USER="${WAWONA_VPHONE_INSTALL_SSH_USER:-root}"
PROFILE="${WAWONA_VPHONE_PROFILE:-$ROOT/.agent-device/vphone-wawona-jb.json}"
STAGE_DIR="${WAWONA_MODEB_STAGE_DIR:-$HOME/.agent-device/test-artifacts/modeb-ios}"

usage() {
  echo "usage: $0 --rootless|--rootful Wawona-YY.M.D-iOS-arm64-{rootless,rootful}.deb" >&2
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
scheme="$1"
deb_in="$2"
[[ "$scheme" == "--rootless" || "$scheme" == "--rootful" ]] || usage
[[ -f "$deb_in" ]] || {
  echo "deb not found: $deb_in" >&2
  exit 1
}
deb="$(abspath "$deb_in")"
mkdir -p "$STAGE_DIR"
staged="$STAGE_DIR/$(basename "$deb")"
if [[ "$deb" != "$staged" ]]; then
  cp -f "$deb" "$staged"
  deb="$staged"
fi

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

echo "== Mode B deb install ($scheme) on $HOST =="
echo "deb: $deb"

echo "== killing competing IOMFB owners =="
vphone_ssh "$HOST" 'killall WawonaModeBDemo WawonaIomfbSmoke WawonaIomfbMetal 2>/dev/null || true'

installed_via_agent=0
if command -v agent-device >/dev/null 2>&1; then
  if agent-device packages apt install "$deb" --device "$DEVICE"; then
    installed_via_agent=1
  else
    echo "agent-device packages apt install failed; falling back to dpkg via SSH" >&2
  fi
fi

if [[ "$installed_via_agent" -eq 0 ]]; then
  remote="/var/mobile/Documents/agent-device/deb/$(basename "$deb")"
  vphone_ssh_put "$HOST" "$remote" "$deb"
  vphone_ssh "$HOST" "dpkg -i '$remote' || apt-get install -f -y"
fi

if [[ "$scheme" == "--rootless" ]]; then
  app_path="$(vphone_ssh "$HOST" "find /var/jb/Applications -name Wawona.app -print -quit 2>/dev/null || true")"
else
  app_path="$(vphone_ssh "$HOST" "find /Applications -name Wawona.app -print -quit 2>/dev/null || true")"
fi
[[ -n "$app_path" ]] || {
  echo "install finished but Wawona.app is missing for $scheme" >&2
  exit 1
}
echo "installed: $app_path"
vphone_ssh "$HOST" "uicache -p '$app_path' || true"
vphone_ssh "$HOST" "uiopen --app Wawona || uiopen --bundleid $BUNDLE || true"
echo "Mode B deb install OK ($scheme)"
