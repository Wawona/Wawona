{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
  fetchSource = common.fetchSource;
  # androidToolchain passed from caller
  xkbcommonSource = {
    source = "github";
    owner = "xkbcommon";
    repo = "libxkbcommon";
    tag = "xkbcommon-1.7.0";
    sha256 = "sha256-m01ZpfEV2BTYPS5dsyYIt6h69VDd1a2j4AtJDXvn1I0=";
  };
  src = fetchSource xkbcommonSource;
  libxml2-android = buildModule.buildForAndroid "libxml2" { };
in
pkgs.stdenv.mkDerivation {
  name = "xkbcommon-android";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    bison
  ];

  buildInputs = [
    libxml2-android
  ];

  preConfigure = ''
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""

    ANDROID_CC="${androidToolchain.androidCC}"
    ANDROID_CXX="${androidToolchain.androidCXX}"

    cat > android-cross.txt <<EOF
[binaries]
c = '$ANDROID_CC'
cpp = '$ANDROID_CXX'
ar = '${androidToolchain.androidAR}'
strip = '${androidToolchain.androidSTRIP}'
ranlib = '${androidToolchain.androidRANLIB}'
pkgconfig = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
c_args = ['--target=${androidToolchain.androidTarget}', '--sysroot=${androidToolchain.androidNdkSysroot}', '-fPIC', '${androidToolchain.androidNdkCflags}']
c_link_args = ['--target=${androidToolchain.androidTarget}', '--sysroot=${androidToolchain.androidNdkSysroot}', '-L${androidToolchain.androidNdkAbiLibDir}']
needs_exe_wrapper = true
EOF

    export PKG_CONFIG_PATH="${libxml2-android}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
  '';

  dontUseMesonConfigure = true;

  buildPhase = ''
    runHook preBuild
    meson setup build --prefix=$out \
      --cross-file=android-cross.txt \
      -Denable-docs=false \
      -Denable-tools=false \
      -Denable-x11=false \
      -Denable-wayland=false \
      -Denable-xkbregistry=false \
      -Ddefault_library=static \
      --buildtype=plain
    meson compile -C build xkbcommon
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    meson install -C build
    runHook postInstall
  '';
}
