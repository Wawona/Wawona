# Mode B multi-VT console (Classic own-display). DRM dumb + PTY zsh.
{
  lib,
  pkgs,
  buildModule,
  xcodeUtils,
  ...
}:

let
  iland = buildModule.buildForMacOS "iland" { };
in
pkgs.stdenv.mkDerivation {
  pname = "modeb-ttyd";
  version = "0.1.0";

  src = ./.;

  __noChroot = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    unset DEVELOPER_DIR
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    export SDKROOT="$MACOS_SDK"
    CLANG="${pkgs.clang}/bin/clang"
    INCLUDES="-I${iland}/include"
    CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -O2 -std=c11 $INCLUDES -I."
    FRAMEWORKS="-framework IOSurface -framework Foundation -framework CoreFoundation -framework IOKit -framework CoreGraphics -framework ApplicationServices -framework QuartzCore -framework Metal -framework Cocoa"
    LIBS="-L${iland}/lib -liland_userland"
    echo "CC modeb-ttyd"
    "$CLANG" $CFLAGS modeb-ttyd.c $LIBS $FRAMEWORKS -o modeb-ttyd
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp modeb-ttyd $out/bin/
  '';

  meta = with lib; {
    description = "Wawona Mode B userspace multi-VT console";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
