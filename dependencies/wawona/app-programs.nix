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
    RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1 || true)
    if [ -z "$RUNTIME" ]; then
      echo "No iOS simulator runtime found. Attempting to provision Xcode automatically..."
      ${xcodeUtils.provisionXcodeScript}/bin/provision-xcode || {
        echo "Error: Failed to provision Xcode. Please open Xcode and install the iOS platform manually or run: sudo xcodebuild -downloadPlatform iOS"
        exit 1
      }
      # Re-check runtime after provisioning
      RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1 || true)
      if [ -z "$RUNTIME" ]; then
        echo "Error: Provisioning finished but no iOS runtime was found. You may need to manually download it in Xcode -> Settings -> Platforms."
        exit 1
      fi
    fi
    SIM_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1 || true)
    if [ -z "$SIM_UDID" ]; then
      echo "Creating simulator '$SIM_NAME'..."
      SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
    fi
    xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true
    
    echo "Opening Simulator.app..."
    open -a "Simulator" 2>/dev/null || open -a "Simulator.app" 2>/dev/null || true
    
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

  wawonaIpad = "${pkgs.writeShellScriptBin "wawona-ipados" ''
    set -euo pipefail
    export PATH="${xcodeUtils.xcodeWrapper}/bin:$PATH"
    DEBUG_MODE=false
    if [ "''${1:-}" = "--debug" ]; then
      DEBUG_MODE=true
      shift
    fi

    APP_PATH="${systemPackages.wawona-ipados-app-sim}/Wawona.app"
    if [ ! -d "$APP_PATH" ]; then
      echo "Error: Wawona.app not found at $APP_PATH"
      exit 1
    fi
    SIM_NAME="Wawona iPadOS Simulator"
    DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Air-13-inch-M2"
    RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1 || true)
    if [ -z "$RUNTIME" ]; then
      echo "No iOS/iPadOS simulator runtime found. Attempting to provision Xcode automatically..."
      ${xcodeUtils.provisionXcodeScript}/bin/provision-xcode || {
        echo "Error: Failed to provision Xcode. Please open Xcode and install the iOS platform manually."
        exit 1
      }
      RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1 || true)
      if [ -z "$RUNTIME" ]; then
        echo "Error: Provisioning finished but no iOS runtime was found."
        exit 1
      fi
    fi
    SIM_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1 || true)
    if [ -z "$SIM_UDID" ]; then
      echo "Creating simulator '$SIM_NAME'..."
      SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
    fi
    xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true

    echo "Opening Simulator.app..."
    open -a "Simulator" 2>/dev/null || open -a "Simulator.app" 2>/dev/null || true

    echo "Installing Wawona.app (iPadOS) to simulator..."
    TMP_APP_ROOT="/tmp/wawona-ipados-install"
    STAGED_APP="$TMP_APP_ROOT/Wawona.app"
    rm -rf "$TMP_APP_ROOT"
    mkdir -p "$TMP_APP_ROOT"
    cp -R "$APP_PATH" "$STAGED_APP"
    chmod -R u+rwX "$TMP_APP_ROOT" || true
    if ! xcrun simctl install "$SIM_UDID" "$STAGED_APP"; then
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
      echo "Launching Wawona (iPadOS)..."
      xcrun simctl launch "$SIM_UDID" com.aspauldingcode.Wawona "$@"
      exit 0
    fi

    DSYM_PATH="${systemPackages.wawona-ipados-app-sim}/Wawona.app.dSYM"
    echo "Launching Wawona iPadOS (paused at spawn for debugger)..."
    LAUNCH_OUTPUT=$(xcrun simctl launch --wait-for-debugger "$SIM_UDID" com.aspauldingcode.Wawona "$@")
    echo "$LAUNCH_OUTPUT"
    PID=$(echo "$LAUNCH_OUTPUT" | awk '/com.aspauldingcode.Wawona:/ {print $NF}')
    if [ -z "$PID" ]; then
      echo "Error: Could not determine app PID for LLDB attach."
      exit 1
    fi
    xcrun simctl spawn "$SIM_UDID" log stream --style compact --predicate 'process == "Wawona"' &
    LOG_STREAM_PID=$!
    trap "kill $LOG_STREAM_PID 2>/dev/null || true" EXIT INT TERM
    if [ -d "$DSYM_PATH" ]; then
      lldb -Q -o "process attach --pid $PID" -o "target symbols add $DSYM_PATH" -o "continue"
    else
      lldb -Q -o "process attach --pid $PID" -o "continue"
    fi
  ''}/bin/wawona-ipados";

  wawonaTvos = "${pkgs.writeShellScriptBin "wawona-tvos" ''
    set -euo pipefail
    export PATH="${xcodeUtils.xcodeWrapper}/bin:$PATH"
    DEBUG_MODE=false
    if [ "''${1:-}" = "--debug" ]; then
      DEBUG_MODE=true
      shift
    fi

    APP_PATH="${systemPackages.wawona-tvos-app-sim}/Wawona.app"
    if [ ! -d "$APP_PATH" ]; then
      echo "Error: Wawona.app not found at $APP_PATH"
      exit 1
    fi
    SIM_NAME="Wawona tvOS Simulator"
    DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K"
    RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "tvOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1 || true)
    if [ -z "$RUNTIME" ]; then
      echo "No tvOS simulator runtime found. Install tvOS runtime in Xcode."
      exit 1
    fi
    SIM_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1 || true)
    if [ -z "$SIM_UDID" ]; then
      echo "Creating simulator '$SIM_NAME'..."
      SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
    fi
    xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true
    open -a "Simulator" 2>/dev/null || open -a "Simulator.app" 2>/dev/null || true

    TMP_APP_ROOT="/tmp/wawona-tvos-install"
    STAGED_APP="$TMP_APP_ROOT/Wawona.app"
    rm -rf "$TMP_APP_ROOT"
    mkdir -p "$TMP_APP_ROOT"
    cp -R "$APP_PATH" "$STAGED_APP"
    chmod -R u+rwX "$TMP_APP_ROOT" || true
    xcrun simctl install "$SIM_UDID" "$STAGED_APP" || {
      xcrun simctl uninstall "$SIM_UDID" com.aspauldingcode.Wawona 2>/dev/null || true
      xcrun simctl install "$SIM_UDID" "$STAGED_APP"
    }

    if [ "$DEBUG_MODE" != "true" ]; then
      xcrun simctl launch "$SIM_UDID" com.aspauldingcode.Wawona "$@"
      exit 0
    fi

    DSYM_PATH="${systemPackages.wawona-tvos-app-sim}/Wawona.app.dSYM"
    LAUNCH_OUTPUT=$(xcrun simctl launch --wait-for-debugger "$SIM_UDID" com.aspauldingcode.Wawona "$@")
    echo "$LAUNCH_OUTPUT"
    PID=$(echo "$LAUNCH_OUTPUT" | awk '/com.aspauldingcode.Wawona:/ {print $NF}')
    [ -n "$PID" ] || { echo "Error: Could not determine app PID for LLDB attach."; exit 1; }
    xcrun simctl spawn "$SIM_UDID" log stream --style compact --predicate 'process == "Wawona"' &
    LOG_STREAM_PID=$!
    trap "kill $LOG_STREAM_PID 2>/dev/null || true" EXIT INT TERM
    if [ -d "$DSYM_PATH" ]; then
      lldb -Q -o "process attach --pid $PID" -o "target symbols add $DSYM_PATH" -o "continue"
    else
      lldb -Q -o "process attach --pid $PID" -o "continue"
    fi
  ''}/bin/wawona-tvos";

  wawonaWatchos = "${pkgs.writeShellScriptBin "wawona-watchos" ''
    set -euo pipefail
    export PATH="${xcodeUtils.xcodeWrapper}/bin:$PATH"
    DEBUG_MODE=false
    if [ "''${1:-}" = "--debug" ]; then
      DEBUG_MODE=true
      shift
    fi

    APP_PATH="${systemPackages.wawona-watchos-app-sim}/Wawona.app"
    if [ ! -d "$APP_PATH" ]; then
      echo "Error: Wawona.app not found at $APP_PATH"
      exit 1
    fi
    SIM_NAME="Wawona watchOS Simulator"
    DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm"
    RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "watchOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1 || true)
    if [ -z "$RUNTIME" ]; then
      echo "No watchOS simulator runtime found. Attempting to provision Xcode automatically..."
      ${xcodeUtils.provisionXcodeScript}/bin/provision-xcode || {
        echo "Error: Failed to provision Xcode. Please open Xcode and install the watchOS platform manually."
        exit 1
      }
      RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "watchOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1 || true)
      if [ -z "$RUNTIME" ]; then
        echo "Error: Provisioning finished but no watchOS runtime was found."
        exit 1
      fi
    fi
    SIM_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1 || true)
    if [ -z "$SIM_UDID" ]; then
      echo "Creating simulator '$SIM_NAME'..."
      SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
    fi
    xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true

    echo "Opening Simulator.app..."
    open -a "Simulator" 2>/dev/null || open -a "Simulator.app" 2>/dev/null || true

    echo "Installing Wawona.app (watchOS) to simulator..."
    TMP_APP_ROOT="/tmp/wawona-watchos-install"
    STAGED_APP="$TMP_APP_ROOT/Wawona.app"
    rm -rf "$TMP_APP_ROOT"
    mkdir -p "$TMP_APP_ROOT"
    cp -R "$APP_PATH" "$STAGED_APP"
    chmod -R u+rwX "$TMP_APP_ROOT" || true
    if ! xcrun simctl install "$SIM_UDID" "$STAGED_APP"; then
      xcrun simctl terminate "$SIM_UDID" com.aspauldingcode.Wawona.watch 2>/dev/null || true
      xcrun simctl uninstall "$SIM_UDID" com.aspauldingcode.Wawona.watch 2>/dev/null || true
      if ! xcrun simctl install "$SIM_UDID" "$STAGED_APP"; then
        xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true
        xcrun simctl erase "$SIM_UDID" 2>/dev/null || true
        xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
        xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true
        xcrun simctl install "$SIM_UDID" "$STAGED_APP"
      fi
    fi

    if [ "$DEBUG_MODE" != "true" ]; then
      echo "Launching Wawona (watchOS)..."
      xcrun simctl launch "$SIM_UDID" com.aspauldingcode.Wawona.watch "$@"
      exit 0
    fi

    DSYM_PATH="${systemPackages.wawona-watchos-app-sim}/Wawona.app.dSYM"
    echo "Launching Wawona watchOS (paused at spawn for debugger)..."
    LAUNCH_OUTPUT=$(xcrun simctl launch --wait-for-debugger "$SIM_UDID" com.aspauldingcode.Wawona.watch "$@")
    echo "$LAUNCH_OUTPUT"
    PID=$(echo "$LAUNCH_OUTPUT" | awk '/com.aspauldingcode.Wawona.watch:/ {print $NF}')
    if [ -z "$PID" ]; then
      echo "Error: Could not determine app PID for LLDB attach."
      exit 1
    fi
    xcrun simctl spawn "$SIM_UDID" log stream --style compact --predicate 'process == "Wawona"' &
    LOG_STREAM_PID=$!
    trap "kill $LOG_STREAM_PID 2>/dev/null || true" EXIT INT TERM
    if [ -d "$DSYM_PATH" ]; then
      lldb -Q -o "process attach --pid $PID" -o "target symbols add $DSYM_PATH" -o "continue"
    else
      lldb -Q -o "process attach --pid $PID" -o "continue"
    fi
  ''}/bin/wawona-watchos";

  wawonaVisionos = "${pkgs.writeShellScriptBin "wawona-visionos" ''
    set -euo pipefail
    export PATH="${xcodeUtils.xcodeWrapper}/bin:$PATH"
    DEBUG_MODE=false
    if [ "''${1:-}" = "--debug" ]; then
      DEBUG_MODE=true
      shift
    fi

    APP_PATH="${systemPackages.wawona-visionos-app-sim}/Wawona.app"
    if [ ! -d "$APP_PATH" ]; then
      echo "Error: Wawona.app not found at $APP_PATH"
      exit 1
    fi
    SIM_NAME="Wawona visionOS Simulator"
    DEV_TYPE_CANDIDATES=$(xcrun simctl list devicetypes 2>/dev/null | awk -F '[()]' '/Apple Vision Pro/ {print $2}')
    DEV_TYPE=""
    for candidate in $DEV_TYPE_CANDIDATES; do
      DEV_TYPE="$candidate"
      break
    done
    if [ -z "$DEV_TYPE" ]; then
      DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-4K"
    fi
    RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "visionOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1 || true)
    if [ -z "$RUNTIME" ]; then
      echo "No visionOS simulator runtime found. Install visionOS runtime in Xcode."
      exit 1
    fi
    SIM_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1 || true)
    if [ -z "$SIM_UDID" ]; then
      echo "Creating simulator '$SIM_NAME'..."
      CREATED=false
      for candidate in $DEV_TYPE_CANDIDATES "$DEV_TYPE"; do
        [ -n "$candidate" ] || continue
        if SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$candidate" "$RUNTIME" 2>/dev/null); then
          CREATED=true
          break
        fi
      done
      if [ "$CREATED" != "true" ]; then
        echo "Error: Could not create visionOS simulator for runtime $RUNTIME."
        echo "Available Vision device types:"
        xcrun simctl list devicetypes 2>/dev/null | grep -i "Vision" || true
        exit 1
      fi
    fi
    xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true
    open -a "Simulator" 2>/dev/null || open -a "Simulator.app" 2>/dev/null || true

    TMP_APP_ROOT="/tmp/wawona-visionos-install"
    STAGED_APP="$TMP_APP_ROOT/Wawona.app"
    rm -rf "$TMP_APP_ROOT"
    mkdir -p "$TMP_APP_ROOT"
    cp -R "$APP_PATH" "$STAGED_APP"
    chmod -R u+rwX "$TMP_APP_ROOT" || true
    xcrun simctl install "$SIM_UDID" "$STAGED_APP" || {
      xcrun simctl uninstall "$SIM_UDID" com.aspauldingcode.Wawona 2>/dev/null || true
      xcrun simctl install "$SIM_UDID" "$STAGED_APP"
    }

    if [ "$DEBUG_MODE" != "true" ]; then
      xcrun simctl launch "$SIM_UDID" com.aspauldingcode.Wawona "$@"
      exit 0
    fi

    DSYM_PATH="${systemPackages.wawona-visionos-app-sim}/Wawona.app.dSYM"
    LAUNCH_OUTPUT=$(xcrun simctl launch --wait-for-debugger "$SIM_UDID" com.aspauldingcode.Wawona "$@")
    echo "$LAUNCH_OUTPUT"
    PID=$(echo "$LAUNCH_OUTPUT" | awk '/com.aspauldingcode.Wawona:/ {print $NF}')
    [ -n "$PID" ] || { echo "Error: Could not determine app PID for LLDB attach."; exit 1; }
    xcrun simctl spawn "$SIM_UDID" log stream --style compact --predicate 'process == "Wawona"' &
    LOG_STREAM_PID=$!
    trap "kill $LOG_STREAM_PID 2>/dev/null || true" EXIT INT TERM
    if [ -d "$DSYM_PATH" ]; then
      lldb -Q -o "process attach --pid $PID" -o "target symbols add $DSYM_PATH" -o "continue"
    else
      lldb -Q -o "process attach --pid $PID" -o "continue"
    fi
  ''}/bin/wawona-visionos";

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
