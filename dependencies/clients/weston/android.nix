{
  lib,
  pkgs,
  fetchurl,
  buildModule,
  androidToolchain,
  ...
}:

let
  version = "13.0.0";
  westonClientSrc = pkgs.callPackage ../../libs/weston-simple-shm/patched-src.nix { };
  libwayland = buildModule.buildForAndroid "libwayland" { };
in
pkgs.runCommand "weston-android-13.0.0" { } ''
  CC="${androidToolchain.androidCC}"
  TARGET="${androidToolchain.androidTarget}"

  # Keep upstream-pinned source for reproducibility metadata.
  : ${fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  }}

  cat > weston_main_stub.c <<'EOF'
  #include <android/log.h>
  int wwn_weston_is_compat_shim(void) { return 1; }
  int weston_main(int argc, const char **argv) {
    (void)argc;
    (void)argv;
    __android_log_print(ANDROID_LOG_INFO, "WawonaWeston", "weston placeholder launched (native port in progress)");
    return 0;
  }
  EOF

  cp ${./mobile-weston-terminal.c} ./weston_terminal_mobile.c
  cp ${westonClientSrc}/xdg-shell-protocol.c ./xdg-shell-protocol.c
  cp ${westonClientSrc}/xdg-shell-client-protocol.h ./xdg-shell-client-protocol.h

  "$CC" --target="$TARGET" ${androidToolchain.androidNdkCflags} -fPIC -shared weston_main_stub.c -llog -landroid -o libweston.so
  "$CC" --target="$TARGET" ${androidToolchain.androidNdkCflags} -fPIC -shared \
    weston_terminal_mobile.c xdg-shell-protocol.c \
    -I. -I${westonClientSrc}/include -I${libwayland}/include -I${libwayland}/include/wayland \
    -L${libwayland}/lib -lwayland-client -llog -landroid -o libweston-terminal.so

  mkdir -p "$out/lib/arm64-v8a"
  cp libweston.so "$out/lib/arm64-v8a/"
  cp libweston-terminal.so "$out/lib/arm64-v8a/"
''
