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
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  ensureIosSimSDK = xcodeUtils.ensureIosSimSDK;
  ffmpegSource = {
    source = "github";
    owner = "FFmpeg";
    repo = "FFmpeg";
    tag = "n7.1";
    sha256 = "sha256-erTkv156VskhYEJWjpWFvHjmcr2hr6qgUi28Ho8NFYk=";
  };
  src = fetchSource ffmpegSource;
in
pkgs.stdenv.mkDerivation {
  name = "ffmpeg-ipados";
  inherit src;

  # We need to access /Applications/Xcode.app for the SDK and toolchain
  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    pkg-config
    nasm
    yasm
    ensureIosSimSDK
  ];

  buildInputs = [ ];

  # Configure phase to set up the environment
  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass the apple-sdk-14.4 fallback
    unset DEVELOPER_DIR

    ${if simulator then ''
      # Robust SDK detection for iPadOS Simulator
      IOS_SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK_PATH" ]; then
        # Fallback 1: via ensureIosSimSDK script
        IOS_SDK_PATH=$(${ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || true
      fi
      if [ ! -d "$IOS_SDK_PATH" ]; then
        # Fallback 2: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK_PATH="$XCODE_APP/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    '' else ''
      # Robust SDK detection for iPadOS Device
      IOS_SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK_PATH" ]; then
        # Fallback 1: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK_PATH="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    ''}

    if [ ! -d "$IOS_SDK_PATH" ]; then
      echo "ERROR: iPadOS SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$IOS_SDK_PATH"
    export IOS_SDK_PATH

    # Find the Developer dir associated with this SDK without using -oP
    export DEVELOPER_DIR=$(echo "$IOS_SDK_PATH" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK_PATH" ] && export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)

    echo "Using iPadOS SDK: $IOS_SDK_PATH"
    echo "Using Developer Dir: $DEVELOPER_DIR"

    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

    if [ ! -d "$IOS_SDK_PATH" ]; then
      echo "Error: iPadOS SDK not found at $IOS_SDK_PATH (even after download attempt)"
      exit 1
    fi

    echo "Using iPadOS SDK: $IOS_SDK_PATH"

    # Use the toolchain from Xcode
    export TOOLCHAIN_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    export CC="$TOOLCHAIN_BIN/clang"
    export CXX="$TOOLCHAIN_BIN/clang++"
    export AR="$TOOLCHAIN_BIN/ar"
    export RANLIB="$TOOLCHAIN_BIN/ranlib"
    export STRIP="$TOOLCHAIN_BIN/strip"
    export NM="$TOOLCHAIN_BIN/nm"

    # HOST compiler (runs on macOS)
    export HOST_CC="/usr/bin/clang"
    export HOST_CFLAGS="-isysroot $MACOS_SDK_PATH"
    export HOST_LDFLAGS="-isysroot $MACOS_SDK_PATH"

    # Flags for TARGET (iOS)
    export CFLAGS="-arch arm64 -isysroot $IOS_SDK_PATH -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget} -fembed-bitcode"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch arm64 -isysroot $IOS_SDK_PATH -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}"
  '';

  configurePhase = ''
    runHook preConfigure

    # Unset SDKROOT so FFmpeg's configure doesn't pass it to host checks
    unset SDKROOT

    # Explicitly disable programs and runtime checks
    # Note: We set --host-cc to the macOS compiler to allow building helper tools
    ./configure \
      --prefix=$out \
      --libdir=$out/lib \
      --shlibdir=$out/lib \
      --enable-cross-compile \
      --target-os=darwin \
      --arch=arm64 \
      --cc="$CC" \
      --cxx="$CXX" \
      --host-cc="$HOST_CC" \
      --host-cflags="$HOST_CFLAGS" \
      --host-ldflags="$HOST_LDFLAGS" \
      --ar="$AR" \
      --ranlib="$RANLIB" \
      --strip="$STRIP" \
      --nm="$NM" \
      --sysroot="$IOS_SDK_PATH" \
      --extra-cflags="$CFLAGS" \
      --extra-ldflags="$LDFLAGS" \
      --enable-rpath \
      --install-name-dir=$out/lib \
      --disable-runtime-cpudetect \
      --disable-programs \
      --disable-doc \
      --disable-debug \
      --disable-shared \
      --enable-static \
      --disable-avdevice \
      --disable-indevs \
      --disable-outdevs \
      --enable-videotoolbox \
      --enable-hwaccel=h264_videotoolbox \
      --enable-hwaccel=hevc_videotoolbox \
      --enable-encoder=h264_videotoolbox \
      --enable-encoder=hevc_videotoolbox \
      --enable-encoder=libx264 \
      --enable-decoder=h264 \
      --enable-decoder=hevc
      
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install || echo "make install failed, continuing with manual installation"

    # Ensure include directory exists
    if [ ! -d "$out/include" ] || [ -z "$(ls -A $out/include 2>/dev/null)" ]; then
      echo "Warning: include directory missing or empty, copying headers from source"
      mkdir -p "$out/include"
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter; do
        if [ -d "$libdir" ]; then
          find "$libdir" -name "*.h" -exec install -D {} "$out/include/{}" \; 2>/dev/null || true
        fi
      done
      # Also copy top-level headers if they exist
      if [ -f "libavcodec/avcodec.h" ]; then
        mkdir -p "$out/include/libavcodec"
        cp libavcodec/*.h "$out/include/libavcodec/" 2>/dev/null || true
      fi
      if [ -f "libavutil/avutil.h" ]; then
        mkdir -p "$out/include/libavutil"
        cp libavutil/*.h "$out/include/libavutil/" 2>/dev/null || true
      fi
    fi

    # Ensure lib directory exists
    if [ ! -d "$out/lib" ] || [ -z "$(ls -A $out/lib 2>/dev/null)" ]; then
      echo "Warning: lib directory missing or empty, copying libraries from source"
      mkdir -p "$out/lib"
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter; do
        if [ -d "$libdir" ]; then
          echo "Copying libraries from $libdir..."
          find "$libdir" -name "*.a" -exec cp -v {} "$out/lib/" \; 2>/dev/null || true
        fi
      done
    fi

    runHook postInstall
  '';

  postInstall = ''
        # FFmpeg should generate .pc files, verify they exist
        if [ ! -f "$out/lib/pkgconfig/libavcodec.pc" ]; then
          echo "Warning: libavcodec.pc not found, creating minimal version"
          mkdir -p "$out/lib/pkgconfig"
          cat > "$out/lib/pkgconfig/libavcodec.pc" <<EOF
    prefix=$out
    exec_prefix=\''${prefix}
    libdir=\''${exec_prefix}/lib
    includedir=\''${prefix}/include

    Name: libavcodec
    Description: FFmpeg codec library
    Version: 7.1
    Requires: libavutil
    Libs: -L\''${libdir} -lavcodec
    Cflags: -I\''${includedir}
    EOF
        fi
        
        if [ ! -f "$out/lib/pkgconfig/libavutil.pc" ]; then
          echo "Warning: libavutil.pc not found, creating minimal version"
          cat > "$out/lib/pkgconfig/libavutil.pc" <<EOF
    prefix=$out
    exec_prefix=\''${prefix}
    libdir=\''${exec_prefix}/lib
    includedir=\''${prefix}/include

    Name: libavutil
    Description: FFmpeg utility library
    Version: 7.1
    Libs: -L\''${libdir} -lavutil
    Cflags: -I\''${includedir}
    EOF
        fi
  '';
}
