{ lib, pkgs, androidSDK }:

let
  androidConfig = import ../android/sdk-config.nix {
    inherit lib androidSDK;
    system = pkgs.stdenv.hostPlatform.system;
  };

  # ---------------------------------------------------------------------------
  # provision-android
  # ---------------------------------------------------------------------------
  # Handles license acceptance and AVD creation.
  # ---------------------------------------------------------------------------
  provisionAndroidScript = pkgs.writeShellScriptBin "provision-android" ''
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
    export ANDROID_SDK_ROOT="${androidConfig.sdkRoot}"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export JAVA_HOME="${pkgs.jdk17.home}"
    export PATH="${pkgs.jdk17}/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools:$PATH"

    # 2. AVD Creation
    AVD_NAME="WawonaEmulator_API36"
    SYSTEM_IMAGE="${androidConfig.systemImageId}"

    if [ "${if androidConfig.emulatorSupported then "true" else "false"}" != "true" ]; then
      echo "[provision-android] Emulator/system-image packages are not available on ${pkgs.stdenv.hostPlatform.system}."
      echo "[provision-android] Skipping AVD provisioning; backend/non-emulator Android builds can still proceed."
      exit 0
    fi

    # Check if AVD already exists in the user's home (where emulator looks)
    # Note: We use a custom .android directory in the current project or home
    export ANDROID_USER_HOME="$HOME/.android"
    mkdir -p "$ANDROID_USER_HOME"

    if ! emulator -list-avds 2>/dev/null | grep -q "^$AVD_NAME$"; then
      echo "[provision-android] Creating AVD '$AVD_NAME'..."
      # Create AVD. 'echo n' answers the "Do you wish to create a custom hardware profile" question.
      printf 'n\n' | avdmanager create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" --force
    fi

    # Enhance the AVD config with modern specs if not already set
    AVD_CONFIG="$ANDROID_USER_HOME/avd/$AVD_NAME.avd/config.ini"
    if [ -f "$AVD_CONFIG" ]; then
      if ! grep -q "hw.ramSize=2048" "$AVD_CONFIG"; then
        echo "[provision-android] Optimizing AVD parameters (RAM, heap, GPU)..."
        # Ensure properties exist or update them
        touch "$AVD_CONFIG.tmp"
        grep -v -E "^(hw.ramSize|vm.heapSize|hw.gpu.enabled|hw.gpu.mode)=" "$AVD_CONFIG" > "$AVD_CONFIG.tmp" || true
        printf 'hw.ramSize=2048\nvm.heapSize=512\nhw.gpu.enabled=yes\nhw.gpu.mode=auto\n' >> "$AVD_CONFIG.tmp"
        mv "$AVD_CONFIG.tmp" "$AVD_CONFIG"
      fi
    fi

    echo "[provision-android] SUCCESS: Android environment is provisioned."
  '';

in
{
  inherit provisionAndroidScript;
}
