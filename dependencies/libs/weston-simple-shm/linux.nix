{
  pkgs,
  lib,
  stdenv,
  fetchurl,
  pkg-config,
  wayland-scanner,
  wayland,
  wayland-protocols,
  libxkbcommon,
  pixman,
  weston,
  ...
}:
stdenv.mkDerivation rec {
  pname = "weston-simple-shm";
  version = "13.0.0";

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    wayland
    libxkbcommon
    pixman
    weston
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cat > config.h <<'EOF'
    #define VERSION "${version}"
    EOF

    WAYLAND_PROTOCOLS_DATADIR="${wayland-protocols}/share/wayland-protocols"
    wayland-scanner client-header "$WAYLAND_PROTOCOLS_DATADIR/stable/xdg-shell/xdg-shell.xml" xdg-shell-client-protocol.h
    wayland-scanner private-code "$WAYLAND_PROTOCOLS_DATADIR/stable/xdg-shell/xdg-shell.xml" xdg-shell-protocol.c
    wayland-scanner client-header "$WAYLAND_PROTOCOLS_DATADIR/unstable/fullscreen-shell/fullscreen-shell-unstable-v1.xml" fullscreen-shell-unstable-v1-client-protocol.h
    wayland-scanner private-code "$WAYLAND_PROTOCOLS_DATADIR/unstable/fullscreen-shell/fullscreen-shell-unstable-v1.xml" fullscreen-shell-unstable-v1-protocol.c

    gcc \
      -D_GNU_SOURCE \
      -I. \
      -Iinclude \
      -I"${weston}/include/libweston-15" \
      clients/simple-shm.c \
      shared/os-compatibility.c \
      xdg-shell-protocol.c \
      fullscreen-shell-unstable-v1-protocol.c \
      $(pkg-config --cflags --libs wayland-client xkbcommon pixman-1) \
      -o weston-simple-shm

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    install -m755 weston-simple-shm "$out/bin/weston-simple-shm"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Standalone Weston simple-shm client for Linux Wawona bundles";
    platforms = platforms.linux;
  };
}
