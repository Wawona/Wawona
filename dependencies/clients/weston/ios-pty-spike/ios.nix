{
  lib,
  pkgs,
  buildModule,
  iosToolchain,
  simulator ? false,
}:

let
  platformInfo = import ../../../toolchains/apple-mobile-platform.nix;
  mobile = platformInfo { inherit iosToolchain simulator; };
  wawonaPty = buildModule.buildForIOS "wawona-pty" { inherit simulator; };
in
pkgs.stdenv.mkDerivation {
  name = "wawona-pty-spike-ios${if simulator then "-sim" else ""}";
  src = ./.;

  __noChroot = true;

  buildInputs = [ wawonaPty ];

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; minVersion = mobile.minVersion; }}
    unset MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
  '';

  buildPhase = ''
    runHook preBuild
    $CC spike.c -I${wawonaPty}/include \
      -arch arm64 -isysroot "$SDKROOT" ${mobile.minVerFlag} \
      -O2 -o wawona-pty-spike \
      ${wawonaPty}/lib/libwwn-pty.a
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp wawona-pty-spike $out/bin/
    runHook postInstall
  '';
}
