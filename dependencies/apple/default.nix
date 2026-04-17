{
  lib,
  pkgs,
  TEAM_ID ? null,
  deploymentTarget ? "17.0",
  xcodeBaseDir ? null,
  allowedXcodeVersions ? [ ],
  nixXcodeenvtests ? null,
}:
let
  # Migration bridge: keep the existing ios-xcodeenv implementation as the
  # engine while all callers are rewired to this single Apple entrypoint.
  legacy = import ../toolchains/ios-xcodeenv.nix {
    inherit lib pkgs TEAM_ID deploymentTarget xcodeBaseDir allowedXcodeVersions;
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

    newest="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1 || true)"
    if [ -n "$newest" ] && [ -d "$newest/Contents/Developer" ]; then
      echo "$newest"
      exit 0
    fi

    echo "ERROR: Xcode not found. Set XCODE_APP or run xcode-select -s." >&2
    exit 1
  '';

  xcodeWrapperCommand = pkgs.writeShellScriptBin "xcode-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="${legacy.xcodeWrapper}/bin:$PATH"
    unset DEVELOPER_DIR

    xcode_app="$(${findXcodeScript}/bin/find-xcode)"
    export XCODE_APP="$xcode_app"
    export DEVELOPER_DIR="$xcode_app/Contents/Developer"
    export PATH="$DEVELOPER_DIR/usr/bin:${legacy.xcodeWrapper}/bin:$PATH"

    if [ -z "''${DEVELOPMENT_TEAM:-}" ] && [ -n "${if TEAM_ID == null then "" else TEAM_ID}" ]; then
      export DEVELOPMENT_TEAM="${if TEAM_ID == null then "" else TEAM_ID}"
    fi

    exec "$@"
  '';
in
legacy
// {
  # Expose the reusable wrapper attrs expected by callers.
  xcodeWrapperDrv = legacy.xcodeWrapper;
  xcodeWrapper = xcodeWrapperCommand;
  xcodeWrapperCommand = xcodeWrapperCommand;
  findXcodeScript = findXcodeScript;
  getXcodePath = findXcodeScript;

  # Metadata for docs/diagnostics: we intentionally keep this optional so eval
  # does not depend on this input's internal structure.
  xcodeenvModel = "nix-xcodeenvtests";
  xcodeenvSource = if nixXcodeenvtests == null then null else toString nixXcodeenvtests;
}
