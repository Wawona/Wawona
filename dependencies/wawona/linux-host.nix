{
  pkgs,
  wawonaVersion,
  wawonaSrc ? ../..,
  waypipeSrc ? null,
  ...
}:

pkgs.writeShellApplication {
  name = "wawona-linux-compositor-host-run";
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
    pkgs.weston
    (pkgs.callPackage ../libs/weston-simple-shm/linux.nix {})
    pkgs.foot
    pkgs.coreutils
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

    exec cargo run --manifest-path "$workdir/Cargo.toml" --bin wawona-linux-compositor-host --features linux-ui -- "$@"
  '';
  meta = {
    description = "Wawona Linux compositor host";
    platforms = pkgs.lib.platforms.linux;
  };
}
