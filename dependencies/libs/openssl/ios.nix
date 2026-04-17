{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain,
}:

let
  xcodeUtils = iosToolchain;
  isVisionOS = iosToolchain.isVisionOSToolchain or false;
  isTVOS = iosToolchain.isTVOSToolchain or false;
in
pkgs.stdenv.mkDerivation {
  name = "openssl-ios";
  src = pkgs.fetchurl {
    url = "https://www.openssl.org/source/openssl-3.3.1.tar.gz";
    sha256 = "sha256-d3zVlihMiDN1oqehG/XSeG/FQTJV76sgxQ1v/m0CC34=";
  };

  nativeBuildInputs = with buildPackages; [ perl ];
  buildInputs = [ ];

  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;

  preConfigure = ''
    ${xcodeUtils.mkIOSBuildEnv {
      inherit simulator;
      minVersion =
        if isVisionOS then "26.0"
        else if isTVOS then "17.0"
        else xcodeUtils.deploymentTarget;
    }}
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export IOS_CC="$XCODE_CLANG"
  '';

  configurePhase = ''
    runHook preConfigure
    export CC="$IOS_CC"
    export CFLAGS="${if isVisionOS then "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT -fPIC" else "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC"}"
    export LDFLAGS="${if isVisionOS then "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT" else "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG"}"
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    ./Configure ${
      if simulator then
        "iossimulator-xcrun"
      else
        "ios64-cross"
    } no-shared no-dso ${if isTVOS then "no-apps" else ""} --prefix=$out --openssldir=$out/etc/ssl
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install_sw install_ssldirs
    runHook postInstall
  '';
}
