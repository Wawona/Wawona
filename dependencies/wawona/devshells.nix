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
    ];
  };

  darwinShell = pkgs.mkShell {
    nativeBuildInputs = [
      pkgs.pkg-config
    ];

    buildInputs = [
      pkgs.rustToolchain  # This provides both cargo and rustc
      pkgs.libxkbcommon
      pkgs.libffi
      pkgs.wayland-protocols
      pkgs.openssl
    ] ++ (if pkgs.stdenv.isDarwin then [
      (toolchains.buildForMacOS "libwayland" { })
      xcodeUtils.ensureIosSimSDK
      xcodeUtils.findXcodeScript
    ] else []);

    # Read TEAM_ID from .envrc if it exists, otherwise use default
    shellHook = ''
      export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
      export WAYLAND_DISPLAY="wayland-0"
      mkdir -p $XDG_RUNTIME_DIR
      chmod 700 $XDG_RUNTIME_DIR

      # Declarative SSL fix for macOS
      if [ "$(uname)" = "Darwin" ]; then
        export NIX_SSL_CERT_FILE="/etc/ssl/cert.pem"
        export SSL_CERT_FILE="/etc/ssl/cert.pem"
      fi

      # Load TEAM_ID from .envrc if it exists
      if [ -f .envrc ]; then
        TEAM_ID=$(grep '^export TEAM_ID=' .envrc | cut -d'=' -f2 | tr -d '"')
        if [ -n "$TEAM_ID" ]; then
          export TEAM_ID="$TEAM_ID"
          echo "Loaded TEAM_ID from .envrc."
        else
          echo "Warning: TEAM_ID not found in .envrc"
        fi
      else
        echo "Warning: .envrc not found. Create one with 'export TEAM_ID=\"your_team_id\"'"
      fi
    '';
  };
in {
  name = system;
  value = {
    default = if pkgs.stdenv.isDarwin then darwinShell else linuxShell;
  };
}) systems)
