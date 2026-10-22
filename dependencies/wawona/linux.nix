{
  pkgs,
  wawonaVersion,
  wawonaSrc ? ../..,
  waypipeSrc ? null,
  coreutilsSrc ? null,
  terminalSrc ? null,
  wawonaLinuxUiBin ? null,
  westonSimpleShmLinuxNix,
  # phoon (wwn-phoon-rs): clean-room Rust moon-phase utility. Bundled on Linux
  # via the toolchain build; falls back to absent if not provided.
  phoon ? null,
  ...
}:

pkgs.writeShellApplication {
  name = "wawona-linux-run";
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
    pkgs.openssh
    pkgs.waypipe
    pkgs.weston
    (pkgs.callPackage westonSimpleShmLinuxNix {})
    pkgs.foot
    pkgs.fastfetch
    pkgs.zsh
    pkgs.kmscube
    pkgs.systemd
    pkgs.coreutils
    pkgs.lldb
    pkgs.cloud-hypervisor
  ] ++ pkgs.lib.optional (phoon != null) phoon;
  text = ''
    set -euo pipefail
    export PATH="''${HOME}/.local/bin:''${PATH:-}"

    # Default: no debugger. Opt in with --debug / WAWONA_LLDB=1.
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

    BIN="${if wawonaLinuxUiBin != null then "${wawonaLinuxUiBin}/bin/wawona-linux-ui" else ""}"
    if [ -n "''${WAWONA_UI_BIN:-}" ] && [ -x "$WAWONA_UI_BIN" ]; then
      BIN="$WAWONA_UI_BIN"
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

    echo "Error: wawonaLinuxUiBin missing or not executable" >&2
    exit 1
  '';
  meta = {
    description = "Wawona Linux GTK nested compositor client";
    platforms = pkgs.lib.platforms.linux;
  };
}
