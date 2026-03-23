{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  src = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-Tools";
    rev = "v2024.4";
    sha256 = "sha256-alJ4X7qbTzsRTqRFdpjdsj0wERVb17czui2muEaKNyI=";
  };
  spirvHeadersSource = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-Headers";
    rev = "3f17b2af6784bfa2c5aa5dbb8e0e74a607dd8b3b";
    sha256 = "sha256-MCQ+i9ymjnxRZP/Agk7rOGdHcB4p67jT4J4athWUlcI=";
  };
  spirvHeaders = spirvHeadersSource;
in
pkgs.stdenv.mkDerivation {
  name = "spirv-tools-macos";
  inherit src;

  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
    ninja
    python3
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
      echo "ERROR: MacOSX SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export CXXFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CXXFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"

    # Fix SPIRV-Headers detection
    mkdir -p external
    cp -r --no-preserve=mode ${spirvHeaders} external/spirv-headers

    # Disable tests
    sed -i 's|add_subdirectory(test)|# add_subdirectory(test)|g' CMakeLists.txt
  '';

  configurePhase = ''
    runHook preConfigure

    cmake . -B build -GNinja \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DSPIRV_WERROR=OFF \
      -DCMAKE_OSX_SYSROOT="$SDKROOT" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="26.0" \
      -DSPIRV_TOOLS_BUILD_STATIC=OFF \
      -DCMAKE_C_COMPILER="$CC" \
      -DCMAKE_CXX_COMPILER="$CXX"
      
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build
    runHook postInstall
  '';
}
