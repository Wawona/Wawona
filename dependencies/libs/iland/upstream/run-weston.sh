#!/bin/bash
#
# Run weston with terminal on macOS via our DRM/GBM/EGL shims.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build-weston"
DYLD_INSERT_LIBRARIES="$SCRIPT_DIR/build/libwayland-mac.dylib"
WESTON_DATA_DIR="$SCRIPT_DIR/weston/data"

WESTON_MODULE_MAP="drm-backend.so=${BUILD_DIR}/libweston/backend-drm/drm-backend.dylib"
WESTON_MODULE_MAP="${WESTON_MODULE_MAP};gl-renderer.so=${BUILD_DIR}/libweston/renderer-gl/gl-renderer.dylib"
WESTON_MODULE_MAP="${WESTON_MODULE_MAP};desktop-shell.so=${BUILD_DIR}/desktop-shell/desktop-shell.dylib"
WESTON_MODULE_MAP="${WESTON_MODULE_MAP};weston-keyboard=${BUILD_DIR}/clients/weston-keyboard"
WESTON_MODULE_MAP="${WESTON_MODULE_MAP};weston-desktop-shell=${BUILD_DIR}/clients/weston-desktop-shell"
WESTON_MODULE_MAP="${WESTON_MODULE_MAP};weston-terminal=${BUILD_DIR}/clients/weston-terminal"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/weston-runtime}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null

# Kill stale processes
echo "=== Cleaning up ==="
sudo pkill -9 weston 2>/dev/null; sudo pkill -9 framebufferd 2>/dev/null
sudo pkill -9 amfiexceptiond 2>/dev/null
sudo rm -f "$XDG_RUNTIME_DIR"/wayland-*

# Generate weston.ini from template
sudo rm -f /tmp/weston-*.ini
TEMP_WESTON_INI=$(mktemp /tmp/weston-XXXXXX.ini)
sed "s|%SourceDirectory%|$SCRIPT_DIR|g" "$SCRIPT_DIR/weston.ini" > "$TEMP_WESTON_INI"

# Start weston
echo "=== Starting weston ==="
sudo env \
    DYLD_INSERT_LIBRARIES="$DYLD_INSERT_LIBRARIES" \
    WESTON_MODULE_MAP="$WESTON_MODULE_MAP" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    WESTON_DATA_DIR="$WESTON_DATA_DIR" \
    "$BUILD_DIR/frontend/weston" --backend=drm \
    --continue-without-input \
    --config="$TEMP_WESTON_INI" &

WESTON_PID=$!

# Wait for wayland socket
echo "=== Waiting for wayland socket ==="
for i in $(seq 1 30); do
    SOCK=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v lock | head -1)
    if [ -n "$SOCK" ] && [ -S "$SOCK" ]; then
        echo "Socket: $SOCK"
        break
    fi
    sleep 1
done

echo "=== Running (PID $WESTON_PID). Ctrl+C to stop. ==="
trap "kill $WESTON_PID 2>/dev/null; rm -f '$TEMP_WESTON_INI'; echo 'Stopped.'; exit" INT TERM
wait $WESTON_PID
