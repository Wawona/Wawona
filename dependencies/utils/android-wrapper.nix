{ lib, pkgs, androidSDK }:

let
  # ---------------------------------------------------------------------------
  # provision-android
  # ---------------------------------------------------------------------------
  # Handles license acceptance and AVD creation.
  # ---------------------------------------------------------------------------
  provisionAndroidScript = pkgs.writeShellScript "provision-android" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # -- Step 0: Ensure HOME is writable for android tools ------------------
    if [[ "''${HOME:-}" == "/var/empty" ]] || [[ "''${HOME:-}" == "/homeless-shelter" ]] || [ -z "''${HOME:-}" ]; then
      export HOME=$(mktemp -d -t android-home.XXXXXXXX)
      echo "[provision-android] Overriding HOME to $HOME" >&2
    fi

    echo "[provision-android] Provisioning Android environment..."

    # 1. Licenses
    # Nix-managed SDK usually has licenses pre-accepted in the store, 
    # but we ensure the environment variable is set for the tools.
    export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export JAVA_HOME="${pkgs.jdk17.home}"
    export PATH="${pkgs.jdk17}/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

    # 2. AVD Creation
    AVD_NAME="WawonaEmulator_API36"
    SYSTEM_IMAGE="system-images;android-36;google_apis_playstore;arm64-v8a"
    
    # Check if AVD already exists in the user's home (where emulator looks)
    # Note: We use a custom .android directory in the current project or home
    export ANDROID_USER_HOME="$HOME/.android"
    mkdir -p "$ANDROID_USER_HOME"

    if ! emulator -list-avds 2>/dev/null | grep -q "^$AVD_NAME$"; then
      echo "[provision-android] Creating AVD '$AVD_NAME'..."
      # Create AVD. 'echo n' answers the "Do you wish to create a custom hardware profile" question.
      echo "n" | avdmanager create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" --force
    else
      echo "[provision-android] AVD '$AVD_NAME' already exists."
    fi

    echo "[provision-android] SUCCESS: Android environment is provisioned."
  '';

in
{
  inherit provisionAndroidScript;
}
