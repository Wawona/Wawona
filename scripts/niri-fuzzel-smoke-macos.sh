#!/usr/bin/env bash
# Nested niri + fuzzel catalog smoke (macOS).
#
# Extends scripts/niri-smoke-macos.sh: after nested niri is up, assert the
# bundled Freedesktop applications catalog is present, XDG_DATA_DIRS points at
# it, and `fuzzel` can start against niri's child Wayland socket (issue #78).
#
# Usage: ./scripts/niri-fuzzel-smoke-macos.sh [/path/to/Wawona.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-}"
WAIT_SECS="${WAWONA_NIRI_SMOKE_WAIT:-45}"
ART_DIR="${WAWONA_NIRI_SMOKE_ARTIFACTS:-$ROOT/.agent-device/test-artifacts}"

log() { echo "[niri-fuzzel-smoke-macos] $*"; }

if [[ -z "$APP" ]]; then
  for cand in \
    /tmp/wawona-fuzzel-smoke.app \
    /tmp/wawona-macos-niri-result/Applications/Wawona.app \
    "$ROOT/result-macos/Applications/Wawona.app" \
    "$ROOT/result/Applications/Wawona.app"
  do
    if [[ -d "$cand" ]]; then
      APP="$cand"
      break
    fi
  done
fi
[[ -d "$APP" ]] || { log "FAIL: Wawona.app not found"; exit 1; }

NIRI_BIN="${WAWONA_NIRI_BIN:-$APP/Contents/Resources/bin/niri}"
FUZZEL_BIN="${WAWONA_FUZZEL_BIN:-$APP/Contents/Resources/bin/fuzzel}"
[[ -x "$NIRI_BIN" ]] || { log "FAIL: bundled niri missing at $NIRI_BIN"; exit 1; }
[[ -x "$FUZZEL_BIN" ]] || { log "FAIL: bundled fuzzel missing at $FUZZEL_BIN"; exit 1; }

# Catalog may live under Contents/Resources/share or $APP/share (macos.nix).
SHARE_ROOT=""
for cand in \
  "$APP/Contents/Resources/share" \
  "$APP/share" \
  "$APP/Contents/Resources/../share"
do
  if [[ -d "$cand/applications" ]]; then
    SHARE_ROOT="$(cd "$cand" && pwd)"
    break
  fi
done
[[ -n "$SHARE_ROOT" ]] || { log "FAIL: no share/applications in app bundle"; exit 1; }
DESK_COUNT="$(find "$SHARE_ROOT/applications" -name '*.desktop' | wc -l | tr -d ' ')"
[[ "$DESK_COUNT" -ge 3 ]] || { log "FAIL: catalog too small ($DESK_COUNT)"; exit 1; }
ICON_COUNT="$(find "$SHARE_ROOT/icons/hicolor" -type f 2>/dev/null | wc -l | tr -d ' ')"
[[ "${ICON_COUNT:-0}" -ge 1 ]] || { log "FAIL: no hicolor icons under $SHARE_ROOT/icons"; exit 1; }
log "PASS: catalog $DESK_COUNT desktops, $ICON_COUNT icons at $SHARE_ROOT"

# Run base nested-niri smoke first (starts Wawona + niri, asserts non-black).
# Capture its logs/runtime via the same paths it uses.
export WAWONA_NIRI_SMOKE_ARTIFACTS="$ART_DIR"
"$ROOT/scripts/niri-smoke-macos.sh" "$APP"

# niri-smoke-macos leaves processes cleaned up via trap. Re-drive a shorter
# nested session just for fuzzel spawn/assert.
RUNTIME_DIR="$(mktemp -d /tmp/wawona-niri-fuzzel.XXXXXX)"
chmod 700 "$RUNTIME_DIR"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
mkdir -p "$ART_DIR" "$RUNTIME_DIR/xdg-data-home"

APP_PID=0
NIRI_PID=0
FUZZEL_PID=0
cleanup() {
  kill "$FUZZEL_PID" 2>/dev/null || true
  kill "$NIRI_PID" 2>/dev/null || true
  kill "$APP_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

log "restarting Wawona for fuzzel spawn check"
"$APP/Contents/MacOS/Wawona" >/tmp/wawona-niri-fuzzel-app.log 2>&1 &
APP_PID=$!

DISPLAY_SOCK=""
for _ in $(seq 1 "$WAIT_SECS"); do
  DISPLAY_SOCK="$(sed -n 's/.*Compositor started — socket: //p' /tmp/wawona-niri-fuzzel-app.log | head -n1)"
  [[ -n "$DISPLAY_SOCK" && -S "$DISPLAY_SOCK" ]] && break
  DISPLAY_SOCK=""
  kill -0 "$APP_PID" 2>/dev/null || { log "FAIL: Wawona exited early"; tail -40 /tmp/wawona-niri-fuzzel-app.log; exit 1; }
  sleep 1
done
[[ -n "$DISPLAY_SOCK" ]] || { log "FAIL: no Wawona socket"; exit 1; }
export XDG_RUNTIME_DIR="$(dirname "$DISPLAY_SOCK")"
export WAYLAND_DISPLAY="$(basename "$DISPLAY_SOCK")"

ICD_JSON=""
for icd in "$APP/Contents/Resources/vulkan/icd.d/"*.json; do
  [[ -f "$icd" ]] && ICD_JSON="$icd" && break
done

NIRI_CFG=""
for cand in \
  "$APP/share/niri/default-config.kdl" \
  "$APP/Contents/Resources/share/niri/default-config.kdl"
do
  if [[ -f "$cand" ]]; then
    NIRI_CFG="$cand"
    break
  fi
done
[[ -n "$NIRI_CFG" ]] || log "NOTE: no bundled niri default-config.kdl; using niri defaults"

export NIRI_BACKEND=nested
export RUST_LOG=niri=info
export DYLD_LIBRARY_PATH="$APP/Contents/Frameworks"
export VK_ICD_FILENAMES="$ICD_JSON"
export VK_DRIVER_FILES="$ICD_JSON"
export XDG_DATA_DIRS="$SHARE_ROOT${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export XDG_DATA_HOME="$RUNTIME_DIR/xdg-data-home"
export PATH="$(dirname "$FUZZEL_BIN"):$PATH"
[[ -n "$NIRI_CFG" ]] && export NIRI_CONFIG="$NIRI_CFG"

"$NIRI_BIN" >/tmp/wawona-niri-fuzzel-niri.log 2>&1 &
NIRI_PID=$!

NIRI_CHILD=""
for _ in $(seq 1 "$WAIT_SECS"); do
  NIRI_CHILD="$(grep -oE 'listening on Wayland socket: [^ ]+' /tmp/wawona-niri-fuzzel-niri.log | awk '{print $NF}' | head -n1 || true)"
  [[ -n "$NIRI_CHILD" && -S "$XDG_RUNTIME_DIR/$NIRI_CHILD" ]] && break
  kill -0 "$NIRI_PID" 2>/dev/null || { log "FAIL: niri exited"; tail -60 /tmp/wawona-niri-fuzzel-niri.log; exit 1; }
  sleep 1
done
[[ -n "$NIRI_CHILD" ]] || { log "FAIL: niri child socket missing"; exit 1; }
log "niri child socket: $NIRI_CHILD"

# Launch fuzzel as a client of nested niri with the bundled catalog.
WAYLAND_DISPLAY="$NIRI_CHILD" \
  XDG_DATA_DIRS="$SHARE_ROOT" \
  XDG_DATA_HOME="$RUNTIME_DIR/xdg-data-home" \
  XDG_CACHE_HOME="$RUNTIME_DIR/cache" \
  "$FUZZEL_BIN" >/tmp/wawona-niri-fuzzel-fuzzel.log 2>&1 &
FUZZEL_PID=$!
sleep 2
kill -0 "$FUZZEL_PID" 2>/dev/null || {
  log "FAIL: fuzzel exited immediately"
  cat /tmp/wawona-niri-fuzzel-fuzzel.log
  exit 1
}
log "PASS: fuzzel stayed up against nested niri (pid $FUZZEL_PID)"

# Screenshot for CI artifacts.
SHOT="$ART_DIR/macos-fuzzel-e2e.png"
screencapture -x "$SHOT" 2>/dev/null || true
[[ -f "$SHOT" ]] && log "screenshot: $SHOT"

# Assert .desktop Names are discoverable (same scan fuzzel uses).
python3 - "$SHARE_ROOT/applications" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
names = []
for p in sorted(root.glob("*.desktop")):
    text = p.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        if line.startswith("Name="):
            names.append(line.split("=", 1)[1].strip())
            break
need = {"Foot Terminal", "Neovim"}
missing = need - set(names)
if missing:
    raise SystemExit(f"missing desktop Names: {sorted(missing)}; have={names[:12]}")
print(f"[niri-fuzzel-smoke-macos] PASS: desktop Names include {sorted(need)} ({len(names)} total)")
PY

log "macOS niri+fuzzel smoke PASSED"
