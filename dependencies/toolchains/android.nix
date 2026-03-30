{ lib, pkgs, androidSDK ? null }:

let
  # Android API level for the app (target SDK)
  androidApiLevel = 36;
  # NDK API level - NDK r27c supports up to API 35
  # Native libraries can be built for API 35 while app targets API 36
  androidNdkApiLevel = 35;
  # Clang triple without API suffix; always pass -D__ANDROID_API__ via androidNdkCflags.
  # API-in-triple form (e.g. aarch64-linux-android35) breaks header resolution on Linux NDK CI.
  androidTarget = "aarch64-linux-android";
  androidNdkCflags = "-D__ANDROID_API__=${toString androidNdkApiLevel}";
  androidndkPkgsMacOS =
    if pkgs.stdenv.buildPlatform.isAarch64 && pkgs.stdenv.buildPlatform.isDarwin then
      let
        ndkVersion = "27.0.12077987";
        hostTag = if pkgs.stdenv.buildPlatform.isAarch64 then "darwin-x86_64" else "darwin-x86_64";
        ndkRoot = pkgs.stdenv.mkDerivation {
          name = "android-ndk-${ndkVersion}";
          src = pkgs.fetchzip {
            url = "https://dl.google.com/android/repository/android-ndk-r27c-darwin.zip";
            sha256 = "sha256-Z4221PHrnFk7VFrs8t9qSn6X6LoIiYMJL08XQ7p+ylA=";
          };
          installPhase = ''
            mkdir -p $out
            if [ -d android-ndk-r27c ]; then
              cp -r android-ndk-r27c/* $out/
            else
              cp -r * $out/
            fi
          '';
        };
        toolchainBase = "${ndkRoot}/toolchains/llvm/prebuilt/${hostTag}";
      in
      {
        inherit ndkRoot toolchainBase;
      }
    else
      null;
  androidndkPkgs =
    if pkgs.stdenv.buildPlatform.isDarwin then
      if pkgs.stdenv.buildPlatform.isAarch64 then
        {
          clang = androidndkPkgsMacOS.toolchainBase;
          binutils = androidndkPkgsMacOS.toolchainBase;
        }
      else
        pkgs.buildPackages.androidndkPkgs
    else if pkgs.stdenv.buildPlatform.isLinux then
      # On Linux host, use the NDK from the SDK directly to avoid evaluation aborts/recursion
      if androidSDK != null then
        let
          ndkRoot = "${androidSDK.androidsdk}/libexec/android-sdk/ndk/27.0.12077973";
          toolchainBase = "${ndkRoot}/toolchains/llvm/prebuilt/linux-x86_64";
        in {
          clang = toolchainBase;
          binutils = toolchainBase;
          inherit ndkRoot;
        }
      else
        pkgs.pkgsCross.aarch64-android.buildPackages.androidndkPkgs
    else
      pkgs.buildPackages.androidndkPkgs;

in
rec {
  inherit androidApiLevel androidNdkApiLevel androidTarget androidNdkCflags;
  androidCC = "${androidndkPkgs.clang}/bin/clang";
  androidCXX = "${androidndkPkgs.clang}/bin/clang++";
  androidAR = "${androidndkPkgs.binutils}/bin/llvm-ar";
  androidSTRIP = "${androidndkPkgs.binutils}/bin/llvm-strip";
  androidRANLIB = "${androidndkPkgs.binutils}/bin/llvm-ranlib";
  androidndkRoot =
    if androidndkPkgs ? ndkRoot then androidndkPkgs.ndkRoot
    else if pkgs.stdenv.isAarch64 && pkgs.stdenv.isDarwin then
      androidndkPkgsMacOS.ndkRoot
    else
      # Try to find the NDK root from the clang path (common for Nixpkgs)
      lib.removeSuffix "/bin/clang" (toString androidndkPkgs.clang) + "/..";
  # Unified sysroot + per-API lib dir (crtbegin_*.o, libc) — required when clang triple has no API suffix.
  androidNdkSysroot = "${androidndkRoot}/sysroot";
  androidNdkAbiLibDir = "${androidNdkSysroot}/usr/lib/aarch64-linux-android/${toString androidNdkApiLevel}";
}
