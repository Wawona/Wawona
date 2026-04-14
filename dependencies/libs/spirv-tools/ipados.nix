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
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # SPIRV-Tools source - same as nixpkgs
  src = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-Tools";
    rev = "vulkan-sdk-1.4.328.0";
    sha256 = "sha256-NXxC5XLvEEIAlA0sym6l7vWj+g8pJ4trsJI3pmZwRxU=";
  };
  spirvHeaders = pkgs.spirv-headers.src; # Need source, not installed headers
in
pkgs.stdenv.mkDerivation {
  name = "spirv-tools-ipados";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
    ninja
    python3
  ];
  buildInputs = [
    spirvHeaders # Headers-only, macOS version OK
  ];
  preConfigure = ''
        if [ -z "''${XCODE_APP:-}" ]; then
          XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
          if [ -n "$XCODE_APP" ]; then
            export XCODE_APP
            export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
            export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
            export SDKROOT="$DEVELOPER_DIR/Platforms/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.platform/Developer/SDKs/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.sdk"
          fi
        fi
        
        echo "DEBUG: XCODE_APP=$XCODE_APP"
        echo "DEBUG: SDKROOT=$SDKROOT"
        
        # Unset macOS deployment target to prevent clang wrapper from adding -mmacos-version-min
        unset MACOSX_DEPLOYMENT_TARGET
        
        # Use -target which is more robust than -mios-simulator-version-min
        # Add -Wno-error to override -Werror added by CMake configuration
        TARGET_FLAGS="-target arm64-apple-ios26.0${if simulator then "-simulator" else ""} -isysroot $SDKROOT -Wno-error"
        
        export NIX_CFLAGS_COMPILE="$TARGET_FLAGS"
        export NIX_CXXFLAGS_COMPILE="$TARGET_FLAGS"
        # Remove flags from NIX_LDFLAGS as they confuse the wrapper/linker
        # CMake will pass necessary flags via CMAKE_EXE_LINKER_FLAGS
        export NIX_LDFLAGS=""
        
        if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
          IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
          IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
        else
          echo "DEBUG: Using Nix clang wrapper"
          IOS_CC="${buildPackages.clang}/bin/clang"
          IOS_CXX="${buildPackages.clang}/bin/clang++"
        fi
        
        echo "DEBUG: IOS_CC=$IOS_CC"
        
        # Force usage of Xcode clang if found, bypassing Nix wrapper
        export CC="$IOS_CC"
        export CXX="$IOS_CXX"
        
        NINJA_PATH="${buildPackages.ninja}/bin/ninja"
        echo "DEBUG: NINJA_PATH=$NINJA_PATH"
        
        TOOLCHAIN_FILE="$PWD/ipados-toolchain.cmake"
        cat > ipados-toolchain.cmake <<EOF
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES arm64)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
    set(CMAKE_C_COMPILER "$IOS_CC")
    set(CMAKE_CXX_COMPILER "$IOS_CXX")
    set(CMAKE_SYSROOT "$SDKROOT")
    set(BUILD_SHARED_LIBS OFF)
    set(CMAKE_BUILD_TYPE Release)
    set(CMAKE_C_FLAGS "$TARGET_FLAGS")
    set(CMAKE_CXX_FLAGS "$TARGET_FLAGS")
    set(CMAKE_C_FLAGS_INIT "$TARGET_FLAGS")
    set(CMAKE_CXX_FLAGS_INIT "$TARGET_FLAGS")
    set(CMAKE_EXE_LINKER_FLAGS "$TARGET_FLAGS")
    set(CMAKE_SHARED_LINKER_FLAGS "$TARGET_FLAGS")
    set(CMAKE_MODULE_LINKER_FLAGS "$TARGET_FLAGS")
    EOF

        # Fix SPIRV-Headers detection
        mkdir -p external
        cp -r --no-preserve=mode ${spirvHeaders} external/spirv-headers

        # Disable building tools (spirv-reduce uses system() which is unavailable on iPadOS)
        sed -i 's|add_subdirectory(tools)|# add_subdirectory(tools)|g' CMakeLists.txt
        
        # Disable tests as well since they depend on tools
        sed -i 's|add_subdirectory(test)|# add_subdirectory(test)|g' CMakeLists.txt
  '';
  configurePhase = ''
    runHook preConfigure

    NINJA_PATH="${buildPackages.ninja}/bin/ninja"
    echo "DEBUG: NINJA_PATH=$NINJA_PATH"

    TOOLCHAIN_FILE="$PWD/ipados-toolchain.cmake"
    cmakeFlagsArray+=("-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE")
    cmakeFlagsArray+=("-DCMAKE_MAKE_PROGRAM=$NINJA_PATH")
    cmakeFlagsArray+=("-DCMAKE_BUILD_TYPE=Release")
    cmakeFlagsArray+=("-DBUILD_SHARED=OFF")
    cmakeFlagsArray+=("-DSPIRV_SKIP_TESTS=ON")
    cmakeFlagsArray+=("-DSPIRV_SKIP_EXECUTABLES=ON")
    cmakeFlagsArray+=("-DSPIRV_WERROR=OFF")
    cmakeFlagsArray+=("-DSPIRV-Headers_SOURCE_DIR=${spirvHeaders}")

    echo "Running cmake with flags: -DCMAKE_INSTALL_PREFIX=$out ''${cmakeFlagsArray[@]}"
    cmake . -GNinja -DCMAKE_INSTALL_PREFIX=$out "''${cmakeFlagsArray[@]}"

    runHook postConfigure
  '';
  cmakeFlags = [ ];
}
