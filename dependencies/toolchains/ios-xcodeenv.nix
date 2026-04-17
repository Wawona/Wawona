{ lib, pkgs, TEAM_ID ? null, deploymentTarget ? "17.0", xcodeBaseDir ? null, allowedXcodeVersions ? [ ] }:

let
  xcodeenv = import ./xcodeenv {
    callPackage = pkgs.callPackage;
  };

  xcodeWrapper = xcodeenv.composeXcodeWrapper {
    versions = allowedXcodeVersions;
    inherit xcodeBaseDir;
  };

  findXcodeScript = pkgs.writeShellScriptBin "find-xcode" ''
    #!/usr/bin/env bash
    set -euo pipefail

    if [ -n "''${XCODE_APP:-}" ] && [ -d "$XCODE_APP/Contents/Developer" ]; then
      echo "$XCODE_APP"
      exit 0
    fi

    if [ -x /usr/bin/xcode-select ]; then
      dev_dir=$(/usr/bin/xcode-select -p 2>/dev/null || true)
      case "$dev_dir" in
        *.app/Contents/Developer)
          xcode_app="''${dev_dir%/Contents/Developer}"
          if [ -d "$xcode_app/Contents/Developer" ]; then
            echo "$xcode_app"
            exit 0
          fi
          ;;
      esac
    fi

    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode_*.app /Applications/Xcode*.app; do
      if [ -d "$candidate/Contents/Developer" ]; then
        echo "$candidate"
        exit 0
      fi
    done

    echo "ERROR: Xcode not found." >&2
    exit 1
  '';

  ensureSdk = name: sdkName: pkgs.writeShellScriptBin name ''
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="${xcodeWrapper}/bin:$PATH"
    sdk_path="$(xcrun --sdk ${sdkName} --show-sdk-path 2>/dev/null || true)"
    if [ -z "$sdk_path" ] || [ ! -d "$sdk_path" ]; then
      echo "ERROR: ${sdkName} SDK not found via xcrun." >&2
      exit 1
    fi
    printf '%s\n' "$sdk_path"
  '';

  ensureIosSDK = ensureSdk "ensure-ios-sdk" "iphoneos";
  ensureIosSimSDK = ensureSdk "ensure-ios-sim-sdk" "iphonesimulator";
  ensureMacosSDK = ensureSdk "ensure-macos-sdk" "macosx";

  findSimulatorScript = pkgs.writeShellScriptBin "find-simulator" ''
    #!/usr/bin/env bash
    set -euo pipefail
    sim_path="$(readlink "${xcodeWrapper}/bin/Simulator" 2>/dev/null || true)"
    if [ -z "$sim_path" ] || [ ! -x "$sim_path" ]; then
      echo "ERROR: Simulator.app not found in active Xcode." >&2
      exit 1
    fi
    printf '%s\n' "$sim_path"
  '';

  mkAppleEnv = { sdkName, minVersion ? deploymentTarget, simulator ? false, platform ? "ios" }:
    let
      linkerTarget =
        if platform == "visionos" then
          if simulator then
            "arm64-apple-xros${minVersion}-simulator"
          else
            "arm64-apple-xros${minVersion}"
        else if platform == "tvos" then
          if simulator then
            "arm64-apple-tvos${minVersion}-simulator"
          else
            "arm64-apple-tvos${minVersion}"
        else if simulator then
          "arm64-apple-ios${minVersion}-simulator"
        else
          "arm64-apple-ios${minVersion}";
      deploymentFlag =
        if platform == "visionos" then
          if simulator then
            "-mvisionos-simulator-version-min=${minVersion}"
          else
            "-mvisionos-version-min=${minVersion}"
        else if platform == "tvos" then
          if simulator then
            "-mtvos-simulator-version-min=${minVersion}"
          else
            "-mtvos-version-min=${minVersion}"
        else if simulator then
          "-mios-simulator-version-min=${minVersion}"
        else
          "-miphoneos-version-min=${minVersion}";
      cargoTarget =
        if platform == "visionos" then
          if simulator then
            "aarch64-apple-visionos-sim"
          else
            "aarch64-apple-visionos"
        else if platform == "tvos" then
          if simulator then
            "aarch64-apple-tvos-sim"
          else
            "aarch64-apple-tvos"
        else if simulator then
          "aarch64-apple-ios-sim"
        else
          "aarch64-apple-ios";
    in
    ''
      export PATH="${xcodeWrapper}/bin:$PATH"
      unset DEVELOPER_DIR

      export SDKROOT="$(xcrun --sdk ${sdkName} --show-sdk-path 2>/dev/null || true)"
      if [ -z "$SDKROOT" ] || [ ! -d "$SDKROOT" ]; then
        echo "ERROR: ${sdkName} SDK not found." >&2
        exit 1
      fi

      export DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
      case "$DEVELOPER_DIR" in
        *.app/Contents/Developer) ;;
        *)
          export DEVELOPER_DIR="$(echo "$SDKROOT" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')"
          ;;
      esac

      export XCODE_APP="$(echo "$DEVELOPER_DIR" | sed 's|/Contents/Developer$||')"
      export XCODE_CLANG_REAL="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      export XCODE_CLANGXX_REAL="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      export PATH="$DEVELOPER_DIR/usr/bin:$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
      export APPLE_SDK_NAME="${sdkName}"
      export APPLE_MIN_VERSION="${minVersion}"
      export APPLE_LINKER_TARGET="${linkerTarget}"
      export APPLE_DEPLOYMENT_FLAG="${deploymentFlag}"
      export APPLE_CARGO_TARGET="${cargoTarget}"
      export IOS_ARCH="arm64"

      # Always use Xcode's real clang. A previous visionOS wrapper prepended
      # `-target arm64-apple-xros…` ahead of `-arch`/`-isysroot` from Autoconf;
      # that combination makes Apple's clang fail "compiler cannot create
      # executables" for Nix-built deps (e.g. libxml2 for visionOS xkbcommon).
      export XCODE_CLANG="$XCODE_CLANG_REAL"
      export XCODE_CLANGXX="$XCODE_CLANGXX_REAL"

      if [ ! -x "$XCODE_CLANG" ] || [ ! -x "$XCODE_CLANGXX" ]; then
        echo "ERROR: Apple clang toolchain not found in $DEVELOPER_DIR." >&2
        exit 1
      fi
    '';

  mkIOSBuildEnv = { simulator ? false, minVersion ? deploymentTarget }:
    mkAppleEnv {
      sdkName = if simulator then "iphonesimulator" else "iphoneos";
      inherit simulator minVersion;
    };

  provisionXcodeScript = pkgs.writeShellScriptBin "provision-xcode" ''
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="${xcodeWrapper}/bin:$PATH"

    xcodebuild -license check >/dev/null 2>&1 || sudo xcodebuild -license accept || true
    sudo xcodebuild -runFirstLaunch || true
    ${ensureIosSimSDK}/bin/ensure-ios-sim-sdk >/dev/null
    echo "Xcode is provisioned for Wawona iOS builds."
  '';

in
{
  inherit
    xcodeenv
    xcodeWrapper
    findXcodeScript
    findSimulatorScript
    ensureIosSDK
    ensureIosSimSDK
    ensureMacosSDK
    provisionXcodeScript
    mkAppleEnv
    mkIOSBuildEnv
    deploymentTarget
    ;

  buildApp = args:
    xcodeenv.buildApp ({
      versions = allowedXcodeVersions;
      inherit xcodeBaseDir;
    } // args);

  simulateApp = args:
    xcodeenv.simulateApp ({
      versions = allowedXcodeVersions;
      inherit xcodeBaseDir;
    } // args);

  xcodeWrapperCommand = pkgs.writeShellScriptBin "xcode-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="${xcodeWrapper}/bin:$PATH"
    unset DEVELOPER_DIR

    xcode_app="$(${findXcodeScript}/bin/find-xcode)"
    export XCODE_APP="$xcode_app"
    export DEVELOPER_DIR="$xcode_app/Contents/Developer"
    export PATH="$DEVELOPER_DIR/usr/bin:${xcodeWrapper}/bin:$PATH"

    if [ -z "''${DEVELOPMENT_TEAM:-}" ] && [ -n "${if TEAM_ID == null then "" else TEAM_ID}" ]; then
      export DEVELOPMENT_TEAM="${if TEAM_ID == null then "" else TEAM_ID}"
    fi

    exec "$@"
  '';
}
