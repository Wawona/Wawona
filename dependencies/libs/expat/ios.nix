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
  fetchSource = common.fetchSource;
  platformInfo = import ../../toolchains/apple-mobile-platform.nix;
  cmakeToolchain = import ../../toolchains/apple-cmake-toolchain.nix;
  mobile = platformInfo { inherit iosToolchain simulator; };
  expatSource = {
    source = "github";
    owner = "libexpat";
    repo = "libexpat";
    tag = "R_2_7_3";
    sha256 = "sha256-dDxnAJsj515vr9+j2Uqa9E+bB+teIBfsnrexppBtdXg=";
  };
  src = fetchSource expatSource;
in
pkgs.stdenv.mkDerivation {
  name = "expat-ios";
  inherit src;

  __noChroot = true;
  dontUseCmakeConfigure = true;

  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; minVersion = mobile.minVersion; }}
    unset MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    ${cmakeToolchain { inherit iosToolchain simulator; }}
    unset SDKROOT
  '';

  configurePhase = ''
    runHook preConfigure
    srcDir="."
    if [ -d expat ]; then
      srcDir="expat"
    fi
    cmake -S "$srcDir" -B build \
      -DCMAKE_TOOLCHAIN_FILE="$PWD/ios-toolchain.cmake" \
      -DCMAKE_INSTALL_PREFIX="$out" \
      -DBUILD_SHARED_LIBS=OFF \
      -DEXPAT_SHARED_LIBS=OFF \
      -DEXPAT_BUILD_TOOLS=OFF \
      -DEXPAT_BUILD_TESTS=OFF
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build --prefix $out
    runHook postInstall
  '';
}
