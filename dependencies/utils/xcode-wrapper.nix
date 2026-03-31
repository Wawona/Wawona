{ lib, pkgs, TEAM_ID ? null }:

let
  # ---------------------------------------------------------------------------
  # Shared Shell Helpers
  # ---------------------------------------------------------------------------
  setupXcodeEnv = ''
    # 1. Strip Nix stdenv's DEVELOPER_DIR to ensure xcrun finds real Xcode.
    unset DEVELOPER_DIR
    
    # 2. Find real Xcode.app (prioritize Xcode_26.app for Tahoe)
    if [ -z "''${XCODE_APP:-}" ]; then
      for candidate in /Applications/Xcode_26.app /Applications/Xcode.app; do
        if [ -d "$candidate" ]; then
          XCODE_APP="$candidate"
          break
        fi
      done
      
      # Fallback to system xcode-select (rejecting Nix store stubs)
      if [ -z "''${XCODE_APP:-}" ] && [ -x /usr/bin/xcode-select ]; then
        REAL_DEV=$(/usr/bin/xcode-select -p 2>/dev/null || true)
        case "$REAL_DEV" in
          /nix/store/*) ;;
          *) XCODE_APP="''${REAL_DEV%/Contents/Developer}" ;;
        esac
      fi
    fi
    
    # 3. Final validation and export
    if [ -n "''${XCODE_APP:-}" ] && [ -d "$XCODE_APP" ]; then
      export XCODE_APP
      export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
    else
      echo "ERROR: Xcode 26 (Tahoe) or system Xcode not found." >&2
      exit 1
    fi
  '';

  # ---------------------------------------------------------------------------
  # find-xcode
  # ---------------------------------------------------------------------------
  findXcodeScript = pkgs.writeShellScriptBin "find-xcode" ''
    ${setupXcodeEnv}
    echo "$XCODE_APP"
  '';

  # ---------------------------------------------------------------------------
  # ensure-sdk (Universal)
  # ---------------------------------------------------------------------------
  # Modern, xcrun-based SDK discovery for Tahoe/Darwin 26.
  ensureSdk = name: sdkName: pkgs.writeShellScriptBin name ''
    #!/usr/bin/env bash
    set -euo pipefail
    ${setupXcodeEnv}
    
    # Primary discovery via xcrun
    SDK_PATH=$(xcrun --sdk ${sdkName} --show-sdk-path 2>/dev/null || true)
    
    # Platform-specific fallbacks for Tahoe structure
    if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
      case "${sdkName}" in
        macosx)          SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" ;;
        iphoneos)        SDK_PATH="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk" ;;
        iphonesimulator) SDK_PATH="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk" ;;
      esac
    fi
    
    if [ -n "$SDK_PATH" ] && [ -d "$SDK_PATH" ]; then
      echo "$SDK_PATH"
    else
      echo "ERROR: ${sdkName} SDK not found for macOS 26." >&2
      exit 1
    fi
  '';

  ensureIosSimSDK = ensureSdk "ensure-ios-sim-sdk" "iphonesimulator";
  ensureIosSDK = ensureSdk "ensure-ios-sdk" "iphoneos";
  ensureMacosSDK = ensureSdk "ensure-macos-sdk" "macosx";

  # ---------------------------------------------------------------------------
  # find-simulator
  # ---------------------------------------------------------------------------
  findSimulatorScript = pkgs.writeShellScriptBin "find-simulator" ''
    #!/usr/bin/env bash
    set -euo pipefail
    ${setupXcodeEnv}
    echo "$DEVELOPER_DIR/Applications/Simulator.app"
  '';

  # ---------------------------------------------------------------------------
  # provision-xcode
  # ---------------------------------------------------------------------------
  provisionXcodeScript = pkgs.writeShellScriptBin "provision-xcode" ''
    #!/usr/bin/env bash
    set -euo pipefail
    ${setupXcodeEnv}
    
    echo "[provision-xcode] Provisioning Xcode for Tahoe (26.0)..."
    
    # 1. License (Tahoe/26.0)
    sudo xcodebuild -license accept 2>/dev/null || true
    
    # 2. First Launch Experience
    sudo xcodebuild -runFirstLaunchExperience || true
    
    # 3. Platform (iOS 26)
    echo "[provision-xcode] Ensuring iOS Simulator platform is installed..."
    ${ensureIosSimSDK}/bin/ensure-ios-sim-sdk >/dev/null
    
    echo "[provision-xcode] SUCCESS: Xcode 26 is provisioned."
  '';

  # ---------------------------------------------------------------------------
  # xcode-wrapper
  # ---------------------------------------------------------------------------
  xcodeWrapper = pkgs.writeShellScriptBin "xcode-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail
    ${setupXcodeEnv}
    
    # Development Team handling (for Code Signing on Tahoe)
    NIX_TEAM_ID="${if TEAM_ID == null then "" else TEAM_ID}"
    if [ -z "''${DEVELOPMENT_TEAM:-}" ]; then
      [ -n "''${TEAM_ID:-}" ] && export DEVELOPMENT_TEAM="''${TEAM_ID}"
      [ -z "''${DEVELOPMENT_TEAM:-}" ] && [ -n "$NIX_TEAM_ID" ] && export DEVELOPMENT_TEAM="$NIX_TEAM_ID"
    fi
    
    exec "$@"
  '';

in
{
  inherit findXcodeScript findSimulatorScript ensureIosSimSDK ensureIosSDK ensureMacosSDK provisionXcodeScript xcodeWrapper;
  
  # Helper for version lookup without recursion
  getXcodePath = findXcodeScript;
}
