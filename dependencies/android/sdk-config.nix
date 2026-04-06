{ lib, system, androidSDK ? null }:

let
  compileSdk = 36;
  targetSdk = 36;
  minSdk = 21;
  androidApiLevel = compileSdk;
  androidNdkApiLevel = 35;
  buildToolsVersion = "36.1.0";
  ndkVersion = "29.0.14206865";
  cmakeVersion = "3.22.1";
  agpVersion = "8.10.0";
  kotlinVersion = "2.0.21";
  androidTarget = "aarch64-linux-android";

  buildToolsPackageName = "build-tools-36-1-0";
  platformPackageName = "platforms-android-36";
  ndkPackageName = "ndk-29-0-14206865";
  cmakePackageName = "cmake-3-22-1";
  cmdlineToolsPackageName = "cmdline-tools-latest";
  platformToolsPackageName = "platform-tools";
  emulatorPackageName = "emulator";
  systemImagePackageName = "system-images-android-36-google-apis-playstore-arm64-v8a";
  systemImageId = "system-images;android-36;google_apis_playstore;arm64-v8a";
  emulatorSupported = system != "aarch64-linux";

  sdkPackageNames = [
    cmdlineToolsPackageName
    buildToolsPackageName
    platformToolsPackageName
    platformPackageName
    cmakePackageName
    ndkPackageName
  ] ++ lib.optionals emulatorSupported [
    emulatorPackageName
    systemImagePackageName
  ];

  sdkRoot =
    if androidSDK == null then
      null
    else if androidSDK ? sdkRoot then
      androidSDK.sdkRoot
    else if androidSDK ? androidsdk then
      "${androidSDK.androidsdk}/share/android-sdk"
    else
      null;

  # NDK prebuilt host tag mapping (host toolchain binaries).
  hostTag =
    {
      x86_64-darwin = "darwin-x86_64";
      aarch64-darwin = "darwin-arm64";
      x86_64-linux = "linux-x86_64";
      aarch64-linux = "linux-arm64";
    }
    .${system} or (throw "Unsupported Android SDK host system: ${system}");
in
{
  inherit
    agpVersion
    androidApiLevel
    androidNdkApiLevel
    androidTarget
    buildToolsPackageName
    buildToolsVersion
    cmakePackageName
    cmakeVersion
    cmdlineToolsPackageName
    compileSdk
    emulatorSupported
    emulatorPackageName
    hostTag
    kotlinVersion
    minSdk
    ndkPackageName
    ndkVersion
    platformPackageName
    platformToolsPackageName
    sdkPackageNames
    sdkRoot
    systemImageId
    systemImagePackageName
    targetSdk
    ;
}
