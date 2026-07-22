let
  mkLldbHelpers = pkgs:
    let
      lldb = pkgs.lldb;
      # Stop-hook + signal handlers require an active target (after binary load or attach).
      lldbPostTargetOpts = ''
        -O "target stop-hook add -o 'thread backtrace all'" \
        -O "process handle SIGINT -s true -n false -p true" \
        -O "process handle SIGTRAP -s true -n false -p true" \
        -O "process handle SIGSEGV -s true -n false -p true" \
        -O "process handle SIGABRT -s true -n false -p true" \
        -O "process handle SIGBUS -s true -n false -p true" \
        -O "process handle SIGILL -s true -n false -p true" \
      '';
      hangHint = ''
        echo "[LLDB] Debugger attached for the whole run (opt-in via --debug)."
        echo "[LLDB] Crash/halt → LLDB stops and prints 'thread backtrace all'."
        echo "[LLDB] Freeze/hang?  process interrupt   (pause — backtraces print on stop)"
        echo "[LLDB] Resume: continue           Quit: quit"
      '';
    in {
      runUnderLldb = pkgs.writeShellScriptBin "wawona-lldb-run" ''
        set -euo pipefail
        if [ "$#" -lt 1 ]; then
          echo "usage: wawona-lldb-run <binary> [args...]" >&2
          exit 2
        fi
        BINARY="$1"
        shift
        if [ ! -x "$BINARY" ]; then
          echo "Error: binary not executable: $BINARY" >&2
          exit 1
        fi
        # Accept Mach-O (macOS) or ELF (Linux) so flake apps share one helper.
        if ! file "$BINARY" 2>/dev/null | grep -qE 'Mach-O.*executable|ELF.*executable'; then
          echo "Error: not a Mach-O/ELF executable: $BINARY" >&2
          exit 1
        fi
        ${hangHint}
        # -O commands run before positional args create a target; create explicitly first.
        exec ${lldb}/bin/lldb \
          -O "target create \"''${BINARY}\"" \
          -O "settings set target.process.follow-fork-mode child" \
          ${lldbPostTargetOpts} \
          -O "run" \
          -- "$@"
      '';
      attachLldb = pkgs.writeShellScriptBin "wawona-lldb-attach" ''
        set -euo pipefail
        if [ "$#" -lt 1 ]; then
          echo "usage: wawona-lldb-attach <pid> [dsym-path]" >&2
          exit 2
        fi
        PID="$1"
        DSYM="''${2:-}"
        ${hangHint}
        if [ -n "$DSYM" ] && [ -d "$DSYM" ]; then
          exec ${lldb}/bin/lldb \
            -O "process attach --continue --pid $PID" \
            -O "target symbols add ''${DSYM}" \
            ${lldbPostTargetOpts}
        else
          exec ${lldb}/bin/lldb \
            -O "process attach --continue --pid $PID" \
            ${lldbPostTargetOpts}
        fi
      '';
      simAttachLldb = pkgs.writeShellScriptBin "wawona-lldb-sim" ''
        set -euo pipefail
        if [ "$#" -lt 1 ]; then
          echo "usage: wawona-lldb-sim <pid> [dsym-path]" >&2
          exit 2
        fi
        PID="$1"
        DSYM="''${2:-}"
        ${hangHint}
        if [ -n "$DSYM" ] && [ -d "$DSYM" ]; then
          exec ${lldb}/bin/lldb \
            -O "process attach --pid $PID" \
            -O "target symbols add ''${DSYM}" \
            ${lldbPostTargetOpts} \
            -O "continue"
        else
          exec ${lldb}/bin/lldb \
            -O "process attach --pid $PID" \
            ${lldbPostTargetOpts} \
            -O "continue"
        fi
      '';
    };

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

  inherit macosEnv mkLldbHelpers;

  macosWrapper = pkgs: wawona:
    let
      lldb = mkLldbHelpers pkgs;
      dsym = "${wawona}/Applications/Wawona.app.dSYM";
      binaryReadyCheck = ''
        wawona_binary_ready() {
          if [ ! -d "$APP" ] || [ ! -x "$BIN" ]; then
            echo "Error: Wawona.app or binary missing — build may have failed." >&2
            return 1
          fi
          if ! file "$BIN" 2>/dev/null | grep -qE 'Mach-O.*executable'; then
            echo "Error: $BIN is not a Mach-O executable — build may be broken." >&2
            return 1
          fi
          return 0
        }
      '';
    in
    pkgs.writeShellScriptBin "wawona" ''
      APP="${wawona}/Applications/Wawona.app"
      BIN="$APP/Contents/MacOS/Wawona"
      export WAWONA_APP_BIN="$BIN"
      ${binaryReadyCheck}
      ${macosEnv}

      # Default: no debugger. Opt in with --debug / WAWONA_LLDB=1.
      # --debug-attach: attach LLDB to an already-running freeze.
      # --no-debug / --release / WAWONA_NO_LLDB=1: accepted no-ops (compat).
      DEBUG_MODE=false
      ATTACH_MODE=false
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --debug) DEBUG_MODE=true; shift ;;
          --debug-attach) ATTACH_MODE=true; shift ;;
          --no-debug|--release) shift ;;
          *) break ;;
        esac
      done
      if [ "''${WAWONA_LLDB:-0}" = "1" ]; then
        DEBUG_MODE=true
      fi
      if [ "''${WAWONA_NO_LLDB:-0}" = "1" ]; then
        DEBUG_MODE=false
        ATTACH_MODE=false
      fi

      wawona_binary_ready || exit 1

      if [ "$ATTACH_MODE" = "true" ]; then
        PID=$(pgrep -x Wawona 2>/dev/null | head -1 || true)
        if [ -z "$PID" ]; then
          echo "Error: no running Wawona process found." >&2
          echo "Launch first: nix run .#wawona-macos" >&2
          echo "Or start under LLDB: nix run .#wawona-macos -- --debug" >&2
          exit 1
        fi
        if ! kill -0 "$PID" 2>/dev/null; then
          echo "Error: Wawona PID $PID is not running." >&2
          exit 1
        fi
        echo "[LLDB] Attaching to Wawona PID $PID (freeze catch: process interrupt)..."
        if [ -d "${dsym}" ]; then
          exec ${lldb.attachLldb}/bin/wawona-lldb-attach "$PID" "${dsym}"
        else
          exec ${lldb.attachLldb}/bin/wawona-lldb-attach "$PID"
        fi
      fi

      if [ "$DEBUG_MODE" = "true" ]; then
        echo "[LLDB] Launching under LLDB (--debug). Freeze? process interrupt"
        exec ${lldb.runUnderLldb}/bin/wawona-lldb-run "$BIN" "$@"
      fi

      exec "$BIN" "$@"
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
