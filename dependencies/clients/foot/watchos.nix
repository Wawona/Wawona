{ lib, stdenv, pkgs, simulator ? false, ... }:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  sdkName    = if simulator then "WatchSimulator" else "WatchOS";
  minVerFlag = if simulator then "-mwatchos-simulator-version-min=10.0" else "-mwatchos-version-min=10.0";
in
stdenv.mkDerivation {
  pname = "foot-watchos-shim";
  version = "1.0.0";
  dontUnpack = true;
  nativeBuildInputs = [ xcodeUtils.findXcodeScript ];
  buildPhase = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      fi
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkName}.platform/Developer/SDKs/${sdkName}.sdk"
    CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
    cat > foot_shim.c <<'EOF'
    extern int weston_simple_shm_main(int argc, char **argv);
    int wwn_foot_is_compat_shim(void) { return 1; }
    int foot_main(int argc, char **argv) {
      (void)argc; (void)argv;
      char *shim_argv[] = { "weston-simple-shm", 0 };
      return weston_simple_shm_main(1, shim_argv);
    }
EOF
    "$CLANG" -c foot_shim.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC -o foot_shim.o
    "$AR" rcs libfoot.a foot_shim.o
  '';
  installPhase = ''
    mkdir -p $out/lib
    cp libfoot.a $out/lib/
  '';
  meta.platforms = lib.platforms.darwin;
}
