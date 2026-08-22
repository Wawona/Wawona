# Mode B multi-VT console: DRM dumb present + libvterm + Doorman getty.
{
  lib,
  pkgs,
  buildModule,
  xcodeUtils,
  doorman,
  ...
}:

let
  iland = buildModule.buildForMacOS "iland" { };
  libvterm = pkgs.libvterm-neovim;
in
pkgs.stdenv.mkDerivation {
  pname = "modeb-ttyd";
  version = "0.3.0";

  src = ./.;

  __noChroot = true;
  dontConfigure = true;

  buildInputs = [ libvterm doorman ];

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
    INCLUDES="-I${iland}/include -I${libvterm}/include -I${doorman}/include"
    CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -O2 -std=c11 $INCLUDES -I."
    FRAMEWORKS="-framework IOSurface -framework Foundation -framework CoreFoundation -framework IOKit -framework CoreGraphics -framework ApplicationServices -framework QuartzCore -framework Metal -framework Cocoa"
    AUTH_FRAMEWORKS="-framework Foundation -framework OpenDirectory -framework Security"
    LIBS="-L${iland}/lib -liland_userland -L${libvterm}/lib -lvterm -Wl,-rpath,${libvterm}/lib"
    echo "CC modeb-getty (Doorman)"
    "$CLANG" $CFLAGS modeb-getty.c \
      ${doorman}/lib/libdoorman.a \
      $AUTH_FRAMEWORKS -lpam -lobjc \
      -o modeb-getty
    echo "CC modeb-ttyd (libvterm)"
    "$CLANG" $CFLAGS modeb-ttyd.c $LIBS $FRAMEWORKS -o modeb-ttyd
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp modeb-ttyd modeb-getty $out/bin/
  '';

  meta = with lib; {
    description = "Wawona Mode B multi-VT console (libvterm + Doorman login)";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
