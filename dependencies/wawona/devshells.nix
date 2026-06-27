{ systems, pkgsFor }:

builtins.listToAttrs (map (system: let
  pkgs = pkgsFor system;
  toolchains = if pkgs.stdenv.isDarwin then import ../toolchains {
    inherit (pkgs) lib pkgs stdenv buildPackages;
    pkgsAndroid = null;
    pkgsIos = null;
  } else null;
  xcodeUtils = if pkgs.stdenv.isDarwin then import ../utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; } else null;
  
  linuxShell = pkgs.mkShell {
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.rustToolchain
      pkgs.libxkbcommon
      pkgs.libffi
      pkgs.wayland-protocols
      pkgs.openssl
      pkgs.nix-output-monitor
    ];
    shellHook = ''
      alias nb='nom build'
      alias nd='nom develop'
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
    ] ++ (if pkgs.stdenv.isDarwin then [
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

      echo "Contributors: nix run .#xcodegen-ios | export WAWONA_SKIP_NIX_PREBUILD=1 for UI iteration"
    '';
  };
in {
  name = system;
  value = {
    default = if pkgs.stdenv.isDarwin then darwinShell else linuxShell;
  };
}) systems)
