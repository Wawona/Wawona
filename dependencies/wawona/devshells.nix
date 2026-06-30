{ systems, pkgsFor }:

let
  releasePackages = pkgs: with pkgs; [
    fastlane
    ruby
    bundler
    cocoapods
    jdk17
    gh
  ];
in
builtins.listToAttrs (map (system: let
  pkgs = pkgsFor system;
  toolchains = if pkgs.stdenv.isDarwin then import pkgs.toolchainsDir {
    inherit (pkgs) lib pkgs stdenv buildPackages;
    pkgsAndroid = null;
    pkgsIos = null;
  } else null;
  xcodeUtils = if pkgs.stdenv.isDarwin then import pkgs.applePath { inherit (pkgs) lib pkgs; } else null;

  releaseShellHook = ''
    if [ -f .release-secrets.env ]; then
      echo "Release secrets: source .release-secrets.env before fastlane beta"
    else
      echo "Release: copy .release-secrets.env.template → .release-secrets.env"
    fi
    echo "Fastlane: nix develop .#release --command fastlane ios beta"
  '';

  # Fastlane match and xcodebuild need DEVELOPER_DIR and xcodebuild on PATH inside
  # nix develop. CI exports these via select-xcode.sh; local dev uses find-xcode.
  darwinXcodeShellHook = pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
    XCODE_APP=""
    if [ -n "''${DEVELOPER_DIR:-}" ]; then
      XCODE_APP="''${DEVELOPER_DIR%/Contents/Developer}"
    fi
    if [ -z "$XCODE_APP" ] || [ ! -d "$XCODE_APP/Contents/Developer" ]; then
      if command -v find-xcode >/dev/null 2>&1; then
        XCODE_APP="$(find-xcode 2>/dev/null || true)"
      else
        XCODE_APP="$(${xcodeUtils.findXcodeScript}/bin/find-xcode 2>/dev/null || true)"
      fi
    fi
    if [ -n "$XCODE_APP" ] && [ -d "$XCODE_APP/Contents/Developer" ]; then
      export XCODE_APP
      export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
    else
      echo "WARNING: Xcode not found — set DEVELOPER_DIR or install Xcode before fastlane/match" >&2
    fi
  '';

  linuxShell = pkgs.mkShell {
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.rustToolchain
      pkgs.libxkbcommon
      pkgs.libffi
      pkgs.wayland-protocols
      pkgs.openssl
      pkgs.nix-output-monitor
    ] ++ releasePackages pkgs;
    shellHook = ''
      alias nb='nom build'
      alias nd='nom develop'
      ${releaseShellHook}
    '';
  };

  darwinShell = pkgs.mkShell {
    nativeBuildInputs = [
      pkgs.pkg-config
    ];

    buildInputs = [
      pkgs.rustToolchain
      pkgs.libxkbcommon
      pkgs.libffi
      pkgs.wayland-protocols
      pkgs.openssl
      pkgs.nix-output-monitor
    ] ++ releasePackages pkgs ++ (if pkgs.stdenv.isDarwin then [
      (toolchains.buildForMacOS "libwayland" { })
      xcodeUtils.ensureIosSimSDK
      xcodeUtils.findXcodeScript
    ] else []);

    shellHook = ''
      export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
      export WAYLAND_DISPLAY="wayland-0"
      mkdir -p $XDG_RUNTIME_DIR
      chmod 700 $XDG_RUNTIME_DIR
      alias nb='nom build'
      alias nd='nom develop'

      if [ "$(uname)" = "Darwin" ]; then
        export NIX_SSL_CERT_FILE="/etc/ssl/cert.pem"
        export SSL_CERT_FILE="/etc/ssl/cert.pem"
      fi

      if [ -f .envrc ]; then
        TEAM_ID=$(grep '^export TEAM_ID=' .envrc | cut -d'=' -f2 | tr -d '"')
        if [ -n "$TEAM_ID" ]; then
          export TEAM_ID="$TEAM_ID"
        fi
      fi

      ${darwinXcodeShellHook}

      echo "Contributors: nix run .#xcodegen-ios | export WAWONA_SKIP_NIX_PREBUILD=1 for UI iteration"
      ${releaseShellHook}
    '';
  };

  releaseShell = pkgs.mkShell {
    inputsFrom = [
      (if pkgs.stdenv.isDarwin then darwinShell else linuxShell)
    ];
    shellHook = ''
      ${if pkgs.stdenv.isDarwin then darwinXcodeShellHook else ""}
      ${releaseShellHook}
    '';
  };
in {
  name = system;
  value = {
    default = if pkgs.stdenv.isDarwin then darwinShell else linuxShell;
    release = releaseShell;
  };
}) systems)
