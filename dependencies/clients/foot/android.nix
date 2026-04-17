{
  lib,
  pkgs,
  buildPackages,
  common,
  androidToolchain,
  buildModule ? null,
}:

pkgs.runCommand "foot-android-1.25.0" { } ''
  CC="${androidToolchain.androidCC}"
  API="${toString androidToolchain.androidNdkApiLevel}"

  cat > foot_stub.c <<'EOF'
  #include <android/log.h>
  int wwn_foot_is_compat_shim(void) { return 1; }
  int foot_main(int argc, const char **argv) {
    (void)argc;
    (void)argv;
    __android_log_print(ANDROID_LOG_INFO, "WawonaFoot", "foot placeholder launched (native port in progress)");
    return 0;
  }
  EOF

  # Match dependencies/toolchains/android.nix adaptive/prebuilt driver: API-qualified triple + sysroot + crt paths.
  "$CC" \
    --target="${androidToolchain.androidTarget}$API" \
    --sysroot="${androidToolchain.androidNdkSysroot}" \
    -B"${androidToolchain.androidNdkAbiLibDir}" \
    -L"${androidToolchain.androidNdkAbiLibDir}" \
    -Wl,-rpath-link,"${androidToolchain.androidNdkAbiLibDir}" \
    ${androidToolchain.androidNdkCflags} \
    -D__ANDROID_API__="$API" \
    -fPIC -shared foot_stub.c -llog -landroid -o libfoot.so

  mkdir -p "$out/lib/arm64-v8a"
  cp libfoot.so "$out/lib/arm64-v8a/"
''
