{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = iosToolchain;
  libffiSource = {
    source = "github";
    owner = "libffi";
    repo = "libffi";
    tag = "v3.5.2";
    sha256 = "sha256-tvNdhpUnOvWoC5bpezUJv+EScnowhURI7XEtYF/EnQw=";
  };
  src = fetchSource libffiSource;
  buildFlags = [
    "--disable-docs"
    "--disable-shared"
    "--enable-static"
  ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "libffi-ios";
  inherit src patches;

  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    libtool
    pkg-config
    texinfo
  ];
  buildInputs = [ ];
  preConfigure = ''
    ${xcodeUtils.mkIOSBuildEnv { inherit simulator; }}
    export IOS_SDK="$SDKROOT"
    if [ ! -f ./configure ]; then
      autoreconf -fi || autogen.sh || true
    fi
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    cat > libffi-ios-cc <<'EOF'
    #!/usr/bin/env bash
    if [ "$#" -eq 1 ]; then
      case "$1" in
        -print-multi-os-directory|-print-multi-directory)
          echo "."
          exit 0
          ;;
      esac
    fi
    exec "$XCODE_CLANG" "$@"
    EOF
    cat > libffi-ios-cxx <<'EOF'
    #!/usr/bin/env bash
    if [ "$#" -eq 1 ]; then
      case "$1" in
        -print-multi-os-directory|-print-multi-directory)
          echo "."
          exit 0
          ;;
      esac
    fi
    exec "$XCODE_CLANGXX" "$@"
    EOF
    chmod +x libffi-ios-cc libffi-ios-cxx

    export CC="$PWD/libffi-ios-cc"
    export CXX="$PWD/libffi-ios-cxx"
    export CFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC"
    export CXXFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC"
    export LDFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG"
  '';
  configurePhase = ''
    runHook preConfigure
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    ./configure --prefix=$out --host=aarch64-apple-darwin ${
      lib.concatMapStringsSep " " (flag: flag) buildFlags
    }
    runHook postConfigure
  '';
  configureFlags = buildFlags;
}
