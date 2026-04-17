let
  macosEnv = ''
    uid="$(id -u)"
    runtime_dir_default="/tmp/wawona-$uid"
    runtime_env_file="$runtime_dir_default/wawona-env.sh"

    # Prefer compositor-exported runtime values when available.
    if [ -f "$runtime_env_file" ]; then
      # shellcheck source=/dev/null
      . "$runtime_env_file" || true
    fi

    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$runtime_dir_default}"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
    if [ ! -d "$XDG_RUNTIME_DIR" ]; then
      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"
    fi
    SOCKET_PATH="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

    # If the service socket is missing, try to revive the compositor host agent.
    if [ ! -S "$SOCKET_PATH" ] && command -v launchctl >/dev/null 2>&1; then
      launchctl kickstart -k "gui/$uid/com.aspauldingcode.wawona.compositorhost" >/dev/null 2>&1 || true
      # Refresh from exported env (compositor may rewrite display/socket choice).
      if [ -f "$runtime_env_file" ]; then
        # shellcheck source=/dev/null
        . "$runtime_env_file" || true
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$runtime_dir_default}"
        export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
        SOCKET_PATH="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
      fi
      i=0
      while [ ! -S "$SOCKET_PATH" ] && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
      done
    fi

    if [ ! -S "$SOCKET_PATH" ]; then
      echo "Warning: Wayland socket not ready at $SOCKET_PATH." >&2
      echo "Hint: run 'nix run .#install' for persistent Wawona menubar/compositor launch agents." >&2
    fi
  '';
in rec {
  unixWrapper = pkgs: name: bin:
    pkgs.writeShellScriptBin name ''
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/tmp/$(id -u)-runtime}"
      export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
      exec ${bin} "$@"
    '';

  toolWrapper = pkgs: tools: binName:
    (unixWrapper pkgs binName "${tools}/bin/${binName}");

  inherit macosEnv;

  macosWrapper = pkgs: wawona: pkgs.writeShellScriptBin "wawona" ''
    APP="${wawona}/Applications/Wawona.app"
    export WAWONA_APP_BIN="$APP/Contents/MacOS/Wawona"
    ${macosEnv}
    if [ "''${1:-}" = "--debug" ] || [ "''${WAWONA_LLDB:-0}" = "1" ]; then
      [ "''${1:-}" = "--debug" ] && shift
      echo "[DEBUG] Starting Wawona under LLDB..."
      exec ${pkgs.lldb}/bin/lldb -o run -o "bt all" -- "$APP/Contents/MacOS/Wawona" "$@"
    else
      exec "$APP/Contents/MacOS/Wawona" "$@"
    fi
  '';

  waypipeWrapper = pkgs: waypipe: wawona: pkgs.writeShellScriptBin "waypipe" ''
    export WAWONA_APP_BIN="${wawona}/Applications/Wawona.app/Contents/MacOS/Wawona"
    ${macosEnv}
    # Point Vulkan loader at KosmicKrisp ICD if available and not overridden
    if [ -z "''${VK_DRIVER_FILES:-}" ]; then
      # Check app bundle first (when launched from Wawona.app)
      APP_ICD="$(dirname "$(dirname "$0")")/Resources/vulkan/icd.d/kosmickrisp_icd.json"
      if [ -f "$APP_ICD" ]; then
        export VK_DRIVER_FILES="$APP_ICD"
      fi
    fi
    exec "${waypipe}/bin/waypipe" "$@"
  '';

  footWrapper = pkgs: foot: wawona: pkgs.writeShellScriptBin "foot" ''
    export WAWONA_APP_BIN="${wawona}/Applications/Wawona.app/Contents/MacOS/Wawona"
    ${macosEnv}

    # Check if user has a config
    if [ ! -f "$HOME/.config/foot/foot.ini" ] && [ ! -f "''${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini" ]; then
      echo "Info: No foot.ini found, using default macOS configuration (Menlo font)"
      DEFAULT_CONFIG="''${XDG_RUNTIME_DIR}/foot-default.ini"
      cat > "$DEFAULT_CONFIG" <<EOF
[main]
font=monospace:size=12
dpi-aware=yes

[tweak]
font-monospace-warn=no
EOF
      exec "${foot}/bin/foot" -o tweak.font-monospace-warn=no -c "$DEFAULT_CONFIG" "$@"
    else
      exec "${foot}/bin/foot" -o tweak.font-monospace-warn=no "$@"
    fi
  '';

  westonAppWrapper = pkgs: weston: wawona: binName: pkgs.writeShellScriptBin binName ''
    export WAWONA_APP_BIN="${wawona}/Applications/Wawona.app/Contents/MacOS/Wawona"
    ${macosEnv}
    child_pid=""
    forward_sigint() {
      if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
        kill -INT "$child_pid" 2>/dev/null || true
      fi
    }
    forward_sigterm() {
      if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
        kill -TERM "$child_pid" 2>/dev/null || true
      fi
    }
    trap forward_sigint INT
    trap forward_sigterm TERM HUP

    # Bringing the compositor app to foreground helps nested Weston windows
    # become key/focused when launched from terminal.
    if command -v osascript >/dev/null 2>&1; then
      (
        sleep 0.25
        osascript -e 'tell application id "com.aspauldingcode.Wawona" to activate' >/dev/null 2>&1 || true
      ) &
    fi

    "${weston}/bin/${binName}" "$@" &
    child_pid=$!
    wait "$child_pid"
    exit_code=$?
    trap - INT TERM HUP
    exit "$exit_code"
  '';

  iosWrapper = pkgs: wawona: pkgs.writeShellScriptBin "wawona-ios" ''
    export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
    exec "${wawona}/bin/wawona-ios-simulator" "$@"
  '';

  androidWrapper = pkgs: wawona: pkgs.writeShellScriptBin "wawona-android" ''
    export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
    exec "${wawona}/bin/wawona-android-run" "$@"
  '';

  linuxWrapper = pkgs: wawona: pkgs.writeShellScriptBin "wawona" ''
    export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
    exec "${wawona}/bin/wawona" "$@"
  '';
}
