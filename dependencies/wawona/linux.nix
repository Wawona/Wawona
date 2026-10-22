{
  pkgs,
  wawonaVersion,
  wawonaSrc ? ../..,
  waypipeSrc ? null,
  coreutilsSrc ? null,
  terminalSrc ? null,
  westonSimpleShmLinuxNix,
  # phoon (wwn-phoon-rs): clean-room Rust moon-phase utility. Bundled on Linux
  # via the toolchain build; falls back to absent if not provided.
  phoon ? null,
  ...
}:

pkgs.writeShellApplication {
  name = "wawona-linux-run";
  excludeShellChecks = [ "SC2157" ];
  runtimeInputs = [
    pkgs.cargo
    pkgs.rustc
    pkgs.python3
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
    pkgs.zsh
    pkgs.kmscube
    pkgs.systemd
    pkgs.coreutils
    pkgs.lldb
    pkgs.cloud-hypervisor
  ] ++ pkgs.lib.optional (phoon != null) phoon;
  text = ''
    set -euo pipefail
    export PKG_CONFIG_PATH="${pkgs.glib.dev}/lib/pkgconfig:${pkgs.gtk4.dev}/lib/pkgconfig:${pkgs.libadwaita.dev}/lib/pkgconfig:${pkgs.cairo.dev}/lib/pkgconfig:${pkgs.pango.dev}/lib/pkgconfig:${pkgs.gdk-pixbuf.dev}/lib/pkgconfig:${pkgs.graphene.dev}/lib/pkgconfig:${pkgs.harfbuzz.dev}/lib/pkgconfig:${pkgs.fribidi.dev}/lib/pkgconfig:${pkgs.freetype.dev}/lib/pkgconfig:${pkgs.fontconfig.dev}/lib/pkgconfig:${pkgs.wayland.dev}/lib/pkgconfig:${pkgs.libxkbcommon.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libffi.dev}/lib/pkgconfig:${pkgs.zstd.dev}/lib/pkgconfig:${pkgs.lz4.dev}/lib/pkgconfig:${pkgs.vulkan-loader.dev}/lib/pkgconfig"
    export LD_LIBRARY_PATH="${pkgs.glib.out}/lib:${pkgs.gtk4}/lib:${pkgs.libadwaita}/lib:${pkgs.cairo.out}/lib:${pkgs.pango.out}/lib:${pkgs.gdk-pixbuf.out}/lib:${pkgs.graphene}/lib:${pkgs.harfbuzz.out}/lib:${pkgs.fribidi}/lib:${pkgs.freetype}/lib:${pkgs.fontconfig.lib}/lib:${pkgs.wayland}/lib:${pkgs.libxkbcommon}/lib:${pkgs.openssl.out}/lib:${pkgs.libffi.out}/lib:${pkgs.zstd.out}/lib:${pkgs.lz4}/lib:${pkgs.vulkan-loader}/lib:''${LD_LIBRARY_PATH:-}"
    export LIBRARY_PATH="$LD_LIBRARY_PATH"
    export PATH="''${HOME}/.local/bin:''${PATH:-}"
    workdir="$(mktemp -d)"
    trap 'chmod -R u+w "$workdir" 2>/dev/null || true; rm -rf "$workdir"' EXIT

    cp -rP "${wawonaSrc}"/. "$workdir"/
    chmod -R u+w "$workdir"

    # Terminal screen and kitty are symlinks into the sibling Terminal repo.
    # Replace broken symlinks with terminalSrc if provided.
    ${if terminalSrc != null then ''
    rm -f "$workdir/src/term/screen.rs" "$workdir/src/term/kitty.rs"
    cp "${terminalSrc}/src/screen.rs" "$workdir/src/term/screen.rs"
    if [ -f "${terminalSrc}/src/kitty.rs" ]; then
      cp "${terminalSrc}/src/kitty.rs" "$workdir/src/term/kitty.rs"
    fi
    chmod u+w "$workdir/src/term/screen.rs" "$workdir/src/term/kitty.rs" 2>/dev/null || true
    '' else ""}

    rm -rf "$workdir/waypipe" "$workdir/coreutils"

    if [ -n "${toString waypipeSrc}" ]; then
      mkdir -p "$workdir/waypipe"
      cp -rL "${waypipeSrc}"/. "$workdir/waypipe"/
      chmod -R u+w "$workdir/waypipe"
      rm -f "$workdir/waypipe/Cargo.lock"
      if [ -f "$workdir/scripts/lib/expand_uutils_workspace_deps.py" ]; then
        python3 "$workdir/scripts/lib/expand_uutils_workspace_deps.py" --waypipe "$workdir/waypipe"
      fi
    fi

    if [ ! -f "$workdir/waypipe/Cargo.toml" ]; then
      echo "Missing ./waypipe dependency and failed to stage waypipe source." >&2
      exit 1
    fi

    # Cargo resolves the optional ./coreutils path dependency even when the
    # feature is disabled, so the manifest must exist in the staged workspace.
    if [ -n "${toString coreutilsSrc}" ]; then
      mkdir -p "$workdir/coreutils"
      cp -rL "${coreutilsSrc}"/. "$workdir/coreutils"/
      chmod -R u+w "$workdir/coreutils"
      rm -f "$workdir/coreutils/Cargo.lock"
      if [ -f "$workdir/scripts/lib/expand_uutils_workspace_deps.py" ]; then
        python3 "$workdir/scripts/lib/expand_uutils_workspace_deps.py" "$workdir/coreutils"
      fi
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
