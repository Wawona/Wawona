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
  modeB ? false,
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
  # Product minimum OS.  This is deliberately separate from the newest SDK.
  deploymentTarget ? null,
  # Path to the Apple cross-compile toolchain (xcode-wrapper). Defaults to the
  # legacy in-tree copy; Wawona's flake overrides this with the wwn-toolchain
  # input store path so the moved dir can be deleted.
  applePath,
  # First-class Rust backend so product xcodebuild copies libwawona.a instead of
  # nested `nix build --impure` (Gate: products iOS sim was recompiling rust).
  rustBackend ? null,
  mobileGuestArtifacts ? null,
  mobileGuestArtifacts16k ? null,
  mobileContainerGuestArtifacts ? null,
  companionBackends ? { },
  ...
}:

let
  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;
  xcodeUtils = import applePath { inherit lib pkgs TEAM_ID; };
  releaseBuild = release || generateIPA || generateXCArchive || modeB;
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
  # Mode B uses the Release Xcode configuration but remains an unsigned app
  # build. Its executable receives the TrollStore ldid signature afterward.
  release = releaseBuild && !modeB;
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
      # generic + arch=arm64 does not match Xcode's placeholder
      # "Any iOS Simulator Device" when no named runtime is visible in the
      # builder. ARCHS=arm64 below still pins the slice.
      ''-destination "generic/platform=${destinationPlatform}"''
    ]
    ++ lib.optionals (!releaseBuild || modeB) [
      ''CODE_SIGNING_ALLOWED=NO''
      ''CODE_SIGNING_REQUIRED=NO''
    ]
    ++ lib.optionals modeB [
      # Command-line scope reaches WawonaModel as well as the app target, so
      # Swift capability gates are compiled for this immutable product flavor.
      ''SWIFT_ACTIVE_COMPILATION_CONDITIONS="WWN_MODE_B"''
    ]
    ++ lib.optionals (deploymentTarget != null) [
      ''IPHONEOS_DEPLOYMENT_TARGET=${deploymentTarget}''
    ]
    ++ lib.optionals (mobileGuestArtifacts != null) [
      # xcodebuild does not preserve arbitrary process environment variables
      # in Run Script phases. Pass these as build settings so the guest embed
      # scripts receive the resolved artifact paths.
      ''WAWONA_MOBILE_GUEST_DIR="${mobileGuestArtifacts}"''
    ]
    ++ lib.optionals (mobileGuestArtifacts16k != null) [
      ''WAWONA_MOBILE_GUEST_16K_DIR="${mobileGuestArtifacts16k}"''
    ]
    ++ lib.optionals (mobileContainerGuestArtifacts != null) [
      ''WAWONA_MOBILE_CONTAINER_GUEST_DIR="${mobileContainerGuestArtifacts}"''
    ]
    # Impure Ship: beta (stores): fastlane match installs App Store profiles; force
    # Manual signing so xcodebuild does not look for a Development account.
    ++ lib.optionals (releaseBuild && generateIPA) [
      ''CODE_SIGN_STYLE=''${WAWONA_CODE_SIGN_STYLE:-Manual}''
      ''CODE_SIGN_IDENTITY="''${WAWONA_CODE_SIGN_IDENTITY:-Apple Distribution}"''
      ''PROVISIONING_PROFILE_SPECIFIER="''${WAWONA_PROVISIONING_PROFILE_SPECIFIER:-match AppStore ${bundleId}}"''
    ]
    # build-app.nix forces ONLY_ACTIVE_ARCH=NO; generic/platform without arch=
    # still compiles x86_64+arm64 Swift (WawonaUIContracts on macos-26).
    ++ lib.optionals simulator [
      ''ONLY_ACTIVE_ARCH=YES''
      ''ARCHS=arm64''
      ''EXCLUDED_ARCHS="x86_64 i386"''
    ]
  );
}).overrideAttrs (old:
let
  injected = (import ./inject-xcode-backend-env.nix {
  inherit
    lib
    rustBackend
    xcodeTarget
    companionBackends
    mobileGuestArtifacts
    mobileGuestArtifacts16k
    mobileContainerGuestArtifacts
    ;
  }) old;
in injected // {
  # Validate the final bundle after all Xcode and stdenv packaging phases.
  postFixup = (old.postFixup or "") + lib.optionalString
    (nativeSdk == "iphoneos" && !releaseBuild) ''
      # Unsigned Nix products have contained an empty back-deployment runtime.
      # Copy the real Apple library and retain the native arm64 slice in the
      # final unsigned bundle. Signed/archive products are never modified here.
      wawona_sim_app="$out/Wawona.app"
      wawona_sim_runtime="$wawona_sim_app/Frameworks/libswift_Concurrency.dylib"
      echo "Restoring final unsigned Swift runtime: $wawona_sim_runtime"
      /usr/bin/xcrun swift-stdlib-tool --copy --verbose \
        --platform ${if simulator then "iphonesimulator" else "iphoneos"} \
        --source-libraries "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.5/${if simulator then "iphonesimulator" else "iphoneos"}" \
        --scan-executable "$wawona_sim_app/Wawona" \
        --scan-folder "$wawona_sim_app/Frameworks" \
        --destination "$wawona_sim_app/Frameworks"
      # Device copies may already be thin; lipo -thin rejects a thin input.
      /usr/bin/lipo "$wawona_sim_runtime" -verify_arch arm64
      if [ "$(/usr/bin/lipo -archs "$wawona_sim_runtime")" != arm64 ]; then
        /usr/bin/lipo "$wawona_sim_runtime" -thin arm64 -output "$wawona_sim_runtime.arm64"
      else
        # swift-stdlib-tool creates an HFS-compressed copy. Nix's final
        # metadata normalization can lose its compressed flag and expose an
        # empty data fork. Rewrite the decoded bytes into a fresh plain file.
        /bin/cat "$wawona_sim_runtime" > "$wawona_sim_runtime.arm64"
      fi
      mv "$wawona_sim_runtime.arm64" "$wawona_sim_runtime"
      [ -s "$wawona_sim_runtime" ] || { echo "Empty final Swift runtime" >&2; exit 1; }
      /usr/bin/file -b "$wawona_sim_runtime" | grep -q 'Mach-O' || {
        echo "Invalid final Swift runtime" >&2; exit 1;
      }
    '';
})
