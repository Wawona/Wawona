#!/usr/bin/env bash
# niri nested smoke (macOS) — Phase 29 capability assertion for wwn-niri.
#
# Boots the Wawona macOS compositor app, launches the bundled niri against it
# (NIRI_BACKEND=nested → niri is a Wayland client of Wawona), and asserts:
#   1. niri connects and stays up,
#   2. niri serves its own child Wayland socket (it is itself a compositor),
#   3. the Wawona window shows a non-black frame (niri's output was composited).
#
# Usage:  ./scripts/niri-smoke-macos.sh [/path/to/Wawona.app]
# The app defaults to the nix build output (nix build .#wawona-macos).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-}"
WAIT_SECS="${WAWONA_NIRI_SMOKE_WAIT:-45}"
ART_DIR="${WAWONA_NIRI_SMOKE_ARTIFACTS:-$ROOT/.agent-device/test-artifacts}"

log() { echo "[niri-smoke-macos] $*"; }

if [[ -z "$APP" ]]; then
  for cand in /tmp/wawona-macos-niri-result "$ROOT/result-macos" "$ROOT/result"; do
    if [[ -d "$cand/Applications/Wawona.app" ]]; then
      APP="$cand/Applications/Wawona.app"
      break
    fi
  done
fi
[[ -d "$APP" ]] || { log "FAIL: Wawona.app not found (pass it as \$1 or nix build .#wawona-macos)"; exit 1; }

NIRI_BIN="${WAWONA_NIRI_BIN:-$APP/Contents/Resources/bin/niri}"
[[ -x "$NIRI_BIN" ]] || { log "FAIL: bundled niri missing at $NIRI_BIN"; exit 1; }

# Bundled niri is compiled against a nix-store XKB path that is absent after
# GHA artifact unpack. Prefer app-bundled xkb, then nixpkgs, then env.
if [[ -z "${XKB_CONFIG_ROOT:-}" ]]; then
  for cand in \
    "$APP/Contents/Resources/share/X11/xkb" \
    "$APP/share/X11/xkb"
  do
    if [[ -d "$cand/rules" ]]; then
      export XKB_CONFIG_ROOT="$cand"
      break
    fi
  done
fi
if [[ -z "${XKB_CONFIG_ROOT:-}" ]] && command -v nix >/dev/null 2>&1; then
  SYS="$(nix eval --impure --raw --expr builtins.currentSystem 2>/dev/null || uname -m | sed 's/arm64/aarch64/;s/x86_64/x86_64/')-darwin"
  XKB_OUT="$(nix build --no-link --print-out-paths "nixpkgs#xkeyboard_config" 2>/dev/null || true)"
  if [[ -z "$XKB_OUT" ]]; then
    XKB_OUT="$(nix build --no-link --print-out-paths --impure --expr "with import (builtins.getFlake \"$ROOT\").inputs.nixpkgs { system = \"$SYS\"; }; xkeyboard_config" 2>/dev/null || true)"
  fi
  if [[ -n "$XKB_OUT" && -d "$XKB_OUT/share/X11/xkb/rules" ]]; then
    export XKB_CONFIG_ROOT="$XKB_OUT/share/X11/xkb"
  fi
fi
[[ -n "${XKB_CONFIG_ROOT:-}" ]] || log "WARN: XKB_CONFIG_ROOT unset; nested niri may BadKeymap on artifact apps"
[[ -n "${XKB_CONFIG_ROOT:-}" ]] && log "XKB_CONFIG_ROOT=$XKB_CONFIG_ROOT"

# Fresh runtime dir so socket discovery is deterministic.
RUNTIME_DIR="$(mktemp -d /tmp/wawona-niri-smoke.XXXXXX)"
chmod 700 "$RUNTIME_DIR"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
mkdir -p "$ART_DIR"

APP_PID=0
NIRI_PID=0
cleanup() {
  kill "$NIRI_PID" 2>/dev/null || true
  kill "$APP_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

log "starting Wawona compositor app ($APP)"
"$APP/Contents/MacOS/Wawona" >/tmp/wawona-niri-smoke-app.log 2>&1 &
APP_PID=$!

# 1. Wait for the Wawona Wayland socket. The app configures its own
# XDG_RUNTIME_DIR (e.g. /tmp/wawona-$UID); parse the advertised socket path
# from its log rather than assuming our exported runtime dir was honored.
DISPLAY_SOCK=""
for _ in $(seq 1 "$WAIT_SECS"); do
  DISPLAY_SOCK="$(sed -n 's/.*Compositor started — socket: //p' /tmp/wawona-niri-smoke-app.log | head -n1)"
  [[ -n "$DISPLAY_SOCK" && -S "$DISPLAY_SOCK" ]] && break
  DISPLAY_SOCK=""
  kill -0 "$APP_PID" 2>/dev/null || { log "FAIL: Wawona app exited before socket"; tail -40 /tmp/wawona-niri-smoke-app.log; exit 1; }
  sleep 1
done
[[ -n "$DISPLAY_SOCK" ]] || { log "FAIL: Wawona Wayland socket never appeared"; tail -40 /tmp/wawona-niri-smoke-app.log; exit 1; }
RUNTIME_DIR="$(dirname "$DISPLAY_SOCK")"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export WAYLAND_DISPLAY="$(basename "$DISPLAY_SOCK")"
log "Wawona socket up: $WAYLAND_DISPLAY (runtime dir: $RUNTIME_DIR)"

# 2. Launch niri nested and wait for its child socket. ANGLE's Vulkan-over-
# Wayland winsys needs the bundled Vulkan ICD (kosmickrisp or MoltenVK).
ICD_JSON=""
for icd in "$APP/Contents/Resources/vulkan/icd.d/"*.json; do
  [[ -f "$icd" ]] && ICD_JSON="$icd" && break
done
log "starting nested niri (VK ICD: ${ICD_JSON:-none})"
# Product macOS app ships config under Contents/Resources/share; some layouts
# also keep $APP/share (macos.nix). Prefer the first that exists.
NIRI_CFG=""
for cand in \
  "$APP/Contents/Resources/share/niri/default-config.kdl" \
  "$APP/share/niri/default-config.kdl"
do
  if [[ -f "$cand" ]]; then
    NIRI_CFG="$cand"
    break
  fi
done
[[ -n "$NIRI_CFG" ]] || log "NOTE: no bundled niri default-config.kdl; using niri defaults"
if [[ -n "$NIRI_CFG" ]]; then
  export NIRI_CONFIG="$NIRI_CFG"
else
  unset NIRI_CONFIG || true
fi
NIRI_BACKEND=nested RUST_LOG=niri=debug \
  DYLD_LIBRARY_PATH="$APP/Contents/Frameworks${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  VK_ICD_FILENAMES="$ICD_JSON" VK_DRIVER_FILES="$ICD_JSON" \
  "$NIRI_BIN" >/tmp/wawona-niri-smoke-niri.log 2>&1 &
NIRI_PID=$!
NIRI_CHILD=""
for _ in $(seq 1 "$WAIT_SECS"); do
  NIRI_CHILD="$(grep -oE 'listening on Wayland socket: [^ ]+' /tmp/wawona-niri-smoke-niri.log | awk '{print $NF}' | head -n1 || true)"
  [[ -n "$NIRI_CHILD" && -S "$RUNTIME_DIR/$NIRI_CHILD" ]] && break
  kill -0 "$NIRI_PID" 2>/dev/null || { log "FAIL: niri exited early"; tail -60 /tmp/wawona-niri-smoke-niri.log; exit 1; }
  sleep 1
done
[[ -n "$NIRI_CHILD" && -S "$RUNTIME_DIR/$NIRI_CHILD" ]] || { log "FAIL: niri child socket never appeared"; tail -60 /tmp/wawona-niri-smoke-niri.log; exit 1; }
log "PASS: niri nested is up; child socket: $NIRI_CHILD"

# Give niri a few frames to draw its background/hotkey overlay into Wawona.
sleep 3
kill -0 "$NIRI_PID" 2>/dev/null || { log "FAIL: niri died after startup"; tail -60 /tmp/wawona-niri-smoke-niri.log; exit 1; }

# 3. Non-black frame assertion: screenshot the Wawona window and check pixels.
SHOT_PNG="$ART_DIR/niri-smoke-macos.png"
WIN_ID="$(osascript -l JavaScript -e '
ObjC.import("CoreGraphics");
const opts = $.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements;
const wins = ObjC.deepUnwrap($.CFBridgingRelease($.CGWindowListCopyWindowInfo(opts, $.kCGNullWindowID))) || [];
const w = wins.find(w => w.kCGWindowOwnerName === "Wawona" && w.kCGWindowLayer === 0);
w ? String(w.kCGWindowNumber) : "";
' 2>/dev/null || true)"
if [[ -z "$WIN_ID" ]] || ! screencapture -x -l "$WIN_ID" "$SHOT_PNG" 2>/dev/null; then
  log "NOTE: window capture failed; falling back to full-screen capture"
  screencapture -x "$SHOT_PNG"
fi
[[ -f "$SHOT_PNG" ]] || { log "FAIL: could not capture a screenshot"; exit 1; }

BMP="$RUNTIME_DIR/frame.bmp"
sips -s format bmp "$SHOT_PNG" --out "$BMP" >/dev/null
if ! python3 - "$BMP" <<'PY'
import struct, sys
with open(sys.argv[1], "rb") as f:
    data = f.read()
off = struct.unpack_from("<I", data, 10)[0]
w, h = struct.unpack_from("<ii", data, 18)
bpp = struct.unpack_from("<H", data, 28)[0] // 8
row = (w * bpp + 3) & ~3
lit = total = 0
for y in range(0, abs(h), max(1, abs(h) // 64)):
    base = off + y * row
    for x in range(0, w, max(1, w // 64)):
        b, g, r = data[base + x * bpp : base + x * bpp + 3]
        total += 1
        if max(r, g, b) > 24:
            lit += 1
frac = lit / max(1, total)
print(f"[niri-smoke-macos] lit-pixel fraction: {frac:.3f}")
sys.exit(0 if frac > 0.02 else 1)
PY
then
  log "FAIL: captured frame is (near-)black — niri produced no visible output"
  exit 1
fi
log "PASS: non-black frame captured ($SHOT_PNG)"
log "niri macOS nested smoke PASSED"
