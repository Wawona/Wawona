{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  # Try to use nixpkgs epoll-shim, otherwise build from source
  epollShimNixpkgs = pkgs.epoll-shim or null;
  fetchSource = common.fetchSource;
  epollShimSource = {
    source = "github";
    owner = "jiixyj";
    repo = "epoll-shim";
    rev = "master";
    sha256 = "sha256-9rlhRGFT8LD98fhHbcEhj3mAIyqeQGcxQdyP7u55lck=";
  };
in
if epollShimNixpkgs != null then
  # Use nixpkgs version if available
  epollShimNixpkgs
else
  # Build from source for macOS
  pkgs.stdenv.mkDerivation {
    name = "epoll-shim-macos";
    src = fetchSource epollShimSource;
    patches = [ ];
    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
    ];
    buildInputs = [ ];
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DCMAKE_INSTALL_PREFIX=$out"
      "-DCMAKE_INSTALL_LIBDIR=lib"
      "-DBUILD_SHARED_LIBS=ON"
    ];
    __noChroot = true;

    configurePhase = ''
      runHook preConfigure
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
      # export NIX_CFLAGS_COMPILE=""
      # export NIX_LDFLAGS=""
      cmake -B build -S . \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$out \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_OSX_SYSROOT="$SDKROOT" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="26.0"
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
      # Verify installation
      if [ -f "$out/lib/libepoll-shim.dylib" ] || [ -f "$out/lib/libepoll-shim.a" ]; then
        echo "epoll-shim installed successfully for macOS"
      else
        echo "Warning: epoll-shim library not found after installation"
        ls -la $out/lib/ || true
      fi
    '';
  }
