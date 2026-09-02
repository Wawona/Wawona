#!/usr/bin/env bash
# Timed smoke matrix: nested compositors via prebaked wawona-container-desktop
# (Wawona run → no nix shell at Start) over vsock waypipe.
#
# Usage:
#   scripts/container-desktop-matrix-macos.sh
#   scripts/container-desktop-matrix-macos.sh sway hyprland labwc flower
#
# Requires Wawona GUI compositor (wayland-0 under /tmp/wawona-$(id -u)/).
# Writes logs + PNGs under .agent-device/test-artifacts/container-matrix/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/.agent-device/test-artifacts/container-matrix"
CLIENT_SCRIPT="$ROOT/scripts/container-desktop-clients-macos.sh"
WWN_LOG="${WWN_LOG:-/tmp/wawona-weston-test.log}"
for candidate in /tmp/wawona-weston-test.log "/tmp/wawona-$(id -u)/wawona.log"; do
  if [[ -f "$candidate" ]]; then
    WWN_LOG="$candidate"
    break
  fi
done

DEFAULT_CLIENTS=(flower sway hyprland labwc weston)
CLIENTS=("${@:-${DEFAULT_CLIENTS[@]}}")

mkdir -p "$ARTIFACTS"
chmod +x "$CLIENT_SCRIPT"

export PATH="/Applications/Wawona.app/Contents/Resources/bin:${PATH:-}"
export WAWONA_CONTAINER_BACKEND=containerization
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/wawona-$(id -u)}"
export WWNP_WAYPIPE_BIN="/Applications/Wawona.app/Contents/Resources/bin/waypipe-fds"

if [[ ! -S "$XDG_RUNTIME_DIR/${WAYLAND_DISPLAY}" ]]; then
  echo "FAIL: compositor socket missing at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" >&2
  echo "Launch Wawona --gui first." >&2
  exit 1
fi

touch "$WWN_LOG"

log_line_count() {
  wc -l < "$WWN_LOG" | tr -d ' '
}

title_pattern_for() {
  case "$1" in
    sway) echo 'Updated title.*(sway|wlroots|WL-1)' ;;
    niri) echo 'Updated title.*[Nn]iri|new_toplevel.*niri' ;;
    plasma|kde|kwin) echo 'Updated title.*(KWin|Plasma|kwin|wlroots)' ;;
    kde-plasma|plasma-full) echo 'Updated title.*(Plasma|KWin|plasma)' ;;
    gnome|gnome-shell) echo 'Updated title.*(GNOME|gnome|mutter|Mutter)' ;;
    mutter) echo 'Updated title.*[Mm]utter' ;;
    hyprland) echo 'Updated title.*(Hyprland|hyprland|wlroots|WL-1)' ;;
    labwc) echo 'Updated title.*[Ll]abwc' ;;
    weston) echo 'Updated title.*Weston Compositor' ;;
    *) echo 'Updated title|new_toplevel' ;;
  esac
}

mem_for() {
  case "$1" in
    plasma|kde|kwin|kde-plasma|plasma-full|gnome|gnome-shell|mutter|hyprland)
      echo 4096
      ;;
    *)
      echo 2048
      ;;
  esac
}

stop_client_container() {
  local name="$1"
  pkill -f "wawona-matrix-.*-${name}" 2>/dev/null || true
  pkill -f "container-desktop-clients-macos.sh ${name}" 2>/dev/null || true
  sleep 2
}

run_one() {
  local name="$1"
  local vsock="$2"
  local pattern
  pattern="$(title_pattern_for "$name")"
  local mem
  mem="$(mem_for "$name")"
  local run_log="$ARTIFACTS/${name}-run.log"
  local shot="$ARTIFACTS/${name}.png"
  local marker
  marker="$(log_line_count)"

  stop_client_container "$name"

  echo ""
  echo "=== matrix: $name (vsock=$vsock mem=${mem}MiB) ==="
  WAWONA_CONTAINER_VSOCK="$vsock" \
    WAWONA_CONTAINER_MEM_MB="$mem" \
    WAWONA_CONTAINER_ID="wawona-matrix-$(id -u)-${name}" \
    "$CLIENT_SCRIPT" "$name" >"$run_log" 2>&1 &
  local pid=$!

  local ok=0
  local i
  local max_wait=120
  case "$name" in
    plasma|kde|kwin|kde-plasma|plasma-full|gnome|gnome-shell|mutter|hyprland|sway)
      max_wait=240
      ;;
  esac
  # Only accept the client-specific title pattern. Do not treat unrelated
  # concurrent toplevels (other matrix runs, leftover niri) as success.
  for i in $(seq 1 "$max_wait"); do
    sleep 5
    if tail -n +"$marker" "$WWN_LOG" 2>/dev/null | rg -qi "$pattern"; then
      ok=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      if rg -q 'Error:|ECONNREFUSED|waypipe relay failed|EOPNOTSUPP|panicked' "$run_log" 2>/dev/null; then
        break
      fi
      # Guest exited without a matching title.
      break
    fi
  done

  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: $name (window title matched)"
    tail -n +"$marker" "$WWN_LOG" | rg -i "$pattern" | tail -2 || true
    if command -v osascript >/dev/null; then
      osascript -e 'tell application "Wawona" to activate' >/dev/null 2>&1 || true
      sleep 1
    fi
    if command -v agent-device >/dev/null; then
      agent-device screenshot --out "$shot" --platform macos --session weston-test 2>/dev/null \
        || agent-device open Wawona --platform macos --session weston-test >/dev/null 2>&1 \
        && agent-device screenshot --out "$shot" --platform macos --session weston-test 2>/dev/null \
        || true
    fi
    [[ -f "$shot" ]] && echo "screenshot: $shot"
    echo "$name PASS" >>"$ARTIFACTS/results.txt"
  else
    echo "FAIL: $name"
    tail -8 "$run_log" || true
    echo "$name FAIL" >>"$ARTIFACTS/results.txt"
  fi

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  stop_client_container "$name"
}

: >"$ARTIFACTS/results.txt"
PORT=1044
for client in "${CLIENTS[@]}"; do
  run_one "$client" "$PORT"
  PORT=$((PORT + 1))
done

echo ""
echo "=== matrix summary ==="
cat "$ARTIFACTS/results.txt"
echo "artifacts: $ARTIFACTS"
