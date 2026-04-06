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
  bundleId ? "com.aspauldingcode.Wawona",
  ...
}:

let
  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit lib pkgs TEAM_ID; };
  releaseBuild = release || generateIPA || generateXCArchive;
  developmentTeam = if TEAM_ID == null || TEAM_ID == "" then null else TEAM_ID;
  autoSigning = automaticProvisioning || developmentTeam != null;
in
xcodeUtils.buildApp {
  name = "Wawona";
  src = xcodeProject;
  target = "Wawona-iOS";
  sdk = if simulator then "iphonesimulator" else "iphoneos";
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
  automaticProvisioning = autoSigning;
  developmentTeam = developmentTeam;
  inherit bundleId;
  appVersion = projectVersion;
  xcodeFlags = lib.concatStringsSep " " (
    [
      ''-project Wawona.xcodeproj''
      ''-jobs 1''
      ''-destination "generic/platform=${if simulator then "iOS Simulator" else "iOS"}"''
    ]
    ++ lib.optionals (!releaseBuild) [
      ''CODE_SIGNING_ALLOWED=NO''
      ''CODE_SIGNING_REQUIRED=NO''
    ]
  );
}
