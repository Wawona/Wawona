# Resolve Apple mobile cross-compile platform flags from iosToolchain tool flags.
# Used by shared ios.nix recipes (cairo, glib, weston, …) when built for
# iOS, iPadOS, tvOS, watchOS, or visionOS via buildFor* routing.
{ iosToolchain, simulator ? false }:

let
  isTVOS = (iosToolchain ? isTVOSToolchain) && iosToolchain.isTVOSToolchain;
  isVisionOS = iosToolchain.isVisionOSToolchain or false;
  isWatchOS = iosToolchain.isWatchOSToolchain or false;
  defaultMin = iosToolchain.deploymentTarget or "17.0";
  minVersion =
    if isWatchOS then "10.0"
    else if isVisionOS then "26.0"
    else if isTVOS then "17.0"
    else defaultMin;
  platform =
    if isWatchOS then "watchos"
    else if isVisionOS then "visionos"
    else if isTVOS then "tvos"
    else "ios";
  sdkPlatform =
    if isWatchOS then
      if simulator then "WatchSimulator" else "WatchOS"
    else if isVisionOS then
      if simulator then "XRSimulator" else "XROS"
    else if isTVOS then
      if simulator then "AppleTVSimulator" else "AppleTVOS"
    else
      if simulator then "iPhoneSimulator" else "iPhoneOS";
  xcrunSdk =
    if isWatchOS then
      if simulator then "watchsimulator" else "watchos"
    else if isVisionOS then
      if simulator then "xrsimulator" else "xros"
    else if isTVOS then
      if simulator then "appletvsimulator" else "appletvos"
    else
      if simulator then "iphonesimulator" else "iphoneos";
  minVerFlag =
    if isVisionOS && simulator then "-target arm64-apple-xros${minVersion}-simulator"
    else if isVisionOS then "-target arm64-apple-xros${minVersion}"
    else if isWatchOS && simulator then "-mwatchos-simulator-version-min=${minVersion}"
    else if isWatchOS then "-mwatchos-version-min=${minVersion}"
    else if isTVOS && simulator then "-mtvos-simulator-version-min=${minVersion}"
    else if isTVOS then "-mtvos-version-min=${minVersion}"
    else if simulator then "-mios-simulator-version-min=${minVersion}"
    else "-miphoneos-version-min=${minVersion}";
  linkerTarget =
    if isVisionOS && simulator then "arm64-apple-xros${minVersion}-simulator"
    else if isVisionOS then "arm64-apple-xros${minVersion}"
    else null;
  cmakeSystemName =
    if isWatchOS || isVisionOS || isTVOS then "Darwin" else "iOS";
  mesonSubsystem =
    if isWatchOS then "watchos"
    else if isTVOS then "tvos"
    else if isVisionOS then "xros"
    else "ios";
in
{
  inherit isTVOS isVisionOS isWatchOS platform minVersion sdkPlatform xcrunSdk minVerFlag cmakeSystemName linkerTarget mesonSubsystem;
}
