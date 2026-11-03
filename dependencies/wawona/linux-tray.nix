{
  pkgs,
  wawonaVersion,
  wawonaLinuxUiBin ? null,
  ...
}:

# Prefer the ahead-of-time binary from linux-ui-prebuilt.nix (same pattern as
# linux.nix). JIT `cargo run` was hermetic-hostile and slow for release gates.
pkgs.writeShellApplication {
  name = "wawona-linux-tray-run";
  runtimeInputs = [
    pkgs.gtk4
    pkgs.libadwaita
    pkgs.glib
    pkgs.cairo
    pkgs.pango
    pkgs.gdk-pixbuf
    pkgs.graphene
    pkgs.harfbuzz
    pkgs.fribidi
    pkgs.freetype
    pkgs.fontconfig
    pkgs.wayland
    pkgs.libxkbcommon
    pkgs.openssl
    pkgs.libffi
    pkgs.zstd
    pkgs.lz4
    pkgs.vulkan-loader
    pkgs.systemd
    pkgs.coreutils
    pkgs.lldb
  ];
  # Strip CR so a CRLF-checked-out tree (issue #164) cannot poison the wrapper.
  text = builtins.replaceStrings ["\r"] [""] ''
    set -euo pipefail
    export PATH="''${HOME}/.local/bin:''${PATH:-}"

    DEBUG_MODE=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --debug) DEBUG_MODE=true; shift ;;
        --no-debug|--release) shift ;;
        *) break ;;
      esac
    done
    if [ "''${WAWONA_LLDB:-0}" = "1" ]; then DEBUG_MODE=true; fi
    if [ "''${WAWONA_NO_LLDB:-0}" = "1" ]; then DEBUG_MODE=false; fi

    BIN="${if wawonaLinuxUiBin != null then "${wawonaLinuxUiBin}/bin/wawona-linux-tray" else ""}"
    if [ -n "''${WAWONA_TRAY_BIN:-}" ] && [ -x "$WAWONA_TRAY_BIN" ]; then
      BIN="$WAWONA_TRAY_BIN"
    fi
    if [ -n "$BIN" ] && [ -x "$BIN" ]; then
      if [ "$DEBUG_MODE" = "true" ]; then
        echo "[LLDB] Launching under LLDB (--debug)." >&2
        exec lldb \
          -O "target create \"$BIN\"" \
          -O "target stop-hook add -o 'thread backtrace all'" \
          -O "run" \
          -- "$@"
      fi
      exec "$BIN" "$@"
    fi

    echo "Error: wawonaLinuxUiBin missing or tray not executable" >&2
    exit 1
  '';
  meta = {
    description = "Wawona Linux tray applet";
    platforms = pkgs.lib.platforms.linux;
  };
}
