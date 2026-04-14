{ lib, pkgs, buildPackages, common, buildModule, simulator ? false, iosToolchain ? null }:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  src = fetchSource {
    source = "github"; owner = "libffi"; repo = "libffi"; tag = "v3.5.2";
    sha256 = "sha256-tvNdhpUnOvWoC5bpezUJv+EScnowhURI7XEtYF/EnQw=";
  };
  sdkName    = if simulator then "WatchSimulator" else "WatchOS";
  xcrunSdk   = if simulator then "watchsimulator" else "watchos";
  minVerFlag = if simulator then "-mwatchos-simulator-version-min=10.0" else "-mwatchos-version-min=10.0";
in
pkgs.stdenv.mkDerivation {
  name = "libffi-watchos";
  inherit src;
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [ autoconf automake libtool pkg-config texinfo ];
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
    XCODE_CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    XCODE_CLANGXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    cat > libffi-watchos-cc <<EOF
#!/usr/bin/env bash
if [ "\$#" -eq 1 ]; then
  case "\$1" in
    -print-multi-os-directory|-print-multi-directory) echo "."; exit 0;;
  esac
fi
exec "$XCODE_CLANG" "\$@"
EOF
    cat > libffi-watchos-cxx <<EOF
#!/usr/bin/env bash
if [ "\$#" -eq 1 ]; then
  case "\$1" in
    -print-multi-os-directory|-print-multi-directory) echo "."; exit 0;;
  esac
fi
exec "$XCODE_CLANGXX" "\$@"
EOF
    chmod +x libffi-watchos-cc libffi-watchos-cxx
    if [ ! -f ./configure ]; then autoreconf -fi || true; fi
    export CC="$PWD/libffi-watchos-cc"
    export CXX="$PWD/libffi-watchos-cxx"
    export CFLAGS="-arch arm64 -isysroot $SDKROOT ${minVerFlag} -fPIC"
    export CXXFLAGS="-arch arm64 -isysroot $SDKROOT ${minVerFlag} -fPIC"
    export LDFLAGS="-arch arm64 -isysroot $SDKROOT ${minVerFlag}"
  '';
  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    ./configure --prefix=$out --host=aarch64-apple-darwin \
      --disable-docs --disable-shared --enable-static
    runHook postConfigure
  '';
}
