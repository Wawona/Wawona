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
  xcodeTarget ? "Wawona-iOS",
  # nativeSdk: base SDK name without "simulator" suffix
  # e.g. "iphoneos" for iOS/iPadOS, "watchos" for watchOS
  nativeSdk ? "iphoneos",
  # platformName: human-readable destination platform for xcodebuild -destination
  # e.g. "iOS", "watchOS"
  platformName ? "iOS",
  bundleId ? "com.aspauldingcode.Wawona",
  # Path to the Apple cross-compile toolchain (xcode-wrapper). Defaults to the
  # legacy in-tree copy; Wawona's flake overrides this with the wwn-toolchain
  # input store path so the moved dir can be deleted.
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
  # xcodebuild -sdk wants iphonesimulator / watchsimulator, not "iphoneos"+"simulator".
  sdk =
    if !simulator then
      nativeSdk
    else if nativeSdk == "iphoneos" then
      "iphonesimulator"
    else if nativeSdk == "appletvos" then
      "appletvsimulator"
    else if nativeSdk == "watchos" then
      "watchsimulator"
    else if nativeSdk == "xros" then
      "xrsimulator"
    else
      throw "ios.nix: simulator build needs sdk mapping for nativeSdk=${nativeSdk}";
  destinationPlatform = if simulator then "${platformName} Simulator" else platformName;
in
# Xcode 26+ may mount Metal.xctoolchain under $HOME/.../DVTDownloads (HOME=$TMPDIR/home
# in build-app.nix). Nix then fails cleanup with:
#   error: cannot unlink ".../MetalToolchain/.../RestoreVersion.plist": Read-only file system
# Detach those mounts before the build phase returns so the temp tree is removable.
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
  # IPA builds sign via fastlane match (host keychain/profiles), not Xcode Automatic.
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
    # Impure Ship: beta (stores): fastlane match installs App Store profiles; force
    # Manual signing so xcodebuild does not look for a Development account.
    ++ lib.optionals (releaseBuild && generateIPA) [
      ''CODE_SIGN_STYLE=''${WAWONA_CODE_SIGN_STYLE:-Manual}''
      ''CODE_SIGN_IDENTITY="''${WAWONA_CODE_SIGN_IDENTITY:-Apple Distribution}"''
      ''PROVISIONING_PROFILE_SPECIFIER="''${WAWONA_PROVISIONING_PROFILE_SPECIFIER:-match AppStore ${bundleId}}"''
    ]
    # build-app.nix forces ONLY_ACTIVE_ARCH=NO; that pulls x86_64 simulator slice on Apple Silicon.
    # Swift macro plugin server often breaks for that slice (malformed response / sandbox_apply).
    ++ lib.optionals simulator [ ''ONLY_ACTIVE_ARCH=YES'' ]
  );
}).overrideAttrs (import ./match-host-signing-attrs.nix { inherit lib; })
