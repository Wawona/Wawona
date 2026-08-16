# Eval-time (--impure) attrs for IPA builds signed via fastlane match.
# Darwin daemon builders do not inherit client impureEnvVars, so bake host
# *paths* into the build script at evaluation. Never bake cert/password
# contents. Only paths to mode-0600 temp files created by Fastlane.
# Do NOT set HOME to the host here. Nixbld cannot write /Users/runner;
# build-app.nix picks a writable HOME and stages profiles / imports P12.
{ lib }:
old: {
  passAsFile = (old.passAsFile or [ ]);
  buildPhase =
    let
      hostHome =
        let
          explicit = builtins.getEnv "WAWONA_HOST_HOME";
        in
        if explicit != "" then explicit else builtins.getEnv "HOME";
      profilesDir = builtins.getEnv "WAWONA_PROFILES_DIR";
      profileSpecifier = builtins.getEnv "WAWONA_PROVISIONING_PROFILE_SPECIFIER";
      codeSignIdentity = builtins.getEnv "WAWONA_CODE_SIGN_IDENTITY";
      codeSignStyle = builtins.getEnv "WAWONA_CODE_SIGN_STYLE";
      distKeychain = builtins.getEnv "WAWONA_DIST_KEYCHAIN";
      distP12PassFile = builtins.getEnv "WAWONA_DIST_P12_PASS_FILE";
    in
    ''
      ${lib.optionalString (hostHome != "") ''export WAWONA_HOST_HOME="${hostHome}"''}
      ${lib.optionalString (profilesDir != "") ''export WAWONA_PROFILES_DIR="${profilesDir}"''}
      ${lib.optionalString (codeSignStyle != "") ''export WAWONA_CODE_SIGN_STYLE="${codeSignStyle}"''}
      ${lib.optionalString (codeSignIdentity != "") ''export WAWONA_CODE_SIGN_IDENTITY="${codeSignIdentity}"''}
      ${lib.optionalString (profileSpecifier != "") ''export WAWONA_PROVISIONING_PROFILE_SPECIFIER="${profileSpecifier}"''}
      ${lib.optionalString (distKeychain != "") ''export WAWONA_DIST_KEYCHAIN="${distKeychain}"''}
      ${lib.optionalString (distP12PassFile != "") ''export WAWONA_DIST_P12_PASS_FILE="${distP12PassFile}"''}
    ''
    + (old.buildPhase or "")
    + ''
      metal_mounts="$HOME/Library/Developer/DVTDownloads/MetalToolchain/mounts"
      if [ -d "$metal_mounts" ]; then
        echo "Detaching MetalToolchain mounts under $metal_mounts ..."
        for mnt in "$metal_mounts"/*; do
          [ -e "$mnt" ] || continue
          /usr/bin/hdiutil detach "$mnt" -force 2>/dev/null \
            || /sbin/umount -f "$mnt" 2>/dev/null \
            || true
        done
        rm -rf "$HOME/Library/Developer/DVTDownloads/MetalToolchain" 2>/dev/null || true
      fi
    '';
}
