{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  # sshpass source - fetch from SourceForge mirror via GitHub
  src = pkgs.fetchurl {
    url = "https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz";
    sha256 = "sha256-rREGwgPLtWGFyjutjGzK/KO0BkaWGU2oefgcjXvf7to=";
  };
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
in
pkgs.stdenv.mkDerivation {
  name = "sshpass-ios";
  version = "1.10";
  
  inherit src;
  
  # No patches needed for sshpass
  patches = [ ];
  
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
  ];
  
  buildInputs = [ ];

  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        if [ "${if simulator then "true" else "false"}" = "true" ]; then
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        else
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        fi
      fi
    fi
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    # Determine architecture
    if [ "${if simulator then "true" else "false"}" = "true" ]; then
      SIMULATOR_ARCH="arm64"
      if [ "$(uname -m)" = "x86_64" ]; then
        SIMULATOR_ARCH="x86_64"
      fi
      export CC="$IOS_CC"
      export CXX="$IOS_CXX"
      export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC"
      export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC"
      export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=26.0"
    else
      export CC="$IOS_CC"
      export CXX="$IOS_CXX"
      export CFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0 -fPIC"
      export CXXFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0 -fPIC"
      export LDFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0"
    fi
  '';

  configurePhase = ''
    runHook preConfigure
    ./configure --prefix=$out --host=arm-apple-darwin
    runHook postConfigure
  '';

  meta = with lib; {
    description = "Non-interactive SSH password authentication";
    homepage = "https://sourceforge.net/projects/sshpass/";
    license = licenses.gpl2Plus;
    platforms = platforms.darwin;
  };
}
