{
  lib,
  pkgs,
  common,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  libffiSource = {
    source = "github";
    owner = "libffi";
    repo = "libffi";
    tag = "v3.5.2";
    sha256 = "sha256-tvNdhpUnOvWoC5bpezUJv+EScnowhURI7XEtYF/EnQw=";
  };
  src = fetchSource libffiSource;
  buildFlags = [
    "--disable-docs"
    "--disable-shared"
    "--enable-static"
  ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "libffi-macos";
  inherit src patches;
  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with pkgs; [
    autoconf
    automake
    autoreconfHook
    libtool
    pkg-config
    texinfo
  ];
  buildInputs = [ ];
  preConfigure = ''
    MACOS_SDK="/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"
    
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export CXXFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CXXFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
  '';
  configurePhase = ''
    runHook preConfigure
    ./configure --prefix=$out --host=aarch64-apple-darwin ${
      lib.concatMapStringsSep " " (flag: flag) buildFlags
    }
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install
    runHook postInstall
  '';
  configureFlags = buildFlags;
}
