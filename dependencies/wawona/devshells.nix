{ systems, pkgsFor }:

let
  # secretspec: CI + local release-env. pass/gnupg stay on the host (dendritic /
  # sops-nix); bundling gnupg here forces a slow Darwin rebuild of the shell.
  releasePackages = pkgs: with pkgs; [
    fastlane
    ruby
    bundler
    cocoapods
    jdk17
    gh
    secretspec
  ];
in
builtins.listToAttrs (map (system: let
  pkgs = pkgsFor system;
  toolchains = if pkgs.stdenv.hostPlatform.isDarwin then import pkgs.toolchainsDir {
    inherit (pkgs) lib pkgs stdenv buildPackages;
    pkgsAndroid = null;
    pkgsIos = null;
  } else null;
  xcodeUtils = if pkgs.stdenv.hostPlatform.isDarwin then import pkgs.applePath { inherit (pkgs) lib pkgs; } else null;

  releaseShellHook = ''
    export SECRETSPEC_FILE="''${SECRETSPEC_FILE:-$PWD/secretspec.toml}"
    export PASSWORD_STORE_DIR="''${PASSWORD_STORE_DIR:-$HOME/.password-store}"
    echo "Release secrets: SecretSpec + pass (tier 0 -> docs/maintainers/secrets.md)"
    echo "Fastlane: ./scripts/release-env.sh fastlane ios beta"
  '';

  # Fastlane match and xcodebuild need DEVELOPER_DIR and xcodebuild on PATH inside
  # nix develop. CI exports these via select-xcode.sh; local dev uses find-xcode.
  darwinXcodeShellHook = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
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
      echo "WARNING: Xcode not found. Set DEVELOPER_DIR or install Xcode before fastlane/match" >&2
    fi
  '';

  linuxShell = pkgs.mkShell {
    preferLocalBuild = true;
    CARGO_PROFILE_RELEASE_LTO = "false";
    nativeBuildInputs = [ pkgs.pkg-config pkgs.ccacheWrapper ];
    buildInputs = [
      pkgs.rustToolchain
      # Wayland client stack: `pkgs.wayland` ships wayland-client.pc required by
      # the wayland-sys crate; wayland-protocols alone is insufficient.
      pkgs.wayland
      pkgs.wayland-protocols
      pkgs.libxkbcommon
      pkgs.libffi
      pkgs.openssl
      # GTK4/libadwaita stack so `cargo build --features linux-ui` (the
      # wawona-linux-ui GTK binary) compiles inside `nix develop`. Mirrors the
      # runtimeInputs of dependencies/wawona/linux.nix.
      pkgs.gtk4
      pkgs.libadwaita
      pkgs.glib
      pkgs.cairo
      pkgs.pango
      pkgs.gdk-pixbuf
      pkgs.graphene
      pkgs.harfbuzz
      pkgs.fribidi
      pkgs.freetype
      pkgs.fontconfig
      pkgs.vulkan-loader
      pkgs.nix-output-monitor
    ] ++ releasePackages pkgs;
    shellHook = ''
      export CCACHE_DIR="$PWD/.ccache"
      alias nb='nom build'
      alias nd='nom develop'
      ${releaseShellHook}
    '';
  };

  darwinShell = pkgs.mkShell {
    preferLocalBuild = true;
    CARGO_PROFILE_RELEASE_LTO = "false";
    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.ccacheWrapper
    ];

    buildInputs = [
      pkgs.rustToolchain
      pkgs.libxkbcommon
      pkgs.libffi
      pkgs.wayland-protocols
      pkgs.openssl
      pkgs.nix-output-monitor
    ] ++ releasePackages pkgs ++ (if pkgs.stdenv.hostPlatform.isDarwin then [
      (toolchains.buildForMacOS "libwayland" { })
      xcodeUtils.ensureIosSimSDK
      xcodeUtils.findXcodeScript
    ] else []);

    shellHook = ''
      export CCACHE_DIR="$PWD/.ccache"
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
        _TEAM_FROM_ENVRC=$(grep '^export TEAM_ID=' .envrc | cut -d'=' -f2 | tr -d '"')
        if [ -n "$_TEAM_FROM_ENVRC" ]; then
          export TEAM_ID="$_TEAM_FROM_ENVRC"
          echo "Loaded TEAM_ID from .envrc."
        fi
      fi
      if [ -n "''${TEAM_ID:-}" ]; then
        export DEVELOPMENT_TEAM="$TEAM_ID"
      fi

      ${darwinXcodeShellHook}

      echo "Contributors: nix run .#xcodegen-ios | export WAWONA_SKIP_NIX_PREBUILD=1 for UI iteration"
      ${releaseShellHook}
    '';
  };

  releaseShell = pkgs.mkShell {
    preferLocalBuild = true;
    inputsFrom = [
      (if pkgs.stdenv.hostPlatform.isDarwin then darwinShell else linuxShell)
    ];
    shellHook = ''
      ${if pkgs.stdenv.hostPlatform.isDarwin then darwinXcodeShellHook else ""}
      ${releaseShellHook}
    '';
  };

  # Compile-only shell for the Linux GTK UI on any host. On Linux it inherits
  # the full linuxShell (which already carries the GTK4 stack). On macOS it
  # layers the GTK4/libadwaita dev libraries (cached for darwin) on top of the
  # darwinShell so contributors and CI-equivalent local checks can run
  # `nix develop .#linux-ui-check -c cargo build --bin wawona-linux-ui --features linux-ui`
  # without a Linux machine.
  linuxUiCheckShell = pkgs.mkShell {
    preferLocalBuild = true;
    inputsFrom = [
      (if pkgs.stdenv.hostPlatform.isDarwin then darwinShell else linuxShell)
    ];
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      pkgs.gtk4
      pkgs.libadwaita
      pkgs.glib
      pkgs.cairo
      pkgs.pango
      pkgs.gdk-pixbuf
      pkgs.graphene
      pkgs.harfbuzz
      pkgs.fribidi
      pkgs.freetype
      pkgs.fontconfig
    ];
  };
in {
  name = system;
  value = {
    default = if pkgs.stdenv.hostPlatform.isDarwin then darwinShell else linuxShell;
    release = releaseShell;
    linux-ui-check = linuxUiCheckShell;
  };
}) systems)
