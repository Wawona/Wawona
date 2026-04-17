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
  xcodeTarget ? "Wawona-visionOS",
  nativeSdk ? "xros",
  platformName ? "visionOS",
  bundleId ? "com.aspauldingcode.Wawona",
  ...
} @ args:

import ./ios.nix (args // {
  inherit
    xcodeTarget
    nativeSdk
    platformName
    bundleId
    ;
})
