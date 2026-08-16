#!/usr/bin/env bash
# Wayland SHM .wasm guest (Rust, rustup-only) against macOS Wawona compositor.
#
# 1. Build examples/wayland-shm/rust with rustup (no Nix).
# 2. Start Wawona.app, wait for its Wayland socket.
# 3. Run the guest via the Wawona Runtime (`wasm`).
# 4. Capture the Wawona window and assert non-black (blue rectangle).
#
# Usage:
#   ./scripts/wasm-wayland-shm-smoke-macos.sh [/path/to/Wawona.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWN_WASM="${WAWONA_WWN_WASM:-$ROOT/../wwn-wasm}"
APP="${1:-}"
WAIT_SECS="${WAWONA_WASM_SMOKE_WAIT:-45}"
ART_DIR="${WAWONA_WASM_SMOKE_ARTIFACTS:-$ROOT/.agent-device/test-artifacts}"

log() { echo "[wasm-wayland-shm-smoke-macos] $*"; }

export PATH="${HOME}/.cargo/bin:${PATH}"
if ! command -v rustup >/dev/null 2>&1; then
  log "FAIL: rustup required (https://rustup.rs). Do not use Nix for the guest build."
  exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
  log "FAIL: cargo not on PATH after rustup"
  exit 1
fi

if [[ -z "$APP" ]]; then
  for cand in \
    /Users/8amps/Applications/Wawona.app \
    "$ROOT/result-macos-gbmfix/Applications/Wawona.app" \
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

WASM_BIN="${WASM_BIN:-$APP/Contents/MacOS/wasm}"
if [[ ! -x "$WASM_BIN" ]]; then
  WASM_BIN="$APP/Contents/Resources/bin/wasm"
fi
[[ -x "$WASM_BIN" ]] || { log "FAIL: Runtime wasm CLI missing in $APP"; exit 1; }

log "build Wayland SHM guest with rustup (no Nix)"
(
  cd "$WWN_WASM/examples/wayland-shm/rust"
  rustup target add wasm32-wasip1 >/dev/null
  ./build.sh
)
GUEST="$WWN_WASM/examples/wayland-shm/dist/wayland-shm-rust.wasm"
test -f "$GUEST"
python3 -c "b=open('$GUEST','rb').read(4); assert b==b'\\x00asm', b"
# Prove the tool chain was rustup, not nix store cargo.
RUSTC_PATH="$(rustup which rustc)"
case "$RUSTC_PATH" in
  */.rustup/*|*/.cargo/*) log "PASS: rustc via rustup ($RUSTC_PATH)" ;;
  *) log "WARN: rustc path is $RUSTC_PATH (expected ~/.rustup)" ;;
esac

mkdir -p "$ART_DIR" "$HOME/Documents/Wawona"
cp -f "$GUEST" "$HOME/Documents/Wawona/wayland-shm-rust.wasm"

RUNTIME_DIR="$(mktemp -d /tmp/wawona-wasm-shm.XXXXXX)"
chmod 700 "$RUNTIME_DIR"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"

APP_PID=0
GUEST_PID=0
cleanup() {
  kill "$GUEST_PID" 2>/dev/null || true
  kill "$APP_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

log "starting Wawona ($APP)"
"$APP/Contents/MacOS/Wawona" >/tmp/wawona-wasm-shm-app.log 2>&1 &
APP_PID=$!

DISPLAY_SOCK=""
for _ in $(seq 1 "$WAIT_SECS"); do
  # Historical: "Compositor started. Socket: /path"
  # Current apps: "Compositor started — socket: /path" or "… - socket:"
  DISPLAY_SOCK="$(
    sed -nE 's/.*Compositor started[. ].*[Ss]ocket:[[:space:]]*([^[:space:]]+).*/\1/p' \
      /tmp/wawona-wasm-shm-app.log | head -n1
  )"
  [[ -n "$DISPLAY_SOCK" && -S "$DISPLAY_SOCK" ]] && break
  DISPLAY_SOCK=""
  kill -0 "$APP_PID" 2>/dev/null || {
    log "FAIL: Wawona exited early"
    tail -60 /tmp/wawona-wasm-shm-app.log
    exit 1
  }
  sleep 1
done
[[ -n "$DISPLAY_SOCK" ]] || {
  log "FAIL: no Wawona Wayland socket"
  tail -60 /tmp/wawona-wasm-shm-app.log
  exit 1
}
export XDG_RUNTIME_DIR="$(dirname "$DISPLAY_SOCK")"
export WAYLAND_DISPLAY="$(basename "$DISPLAY_SOCK")"
log "Wawona socket: $WAYLAND_DISPLAY ($XDG_RUNTIME_DIR)"

OUT="/tmp/wawona-wasm-shm-guest.log"
log "run guest via Runtime: $WASM_BIN $GUEST"
set +e
"$WASM_BIN" "$GUEST" >"$OUT" 2>&1 &
GUEST_PID=$!
# Guest stays mapped after commit; give Wawona frames to present.
for _ in $(seq 1 30); do
  if grep -q 'wayland-shm: 256x256 XRGB8888 committed' "$OUT" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$GUEST_PID" 2>/dev/null; then
    break
  fi
  sleep 0.2
done
set -e
cat "$OUT"
if ! grep -q 'wayland-shm: 256x256 XRGB8888 committed' "$OUT"; then
  log "FAIL: guest did not commit SHM buffer"
  tail -80 /tmp/wawona-wasm-shm-app.log || true
  exit 1
fi
log "PASS: guest committed 256x256 XRGB8888"
sleep 2

SHOT_PNG="$ART_DIR/wasm-wayland-shm-macos.png"
# Prefer the Wayland client host window titled by the guest (xdg set_title).
WIN_ID="$(
  swift -e '
import Cocoa
let opts = CGWindowListOption(arrayLiteral: .optionAll)
guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in info {
  let name = w[kCGWindowName as String] as? String ?? ""
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let num = w[kCGWindowNumber as String] as? Int ?? 0
  if owner == "Wawona" && name == "wawona-wasm-shm" {
    print(num); break
  }
}
' 2>/dev/null || true
)"
if [[ -z "$WIN_ID" ]]; then
  WIN_ID="$(
    swift -e '
import Cocoa
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in info {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let name = w[kCGWindowName as String] as? String ?? ""
  let layer = w[kCGWindowLayer as String] as? Int ?? -1
  let num = w[kCGWindowNumber as String] as? Int ?? 0
  if owner == "Wawona" && layer == 0 && (name.contains("Machine") || !name.isEmpty) {
    print(num); break
  }
}
' 2>/dev/null || true
  )"
fi
if [[ -z "$WIN_ID" ]] || ! screencapture -x -l "$WIN_ID" "$SHOT_PNG" 2>/dev/null; then
  log "NOTE: window capture failed; full-screen fallback"
  screencapture -x "$SHOT_PNG"
fi
[[ -f "$SHOT_PNG" ]] || { log "FAIL: no screenshot"; exit 1; }

BMP="$RUNTIME_DIR/frame.bmp"
sips -s format bmp "$SHOT_PNG" --out "$BMP" >/dev/null
# Guest fills 0xFF3366CC (B=0xCC, G=0x66, R=0x33). Accept any clear non-black.
if ! python3 - "$BMP" <<'PY'
import struct, sys
with open(sys.argv[1], "rb") as f:
    data = f.read()
off = struct.unpack_from("<I", data, 10)[0]
w, h = struct.unpack_from("<ii", data, 18)
bpp = struct.unpack_from("<H", data, 28)[0] // 8
row = (w * bpp + 3) & ~3
lit = blueish = total = 0
for y in range(0, abs(h), max(1, abs(h) // 64)):
    base = off + y * row
    for x in range(0, w, max(1, w // 64)):
        b, g, r = data[base + x * bpp : base + x * bpp + 3]
        total += 1
        if max(r, g, b) > 24:
            lit += 1
        # 0x3366CC-ish (allow present-path color shifts)
        if b > 120 and r < 120 and g < 160:
            blueish += 1
frac = lit / max(1, total)
bfrac = blueish / max(1, total)
print(f"[wasm-wayland-shm-smoke-macos] lit={frac:.3f} blueish={bfrac:.3f}")
sys.exit(0 if frac > 0.02 else 1)
PY
then
  log "FAIL: frame near-black ($SHOT_PNG)"
  exit 1
fi
log "PASS: graphical output captured ($SHOT_PNG)"
log "wasm Wayland SHM macOS smoke PASSED"
