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
  # Use pixman from nixpkgs source
  pixmanSource = pkgs.pixman.src;
  src = pixmanSource;
  buildFlags = [
    "-Dopenmp=disabled"
    "-Dgtk=disabled"
    "-Dtests=disabled"
    "-Ddemos=disabled"
  ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "pixman-ios";
  inherit src patches;

  # We need to access /Applications/Xcode.app for the SDK and toolchain
  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    (python3.withPackages (
      ps: with ps; [
        setuptools
        pip
        packaging
        mako
        pyyaml
      ]
    ))
  ];
  buildInputs = [ ];
  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass the apple-sdk-14.4 fallback
    unset DEVELOPER_DIR

    ${if simulator then ''
      # Robust SDK detection for iOS Simulator
      IOS_SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK_PATH" ]; then
        # Fallback 1: via ensureIosSimSDK script
        IOS_SDK_PATH=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || true
      fi
      if [ ! -d "$IOS_SDK_PATH" ]; then
        # Fallback 2: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK_PATH="$XCODE_APP/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    '' else ''
      # Robust SDK detection for iOS Device
      IOS_SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK_PATH" ]; then
        # Fallback 1: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK_PATH="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    ''}

    if [ ! -d "$IOS_SDK_PATH" ]; then
      echo "ERROR: iOS SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$IOS_SDK_PATH"
    export IOS_SDK_PATH

    # Find the Developer dir associated with this SDK
    # Use sed instead of grep -oP for macOS compatibility
    export DEVELOPER_DIR=$(echo "$IOS_SDK_PATH" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK_PATH" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    echo "Using iOS SDK: $IOS_SDK_PATH"
    echo "Using Developer Dir: $DEVELOPER_DIR"
    
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    
    # Create iOS cross-file for Meson
    cat > ios-cross-file.txt <<EOF
[binaries]
c = '$IOS_CC'
cpp = '$IOS_CXX'
ar = 'ar'
strip = 'strip'
pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}', '-fPIC']
cpp_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}', '-fPIC']
c_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}']
EOF
  '';
  configurePhase = ''
    runHook preConfigure
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=ios-cross-file.txt \
      --buildtype=release \
      -Ddefault_library=static \
      ${lib.concatMapStringsSep " " (flag: flag) buildFlags}
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    meson install -C build
    runHook postInstall
  '';
}
