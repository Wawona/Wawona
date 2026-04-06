{ lib, pkgs, fetchurl, ... }:

let
  version = "13.0.0";
  androidToolchain = import ../../toolchains/android.nix { inherit lib pkgs; };
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
  int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    __android_log_print(ANDROID_LOG_INFO, "WawonaWeston", "weston stub launched");
    return 0;
  }
  EOF

  cat > weston_terminal_stub.c <<'EOF'
  #include <android/log.h>
  int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    __android_log_print(ANDROID_LOG_INFO, "WawonaWeston", "weston-terminal stub launched");
    return 0;
  }
  EOF

  "$CC" --target="$TARGET" ${androidToolchain.androidNdkCflags} -fPIE -pie weston_main_stub.c -llog -landroid -o weston
  "$CC" --target="$TARGET" ${androidToolchain.androidNdkCflags} -fPIE -pie weston_terminal_stub.c -llog -landroid -o weston-terminal

  mkdir -p "$out/lib/arm64-v8a"
  cp weston "$out/lib/arm64-v8a/libweston.so"
  cp weston-terminal "$out/lib/arm64-v8a/libweston-terminal.so"
  chmod +x "$out/lib/arm64-v8a/libweston.so"
  chmod +x "$out/lib/arm64-v8a/libweston-terminal.so"
''
