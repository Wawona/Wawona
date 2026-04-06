{
  pkgs,
  wawonaVersion,
  wawonaSrc,
  macosBackend ? null,
  iosBackend ? null,
  iosSimBackend ? null,
  TEAM_ID ? null,
  iosDeps ? {},
  iosSimDeps ? {},
  macosDeps ? {},
  macosWeston ? null,
}:

let
  lib = pkgs.lib;
  strip = d: if d == null then "" else toString d;
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit lib pkgs TEAM_ID; };

  # Dependency version strings (must match the tags/versions in dependencies/libs/*)
  depVersions = {
    wayland   = "1.23.0";
    xkbcommon = "1.7.0";
    lz4       = "1.10.0";
    zstd      = "1.5.7";
    libffi    = "3.5.2";
    sshpass   = "1.10";
    waypipe   = "0.10.6";
  };

  # Build escaped preprocessor definitions for Xcode (string macros need escaped quotes)
  versionDefs = [
    "WAWONA_VERSION=\\\"${wawonaVersion}\\\""
    "WAWONA_WAYLAND_VERSION=\\\"${depVersions.wayland}\\\""
    "WAWONA_XKBCOMMON_VERSION=\\\"${depVersions.xkbcommon}\\\""
    "WAWONA_LZ4_VERSION=\\\"${depVersions.lz4}\\\""
    "WAWONA_ZSTD_VERSION=\\\"${depVersions.zstd}\\\""
    "WAWONA_LIBFFI_VERSION=\\\"${depVersions.libffi}\\\""
    "WAWONA_SSHPASS_VERSION=\\\"${depVersions.sshpass}\\\""
    "WAWONA_WAYPIPE_VERSION=\\\"${depVersions.waypipe}\\\""
  ];

  # PreBuildScript helper
  # src/core is entirely Rust (0 C/ObjC files) — excluded entirely
  # src/stubs depend on system headers (wayland, vulkan) that are only
  # available from the Nix build environment, so they stay out of Xcode.
  # The Xcode build compiles only the platform ObjC layer and links libwawona.a
  commonExcludes = ["**/*.rs" "**/*.toml" "**/*.md" "**/Cargo.lock" "**/.DS_Store" "**/renderer_android.*" "**/WWNSettings.c"];

  projectConfig = {
    name = "Wawona";
    options = {
      bundleIdPrefix = "com.aspauldingcode";
      deploymentTarget = {
        iOS = "26.0";
        macOS = "26.0";
      };
      generateEmptyDirectories = true;
    };
    settings = {
      base = {
        PRODUCT_NAME = "Wawona";
        MARKETING_VERSION = "0.1.0";
        CURRENT_PROJECT_VERSION = "1";
        CODE_SIGN_STYLE = "Automatic";
        CLANG_ENABLE_MODULES = "YES";
        CLANG_ENABLE_OBJC_ARC = "YES";
        ENABLE_BITCODE = "NO";
        GCC_PREPROCESSOR_DEFINITIONS = [
          "$(inherited)"
          "USE_RUST_CORE=1"
        ];
        HEADER_SEARCH_PATHS = [
          "$(inherited)"
          "${strip (iosDeps.libwayland or null)}/include"
          "${strip (iosDeps.xkbcommon or null)}/include"
          "$(SRCROOT)/src"
          "$(SRCROOT)/src/platform/macos/ui"
          "$(SRCROOT)/src/platform/macos/ui/Helpers"
          "$(SRCROOT)/src/platform/macos/ui/Settings"
          "$(SRCROOT)/src/extensions"
          "$(SRCROOT)/src/platform/macos"
          "$(SRCROOT)/src/platform/ios"
          "${strip (iosDeps.pixman or null)}/include"
          "${strip (iosDeps.openssl or null)}/include"
        ];
      };
    };
    targets = {
      Wawona-iOS = {
        type = "application";
        platform = "iOS";
        sources = [
          {
            path = "src/platform/macos";
            excludes = commonExcludes ++ [
              "*Window*"
              "*MacOS*"
              "*Popup*"
              "main.m"
              "ui/**"
            ];
          }
          { path = "src/platform/macos/main.m"; }
          { path = "src/platform/ios"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui/Settings"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ];
        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            ASSETCATALOG_COMPILER_APPICON_NAME = "";
            TARGETED_DEVICE_FAMILY = "1,2";
            CODE_SIGN_STYLE = "Automatic";
            ENABLE_DEBUG_DYLIB = "NO";
            "CODE_SIGNING_ALLOWED[config=Debug]" = "NO";
            "CODE_SIGNING_REQUIRED[config=Debug]" = "NO";
            "CODE_SIGN_STYLE[config=Debug]" = "Manual";
            CODE_SIGNING_ALLOWED = "YES";
            CODE_SIGNING_REQUIRED = "YES";
            "CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = "NO";
            "CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = "NO";
            "VALID_ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ONLY_ACTIVE_ARCH" = "YES";
            OTHER_CODE_SIGN_FLAGS = [
              "$(inherited)"
              "--deep"
              "--identifier"
              "$(PRODUCT_BUNDLE_IDENTIFIER)"
            ];
            "FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]" = [
              "$(inherited)"
              "$(SDKROOT)/System/Library/SubFrameworks"
            ];
            "FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]" = [
              "$(inherited)"
              "$(SDKROOT)/System/Library/SubFrameworks"
            ];
            "OTHER_LDFLAGS[sdk=iphoneos*]" = [
              "$(inherited)"
              "-L${strip (iosDeps.libwayland or null)}/lib"
              "-L${strip (iosDeps.xkbcommon or null)}/lib"
              "-L${strip (iosDeps.libffi or null)}/lib"
              "-L${strip (iosDeps.pixman or null)}/lib"
              "-L${strip (iosDeps.zstd or null)}/lib"
              "-L${strip (iosDeps.lz4 or null)}/lib"
              "-L${strip (iosDeps.libssh2 or null)}/lib"
              "-L${strip (iosDeps.mbedtls or null)}/lib"
              "-L${strip (iosDeps.openssl or null)}/lib"
              "-L${strip (iosDeps.epoll-shim or null)}/lib"
               "-L${strip (iosDeps.weston-simple-shm or null)}/lib"
               "-L${strip (iosDeps.weston or null)}/lib"
               "-lxkbcommon"
               "-lwayland-client"
               "-lffi"
               "-lpixman-1"
               "-lzstd"
               "-llz4"
               "-lz"
               "-lssh2"
               "-lmbedcrypto"
               "-lmbedx509"
               "-lmbedtls"
               "-lssl"
               "-lcrypto"
               "-lepoll-shim"
               "-lweston_simple_shm"
               "-lweston-13"
               "-lweston-desktop-13"
               "-lweston-terminal"
               "${strip iosBackend}/lib/libwawona.a"
            ];
            "OTHER_LDFLAGS[sdk=iphonesimulator*]" = [
              "$(inherited)"
              "-L${strip (iosSimDeps.libwayland or null)}/lib"
              "-L${strip (iosSimDeps.xkbcommon or null)}/lib"
              "-L${strip (iosSimDeps.libffi or null)}/lib"
              "-L${strip (iosSimDeps.pixman or null)}/lib"
              "-L${strip (iosSimDeps.zstd or null)}/lib"
              "-L${strip (iosSimDeps.lz4 or null)}/lib"
              "-L${strip (iosSimDeps.libssh2 or null)}/lib"
              "-L${strip (iosSimDeps.mbedtls or null)}/lib"
              "-L${strip (iosSimDeps.openssl or null)}/lib"
              "-L${strip (iosSimDeps.epoll-shim or null)}/lib"
               "-L${strip (iosSimDeps.weston-simple-shm or null)}/lib"
               "-L${strip (iosSimDeps.weston or null)}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lffi"
              "-lpixman-1"
              "-lzstd"
              "-llz4"
              "-lz"
              "-lssh2"
              "-lmbedcrypto"
              "-lmbedx509"
              "-lmbedtls"
              "-lssl"
              "-lcrypto"
               "-lepoll-shim"
               "-lweston_simple_shm"
               "-lweston-13"
               "-lweston-desktop-13"
               "-lweston-terminal"
               "${strip iosSimBackend}/lib/libwawona.a"
            ];
            GCC_PREPROCESSOR_DEFINITIONS = [
              "$(inherited)"
              "TARGET_OS_IPHONE=1"
              "PRODUCT_BUNDLE_IDENTIFIER=\\\"com.aspauldingcode.Wawona\\\""
            ] ++ versionDefs;
            "HEADER_SEARCH_PATHS[sdk=iphoneos*]" = [
              "$(inherited)"
              "${strip (iosDeps.libwayland or null)}/include"
              "${strip (iosDeps.libwayland or null)}/include/wayland"
              "${strip (iosDeps.xkbcommon or null)}/include"
              "${strip (iosDeps.libssh2 or null)}/include"
            ];
            "HEADER_SEARCH_PATHS[sdk=iphonesimulator*]" = [
              "$(inherited)"
              "${strip (iosSimDeps.libwayland or null)}/include"
              "${strip (iosSimDeps.libwayland or null)}/include/wayland"
              "${strip (iosSimDeps.xkbcommon or null)}/include"
              "${strip (iosSimDeps.libssh2 or null)}/include"
            ];
          };
        };
        dependencies = [
          { sdk = "UIKit.framework"; }
          { sdk = "Foundation.framework"; }
          { sdk = "CoreGraphics.framework"; }
          { sdk = "QuartzCore.framework"; }
          { sdk = "CoreVideo.framework"; }
          { sdk = "Metal.framework"; }
          { sdk = "MetalKit.framework"; }
          { sdk = "IOSurface.framework"; }
          { sdk = "CoreMedia.framework"; }
          { sdk = "AVFoundation.framework"; }
          { sdk = "Security.framework"; }
          { sdk = "Network.framework"; }
        ];
      };
      Wawona-macOS = {
        type = "application";
        platform = "macOS";
        sources = [
          { path = "src/platform/macos"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
          { path = "src/resources/macos"; type = "folder"; }
        ];
        postBuildScripts = [
          {
            name = "Bundle Executables";
            basedOnDependencyAnalysis = false;
            script = ''
              WAYPIPE_SRC="${strip (macosDeps.waypipe or null)}/bin/waypipe"
              SSHPASS_SRC="${strip (macosDeps.sshpass or null)}/bin/sshpass"
              WESTON_SRC="${strip macosWeston}/bin"
              
              BIN_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/bin"
              MACOS_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/MacOS"
              mkdir -p "$BIN_DEST"

              # Bundle Waypipe
              if [ -f "$WAYPIPE_SRC" ]; then
                install -m 755 "$WAYPIPE_SRC" "$BIN_DEST/waypipe"
                install -m 755 "$WAYPIPE_SRC" "$MACOS_DEST/waypipe"
                echo "Bundled waypipe"
              fi

              # Bundle sshpass
              if [ -f "$SSHPASS_SRC" ]; then
                install -m 755 "$SSHPASS_SRC" "$BIN_DEST/sshpass"
                install -m 755 "$SSHPASS_SRC" "$MACOS_DEST/sshpass"
                echo "Bundled sshpass"
              fi

              # Bundle Weston Clients
              if [ -d "$WESTON_SRC" ]; then
                for client in weston weston-terminal weston-simple-egl weston-simple-shm weston-flower weston-smoke weston-resizor weston-scaler; do
                  if [ -f "$WESTON_SRC/$client" ]; then
                    install -m 755 "$WESTON_SRC/$client" "$BIN_DEST/$client"
                    echo "Bundled $client"
                  fi
                done
              fi
            '';
          }
        ];
        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            CODE_SIGN_STYLE = "Automatic";
            HEADER_SEARCH_PATHS = [
              "$(inherited)"
              "${strip (macosDeps.libwayland or null)}/include"
              "${strip (macosDeps.libwayland or null)}/include/wayland"
              "${strip (iosDeps.xkbcommon or null)}/include"
              "$(SRCROOT)/src"
              "$(SRCROOT)/src/platform/macos/ui"
              "$(SRCROOT)/src/platform/macos/ui/Helpers"
              "$(SRCROOT)/src/platform/macos/ui/Settings"
              "$(SRCROOT)/src/platform/macos"
            ];
            OTHER_LDFLAGS = [
              "$(inherited)"
              "-L${strip (macosDeps.libwayland or null)}/lib"
              "-L${strip (macosDeps.xkbcommon or null)}/lib"
              "-L${pkgs.pixman}/lib"
              "-L${pkgs.openssl.out}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lwayland-server"
              "-lpixman-1"
              "-lssl"
              "-lcrypto"
              "-lz"
              "${strip macosBackend}/lib/libwawona.a"
            ];
            GCC_PREPROCESSOR_DEFINITIONS = [
              "$(inherited)"
              "USE_RUST_CORE=1"
              "PRODUCT_BUNDLE_IDENTIFIER=\\\"com.aspauldingcode.Wawona\\\""
            ] ++ versionDefs;
          };
        };
        dependencies = [
          { sdk = "Cocoa.framework"; }
          { sdk = "Foundation.framework"; }
          { sdk = "CoreGraphics.framework"; }
          { sdk = "QuartzCore.framework"; }
          { sdk = "CoreVideo.framework"; }
          { sdk = "Metal.framework"; }
          { sdk = "MetalKit.framework"; }
          { sdk = "IOSurface.framework"; }
          { sdk = "CoreMedia.framework"; }
          { sdk = "VideoToolbox.framework"; }
          { sdk = "AVFoundation.framework"; }
          { sdk = "Security.framework"; }
          { sdk = "Network.framework"; }
          { sdk = "ColorSync.framework"; }
        ];
      };
    };
  };

  projectYamlFile = pkgs.writeText "project.yml" (builtins.toJSON projectConfig);
  projectDrv = pkgs.stdenv.mkDerivation {
    pname = "WawonaXcodeProject";
    version = wawonaVersion;
    src = wawonaSrc;

    nativeBuildInputs = [ pkgs.xcodegen ];

    buildPhase = ''
      runHook preBuild
      cp ${projectYamlFile} project.yml
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      export HOME="$TMPDIR"
      export USER="nobody"
      ${pkgs.xcodegen}/bin/xcodegen generate --spec project.yml
      mkdir -p $out
      cp -R . "$out/"
      runHook postInstall
    '';
  };

  # Script to generate project (headless)
  generateScript = pkgs.writeShellScriptBin "xcodegen" ''
    set -euo pipefail
    SPEC_PATH=${projectYamlFile}

    if command -v nix >/dev/null 2>&1; then
      FLAKE_REF="."
      if [ -f "crates/Wawona/flake.nix" ]; then
        FLAKE_REF="./crates/Wawona"
      fi
      nix build --no-link "$FLAKE_REF#wawona-macos-backend" "$FLAKE_REF#wawona-ios-backend" "$FLAKE_REF#wawona-ios-sim-backend" >/dev/null
    fi

    if [ -d "Wawona.xcodeproj" ]; then
      chmod -R u+w "Wawona.xcodeproj" 2>/dev/null || true
      rm -rf "Wawona.xcodeproj"
    fi

    TMP_SPEC="./.xcodegen-project.tmp.json"
    rm -f "$TMP_SPEC"
    cp "$SPEC_PATH" "$TMP_SPEC"
    chmod u+w "$TMP_SPEC"
    trap 'rm -f "$TMP_SPEC"' EXIT
    rm -rf "./Wawona.xcodeproj"
    EFFECTIVE_TEAM_ID="''${TEAM_ID:-}"
    if [ -n "$EFFECTIVE_TEAM_ID" ] && command -v security >/dev/null 2>&1; then
      if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "(''$EFFECTIVE_TEAM_ID)"; then
        echo "Warning: TEAM_ID=''$EFFECTIVE_TEAM_ID has no matching local Apple Development certificate."
        echo "Installed signing identities:"
        security find-identity -v -p codesigning 2>/dev/null || true
        echo "Keeping explicit TEAM_ID from environment; install matching cert/account for this team in Xcode."
      fi
    fi
    if [ -n "$EFFECTIVE_TEAM_ID" ]; then
      # Only apply team to iOS target so user-selected macOS signing is untouched.
      TMP_SPEC="$TMP_SPEC" EFFECTIVE_TEAM_ID="$EFFECTIVE_TEAM_ID" ${pkgs.python3}/bin/python3 <<'EOF'
import json
from pathlib import Path
import os

p = Path(os.environ["TMP_SPEC"])
data = json.loads(p.read_text())
team = os.environ.get("EFFECTIVE_TEAM_ID", "").strip()
if team:
    ios_target = data.setdefault("targets", {}).setdefault("Wawona-iOS", {})
    base = ios_target.setdefault("settings", {}).setdefault("base", {})
    base["DEVELOPMENT_TEAM"] = team
    p.write_text(json.dumps(data, indent=2))
EOF
      echo "Applied TEAM_ID=$EFFECTIVE_TEAM_ID to Wawona-iOS."
    fi
    ${xcodeUtils.xcodeWrapper}/bin/xcode-wrapper ${pkgs.xcodegen}/bin/xcodegen generate --spec "$TMP_SPEC"

    mkdir -p "Wawona.xcodeproj/xcshareddata/xcschemes"
    cat > "Wawona.xcodeproj/xcshareddata/xcschemes/xcschememanagement.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SchemeUserState</key>
  <dict>
    <key>Wawona-iOS.xcscheme_^#shared#^_</key>
    <dict>
      <key>orderHint</key>
      <integer>0</integer>
    </dict>
    <key>Wawona-macOS.xcscheme_^#shared#^_</key>
    <dict>
      <key>orderHint</key>
      <integer>1</integer>
    </dict>
  </dict>
  <key>SuppressBuildableAutocreation</key>
  <dict/>
</dict>
</plist>
EOF

    echo "Wawona.xcodeproj generated in current directory."
  '';

  # Script to generate AND open project
  openScript = pkgs.writeShellScriptBin "xcodegen-open" ''
    set -e
    ${generateScript}/bin/xcodegen
    
    echo "Opening Wawona.xcodeproj..."
    if [ -d "Wawona.xcodeproj" ]; then
      open Wawona.xcodeproj
      echo "Project opened in Xcode."
    else
      echo "Error: Wawona.xcodeproj was not generated."
      exit 1
    fi
  '';
in {
  project = projectDrv;
  app = generateScript;
  inherit openScript;
}
