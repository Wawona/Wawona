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
      export MACOSX_DEPLOYMENT_TARGET="26.0"
      # export NIX_CFLAGS_COMPILE=""
      # export NIX_LDFLAGS=""
      cmake -B build -S . \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$out \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DBUILD_SHARED_LIBS=ON \
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
