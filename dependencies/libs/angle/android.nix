# ANGLE for Android — prebuilt shared libs (native GLES/Vulkan backend).
# Static GN cross-build lives in cross-base.nix (usePrebuilt=false).
{
  lib,
  pkgs,
  buildPackages,
  common ? null,
  buildModule ? null,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  usePrebuilt ? true,
}:

if usePrebuilt then
  let
    sources = import ./prebuilt-sources.nix { inherit lib pkgs; };
    src = pkgs.fetchurl {
      url = sources.androidArm64.url;
      hash = sources.androidArm64.hash;
    };
  in
  pkgs.stdenv.mkDerivation {
    pname = "angle-android";
    version = sources.androidArm64.version;

    inherit src;
    dontConfigure = true;
    dontBuild = true;
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      tar -xzf $src
      mkdir -p $out/lib $out/include
      cp lib/libEGL.so $out/lib/
      cp lib/libGLESv2.so $out/lib/
      cp -r include/* $out/include/
      runHook postInstall
    '';

    meta = with lib; {
      description = "ANGLE OpenGL ES for Android (prebuilt shared)";
      homepage = "https://angleproject.org";
      license = licenses.bsd3;
      platforms = [ "aarch64-linux-android" ];
    };
  }
else
  let
    ndkRoot = androidToolchain.androidndkRoot;
    ndkHostTag = androidToolchain.androidNdkHostTag;
  in
  import ./cross-base.nix {
    inherit lib pkgs buildPackages;
    pname = "angle-android";

    gnExtraFlags = [
      "target_os=\"android\""
      "target_cpu=\"arm64\""
      "android_ndk_root=\"${ndkRoot}\""
      "android_ndk_api_level=${toString androidToolchain.androidNdkApiLevel}"
      "angle_enable_vulkan=true"
      "angle_enable_metal=false"
    ];

    preConfigureHook = ''
      export CC="${androidToolchain.androidCC}"
      export CXX="${androidToolchain.androidCXX}"
      export AR="${androidToolchain.androidAR}"
      export PATH="${ndkRoot}/toolchains/llvm/prebuilt/${ndkHostTag}/bin:$PATH"
    '';

    installHook = ''
      OUT_DIR=$(find . -maxdepth 3 -type d -name 'Release*' | head -n1)
      [ -n "$OUT_DIR" ] || OUT_DIR=out
      mkdir -p $out/lib $out/include
      for lib in $(find "$OUT_DIR" -name 'libEGL.a' -o -name 'libGLESv2.a' 2>/dev/null); do
        install -m644 "$lib" $out/lib/
      done
      if [ ! -f $out/lib/libEGL.a ] || [ ! -f $out/lib/libGLESv2.a ]; then
        echo "ERROR: expected libEGL.a and libGLESv2.a in ANGLE Android build output" >&2
        find "$OUT_DIR" -name '*.a' | head -20 >&2
        exit 1
      fi
      cp -rv ../../include/EGL ../../include/GLES2 ../../include/GLES3 ../../include/KHR $out/include/
    '';
  }
