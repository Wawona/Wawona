{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  westonSimpleShmSrc = pkgs.callPackage ./patched-src.nix { };
  libwayland = buildModule.buildForMacOS "libwayland" { };
  epollShim = buildModule.buildForMacOS "epoll-shim" { };
in
pkgs.stdenv.mkDerivation {
  name = "libweston-simple-shm-macos";
  src = westonSimpleShmSrc;

  nativeBuildInputs = [ xcodeUtils.findXcodeScript ];

  buildPhase = ''
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    export SDKROOT="$MACOS_SDK"

    MACOS_CC="clang"
    
    OBJ_FILES=""
    # Compile sources
    for src_file in clients/simple-shm.c shared/os-compatibility.c xdg-shell-protocol.c fullscreen-shell-unstable-v1-protocol.c; do
      obj_file="$(basename $src_file .c).o"
      $MACOS_CC -c "$src_file" \
         -I. \
         -Ishared \
         -Iinclude \
         -I${libwayland}/include/wayland \
         -I${libwayland}/include \
         -I${epollShim}/include/libepoll-shim \
         -fPIC -isysroot "$SDKROOT" -mmacosx-version-min=12.0 \
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
