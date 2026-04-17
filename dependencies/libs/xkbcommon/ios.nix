{
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain,
}:

let
  fetchSource = common.fetchSource;
  xkbcommonSource = {
    source = "github";
    owner = "xkbcommon";
    repo = "libxkbcommon";
    tag = "xkbcommon-1.7.0";
    sha256 = "sha256-m01ZpfEV2BTYPS5dsyYIt6h69VDd1a2j4AtJDXvn1I0=";
  };
  src = fetchSource xkbcommonSource;
in
pkgs.stdenv.mkDerivation {
  name = "xkbcommon-ios";
  inherit src;

  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    bison
  ];

  buildInputs = [
    (
      if (iosToolchain.isVisionOSToolchain or false) then
        buildModule.buildForVisionOS "libxml2" { inherit simulator; }
      else
        buildModule.buildForIOS "libxml2" { }
    )
  ];

  preConfigure = ''
    unset DEVELOPER_DIR
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; }}

    # mkIOSBuildEnv prepends Xcode usr/bin; its byacc cannot parse libxkbcommon's
    # parser.y (%define api.pure). Prefer Nix bison.
    export PATH="${buildPackages.bison}/bin:$PATH"

    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export CC="$XCODE_CLANG"
    export CXX="$XCODE_CLANGXX"

    _CC="$XCODE_CLANG"
    _CXX="$XCODE_CLANGXX"
    _SDK="$SDKROOT"
    _ARCH="$IOS_ARCH"
    _DEPLOY="$APPLE_DEPLOYMENT_FLAG"
    if [[ "''${APPLE_SDK_NAME:-}" == xros ]] || [[ "''${APPLE_SDK_NAME:-}" == xrsimulator ]]; then
      _TARGET="$APPLE_LINKER_TARGET"
      _DEPLOY=""
    else
      _TARGET=""
    fi

    echo "xkbcommon: SDK=$_SDK deployment=$_DEPLOY target=$_TARGET"

    if [[ -n "$_TARGET" ]]; then
      cat > ios-cross.txt <<EOF
[binaries]
c = '$_CC'
cpp = '$_CXX'
c_for_build = '${buildPackages.clang}/bin/clang'
cpp_for_build = '${buildPackages.clang}/bin/clang++'
ar = 'ar'
strip = 'strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
c_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-fPIC']
c_link_args = ['-target', '$_TARGET', '-isysroot', '$_SDK']
needs_exe_wrapper = true
EOF
    else
      cat > ios-cross.txt <<EOF
[binaries]
c = '$_CC'
cpp = '$_CXX'
c_for_build = '${buildPackages.clang}/bin/clang'
cpp_for_build = '${buildPackages.clang}/bin/clang++'
ar = 'ar'
strip = 'strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
c_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC']
c_link_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY']
needs_exe_wrapper = true
EOF
    fi
  '';

  dontUseMesonConfigure = true;

  buildPhase = ''
    runHook preBuild
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    meson setup build --prefix=$out \
      --cross-file=ios-cross.txt \
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
