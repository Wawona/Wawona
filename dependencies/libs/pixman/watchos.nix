{ lib, pkgs, buildPackages, common, buildModule, simulator ? false, iosToolchain ? null }:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  src = pkgs.pixman.src;
  sdkName  = if simulator then "WatchSimulator" else "WatchOS";
  xcrunSdk = if simulator then "watchsimulator" else "watchos";
  minVerFlag = if simulator then "-mwatchos-simulator-version-min=10.0" else "-mwatchos-version-min=10.0";
in
pkgs.stdenv.mkDerivation {
  name = "pixman-watchos";
  inherit src;
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    meson ninja pkg-config
    (python3.withPackages (ps: with ps; [ setuptools pip packaging mako pyyaml ]))
  ];
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
    cat > watchos-cross-file.txt <<EOF
[binaries]
c = '$IOS_CC'
cpp = '$IOS_CXX'
ar = 'ar'
strip = 'strip'
pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
[built-in options]
c_args   = ['-arch','arm64','-isysroot','$SDKROOT','${minVerFlag}','-fPIC']
cpp_args = ['-arch','arm64','-isysroot','$SDKROOT','${minVerFlag}','-fPIC']
c_link_args   = ['-arch','arm64','-isysroot','$SDKROOT','${minVerFlag}']
cpp_link_args = ['-arch','arm64','-isysroot','$SDKROOT','${minVerFlag}']
EOF
  '';
  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    meson setup build --prefix=$out --libdir=$out/lib --cross-file=watchos-cross-file.txt \
      --buildtype=release -Ddefault_library=static \
      -Dopenmp=disabled -Dgtk=disabled -Dtests=disabled -Ddemos=disabled
    runHook postConfigure
  '';
  buildPhase  = "runHook preBuild; meson compile -C build; runHook postBuild";
  installPhase = "runHook preInstall; meson install -C build; runHook postInstall";
}
