let
  macosEnv = ''
    export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
    if [ ! -d "$XDG_RUNTIME_DIR" ]; then
      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"
    fi
    SOCKET_PATH="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
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
font=Menlo:size=12,Monaco:size=12,monospace:size=12
dpi-aware=yes
EOF
      exec "${foot}/bin/foot" -c "$DEFAULT_CONFIG" "$@"
    else
      exec "${foot}/bin/foot" "$@"
    fi
  '';

  westonAppWrapper = pkgs: weston: wawona: binName: pkgs.writeShellScriptBin binName ''
    export WAWONA_APP_BIN="${wawona}/Applications/Wawona.app/Contents/MacOS/Wawona"
    ${macosEnv}
    child_pid=""
    forward_sigterm() {
      if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
        kill -TERM "$child_pid" 2>/dev/null || true
      fi
    }
    trap forward_sigterm INT TERM HUP
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
