# Shared meson cross-compile setup for Apple mobile ios.nix recipes.
# Writes ios-cross-file.txt (and optionally native-file.txt) after resolving
# platform SDK + min-version flags via apple-mobile-platform.nix.
{ lib, buildPackages, xcodeUtils, iosToolchain, simulator ? false }:

let
  platformInfo = import ./apple-mobile-platform.nix;
  mobile = platformInfo { inherit iosToolchain simulator; };
  polyfillsHeader = "${builtins.path { path = ./apple-polyfills.h; name = "apple-polyfills.h"; }}";
  polyfillArg = ", '-include', '${polyfillsHeader}'";
in
{
  inherit mobile;

  preConfigureShell =
    {
      includePolyfills ? false,
      needsExeWrapper ? false,
      extraCrossBinaries ? "",
    }:
    let
      polyfillSuffix = if includePolyfills then polyfillArg else "";
      exeWrapperBlock =
        if needsExeWrapper then
          ''
            [properties]
            needs_exe_wrapper = true

          ''
        else
          "";
      compileArgs =
        if mobile.isVisionOS then
          "['-target', '${mobile.linkerTarget}', '-isysroot', '\$SDKROOT', '-fPIC'${polyfillSuffix}]"
        else
          "['-arch', 'arm64', '-isysroot', '\$SDKROOT', '${mobile.minVerFlag}', '-fPIC'${polyfillSuffix}]";
      linkArgs =
        if mobile.isVisionOS then
          "['-target', '${mobile.linkerTarget}', '-isysroot', '\$SDKROOT']"
        else
          "['-arch', 'arm64', '-isysroot', '\$SDKROOT', '${mobile.minVerFlag}']";
    in
    ''
      unset DEVELOPER_DIR
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      fi
      export SDKROOT="$DEVELOPER_DIR/Platforms/${mobile.sdkPlatform}.platform/Developer/SDKs/${mobile.sdkPlatform}.sdk"
      if [ ! -d "$SDKROOT" ]; then
        echo "ERROR: ${mobile.sdkPlatform} SDK not found. Build cannot proceed." >&2
        exit 1
      fi
      export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

      export NIX_CFLAGS_COMPILE=""
      export NIX_CXXFLAGS_COMPILE=""
      export NIX_LDFLAGS=""
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"

      cat > ios-cross-file.txt <<EOF
      [binaries]
      c = '$IOS_CC'
      cpp = '$IOS_CXX'
      ${extraCrossBinaries}ar = 'ar'
      strip = 'strip'
      pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

      [host_machine]
      system = 'darwin'
      cpu_family = 'aarch64'
      cpu = 'aarch64'
      endian = 'little'
      subsystem = '${mobile.mesonSubsystem}'

      ${exeWrapperBlock}[built-in options]
      c_args = ${compileArgs}
      cpp_args = ${compileArgs}
      c_link_args = ${linkArgs}
      cpp_link_args = ${linkArgs}
      EOF
    '';

  nativeFileShell = ''
    MACOS_SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
    NATIVE_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    NATIVE_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    cat > native-file.txt <<EOF
    [binaries]
    c = '$NATIVE_CC'
    cpp = '$NATIVE_CXX'
    ar = 'ar'
    strip = 'strip'
    pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'

    [built-in options]
    c_args = ['-isysroot', '$MACOS_SDK_PATH']
    cpp_args = ['-isysroot', '$MACOS_SDK_PATH']
    c_link_args = ['-isysroot', '$MACOS_SDK_PATH']
    cpp_link_args = ['-isysroot', '$MACOS_SDK_PATH']
    EOF
  '';
}
