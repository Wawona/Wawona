{ lib, pkgs, androidSDK ? null, allowExperimentalFallback ? false }:

let
  androidConfig = import ../android/sdk-config.nix {
    inherit lib androidSDK;
    system = pkgs.stdenv.hostPlatform.system;
  };

  androidApiLevel = androidConfig.androidApiLevel;
  androidNdkApiLevel = androidConfig.androidNdkApiLevel;
  androidTarget = androidConfig.androidTarget;
  androidNdkCflags = "-fuse-ld=lld";
  hostTagRequested = androidConfig.hostTag;

  ndkRoot =
    if androidConfig.sdkRoot == null then
      throw "androidSDK with sdkRoot/androidsdk is required for Android toolchain resolution"
    else
      "${androidConfig.sdkRoot}/ndk/${androidConfig.ndkVersion}";

  nativeToolchainBase = "${ndkRoot}/toolchains/llvm/prebuilt/${hostTagRequested}";
  compatHostTag =
    if hostTagRequested == "linux-arm64" then
      "linux-x86_64"
    else if hostTagRequested == "darwin-arm64" then
      "darwin-x86_64"
    else
      hostTagRequested;
  compatToolchainBase = "${ndkRoot}/toolchains/llvm/prebuilt/${compatHostTag}";
  nativePrebuiltExists = builtins.pathExists nativeToolchainBase;
  compatPrebuiltExists = builtins.pathExists compatToolchainBase;
  useSourceFallback =
    if nativePrebuiltExists then
      false
    else if allowExperimentalFallback && compatPrebuiltExists then
      true
    else
      throw ''
        Android NDK prebuilt toolchain for host tag '${hostTagRequested}' is unavailable at:
          ${nativeToolchainBase}

        Stable CI policy requires native host prebuilts only.
        If you want to try the compatibility fallback path, opt in explicitly with:
          WAWONA_ANDROID_EXPERIMENTAL_FALLBACK=1
        and run with --impure.
      '';
  toolchainBase = if useSourceFallback then compatToolchainBase else nativeToolchainBase;
  prebuiltCC = "${nativeToolchainBase}/bin/${androidTarget}${toString androidNdkApiLevel}-clang";
  prebuiltCXX = "${nativeToolchainBase}/bin/${androidTarget}${toString androidNdkApiLevel}-clang++";
  prebuiltAR = "${nativeToolchainBase}/bin/llvm-ar";
  prebuiltSTRIP = "${nativeToolchainBase}/bin/llvm-strip";
  prebuiltRANLIB = "${nativeToolchainBase}/bin/llvm-ranlib";
  useCompatNdkDriver = hostTagRequested == "darwin-arm64" && useSourceFallback;
  fallbackCC =
    if useCompatNdkDriver then
      "${toolchainBase}/bin/clang"
    else
      "${pkgs.llvmPackages.clang-unwrapped}/bin/clang";
  fallbackCXX =
    if useCompatNdkDriver then
      "${toolchainBase}/bin/clang++"
    else
      "${pkgs.llvmPackages.clang-unwrapped}/bin/clang++";
  fallbackLld =
    if useCompatNdkDriver then
      "${toolchainBase}/bin/ld.lld"
    else
      "${pkgs.llvmPackages.lld}/bin/ld.lld";
  fallbackAR =
    if useCompatNdkDriver then
      "${toolchainBase}/bin/llvm-ar"
    else
      "${pkgs.llvmPackages.bintools}/bin/ar";
  fallbackSTRIP =
    if useCompatNdkDriver then
      "${toolchainBase}/bin/llvm-strip"
    else
      "${pkgs.llvmPackages.bintools}/bin/strip";
  fallbackRANLIB =
    if useCompatNdkDriver then
      "${toolchainBase}/bin/llvm-ranlib"
    else
      "${pkgs.llvmPackages.bintools}/bin/ranlib";
  ndkSysroot = "${toolchainBase}/sysroot";
  ndkAbiLibDir = "${ndkSysroot}/usr/lib/aarch64-linux-android/${toString androidNdkApiLevel}";

  # Common compile-only detector: when clang is invoked with -c/-S/-E/-fsyntax-only
  # it does not link, so passing linker flags (-L, -fuse-ld, -Wl,-rpath-link) makes
  # clang emit -Wunused-command-line-argument. Meson's feature checks compile with
  # -Werror=unused-command-line-argument, which turns those into hard errors (seen
  # in fontconfig's gperf-len-type probe). Drop the linker flags in that case.
  adaptiveProbeAndLinkDetect = ''
    # Autoconf/libtool GCC probe compatibility.
    if [ "$#" -eq 1 ]; then
      case "$1" in
        -print-multi-os-directory|-print-multi-directory)
          echo "."
          exit 0
          ;;
      esac
    fi

    compile_only=0
    for arg in "$@"; do
      case "$arg" in
        -c|-S|-E|-fsyntax-only) compile_only=1 ;;
      esac
    done
    if [ "$compile_only" -eq 1 ]; then
      LINK_ARGS=()
    else
      LINK_ARGS=(-L"${ndkAbiLibDir}" -Wl,-rpath-link,"${ndkAbiLibDir}" -fuse-ld="${fallbackLld}")
    fi
  '';

  adaptiveCC = pkgs.writeShellScript "android-cc-adaptive" ''
    ${adaptiveProbeAndLinkDetect}

    # For arm64-host fallback, use the fallback clang's own resource headers.
    # Mixing NDK prebuilt resource headers with fallback clang triggers NEON
    # builtin mismatches (seen in zstd-android on linux-aarch64 CI).
    # NB: do not pass -D__ANDROID_API__ here. The target triple already encodes the
    # API level, and the NDK headers define __ANDROID_API__ = __ANDROID_MIN_SDK_VERSION__;
    # redefining it textually trips -Wmacro-redefined, which breaks meson feature
    # checks that compile with -Werror (e.g. glib's size_t-typedef probe).
    exec "${fallbackCC}" \
      --target=${androidTarget}${toString androidNdkApiLevel} \
      --sysroot="${ndkSysroot}" \
      -B"${ndkAbiLibDir}" \
      "''${LINK_ARGS[@]}" \
      "$@"
  '';

  adaptiveCXX = pkgs.writeShellScript "android-cxx-adaptive" ''
    ${adaptiveProbeAndLinkDetect}

    # Keep fallback C++ path symmetric with C path above.
    exec "${fallbackCXX}" \
      --target=${androidTarget}${toString androidNdkApiLevel} \
      --sysroot="${ndkSysroot}" \
      -B"${ndkAbiLibDir}" \
      "''${LINK_ARGS[@]}" \
      "$@"
  '';

  androidGnuAR = pkgs.writeShellScript "android-gnu-ar" ''
    exec "${if useSourceFallback then fallbackAR else prebuiltAR}" --format=gnu "$@"
  '';
  androidGnuRANLIB = pkgs.writeShellScript "android-gnu-ranlib" ''
    exec "${if useSourceFallback then fallbackRANLIB else prebuiltRANLIB}" "$@"
  '';

in
rec {
  inherit androidApiLevel androidNdkApiLevel androidTarget androidNdkCflags;
  # Contract: callers should consume these exported values rather than
  # reconstructing host-tag/prebuilt paths in module-local code.
  androidNdkHostTag = hostTagRequested;
  androidNdkCompatHostTag = compatHostTag;
  androidNdkNativePrebuiltExists = nativePrebuiltExists;
  androidNdkCompatPrebuiltExists = compatPrebuiltExists;
  androidNdkExperimentalFallbackEnabled = allowExperimentalFallback;
  androidNdkIsFallback = useSourceFallback;
  androidNdkToolchainBase = toolchainBase;

  androidCC = if useSourceFallback then adaptiveCC else prebuiltCC;
  androidCXX = if useSourceFallback then adaptiveCXX else prebuiltCXX;
  androidAR = androidGnuAR;
  androidSTRIP = if useSourceFallback then fallbackSTRIP else prebuiltSTRIP;
  androidRANLIB = androidGnuRANLIB;
  androidndkRoot = ndkRoot;
  # Unified sysroot + per-API lib dir (crtbegin_*.o, libc) — required when clang triple has no API suffix.
  androidNdkSysroot = ndkSysroot;
  androidNdkAbiLibDir = ndkAbiLibDir;
  androidNdkAbiLibDirFallback = "${androidNdkSysroot}/usr/lib/aarch64-linux-android";
}
