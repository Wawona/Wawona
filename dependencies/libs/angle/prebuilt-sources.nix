# Pinned prebuilt ANGLE artifacts (community builds — see dependencies/libs/angle/README.md).
{
  lib,
  pkgs,
  ...
}:

{
  iosArm64 = {
    version = "a96fca8";
    url = "https://github.com/XCSoar/angle-libs/releases/download/a96fca8/angle-ios-arm64-a96fca8d5ee2ca61e8de419e38cd577579281c9e.tar.gz";
    hash = "sha256-lt5lFY3DHGQ4Eks5tXHaiLu32tUKvextMDVpzDq4Z44=";
    unpackDir = "angle-ios-arm64-a96fca8d5ee2ca61e8de419e38cd577579281c9e";
    eglLib = "libEGL_static.a";
    glesLib = "libGLESv2_static.a";
  };

  # Universal XCFramework dylibs (simulator + device). Simulator Nix builds use the
  # ios-arm64_x86_64-simulator slice; device builds use XCSoar static archives above.
  iosUniversal = {
    version = "3100009";
    url = "https://github.com/jeremyfa/build-angle/releases/download/angle-3100009/angle-ios-universal.zip";
    hash = "sha256-FKxonp7zx2+y32zuOCoZKKWK/90XjgFaNhpEX7XOa9w=";
    simEgl = "libEGL.xcframework/ios-arm64_x86_64-simulator/libEGL.framework/libEGL";
    simGles = "libGLESv2.xcframework/ios-arm64_x86_64-simulator/libGLESv2.framework/libGLESv2";
    deviceEgl = "libEGL.xcframework/ios-arm64/libEGL.framework/libEGL";
    deviceGles = "libGLESv2.xcframework/ios-arm64/libGLESv2.framework/libGLESv2";
  };

  androidArm64 = {
    version = "chromium-7151";
    url = "https://github.com/kubuszok/sge-angle-natives/releases/download/chromium-7151/angle-android-arm64.tar.gz";
    hash = "sha256-6TquznsQSNyx+rkQK13wAcil2D7j28T8odC2zxwdGPk=";
    shared = true;
  };
}
