{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
}:

let
  fetchSource = common.fetchSource;
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
  name = "ffmpeg-android";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    pkg-config
    nasm
    yasm
  ];

  buildInputs = [ ];

  preConfigure = ''
    # Use shared Android toolchain wrappers so fallback/runtime handling
    # stays consistent with other Android derivations.
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"

    # Determine NM path from AR path (usually same directory)
    export NM="$(dirname "${androidToolchain.androidAR}")/llvm-nm"

    # Set up HOST compiler (runs on macOS)
    export HOST_CC="${pkgs.clang}/bin/clang"

    # Keep configure probe flags minimal; shared wrapper injects target/sysroot.
    export CFLAGS="-fPIC"
    export CXXFLAGS="-fPIC"
    export LDFLAGS=""
  '';

  configurePhase = ''
    runHook preConfigure

    # Explicitly disable programs and runtime checks
    # Note: We set --host-cc to the macOS compiler to allow building helper tools
    ./configure \
      --prefix=$out \
      --libdir=$out/lib \
      --shlibdir=$out/lib \
      --enable-cross-compile \
      --target-os=android \
      --arch=aarch64 \
      --sysroot=${androidToolchain.androidNdkSysroot} \
      --cc="$CC" \
      --cxx="$CXX" \
      --ar="$AR" \
      --ranlib="$RANLIB" \
      --strip="$STRIP" \
      --nm="$NM" \
      --host-cc="$HOST_CC" \
      --extra-cflags="$CFLAGS" \
      --extra-ldflags="$LDFLAGS" \
      --disable-runtime-cpudetect \
      --disable-programs \
      --disable-doc \
      --disable-debug \
      --enable-shared \
      --disable-static \
      --disable-avdevice \
      --disable-indevs \
      --disable-outdevs \
      --enable-jni \
      --enable-mediacodec \
      --enable-decoder=h264_mediacodec \
      --enable-decoder=hevc_mediacodec \
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
    make install
    runHook postInstall
  '';

  postInstall = ''
        # Ensure pkg-config files exist
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
