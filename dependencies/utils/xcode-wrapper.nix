{ lib, pkgs, TEAM_ID ? null }:

let
  # ---------------------------------------------------------------------------
  # find-xcode
  # ---------------------------------------------------------------------------
  # Finds real Xcode.app, stripping any Nix-imposed DEVELOPER_DIR override
  # first.  Returns the Xcode.app path (no trailing slash).
  # ---------------------------------------------------------------------------
  findXcodeScript = pkgs.writeShellScriptBin "find-xcode" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # 1. Honour an explicit caller-supplied XCODE_APP.
    if [ -n "''${XCODE_APP:-}" ] && [ -d "''${XCODE_APP}" ]; then
      echo "''${XCODE_APP}"
      exit 0
    fi

    # 2. Strip any Nix-imposed DEVELOPER_DIR so that xcode-select reads the
    #    system symlink at /var/db/xcode_select_link instead of the Nix store.
    unset DEVELOPER_DIR

    # 3. Try the system xcode-select (absolute path, bypasses PATH overrides).
    if [ -x /usr/bin/xcode-select ]; then
      REAL_DEV_DIR=$(/usr/bin/xcode-select -p 2>/dev/null || true)
      if [ -n "$REAL_DEV_DIR" ]; then
        # Reject Nix store paths — they are SDK stubs, not real Xcode.
        case "$REAL_DEV_DIR" in
          /nix/store/*) ;;  # fall through to manual search
          *)
            XCODE_APP="''${REAL_DEV_DIR%/Contents/Developer}"
            if [ -d "$XCODE_APP" ] && [[ "$XCODE_APP" == *.app ]]; then
              echo "$XCODE_APP"
              exit 0
            fi
            ;;
        esac
      fi
    fi

    # 4. Check well-known locations.
    for candidate in \
        /Applications/Xcode.app \
        /Applications/Xcode_16.app \
        /Applications/Xcode-beta.app; do
      if [ -d "$candidate" ]; then
        echo "$candidate"
        exit 0
      fi
    done

    # 5. Search /Applications for any Xcode*.app (picks the first/latest).
    if [ -d /Applications ]; then
      XCODE_APP=$(find /Applications -maxdepth 1 -name "Xcode*.app" -type d 2>/dev/null \
                  | sort -V | tail -1)
      if [ -n "$XCODE_APP" ]; then
        echo "$XCODE_APP"
        exit 0
      fi
    fi

    echo "ERROR: Xcode not found. Install Xcode from the App Store." >&2
    exit 1
  '';

  # Get Xcode path helper
  getXcodePath = pkgs.writeShellScriptBin "get-xcode-path" ''
    ${findXcodeScript}/bin/find-xcode
  '';

  # ---------------------------------------------------------------------------
  # find-simulator
  # ---------------------------------------------------------------------------
  # Finds the absolute path to Simulator.app within Xcode.
  # ---------------------------------------------------------------------------
  findSimulatorScript = pkgs.writeShellScriptBin "find-simulator" ''
    #!/usr/bin/env bash
    set -euo pipefail
    XCODE_APP=$(${findXcodeScript}/bin/find-xcode)
    SIM_APP="$XCODE_APP/Contents/Developer/Applications/Simulator.app"
    if [ -d "$SIM_APP" ]; then
      echo "$SIM_APP"
    else
      echo "ERROR: Simulator.app not found at $SIM_APP" >&2
      exit 1
    fi
  '';

  # ---------------------------------------------------------------------------
  # ensure-ios-sim-sdk
  # ---------------------------------------------------------------------------
  # Ensures the iOS Simulator SDK is present on this machine and prints its
  # path to stdout so callers can do:
  #   IOS_SIM_SDK=$(ensure-ios-sim-sdk)
  #   export SDKROOT="$IOS_SIM_SDK"
  #
  # Strategy:
  #   1. Unset DEVELOPER_DIR (strips Nix stdenv override).
  #   2. Use /usr/bin/xcrun to locate the LATEST installed simulator SDK.
  #      xcrun always finds the SDK for the active Xcode automatically.
  #   3. If not found, run xcodebuild -downloadPlatform iOS and retry.
  # ---------------------------------------------------------------------------
  ensureIosSimSDK = pkgs.writeShellScriptBin "ensure-ios-sim-sdk" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # ── Step 0: Ensure HOME is writable for xcodebuild ─────────────────────
    # Nix sets HOME to /var/empty which causes Apple tools to fail with:
    # "Unable to determine SimDeviceSet for subscriptions"
    if [[ "''${HOME:-}" == "/var/empty" ]] || [[ "''${HOME:-}" == "/homeless-shelter" ]] || [ -z "''${HOME:-}" ]; then
      export HOME=$(mktemp -d -t xcodebuild-home.XXXXXXXX)
      echo "[ensure-ios-sim-sdk] Overriding HOME to $HOME" >&2
      
      # Satisfy IDESimulatorRuntimeVersionCoordinator and CoreSimulator
      mkdir -p "$HOME/Library/Developer/Xcode"
      mkdir -p "$HOME/Library/Developer/CoreSimulator/Devices"
      mkdir -p "$HOME/Library/Caches/com.apple.dt.Xcode"
    fi

    # Strip Nix stdenv's DEVELOPER_DIR so xcrun/xcode-select use real Xcode.
    unset DEVELOPER_DIR

    # ── Step 1: try xcrun to find the latest installed simulator SDK ──────
    if [ -x /usr/bin/xcrun ]; then
      SIM_SDK=$(/usr/bin/xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
      if [ -n "$SIM_SDK" ] && [ -d "$SIM_SDK" ]; then
        echo "[ensure-ios-sim-sdk] Found iOS Simulator SDK: $SIM_SDK" >&2
        echo "$SIM_SDK"
        exit 0
      fi
    fi

    # ── Step 2: no SDK found — download it via xcodebuild ─────────────────
    XCODE_APP=$(${findXcodeScript}/bin/find-xcode) || {
      echo "[ensure-ios-sim-sdk] ERROR: Xcode not found." >&2
      echo "  Install Xcode from the App Store, then run:" >&2
      echo "    sudo xcodebuild -downloadPlatform iOS" >&2
      exit 1
    }

    # Reject Nix store paths (they are SDK stubs, not real Xcode).
    case "$XCODE_APP" in
      /nix/store/*)
        echo "[ensure-ios-sim-sdk] ERROR: found Xcode path inside Nix store: $XCODE_APP" >&2
        echo "  Real Xcode is not installed. Install Xcode 16+ from the App Store." >&2
        exit 1
        ;;
    esac

    XCODEBUILD="$XCODE_APP/Contents/Developer/usr/bin/xcodebuild"
    if [ ! -x "$XCODEBUILD" ]; then
      echo "[ensure-ios-sim-sdk] ERROR: xcodebuild not found at $XCODEBUILD" >&2
      exit 1
    fi

    # Accept license silently.
    "$XCODEBUILD" -license check 2>/dev/null \
      || sudo "$XCODEBUILD" -license accept 2>/dev/null \
      || true

    echo "[ensure-ios-sim-sdk] Downloading iOS Simulator platform (this may take a few minutes)..." >&2
    "$XCODEBUILD" -downloadPlatform iOS || {
      echo "[ensure-ios-sim-sdk] ERROR: xcodebuild -downloadPlatform iOS failed." >&2
      echo "  Try manually: sudo xcodebuild -downloadPlatform iOS" >&2
      echo "  Or: Xcode → Settings → Platforms → iOS → Download" >&2
      exit 1
    }

    # ── Step 3: retry xcrun after download ────────────────────────────────
    SIM_SDK=$(/usr/bin/xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
    if [ -n "$SIM_SDK" ] && [ -d "$SIM_SDK" ]; then
      echo "[ensure-ios-sim-sdk] Installed iOS Simulator SDK: $SIM_SDK" >&2
      echo "$SIM_SDK"
      exit 0
    fi

    echo "[ensure-ios-sim-sdk] ERROR: SDK still not found after download." >&2
    exit 1
  '';

  # ---------------------------------------------------------------------------
  # ensure-ios-sdk (iPhoneOS)
  # ---------------------------------------------------------------------------
  ensureIosSDK = pkgs.writeShellScriptBin "ensure-ios-sdk" ''
    #!/usr/bin/env bash
    set -euo pipefail
    unset DEVELOPER_DIR
    if [ -x /usr/bin/xcrun ]; then
      IOS_SDK=$(/usr/bin/xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ -n "$IOS_SDK" ] && [ -d "$IOS_SDK" ]; then
        echo "$IOS_SDK"
        exit 0
      fi
    fi
    XCODE_APP=$(${findXcodeScript}/bin/find-xcode)
    IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    if [ -d "$IOS_SDK" ]; then
      echo "$IOS_SDK"
    else
      echo "ERROR: iOS SDK not found at $IOS_SDK" >&2
      exit 1
    fi
  '';

  # ---------------------------------------------------------------------------
  # provision-xcode
  # ---------------------------------------------------------------------------
  # Handles license acceptance, first-launch, and platform downloading.
  # This usually requires sudo for the license and first-launch parts.
  # ---------------------------------------------------------------------------
  provisionXcodeScript = pkgs.writeShellScriptBin "provision-xcode" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    XCODE_APP=$(${findXcodeScript}/bin/find-xcode)
    XCODEBUILD="$XCODE_APP/Contents/Developer/usr/bin/xcodebuild"
    
    echo "[provision-xcode] Provisioning Xcode at $XCODE_APP..."
    
    # 1. License
    if ! "$XCODEBUILD" -license check 2>/dev/null; then
      echo "[provision-xcode] Xcode license not accepted. Accepting now (requires sudo)..."
      sudo "$XCODEBUILD" -license accept || {
        echo "[provision-xcode] ERROR: Failed to accept license." >&2
        exit 1
      }
    else
      echo "[provision-xcode] Xcode license already accepted."
    fi
    
    # 2. First Launch Experience
    echo "[provision-xcode] Ensuring First Launch Experience is complete (requires sudo)..."
    sudo "$XCODEBUILD" -runFirstLaunchExperience || true
    
    # 3. Platform (iOS)
    echo "[provision-xcode] Ensuring iOS Simulator platform is installed..."
    ${ensureIosSimSDK}/bin/ensure-ios-sim-sdk >/dev/null
    
    echo "[provision-xcode] SUCCESS: Xcode is provisioned for iOS development."
  '';
in
{
  inherit findXcodeScript getXcodePath findSimulatorScript ensureIosSimSDK ensureIosSDK provisionXcodeScript;

  # Wrapper that sets up Xcode environment for commands (e.g. xcodegen).
  xcodeWrapper = pkgs.writeShellScriptBin "xcode-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail
    NIX_TEAM_ID="${if TEAM_ID == null then "" else TEAM_ID}"

    unset DEVELOPER_DIR
    XCODE_APP=$(${findXcodeScript}/bin/find-xcode)
    export XCODE_APP
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

    if [ -z "''${DEVELOPMENT_TEAM:-}" ]; then
      if [ -n "''${TEAM_ID:-}" ]; then
        export DEVELOPMENT_TEAM="''${TEAM_ID}"
      elif [ -n "$NIX_TEAM_ID" ]; then
        export DEVELOPMENT_TEAM="$NIX_TEAM_ID"
      fi
    fi

    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
    exec "$@"
  '';
}
