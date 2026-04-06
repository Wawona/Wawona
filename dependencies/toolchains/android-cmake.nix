{ lib, pkgs, androidToolchain }:

let
  useWrappedCrossCmake = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
  androidApi = toString androidToolchain.androidNdkApiLevel;
  ndkIncludeDir = "${androidToolchain.androidNdkSysroot}/usr/include";
  ndkLibSearchPaths = [
    androidToolchain.androidNdkAbiLibDir
    androidToolchain.androidNdkAbiLibDirFallback
  ];
  libPathCandidates =
    libName:
    let
      base = "lib${libName}";
    in
    [
      "${androidToolchain.androidNdkAbiLibDir}/${base}.so"
      "${androidToolchain.androidNdkAbiLibDirFallback}/${base}.so"
      "${androidToolchain.androidNdkAbiLibDir}/${base}.a"
      "${androidToolchain.androidNdkAbiLibDirFallback}/${base}.a"
    ];
in
rec {
  inherit useWrappedCrossCmake;

  # Shared cross-mode flags for Android CMake builds.
  #
  # For linux-aarch64 hosts we intentionally use Linux cross mode with an Android
  # sysroot because CMake's Android platform init path can require legacy NDK
  # layouts that are not always present in modern SDK compositions.
  mkCrossFlags =
    {
      abi ? "arm64-v8a",
      useAndroidToolchainFile ? false,
    }:
    if useWrappedCrossCmake then
      [
        "-DCMAKE_SYSTEM_NAME=Linux"
        "-DCMAKE_SYSROOT=${androidToolchain.androidNdkSysroot}"
        "-DCMAKE_FIND_ROOT_PATH=${androidToolchain.androidNdkSysroot}"
        "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"
        "-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY"
        "-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
        "-DCMAKE_INCLUDE_PATH=${ndkIncludeDir}"
        "-DCMAKE_LIBRARY_PATH=${lib.concatStringsSep ";" ndkLibSearchPaths}"
      ]
    else if useAndroidToolchainFile then
      [
        "-DCMAKE_TOOLCHAIN_FILE=${androidToolchain.androidndkRoot}/build/cmake/android.toolchain.cmake"
        "-DANDROID_ABI=${abi}"
        "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
        "-DANDROID_PLATFORM=android-${androidApi}"
      ]
    else
      [
        "-DCMAKE_SYSTEM_NAME=Android"
        "-DCMAKE_ANDROID_ARCH_ABI=${abi}"
        "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
        "-DCMAKE_ANDROID_API=${androidApi}"
      ];

  androidLib =
    libName:
    let
      candidates = libPathCandidates libName;
      existing = builtins.filter builtins.pathExists candidates;
    in
    if existing != [ ] then builtins.head existing else builtins.head candidates;

  cmakeLibFlag =
    {
      variable,
      libName,
    }:
    "-D${variable}_LIBRARY=${androidLib libName}";

  cmakeExactFlag =
    {
      variable,
      value,
    }:
    "-D${variable}=${value}";
}
