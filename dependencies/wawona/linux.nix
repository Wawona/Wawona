{
  pkgs,
  wawonaVersion,
  wawonaSrc ? ../..,
  waypipeSrc ? null,
  coreutilsSrc ? null,
  westonSimpleShmLinuxNix,
  ...
}:

pkgs.writeShellApplication {
  name = "wawona-linux-run";
  runtimeInputs = [
    pkgs.cargo
    pkgs.rustc
    pkgs.pkg-config
    pkgs.stdenv.cc
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
    pkgs.neovim
    pkgs.zsh
    pkgs.kmscube
    pkgs.systemd
    pkgs.coreutils
    pkgs.lldb
  ];
  text = ''
    set -euo pipefail
    export PKG_CONFIG_PATH="${pkgs.glib.dev}/lib/pkgconfig:${pkgs.gtk4.dev}/lib/pkgconfig:${pkgs.libadwaita.dev}/lib/pkgconfig:${pkgs.cairo.dev}/lib/pkgconfig:${pkgs.pango.dev}/lib/pkgconfig:${pkgs.gdk-pixbuf.dev}/lib/pkgconfig:${pkgs.graphene.dev}/lib/pkgconfig:${pkgs.harfbuzz.dev}/lib/pkgconfig:${pkgs.fribidi.dev}/lib/pkgconfig:${pkgs.freetype.dev}/lib/pkgconfig:${pkgs.fontconfig.dev}/lib/pkgconfig:${pkgs.wayland.dev}/lib/pkgconfig:${pkgs.libxkbcommon.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libffi.dev}/lib/pkgconfig:${pkgs.zstd.dev}/lib/pkgconfig:${pkgs.lz4.dev}/lib/pkgconfig:${pkgs.vulkan-loader.dev}/lib/pkgconfig"
    export LD_LIBRARY_PATH="${pkgs.glib.out}/lib:${pkgs.gtk4}/lib:${pkgs.libadwaita}/lib:${pkgs.cairo.out}/lib:${pkgs.pango.out}/lib:${pkgs.gdk-pixbuf.out}/lib:${pkgs.graphene}/lib:${pkgs.harfbuzz.out}/lib:${pkgs.fribidi}/lib:${pkgs.freetype}/lib:${pkgs.fontconfig.lib}/lib:${pkgs.wayland}/lib:${pkgs.libxkbcommon}/lib:${pkgs.openssl.out}/lib:${pkgs.libffi.out}/lib:${pkgs.zstd.out}/lib:${pkgs.lz4}/lib:${pkgs.vulkan-loader}/lib:''${LD_LIBRARY_PATH:-}"
    export LIBRARY_PATH="$LD_LIBRARY_PATH"
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT

    cp -rL "${wawonaSrc}"/. "$workdir"/
    chmod -R u+w "$workdir"

    if [ ! -f "$workdir/waypipe/Cargo.toml" ]; then
      mkdir -p "$workdir/waypipe"
      cp -rL "${waypipeSrc}"/. "$workdir/waypipe"/
      chmod -R u+w "$workdir/waypipe"
    fi

    if [ ! -f "$workdir/waypipe/Cargo.toml" ]; then
      echo "Missing ./waypipe dependency and failed to stage waypipe source." >&2
      exit 1
    fi

    # Cargo resolves the optional ./coreutils path dependency even when the
    # feature is disabled, so the manifest must exist in the staged workspace.
    if [ ! -f "$workdir/coreutils/Cargo.toml" ]; then
      mkdir -p "$workdir/coreutils"
      cp -rL "${coreutilsSrc}"/. "$workdir/coreutils"/
      chmod -R u+w "$workdir/coreutils"
    fi

    if [ ! -f "$workdir/coreutils/Cargo.toml" ]; then
      echo "Missing ./coreutils dependency and failed to stage coreutils source." >&2
      exit 1
    fi

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

    if [ "$DEBUG_MODE" = "true" ]; then
      echo "[LLDB] Building then launching under LLDB (--debug). Freeze? process interrupt" >&2
      cargo build --manifest-path "$workdir/Cargo.toml" --bin wawona-linux-ui --features linux-ui
      BIN="$workdir/target/debug/wawona-linux-ui"
      if [ ! -x "$BIN" ]; then
        echo "Error: expected binary missing at $BIN" >&2
        exit 1
      fi
      exec lldb \
        -O "target create \"$BIN\"" \
        -O "target stop-hook add -o 'thread backtrace all'" \
        -O "run" \
        -- "$@"
    fi

    exec cargo run --manifest-path "$workdir/Cargo.toml" --bin wawona-linux-ui --features linux-ui -- "$@"
  '';
  meta = {
    description = "Wawona Linux GTK nested compositor client";
    platforms = pkgs.lib.platforms.linux;
  };
}
