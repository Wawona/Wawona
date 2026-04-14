{ lib, pkgs, buildPackages, common, buildModule, simulator ? false, iosToolchain ? null }:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  westonSimpleShmSrc = pkgs.callPackage ./patched-src.nix { };
  libwayland = buildModule.buildForWatchOS "libwayland" { inherit simulator; };
  epollShim  = buildModule.buildForWatchOS "epoll-shim"  { inherit simulator; };
  sdkName    = if simulator then "WatchSimulator" else "WatchOS";
  xcrunSdk   = if simulator then "watchsimulator" else "watchos";
  minVerFlag = if simulator then "-mwatchos-simulator-version-min=10.0" else "-mwatchos-version-min=10.0";
in
pkgs.stdenv.mkDerivation {
  name = "libweston-simple-shm-watchos";
  src = westonSimpleShmSrc;
  __noChroot = true;
  nativeBuildInputs = [ xcodeUtils.findXcodeScript ];
  buildPhase = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkName}.platform/Developer/SDKs/${sdkName}.sdk"
      fi
    fi
    IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    OBJ_FILES=""
    for src_file in clients/simple-shm.c shared/os-compatibility.c xdg-shell-protocol.c fullscreen-shell-unstable-v1-protocol.c; do
      obj_file="$(basename $src_file .c).o"
      $IOS_CC -c "$src_file" \
        -I. -Ishared -Iinclude \
        -I${libwayland}/include/wayland -I${libwayland}/include \
        -I${epollShim}/include/libepoll-shim \
        -fPIC -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} \
        -o "$obj_file"
      OBJ_FILES="$OBJ_FILES $obj_file"
    done
    ar rcs libweston_simple_shm.a $OBJ_FILES
  '';
  installPhase = ''
    mkdir -p $out/lib
    cp libweston_simple_shm.a $out/lib/
  '';
}
