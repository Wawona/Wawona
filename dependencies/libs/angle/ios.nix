# ANGLE for iOS — prebuilt libs (Metal backend).
# Prebuilt: jeremyfa universal XCFramework dylib slices (device + simulator).
# Full GN cross-build lives in cross-base.nix (usePrebuilt=false).
{
  lib,
  pkgs,
  buildPackages,
  common ? null,
  buildModule ? null,
  simulator ? false,
  iosToolchain ? null,
  usePrebuilt ? true,
}:

if usePrebuilt then
  let
    sources = import ./prebuilt-sources.nix { inherit lib pkgs; };
    xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
    slice =
      if simulator then
        {
          pname = "angle-ios-simulator";
          egl = sources.iosUniversal.simEgl;
          gles = sources.iosUniversal.simGles;
        }
      else
        {
          pname = "angle-ios";
          egl = sources.iosUniversal.deviceEgl;
          gles = sources.iosUniversal.deviceGles;
        };
  in
  pkgs.stdenv.mkDerivation {
    pname = slice.pname;
    version = sources.iosUniversal.version;

    src = pkgs.fetchurl {
      url = sources.iosUniversal.url;
      hash = sources.iosUniversal.hash;
    };
    nativeBuildInputs = [ pkgs.unzip ];
    dontConfigure = true;
    dontBuild = true;
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      unset DEVELOPER_DIR
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      fi
      unzip -q $src -d "$TMPDIR/angle-ios"
      root="$TMPDIR/angle-ios"
      mkdir -p $out/lib $out/include $out/nix-support

      # Do not rename dylib exports: llvm-objcopy updates the symtab but not the
      # Mach-O export trie, so renamed angle_* entry points are invisible to ld.
      # iland loads these at runtime via dlopen when link-kind is dylib.
      if [ "${if simulator then "1" else "0"}" = "1" ]; then
        lipo -thin arm64 "$root/${slice.egl}" -output $out/lib/libEGL.dylib
        lipo -thin arm64 "$root/${slice.gles}" -output $out/lib/libGLESv2.dylib
      else
        cp "$root/${slice.egl}" $out/lib/libEGL.dylib
        cp "$root/${slice.gles}" $out/lib/libGLESv2.dylib
      fi
      install_name_tool -id @rpath/libEGL.dylib $out/lib/libEGL.dylib
      install_name_tool -id @rpath/libGLESv2.dylib $out/lib/libGLESv2.dylib

      cp -r "$root/include/"* $out/include/
      echo dylib > $out/nix-support/link-kind
      runHook postInstall
    '';

    meta = with lib; {
      description =
        "ANGLE OpenGL ES for iOS ${if simulator then "Simulator" else ""} (prebuilt dylib, Metal)";
      homepage = "https://angleproject.org";
      license = licenses.bsd3;
      platforms = platforms.darwin;
    };
  }
else
  let
    xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
    sdkPlatform = if simulator then "iPhoneSimulator" else "iPhoneOS";
    minFlag =
      if simulator then
        "-mios-simulator-version-min=${iosToolchain.deploymentTarget}"
      else
        "-miphoneos-version-min=${iosToolchain.deploymentTarget}";
  in
  import ./cross-base.nix {
    inherit lib pkgs buildPackages;
    pname = if simulator then "angle-ios-simulator" else "angle-ios";

    gnExtraFlags = [
      "target_os=\"ios\""
      "target_cpu=\"arm64\""
      "target_environment=\"${if simulator then "simulator" else "device"}\""
      "angle_enable_metal=true"
      "angle_enable_vulkan=false"
      "ios_deployment_target=\"${iosToolchain.deploymentTarget}\""
      "use_custom_libcxx=false"
    ];

    preConfigureHook = ''
      unset DEVELOPER_DIR
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      fi
      export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
      export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
      export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      export AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
      export CFLAGS="-arch arm64 -isysroot $SDKROOT ${minFlag}"
      export CXXFLAGS="$CFLAGS"
      export LDFLAGS="-arch arm64 -isysroot $SDKROOT ${minFlag}"
    '';

    installHook = ''
      OUT_DIR=$(find . -maxdepth 3 -type d -name 'Release*' | head -n1)
      [ -n "$OUT_DIR" ] || OUT_DIR=out
      mkdir -p $out/lib $out/include
      shopt -s nullglob
      for lib in "$OUT_DIR"/*.a "$OUT_DIR"/obj/lib*.a "$OUT_DIR"/lib*.a; do
        base=$(basename "$lib")
        case "$base" in
          libEGL.a|libGLESv2.a|libGLESv1_CM.a|libangle_common.a) install -m644 "$lib" $out/lib/ ;;
        esac
      done
      for lib in $(find "$OUT_DIR" -name 'libEGL.a' -o -name 'libGLESv2.a' 2>/dev/null); do
        install -m644 "$lib" $out/lib/
      done
      if [ ! -f $out/lib/libEGL.a ] || [ ! -f $out/lib/libGLESv2.a ]; then
        echo "ERROR: expected libEGL.a and libGLESv2.a in ANGLE iOS build output" >&2
        find "$OUT_DIR" -name '*.a' | head -20 >&2 || true
        exit 1
      fi
      cp -rv ../../include/EGL ../../include/GLES2 ../../include/GLES3 ../../include/KHR $out/include/
      echo static > $out/nix-support/link-kind
    '';
  }
