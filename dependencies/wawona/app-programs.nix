{ pkgs, systemPackages, xcodeUtils }:

{
  wawonaIos = "${pkgs.writeShellScriptBin "wawona-ios" ''
    set -euo pipefail
    export PATH="${xcodeUtils.xcodeWrapper}/bin:$PATH"
    DEBUG_MODE=false
    if [ "''${1:-}" = "--debug" ]; then
      DEBUG_MODE=true
      shift
    fi

    APP_PATH="${systemPackages.wawona-ios-app-sim}/Wawona.app"
    if [ ! -d "$APP_PATH" ]; then
      echo "Error: Wawona.app not found at $APP_PATH"
      exit 1
    fi
    SIM_NAME="Wawona iOS Simulator"
    DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
    RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1)
    if [ -z "$RUNTIME" ]; then
      echo "No iOS simulator runtime found. Attempting to provision Xcode automatically..."
      ${xcodeUtils.provisionXcodeScript}/bin/provision-xcode || {
        echo "Error: Failed to provision Xcode. Please open Xcode and install the iOS platform manually or run: sudo xcodebuild -downloadPlatform iOS"
        exit 1
      }
      # Re-check runtime after provisioning
      RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1)
      if [ -z "$RUNTIME" ]; then
        echo "Error: Provisioning finished but no iOS runtime was found. You may need to manually download it in Xcode -> Settings -> Platforms."
        exit 1
      fi
    fi
    SIM_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
    if [ -z "$SIM_UDID" ]; then
      echo "Creating simulator '$SIM_NAME'..."
      SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
    fi
    xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true
    
    SIM_APP_PATH=$(${xcodeUtils.findSimulatorScript}/bin/find-simulator)
    SIM_APP_BUNDLE="$(dirname "$(dirname "$SIM_APP_PATH")")"
    echo "Opening $SIM_APP_BUNDLE..."
    open -a "$SIM_APP_BUNDLE" 2>/dev/null || true
    
    echo "Installing Wawona.app to simulator..."
    TMP_APP_ROOT="/tmp/wawona-ios-install"
    STAGED_APP="$TMP_APP_ROOT/Wawona.app"
    rm -rf "$TMP_APP_ROOT"
    mkdir -p "$TMP_APP_ROOT"
    cp -R "$APP_PATH" "$STAGED_APP"
    chmod -R u+rwX "$TMP_APP_ROOT" || true
    if ! xcrun simctl install "$SIM_UDID" "$STAGED_APP"; then
      echo "Install failed; trying clean install and simulator reset..."
      xcrun simctl terminate "$SIM_UDID" com.aspauldingcode.Wawona 2>/dev/null || true
      xcrun simctl uninstall "$SIM_UDID" com.aspauldingcode.Wawona 2>/dev/null || true
      if ! xcrun simctl install "$SIM_UDID" "$STAGED_APP"; then
        xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true
        xcrun simctl erase "$SIM_UDID" 2>/dev/null || true
        xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
        xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true
        xcrun simctl install "$SIM_UDID" "$STAGED_APP"
      fi
    fi

    if [ "$DEBUG_MODE" != "true" ]; then
      echo "Launching Wawona..."
      xcrun simctl launch "$SIM_UDID" com.aspauldingcode.Wawona "$@"
      exit 0
    fi

    DSYM_PATH="${systemPackages.wawona-ios-app-sim}/Wawona.app.dSYM"
    echo "Launching Wawona (paused at spawn for debugger)..."
    LAUNCH_OUTPUT=$(xcrun simctl launch --wait-for-debugger "$SIM_UDID" com.aspauldingcode.Wawona "$@")
    echo "$LAUNCH_OUTPUT"
    PID=$(echo "$LAUNCH_OUTPUT" | awk '/com.aspauldingcode.Wawona:/ {print $NF}')
    if [ -z "$PID" ]; then
      echo "Error: Could not determine app PID for LLDB attach."
      exit 1
    fi
    LOG_STREAM_PID=""
    cleanup_log_stream() {
      if [ -n "$LOG_STREAM_PID" ] && kill -0 "$LOG_STREAM_PID" 2>/dev/null; then
        kill "$LOG_STREAM_PID" 2>/dev/null || true
        wait "$LOG_STREAM_PID" 2>/dev/null || true
      fi
    }
    trap cleanup_log_stream EXIT INT TERM
    echo "Starting live simulator logs for Wawona..."
    xcrun simctl spawn "$SIM_UDID" log stream --style compact --predicate 'process == "Wawona"' &
    LOG_STREAM_PID=$!
    echo "Attaching LLDB to PID $PID..."
    if [ -d "$DSYM_PATH" ]; then
      lldb -Q \
        -o "process attach --pid $PID" \
        -o "target symbols add $DSYM_PATH" \
        -o "continue"
    else
      lldb -Q \
        -o "process attach --pid $PID" \
        -o "continue"
    fi
    LLDB_EXIT=$?
    cleanup_log_stream
    exit $LLDB_EXIT
  ''}/bin/wawona-ios";

  weston = let
    pkg = systemPackages.weston;
    wrapper = pkgs.writeShellScriptBin "weston-run" ''
      if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
      fi
      exec ${pkg}/bin/weston "$@"
    '';
  in "${wrapper}/bin/weston-run";

}
