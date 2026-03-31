{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  epollShimSource = {
    source = "github";
    owner = "jiixyj";
    repo = "epoll-shim";
    # Using latest commit from master branch
    # Note: epoll-shim uses master as default branch
    rev = "master";
    sha256 = "sha256-9rlhRGFT8LD98fhHbcEhj3mAIyqeQGcxQdyP7u55lck=";
  };
  src = fetchSource epollShimSource;
in
pkgs.stdenv.mkDerivation {
  name = "epoll-shim-ios";
  inherit src;
  patches = [ ];
  
  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
    file
  ];
  buildInputs = [ ];
  postPatch = ''
    # Disable tests for iOS cross-compilation using Nix patches
    # Tests can't run during cross-compilation and cause build failures
    if [ -f CMakeLists.txt ]; then
      # Disable enable_testing() call
      substituteInPlace CMakeLists.txt \
        --replace "enable_testing()" "# enable_testing() # Disabled for iOS cross-compilation" || true
      
      # Disable test subdirectory
      substituteInPlace CMakeLists.txt \
        --replace "add_subdirectory(test)" "# add_subdirectory(test) # Disabled for iOS cross-compilation" || true
      
      # If tests are conditionally included with BUILD_TESTING, disable them
      substituteInPlace CMakeLists.txt \
        --replace "if(BUILD_TESTING)" "if(FALSE AND BUILD_TESTING)" || true
      substituteInPlace CMakeLists.txt \
        --replace "if (BUILD_TESTING)" "if (FALSE AND BUILD_TESTING)" || true
      
      # Disable CTest inclusion
      substituteInPlace CMakeLists.txt \
        --replace "include(CTest)" "# include(CTest) # Disabled for iOS cross-compilation" || true
      
      # Fix sysctl warning on iOS (discard qualifiers)
      # Added (int *) cast to silence the warning
      substituteInPlace src/timerfd_ctx.c \
        --replace "sysctl((int const[2])" "sysctl((int *)(int const[2])" || true

      echo "Patched CMakeLists.txt and sources for iOS cross-compilation"
    fi
  '';
  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

    ${if simulator then ''
      # Robust SDK detection for iOS Simulator
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
      # Robust SDK detection for iOS Device
      IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    ''}

    if [ ! -d "$IOS_SDK" ]; then
      echo "ERROR: iOS SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$IOS_SDK"
    export IOS_SDK

    # Find the Developer dir associated with this SDK
    # Use sed instead of grep -oP for macOS compatibility
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    echo "Using iOS SDK: $IOS_SDK"
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
        IOS_ARCH="${if simulator then pkgs.stdenv.hostPlatform.darwinArch else "arm64"}"
        
        cat > ios-toolchain.cmake <<EOF
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES $IOS_ARCH)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
    set(CMAKE_OSX_SYSROOT "$SDKROOT")
    set(CMAKE_C_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0")
    set(CMAKE_CXX_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0")
    set(CMAKE_C_COMPILER "$IOS_CC")
    set(CMAKE_CXX_COMPILER "$IOS_CXX")
    set(CMAKE_SYSROOT "$SDKROOT")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
    set(CMAKE_CROSSCOMPILING TRUE)
    # Disable code signing for try_run executables
    set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
    # Tell CMake the compilers work (skip tests)
    set(CMAKE_C_COMPILER_WORKS TRUE)
    set(CMAKE_CXX_COMPILER_WORKS TRUE)
    EOF
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_INSTALL_PREFIX=$out"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    # Build static library for iOS (shared libraries require code signing)
    "-DBUILD_SHARED_LIBS=OFF"
    # Cross-compilation cache variables to avoid try_run() failures
    # iOS/macOS kqueue supports one-shot timers with timeout zero
    "-DALLOWS_ONESHOT_TIMERS_WITH_TIMEOUT_ZERO_EXITCODE=0"
    "-DALLOWS_ONESHOT_TIMERS_WITH_TIMEOUT_ZERO_EXITCODE__TRYRUN_OUTPUT="
  ];
  configurePhase = ''
    runHook preConfigure
    # Capture SDKROOT before unsetting it for host builds
    SDKROOT_VAL="$SDKROOT"
    # Unset SDKROOT so it doesn't leak into host-side tool builds during cmake checks
    unset SDKROOT

    # Add iOS-specific flags that depend on SDKROOT
    EXTRA_CMAKE_FLAGS=""
    if [ -n "$SDKROOT_VAL" ]; then
      EXTRA_CMAKE_FLAGS="-DCMAKE_OSX_SYSROOT=$SDKROOT_VAL -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0"
    fi
    cmake -B build -S . \
      -DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_SHARED_LIBS=OFF \
      -DALLOWS_ONESHOT_TIMERS_WITH_TIMEOUT_ZERO_EXITCODE=0 \
      -DALLOWS_ONESHOT_TIMERS_WITH_TIMEOUT_ZERO_EXITCODE__TRYRUN_OUTPUT= \
      $EXTRA_CMAKE_FLAGS
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    cmake --build build --parallel $NIX_BUILD_CORES
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    cmake --install build
    runHook postInstall
  '';
  postInstall = ''
        # Ensure pkg-config files are in the right place
        if [ -d "$out/lib/pkgconfig" ]; then
          mkdir -p $out/lib/pkgconfig
        fi
        
        # Verify installation and test the library
        echo "=== Verifying epoll-shim iOS build ==="
        
        # Check library exists
        if [ -f "$out/lib/libepoll-shim.a" ]; then
          echo "✓ Static library found: $out/lib/libepoll-shim.a"
          ls -lh "$out/lib/libepoll-shim.a"
          
          # Verify library architecture (should be arm64 for iOS)
          if command -v file >/dev/null 2>&1; then
            echo "=== Library architecture verification ==="
            file "$out/lib/libepoll-shim.a" || true
            # Check for arm64 architecture
            if file "$out/lib/libepoll-shim.a" | grep -q "arm64\|ARM64\|aarch64"; then
              echo "✓ Library architecture is correct for iOS (arm64)"
            else
              echo "⚠ Warning: Library architecture may not be correct for iOS"
              file "$out/lib/libepoll-shim.a" || true
            fi
          fi
          
          # Verify library contains symbols (basic sanity check)
          if command -v ar >/dev/null 2>&1 && command -v nm >/dev/null 2>&1; then
            echo "=== Library symbol verification ==="
            # Extract and check for epoll-related symbols
            if ar t "$out/lib/libepoll-shim.a" 2>/dev/null | head -5 > /dev/null; then
              echo "✓ Library archive contains object files"
              # Try to check for epoll symbols (this is a basic check)
              TEMP_DIR=$(mktemp -d)
              OLD_PWD=$(pwd)
              cd "$TEMP_DIR" || exit 1
              if ar x "$out/lib/libepoll-shim.a" 2>/dev/null; then
                if nm *.o 2>/dev/null | grep -q "epoll\|kqueue"; then
                  echo "✓ Library contains epoll/kqueue-related symbols"
                fi
                rm -f *.o 2>/dev/null || true
              fi
              cd "$OLD_PWD" || true
              rm -rf "$TEMP_DIR" 2>/dev/null || true
            fi
          fi
          
          # Verify headers are installed
          if [ -d "$out/include" ]; then
            echo "=== Header verification ==="
            if [ -f "$out/include/epoll-shim/epoll.h" ] || [ -f "$out/include/libepoll-shim/sys/epoll.h" ]; then
              echo "✓ epoll.h header found"
              find "$out/include" -name "*.h" | head -5
            else
              echo "⚠ Warning: epoll.h header not found in expected location"
              find "$out/include" -name "*.h" | head -10 || true
            fi
          fi
          
          # Test linking: Create a minimal test program to verify the library links correctly
          echo "=== Testing library linkage ==="
          # Re-setup iOS toolchain for link test
          # Already set up in preConfigure, but ensure SDKROOT and IOS_CC are exported
          # Capture back the SDKROOT we unset during configure
          RE_SDKROOT=$(xcrun --sdk ${if simulator then "iphonesimulator" else "iphoneos"} --show-sdk-path 2>/dev/null || echo "$SDKROOT_VAL")
          if [ -n "$RE_SDKROOT" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
             RE_IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
          else
             RE_IOS_CC="${buildPackages.clang}/bin/clang"
          fi
          
          cat > test_link.c <<'TESTCODE'
    #include <sys/epoll.h>
    #include <unistd.h>
    #include <stdio.h>
    int main() {
        int epfd = epoll_create1(0);
        if (epfd >= 0) {
            printf("epoll_create1() succeeded: fd=%d\n", epfd);
            close(epfd);
            return 0;
        }
        printf("epoll_create1() failed\n");
        return 1;
    }
    TESTCODE
          
          # REQUIRED TEST: Compile and link a test program (this verifies the library works)
          # This test MUST pass for the build to succeed
          if [ -n "$RE_SDKROOT" ] && [ -n "$RE_IOS_CC" ] && [ -x "$RE_IOS_CC" ]; then
            echo "Running link test: Compiling test program with iOS toolchain..."
            
            # Set up pkg-config
            export PKG_CONFIG_PATH="$out/lib/pkgconfig:$out/libdata/pkgconfig"
            # Fallback flags if pkg-config fails or isn't available
            PKG_CFLAGS=$(pkg-config --cflags epoll-shim 2>/dev/null || echo "-I$out/include/libepoll-shim")
            PKG_LIBS=$(pkg-config --libs epoll-shim 2>/dev/null || echo "-L$out/lib -lepoll-shim -lepoll-shim-interpose")
            
            echo "Using flags: $PKG_CFLAGS $PKG_LIBS"
            
            IOS_ARCH="${if simulator then pkgs.stdenv.hostPlatform.darwinArch else "arm64"}"
            
            TEST_OUTPUT=$("$RE_IOS_CC" -isysroot "$RE_SDKROOT" \
               -arch $IOS_ARCH \
               -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 \
               $PKG_CFLAGS \
               $PKG_LIBS \
               test_link.c \
               -o test_link_ios 2>&1)
            TEST_EXIT_CODE=$?
            
            if [ $TEST_EXIT_CODE -eq 0 ] && [ -f test_link_ios ]; then
              echo "✓ Test program compiled and linked successfully"
              echo "✓ Library is linkable and headers are correct"
              
              # Verify the test binary is for iOS arm64
              if command -v file >/dev/null 2>&1; then
                BINARY_ARCH=$(file test_link_ios | grep -o "arm64\|ARM64\|aarch64" || echo "")
                if [ -n "$BINARY_ARCH" ]; then
                  echo "✓ Test binary architecture is correct: $BINARY_ARCH"
                fi
              fi
              
              rm -f test_link.c test_link_ios 2>/dev/null || true
            else
              echo "✗ ERROR: Link test FAILED"
              echo "Test compilation output:"
              echo "$TEST_OUTPUT"
              echo ""
              echo "This indicates the library cannot be linked or headers are incorrect"
              rm -f test_link.c test_link_ios 2>/dev/null || true
              exit 1
            fi
          else
            echo "✗ ERROR: Cannot run link test - iOS toolchain not available"
            echo "XCODE_APP: ''${XCODE_APP:-not set}"
            echo "SDKROOT: ''${SDKROOT:-not set}"
            echo "IOS_CC: ''${IOS_CC:-not set}"
            exit 1
          fi
          
          echo "=== epoll-shim iOS build verification complete ==="
          echo "✓ Library built successfully for iOS"
        else
          echo "✗ ERROR: epoll-shim library not found after installation"
          echo "Checking build directory:"
          find build -name "*.a" -o -name "*.dylib" 2>/dev/null | head -10 || true
          ls -la "$out/lib/" || true
          ls -la "$out/" || true
          exit 1
        fi
  '';
}
