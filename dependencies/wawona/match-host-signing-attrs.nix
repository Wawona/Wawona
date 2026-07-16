# Eval-time (--impure) attrs for IPA builds signed via fastlane match.
# Darwin daemon builders do not inherit client impureEnvVars, so bake host
# HOME + staged .mobileprovision paths into the build script at evaluation.
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
    in
    ''
      ${lib.optionalString (hostHome != "") ''
        export WAWONA_HOST_HOME="${hostHome}"
        export HOME="${hostHome}"
        export CFFIXED_USER_HOME="$HOME"
      ''}
      ${lib.optionalString (codeSignStyle != "") ''export WAWONA_CODE_SIGN_STYLE="${codeSignStyle}"''}
      ${lib.optionalString (codeSignIdentity != "") ''export WAWONA_CODE_SIGN_IDENTITY="${codeSignIdentity}"''}
      ${lib.optionalString (profileSpecifier != "") ''export WAWONA_PROVISIONING_PROFILE_SPECIFIER="${profileSpecifier}"''}
      ${lib.optionalString (profilesDir != "") ''
        mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
        mkdir -p "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
        cp -f "${profilesDir}/"*.mobileprovision \
          "$HOME/Library/MobileDevice/Provisioning Profiles/"
        cp -f "${profilesDir}/"*.mobileprovision \
          "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"
        echo "Staged match profiles from ${profilesDir} into $HOME"
        ls -la "$HOME/Library/MobileDevice/Provisioning Profiles" || true
      ''}
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
