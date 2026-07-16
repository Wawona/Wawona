{
  lib,
  pkgs,
  wawonaSrc,
  wawonaVersion ? null,
  simulator ? true,
  xcodeProject,
  TEAM_ID ? null,
  release ? false,
  generateIPA ? false,
  generateXCArchive ? false,
  certificateFile ? null,
  certificatePassword ? null,
  provisioningProfile ? null,
  codeSignIdentity ? null,
  signMethod ? null,
  automaticProvisioning ? false,
  # Per-platform overrides
  # target: Xcode scheme/target name
  xcodeTarget ? "Wawona-iPadOS",
  # nativeSdk: base SDK name without "simulator" suffix
  # e.g. "iphoneos" for iOS/iPadOS, "watchos" for watchOS
  nativeSdk ? "iphoneos",
  # platformName: human-readable destination platform for xcodebuild -destination
  # e.g. "iOS", "watchOS"
  platformName ? "iOS",
  bundleId ? "com.aspauldingcode.Wawona",
  applePath,
  ...
}:

let
  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;
  xcodeUtils = import applePath { inherit lib pkgs TEAM_ID; };
  releaseBuild = release || generateIPA || generateXCArchive;
  developmentTeam = if TEAM_ID == null || TEAM_ID == "" then null else TEAM_ID;
  autoSigning = automaticProvisioning || developmentTeam != null;
  sdk =
    if !simulator then
      nativeSdk
    else if nativeSdk == "iphoneos" then
      "iphonesimulator"
    else if nativeSdk == "watchos" then
      "watchsimulator"
    else
      throw "ipados.nix: simulator build needs sdk mapping for nativeSdk=${nativeSdk}";
  destinationPlatform = if simulator then "${platformName} Simulator" else platformName;
in
(xcodeUtils.buildApp {
  name = "Wawona";
  src = xcodeProject;
  target = xcodeTarget;
  # Xcode requires -scheme (not just -target) when -archivePath is set for IPA.
  scheme = xcodeTarget;
  inherit sdk;
  __noChroot = true;
  configuration = if releaseBuild then "Release" else "Debug";
  release = releaseBuild;
  inherit
    certificateFile
    certificatePassword
    provisioningProfile
    codeSignIdentity
    signMethod
    generateIPA
    generateXCArchive
    ;
  matchHostSigning = generateIPA;
  automaticProvisioning = autoSigning && !generateIPA;
  developmentTeam = developmentTeam;
  inherit bundleId;
  appVersion = projectVersion;
  xcodeFlags = lib.concatStringsSep " " (
    [
      ''-project Wawona.xcodeproj''
      ''-jobs ''${WAWONA_XCODEBUILD_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}''
      ''-destination "generic/platform=${destinationPlatform}"''
    ]
    ++ lib.optionals (!releaseBuild) [
      ''CODE_SIGNING_ALLOWED=NO''
      ''CODE_SIGNING_REQUIRED=NO''
    ]
    ++ lib.optionals (releaseBuild && generateIPA) [
      ''CODE_SIGN_STYLE=''${WAWONA_CODE_SIGN_STYLE:-Manual}''
      ''CODE_SIGN_IDENTITY="''${WAWONA_CODE_SIGN_IDENTITY:-Apple Distribution}"''
      ''PROVISIONING_PROFILE_SPECIFIER="''${WAWONA_PROVISIONING_PROFILE_SPECIFIER:-match AppStore ${bundleId}}"''
    ]
    ++ lib.optionals simulator [ ''ONLY_ACTIVE_ARCH=YES'' ]
  );
}).overrideAttrs (import ./match-host-signing-attrs.nix { inherit lib; })
