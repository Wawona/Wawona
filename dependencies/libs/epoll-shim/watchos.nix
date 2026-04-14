{ lib, pkgs, buildPackages, common, buildModule, simulator ? false, iosToolchain ? null }:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  src = fetchSource {
    source = "github"; owner = "jiixyj"; repo = "epoll-shim"; rev = "master";
    sha256 = "sha256-9rlhRGFT8LD98fhHbcEhj3mAIyqeQGcxQdyP7u55lck=";
  };
  sdkName  = if simulator then "WatchSimulator" else "WatchOS";
  xcrunSdk = if simulator then "watchsimulator" else "watchos";
  minVerFlag = if simulator then "-mwatchos-simulator-version-min=10.0" else "-mwatchos-version-min=10.0";
  arch = "arm64";
in
pkgs.stdenv.mkDerivation {
  name = "epoll-shim-watchos";
  inherit src;
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [ cmake pkg-config file perl ];

  postPatch = ''
    perl -0pi -e 's/^\s*enable_testing\(\)\s*$/# enable_testing() # Disabled/mg' CMakeLists.txt
    perl -0pi -e 's/^\s*include\(\s*CTest\s*\)\s*$/# include(CTest) # Disabled/mg' CMakeLists.txt
    perl -0pi -e 's/^\s*add_subdirectory\(\s*test\s*\)\s*$/# add_subdirectory(test) # Disabled/mg' CMakeLists.txt
    perl -0pi -e 's/^\s*if\s*\(\s*BUILD_TESTING\s*\)\s*$/if(FALSE AND BUILD_TESTING)/mg' CMakeLists.txt
    if [ -f src/CMakeLists.txt ]; then
      perl -0pi -e 's/^\s*add_subdirectory\(\s*external\/microatf\s*\)\s*$/# add_subdirectory(external\/microatf) # Disabled/mg' src/CMakeLists.txt
      perl -0pi -e 's/find_package\\(Threads REQUIRED\\)/if(WATCHOS)\n  if(NOT TARGET Threads::Threads)\n    add_library(Threads::Threads INTERFACE IMPORTED)\n  endif()\nelse()\n  find_package(Threads REQUIRED)\nendif()/g' src/CMakeLists.txt
    fi
    substituteInPlace src/timerfd_ctx.c \
      --replace "sysctl((int const[2])" "sysctl((int *)(int const[2])" || true
  '';

  preConfigure = ''
    unset DEVELOPER_DIR
    SDK=$(xcrun --sdk ${xcrunSdk} --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$SDK" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
      SDK="$XCODE_APP/Contents/Developer/Platforms/${sdkName}.platform/Developer/SDKs/${sdkName}.sdk"
    fi
    [ -d "$SDK" ] || { echo "ERROR: watchOS SDK not found"; exit 1; }
    export SDKROOT="$SDK"
    export DEVELOPER_DIR=$(echo "$SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$SDK" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
    export NIX_CFLAGS_COMPILE="" NIX_CXXFLAGS_COMPILE="" NIX_LDFLAGS=""
    IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    cat > watchos-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME watchOS)
set(CMAKE_OSX_ARCHITECTURES ${arch})
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.0)
set(CMAKE_OSX_SYSROOT "$SDKROOT")
set(CMAKE_C_FLAGS   "-arch ${arch} ${minVerFlag}")
set(CMAKE_CXX_FLAGS "-arch ${arch} ${minVerFlag}")
set(CMAKE_C_COMPILER   "$IOS_CC")
set(CMAKE_CXX_COMPILER "$IOS_CXX")
set(CMAKE_SYSROOT "$SDKROOT")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_CROSSCOMPILING TRUE)
set(THREADS_PREFER_PTHREAD_FLAG FALSE CACHE BOOL "" FORCE)
set(CMAKE_HAVE_LIBC_PTHREAD TRUE CACHE BOOL "" FORCE)
set(CMAKE_USE_PTHREADS_INIT TRUE CACHE BOOL "" FORCE)
set(CMAKE_THREAD_LIBS_INIT "" CACHE STRING "" FORCE)
set(Threads_FOUND TRUE CACHE BOOL "" FORCE)
set(CMAKE_C_COMPILER_WORKS TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)
EOF
  '';

  configurePhase = ''
    runHook preConfigure
    SDKROOT_VAL="$SDKROOT"
    unset SDKROOT
    EXTRA=""
    [ -n "$SDKROOT_VAL" ] && EXTRA="-DCMAKE_OSX_SYSROOT=$SDKROOT_VAL -DCMAKE_OSX_DEPLOYMENT_TARGET=10.0"
    cmake -B build -S . \
      -DCMAKE_TOOLCHAIN_FILE=watchos-toolchain.cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_TESTING=OFF \
      -DALLOWS_ONESHOT_TIMERS_WITH_TIMEOUT_ZERO_EXITCODE=0 \
      -DALLOWS_ONESHOT_TIMERS_WITH_TIMEOUT_ZERO_EXITCODE__TRYRUN_OUTPUT= \
      $EXTRA
    runHook postConfigure
  '';
  buildPhase  = "runHook preBuild; cmake --build build --parallel $NIX_BUILD_CORES; runHook postBuild";
  installPhase = "runHook preInstall; cmake --install build; runHook postInstall";
}
