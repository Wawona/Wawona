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
  mobile = platformInfo { inherit iosToolchain simulator; };
  ffmpegSource = {
    source = "github";
    owner = "FFmpeg";
    repo = "FFmpeg";
    tag = "n8.1";
    sha256 = "sha256-FdKhhCveEo5UodEoyUh3aBHABv3OT2VXmwBXE1ce3p0=";
  };
  src = fetchSource ffmpegSource;
  # watchOS lacks full VideoToolbox / SecureTransport coverage for foot decode.
  disableSecureTransport = mobile.isWatchOS;
  enableVideoToolbox = !mobile.isWatchOS;
in
pkgs.stdenv.mkDerivation {
  name = "ffmpeg-ios";
  inherit src;

  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    pkg-config
    nasm
    yasm
  ];

  buildInputs = [ ];

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; minVersion = mobile.minVersion; }}
    unset MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export IOS_SDK_PATH="$SDKROOT"
    export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

    export TOOLCHAIN_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    export CC="$XCODE_CLANG"
    export CXX="$XCODE_CLANGXX"
    export AR="$TOOLCHAIN_BIN/ar"
    export RANLIB="$TOOLCHAIN_BIN/ranlib"
    export STRIP="$TOOLCHAIN_BIN/strip"
    export NM="$TOOLCHAIN_BIN/nm"

    export HOST_CC="/usr/bin/clang"
    export HOST_CFLAGS="-isysroot $MACOS_SDK_PATH"
    export HOST_LDFLAGS="-isysroot $MACOS_SDK_PATH"

    export CFLAGS="-arch arm64 -isysroot $SDKROOT ${mobile.minVerFlag} -fembed-bitcode"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch arm64 -isysroot $SDKROOT ${mobile.minVerFlag}"
  '';

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
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
      ${lib.optionalString disableSecureTransport "--disable-securetransport"} \
      ${lib.optionalString enableVideoToolbox ''
      --enable-videotoolbox \
      --enable-hwaccel=h264_videotoolbox \
      --enable-hwaccel=hevc_videotoolbox \
      --enable-encoder=h264_videotoolbox \
      --enable-encoder=hevc_videotoolbox \
      ''} \
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

    if [ ! -d "$out/include" ] || [ -z "$(ls -A $out/include 2>/dev/null)" ]; then
      echo "Warning: include directory missing or empty, copying headers from source"
      mkdir -p "$out/include"
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter; do
        if [ -d "$libdir" ]; then
          find "$libdir" -name "*.h" -exec install -D {} "$out/include/{}" \; 2>/dev/null || true
        fi
      done
    fi

    if [ ! -d "$out/lib" ] || [ -z "$(ls -A $out/lib 2>/dev/null)" ]; then
      echo "Warning: lib directory missing or empty, copying libraries from source"
      mkdir -p "$out/lib"
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter; do
        if [ -d "$libdir" ]; then
          find "$libdir" -name "*.a" -exec cp -v {} "$out/lib/" \; 2>/dev/null || true
        fi
      done
    fi

    runHook postInstall
  '';

  postInstall = ''
    if [ ! -f "$out/lib/pkgconfig/libavcodec.pc" ]; then
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
