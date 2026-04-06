{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  westonSimpleShmSrc = pkgs.callPackage ./patched-src.nix { };
  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  epollShim = buildModule.buildForIOS "epoll-shim" { inherit simulator; };
in
pkgs.stdenv.mkDerivation {
  name = "libweston-simple-shm-ios";
  src = westonSimpleShmSrc;
  __noChroot = true;

  nativeBuildInputs = [ xcodeUtils.findXcodeScript ];

  buildPhase = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export SDKROOT="$DEVELOPER_DIR/Platforms/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.platform/Developer/SDKs/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.sdk"
      fi
    fi

    IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    IOS_ARCH="arm64"
    
    OBJ_FILES=""
    # Compile sources
    for src_file in clients/simple-shm.c shared/os-compatibility.c xdg-shell-protocol.c fullscreen-shell-unstable-v1-protocol.c; do
      obj_file="$(basename $src_file .c).o"
      $IOS_CC -c "$src_file" \
         -I. \
         -Ishared \
         -Iinclude \
         -I${libwayland}/include/wayland \
         -I${libwayland}/include \
         -I${epollShim}/include/libepoll-shim \
         -fPIC -arch $IOS_ARCH -isysroot "$SDKROOT" -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 \
         -o "$obj_file"
      OBJ_FILES="$OBJ_FILES $obj_file"
    done

    # Archive into static library
    ar rcs libweston_simple_shm.a $OBJ_FILES
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp libweston_simple_shm.a $out/lib/
  '';
}
