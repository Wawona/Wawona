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
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
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
  name = "xkbcommon-ipados";
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
    (buildModule.buildForIPadOS "libxml2" { inherit simulator; })
  ];
  
  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

    ${if simulator then ''
      # Robust SDK detection for iPadOS Simulator
      IOS_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: via ensureIosSimSDK script
        IOS_SDK=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || true
      fi
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 2: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    '' else ''
      # Robust SDK detection for iPadOS Device
      IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    ''}

    if [ ! -d "$IOS_SDK" ]; then
      echo "ERROR: iPadOS SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$IOS_SDK"
    export IOS_SDK

    # Find the Developer dir associated with this SDK
    # Use sed instead of grep -oP for macOS compatibility
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    echo "Using iPadOS SDK: $IOS_SDK"
    echo "Using Developer Dir: $DEVELOPER_DIR"
    
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    
    # App Store build target: arm64 iPhoneOS
    IOS_ARCH="arm64"
    
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export CFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export CXXFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export LDFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"
    
    # Meson cross file for iPadOS
    cat > ipados-cross.txt <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
c_for_build = '${buildPackages.clang}/bin/clang'
cpp_for_build = '${buildPackages.clang}/bin/clang++'
ar = 'ar'
strip = 'strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'darwin'
cpu_family = '$IOS_ARCH'
cpu = '$IOS_ARCH'
endian = 'little'

[properties]
c_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0']
c_link_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0']
needs_exe_wrapper = true
EOF
  '';
  
  dontUseMesonConfigure = true;
  
  buildPhase = ''
    runHook preBuild
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    meson setup build --prefix=$out \
      --cross-file=ipados-cross.txt \
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
