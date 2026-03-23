{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
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
  name = "ffmpeg-macos";
  inherit src;

  patches = [
    # Fix FATE tests
    ./fix-fate-ffmpeg-spec-disposition-7.1.patch
  ];

  nativeBuildInputs = with pkgs; [
    pkg-config
    nasm # Required for x264/x265
    yasm # Alternative assembler
  ];

  buildInputs = with pkgs; [
    # Core dependencies
    zlib
  ];

  preConfigure = ''
    # Robust SDK detection using xcrun (gold standard for modern macOS)
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 1: Command Line Tools path
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 2: Legacy system path
      MACOS_SDK="/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 3: Custom script
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 4: Global xcode-select
      MACOS_SDK=$(/usr/bin/xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 5: Nix-provided SDK (if available)
      MACOS_SDK="${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    fi

    if [ ! -d "$MACOS_SDK" ]; then
      echo "ERROR: MacOSX SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    # FFmpeg uses configure script, not CMake
    # Set up cross-compilation flags
    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    export AR="${pkgs.llvmPackages.bintools}/bin/llvm-ar"
    export RANLIB="${pkgs.llvmPackages.bintools}/bin/llvm-ranlib"
    export STRIP="${pkgs.llvmPackages.bintools}/bin/llvm-strip"

    # Architecture and SDK flags
    # FFmpeg requires C11 support - set for both host and target
    export CFLAGS="-arch arm64 -isysroot ${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -mmacosx-version-min=26.0 -std=c11"
    export CXXFLAGS="-arch arm64 -isysroot ${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -mmacosx-version-min=26.0"
    export LDFLAGS="-arch arm64 -isysroot ${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -mmacosx-version-min=26.0"

    # Host compiler flags for FFmpeg's configure tests
    export HOSTCC="${pkgs.clang}/bin/clang"
    export HOSTCFLAGS="-std=c11"
  '';

  configureFlags = [
    "--cc=${pkgs.clang}/bin/clang"
    "--cxx=${pkgs.clang}/bin/clang++"
    # "--host-cc=${pkgs.clang}/bin/clang"
    "--arch=arm64"
    "--target-os=darwin"
    # "--enable-cross-compile"
    "--sysroot=$SDKROOT"
    "--prefix=$out"
    "--libdir=$out/lib"
    "--shlibdir=$out/lib"
    "--extra-cflags=-std=c11"
    "--enable-rpath"
    "--install-name-dir=$out/lib"

    # Enable VideoToolbox for hardware encoding on macOS
    "--enable-videotoolbox"
    "--enable-hwaccel=h264_videotoolbox"
    "--enable-hwaccel=hevc_videotoolbox"

    # Enable Vulkan support (for waypipe)
    # Note: Vulkan support requires external Vulkan SDK/libs
    # For macOS/iOS, we rely on kosmickrisp/MoltenVK
    # "--enable-vulkan"  # Disabled for now - requires Vulkan SDK

    # Enable required codecs for waypipe
    "--enable-encoder=h264_videotoolbox"
    "--enable-encoder=hevc_videotoolbox"
    "--enable-encoder=libx264"
    "--enable-decoder=h264"
    "--enable-decoder=hevc"

    # Disable unnecessary features to reduce build time
    "--disable-doc"
    "--disable-ffplay"
    "--disable-ffprobe"
    "--disable-programs"
    "--disable-debug"
    "--disable-static"
    "--disable-avdevice"
    "--enable-shared"
  ];

  # FFmpeg uses autotools configure script
  configurePhase = ''
    runHook preConfigure
    ./configure $configureFlags
    runHook postConfigure
  '';

  # Build and install
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    # Install headers and libraries
    # FFmpeg installs headers with 'make install-headers' or 'make install' should include them
    make install || echo "make install failed, continuing with manual installation"

    # Ensure include directory exists - FFmpeg should install headers to $out/include
    # But if it doesn't, copy them manually from source
    if [ ! -d "$out/include" ] || [ -z "$(ls -A $out/include 2>/dev/null)" ]; then
      echo "Warning: include directory missing or empty, copying headers from source"
      mkdir -p "$out/include"
      # Copy headers from source build directory
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter libavdevice; do
        if [ -d "$libdir" ]; then
          # Copy header files
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

    # Ensure lib directory exists - FFmpeg should install libraries to $out/lib
    # But if it doesn't, copy them manually from source
    if [ ! -d "$out/lib" ] || [ -z "$(ls -A $out/lib 2>/dev/null)" ]; then
      echo "Warning: lib directory missing or empty, copying libraries from source"
      mkdir -p "$out/lib"
      # Copy libraries from source build directory
      # FFmpeg builds libs in subdirectories like libavcodec/libavcodec.dylib or libavcodec/libavcodec.a
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter libavdevice; do
        if [ -d "$libdir" ]; then
          echo "Copying libraries from $libdir..."
          # Copy dylib files (macOS shared libraries)
          find "$libdir" -name "*.dylib*" -exec cp -v {} "$out/lib/" \; 2>/dev/null || true
          # Copy .a files (static libraries)
          find "$libdir" -name "*.a" -exec cp -v {} "$out/lib/" \; 2>/dev/null || true
        fi
      done
      
      # Fix install names and dependencies for dylibs
      if [ -n "$(ls -A $out/lib/*.dylib 2>/dev/null)" ]; then
        echo "Fixing install names and dependencies for dylibs..."
        for dylib in $out/lib/*.dylib; do
          # Fix ID
          libname=$(basename "$dylib")
          install_name_tool -id "$out/lib/$libname" "$dylib" || true
          
          # Fix dependencies
          # Get list of dependencies that look like dylibs
          # We skip the first line (the library itself) usually, but checking all is safer if we filter by name
          otool -L "$dylib" | grep ".dylib" | grep -v ":" | while read -r dep rest; do
            depname=$(basename "$dep")
            # Check if this dependency exists in our output directory
            if [ -f "$out/lib/$depname" ] && [ "$dep" != "$out/lib/$depname" ]; then
              echo "Changing dependency $dep to $out/lib/$depname in $libname"
              install_name_tool -change "$dep" "$out/lib/$depname" "$dylib" || true
            fi
          done
        done
      fi
    fi

    # Verify headers were installed
    if [ ! -f "$out/include/libavcodec/avcodec.h" ]; then
      echo "Error: libavcodec/avcodec.h not found after install" >&2
      exit 1
    fi
    if [ ! -f "$out/include/libavutil/avutil.h" ]; then
      echo "Error: libavutil/avutil.h not found after install" >&2
      exit 1
    fi

    # Verify libraries were installed
    echo "Checking for installed libraries in $out/lib..."
    echo "OUT is $out"
    echo "Current directory: $(pwd)"

    if [ ! -d "$out/lib" ]; then
        echo "Error: $out/lib directory does not exist!"
        echo "Searching for installed files in /nix/store:"
        find /nix/store -name "libavcodec.dylib" -maxdepth 4 2>/dev/null || true
        echo "Searching for installed files in current dir:"
        find . -name "libavcodec.dylib" -maxdepth 4 || true
        
        echo "Checking config.mak for prefix/libdir:"
        grep -i "prefix" ffbuild/config.mak || true
        grep -i "libdir" ffbuild/config.mak || true
        
        echo "Contents of $out:"
        ls -la "$out" || true
        exit 1
    fi

    ls -la "$out/lib"

    if [ -z "$(ls -A $out/lib/*.dylib 2>/dev/null)" ] && [ -z "$(ls -A $out/lib/*.a 2>/dev/null)" ]; then
      echo "Error: No libraries found in $out/lib" >&2
      echo "Build directory contents (searching for libraries):"
      find . -name "libavcodec*" -maxdepth 2 || true
      echo "Config.log tail:"
      tail -n 50 ffbuild/config.log || true
      exit 1
    fi

    runHook postInstall
  '';

  # Ensure pkg-config files are generated
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
