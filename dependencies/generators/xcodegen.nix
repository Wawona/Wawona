{
  pkgs,
  wawonaVersion,
  wawonaSrc,
  macosBackend ? null,
  iosBackend ? null,
  iosSimBackend ? null,
  ipadosBackend ? null,
  ipadosSimBackend ? null,
  tvosBackend ? null,
  tvosSimBackend ? null,
  visionosBackend ? null,
  visionosSimBackend ? null,
  watchosBackend ? null,
  watchosSimBackend ? null,
  TEAM_ID ? null,
  iosDeps ? {},
  iosSimDeps ? {},
  ipadosDeps ? {},
  ipadosSimDeps ? {},
  tvosDeps ? {},
  tvosSimDeps ? {},
  visionosDeps ? {},
  visionosSimDeps ? {},
  macosDeps ? {},
  watchosDeps ? {},
  watchosSimDeps ? {},
  macosWeston ? null,
  macosFoot ? null,
}:

let
  lib = pkgs.lib;
  strip = d: if d == null then "" else toString d;
  xcodeUtils = import ../apple/default.nix { inherit lib pkgs TEAM_ID; };

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
  preBuildScript = pkgs.writeShellScript "wawona-xcode-prebuild.sh" ''
    set -euo pipefail

    if ! command -v nix >/dev/null 2>&1; then
      echo "nix not available; skipping backend prebuild"
      exit 0
    fi

    FLAKE_REF="."
    if [ -f "crates/Wawona/flake.nix" ]; then
      FLAKE_REF="./crates/Wawona"
    fi

    # Keep all Nix store inputs referenced by the generated Xcode project alive.
    # The project hardcodes /nix/store paths for platform backends/libs; if those
    # paths are GC'd, Xcode reports "No such file or directory" across targets.
    # First realize backend outputs, then create a stable GC root for xcodegen.
    # This ensures the linked libwawona.a paths exist before the link phase.
    nix build --no-link \
      "$FLAKE_REF#wawona-macos-backend" \
      "$FLAKE_REF#wawona-ios-backend" \
      "$FLAKE_REF#wawona-ios-sim-backend" \
      "$FLAKE_REF#wawona-ipados-backend" \
      "$FLAKE_REF#wawona-ipados-sim-backend" \
      "$FLAKE_REF#wawona-tvos-backend" \
      "$FLAKE_REF#wawona-tvos-sim-backend" \
      "$FLAKE_REF#wawona-visionos-backend" \
      "$FLAKE_REF#wawona-visionos-sim-backend" \
      "$FLAKE_REF#wawona-watchos-backend" \
      "$FLAKE_REF#wawona-watchos-sim-backend" >/dev/null

    mkdir -p .nix-gcroots
    nix build --out-link .nix-gcroots/xcodegen "$FLAKE_REF#xcodegen" >/dev/null
  '';

  # src/core is entirely Rust (0 C/ObjC files) — excluded entirely
  # src/stubs depend on system headers (wayland, vulkan) that are only
  # available from the Nix build environment, so they stay out of Xcode.
  # The Xcode build compiles only the platform ObjC layer and links libwawona.a
  commonExcludes = ["**/*.rs" "**/*.toml" "**/*.md" "**/Cargo.lock" "**/.DS_Store" "**/renderer_android.*" "**/WWNSettings.c" "**/Skip/**"];

  projectConfig = {
    name = "Wawona";
    options = {
      bundleIdPrefix = "com.aspauldingcode";
      deploymentTarget = {
        iOS = "17.0";
        macOS = "14.0";
      };
      generateEmptyDirectories = true;
    };
    settings = {
      base = {
        PRODUCT_NAME = "Wawona";
        MARKETING_VERSION = "0.1.0";
        CURRENT_PROJECT_VERSION = "1";
        CODE_SIGN_STYLE = "Automatic";
        SWIFT_VERSION = "5.0";
        SWIFT_OBJC_BRIDGING_HEADER = "src/platform/macos/WWN-Bridging-Header.h";
        CLANG_ENABLE_MODULES = "YES";
        CLANG_ENABLE_OBJC_ARC = "YES";
        DEAD_CODE_STRIPPING = "YES";
        STRING_CATALOG_GENERATE_SYMBOLS = "YES";
        ENABLE_BITCODE = "NO";
        # Xcode 15+ default enables script sandbox; breaks swift-plugin-server / macros under some builds (sandbox_apply EPERM).
        ENABLE_USER_SCRIPT_SANDBOXING = "NO";
        GCC_PREPROCESSOR_DEFINITIONS = [
          "$(inherited)"
          "USE_RUST_CORE=1"
        ];
        HEADER_SEARCH_PATHS = [
          "$(inherited)"
          "$(SRCROOT)/src"
          "$(SRCROOT)/src/platform/macos/ui"
          "$(SRCROOT)/src/platform/macos/ui/Machines"
          "$(SRCROOT)/src/platform/macos/ui/Helpers"
          "$(SRCROOT)/src/platform/macos/ui/Settings"
          "$(SRCROOT)/src/extensions"
          "$(SRCROOT)/src/platform/macos"
          "$(SRCROOT)/src/platform/ios"
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
              "WWNLaunchAgentManager.h"
              "WWNLaunchAgentManager.m"
              "ui/**"
            ];
          }
          { path = "src/platform/ios"; excludes = commonExcludes ++ [ "WWNWaypipeRunnerVisionStub.m" ]; }
          { path = "src/platform/macos/ui/Machines"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui/Settings"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ];
        preBuildScripts = [
          {
            path = preBuildScript;
            name = "Build Rust Backend via Nix";
            basedOnDependencyAnalysis = false;
            outputFiles = [ "$(BUILT_PRODUCTS_DIR)/libwawona.a" ];
          }
        ];

        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon";
            # Reduces actool work that ties thinned catalogs to installed Simulator runtimes.
            ENABLE_ON_DEMAND_RESOURCES = "NO";
            SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            TARGETED_DEVICE_FAMILY = "1";
            SUPPORTS_MACCATALYST = "NO";
            SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = "NO";
            SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = "NO";
            CODE_SIGN_STYLE = "Automatic";
            ENABLE_DEBUG_DYLIB = "NO";
            # Allow compile/link without selecting a local Apple team.
            CODE_SIGNING_ALLOWED = "NO";
            CODE_SIGNING_REQUIRED = "NO";
            "VALID_ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ONLY_ACTIVE_ARCH" = "YES";
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
               "-L${strip (iosDeps.foot or null)}/lib"
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
               "-lfoot"
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
               "-L${strip (iosSimDeps.foot or null)}/lib"
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
               "-lfoot"
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
          { target = "WawonaModel"; embed = true; codeSign = true; }
          { target = "WawonaUIContracts"; embed = true; codeSign = true; }
          { sdk = "UIKit.framework"; }
          { sdk = "SwiftUI.framework"; }
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
      Wawona-iPadOS = {
        type = "application";
        platform = "iOS";
        sources = [
          {
            path = "src/platform/macos";
            excludes = commonExcludes ++ [
              "*Window*"
              "*MacOS*"
              "*Popup*"
              "WWNLaunchAgentManager.h"
              "WWNLaunchAgentManager.m"
              "ui/**"
            ];
          }
          { path = "src/platform/ios"; excludes = commonExcludes ++ [ "WWNWaypipeRunnerVisionStub.m" ]; }
          { path = "src/platform/macos/ui/Machines"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui/Settings"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ];
        preBuildScripts = [
          {
            path = preBuildScript;
            name = "Build Rust Backend via Nix";
            basedOnDependencyAnalysis = false;
            outputFiles = [ "$(BUILT_PRODUCTS_DIR)/libwawona.a" ];
          }
        ];

        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            # watchOS icon assets are currently generated outside Assets.xcassets.
            # Leave blank so actool does not require a watch-specific AppIcon set.
            ASSETCATALOG_COMPILER_APPICON_NAME = "";
            ENABLE_ON_DEMAND_RESOURCES = "NO";
            SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            TARGETED_DEVICE_FAMILY = "2";
            SUPPORTS_MACCATALYST = "NO";
            SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = "NO";
            SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = "NO";
            CODE_SIGN_STYLE = "Automatic";
            ENABLE_DEBUG_DYLIB = "NO";
            # Allow compile/link without selecting a local Apple team.
            CODE_SIGNING_ALLOWED = "NO";
            CODE_SIGNING_REQUIRED = "NO";
            "VALID_ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ONLY_ACTIVE_ARCH" = "YES";
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
              "-L${strip (ipadosDeps.libwayland or null)}/lib"
              "-L${strip (ipadosDeps.xkbcommon or null)}/lib"
              "-L${strip (ipadosDeps.libffi or null)}/lib"
              "-L${strip (ipadosDeps.pixman or null)}/lib"
              "-L${strip (ipadosDeps.zstd or null)}/lib"
              "-L${strip (ipadosDeps.lz4 or null)}/lib"
              "-L${strip (ipadosDeps.libssh2 or null)}/lib"
              "-L${strip (ipadosDeps.mbedtls or null)}/lib"
              "-L${strip (ipadosDeps.openssl or null)}/lib"
              "-L${strip (ipadosDeps.epoll-shim or null)}/lib"
              "-L${strip (ipadosDeps.weston-simple-shm or null)}/lib"
              "-L${strip (ipadosDeps.weston or null)}/lib"
              "-L${strip (ipadosDeps.foot or null)}/lib"
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
              "-lfoot"
              "${strip ipadosBackend}/lib/libwawona.a"
            ];
            "OTHER_LDFLAGS[sdk=iphonesimulator*]" = [
              "$(inherited)"
              "-L${strip (ipadosSimDeps.libwayland or null)}/lib"
              "-L${strip (ipadosSimDeps.xkbcommon or null)}/lib"
              "-L${strip (ipadosSimDeps.libffi or null)}/lib"
              "-L${strip (ipadosSimDeps.pixman or null)}/lib"
              "-L${strip (ipadosSimDeps.zstd or null)}/lib"
              "-L${strip (ipadosSimDeps.lz4 or null)}/lib"
              "-L${strip (ipadosSimDeps.libssh2 or null)}/lib"
              "-L${strip (ipadosSimDeps.mbedtls or null)}/lib"
              "-L${strip (ipadosSimDeps.openssl or null)}/lib"
              "-L${strip (ipadosSimDeps.epoll-shim or null)}/lib"
              "-L${strip (ipadosSimDeps.weston-simple-shm or null)}/lib"
              "-L${strip (ipadosSimDeps.weston or null)}/lib"
              "-L${strip (ipadosSimDeps.foot or null)}/lib"
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
              "-lfoot"
              "${strip ipadosSimBackend}/lib/libwawona.a"
            ];
            GCC_PREPROCESSOR_DEFINITIONS = [
              "$(inherited)"
              "TARGET_OS_IPHONE=1"
              "PRODUCT_BUNDLE_IDENTIFIER=\\\"com.aspauldingcode.Wawona\\\""
            ] ++ versionDefs;
            "HEADER_SEARCH_PATHS[sdk=iphoneos*]" = [
              "$(inherited)"
              "${strip (ipadosDeps.libwayland or null)}/include"
              "${strip (ipadosDeps.libwayland or null)}/include/wayland"
              "${strip (ipadosDeps.xkbcommon or null)}/include"
              "${strip (ipadosDeps.libssh2 or null)}/include"
            ];
            "HEADER_SEARCH_PATHS[sdk=iphonesimulator*]" = [
              "$(inherited)"
              "${strip (ipadosSimDeps.libwayland or null)}/include"
              "${strip (ipadosSimDeps.libwayland or null)}/include/wayland"
              "${strip (ipadosSimDeps.xkbcommon or null)}/include"
              "${strip (ipadosSimDeps.libssh2 or null)}/include"
            ];
          };
        };
        dependencies = [
          { target = "WawonaModel"; embed = true; codeSign = true; }
          { target = "WawonaUIContracts"; embed = true; codeSign = true; }
          { sdk = "UIKit.framework"; }
          { sdk = "SwiftUI.framework"; }
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
      Wawona-tvOS = {
        type = "application";
        platform = "tvOS";
        sources = [
          {
            path = "src/platform/macos";
            excludes = commonExcludes ++ [
              "*Window*"
              "*MacOS*"
              "*Popup*"
              "WWNLaunchAgentManager.h"
              "WWNLaunchAgentManager.m"
              "ui/**"
            ];
          }
          { path = "src/platform/ios"; excludes = commonExcludes ++ [ "WWNWaypipeRunnerVisionStub.m" ]; }
          { path = "src/platform/macos/ui/Machines"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui/Settings"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ];
        preBuildScripts = [
          {
            path = preBuildScript;
            name = "Build Rust Backend via Nix";
            basedOnDependencyAnalysis = false;
            outputFiles = [ "$(BUILT_PRODUCTS_DIR)/libwawona.a" ];
          }
        ];

        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            ASSETCATALOG_COMPILER_APPICON_NAME = "Wawona";
            ENABLE_ON_DEMAND_RESOURCES = "NO";
            SUPPORTED_PLATFORMS = "appletvos appletvsimulator";
            TARGETED_DEVICE_FAMILY = "3";
            CODE_SIGN_STYLE = "Automatic";
            ENABLE_DEBUG_DYLIB = "NO";
            CODE_SIGNING_ALLOWED = "YES";
            CODE_SIGNING_REQUIRED = "YES";
            "CODE_SIGNING_ALLOWED[sdk=appletvsimulator*]" = "NO";
            "CODE_SIGNING_REQUIRED[sdk=appletvsimulator*]" = "NO";
            "VALID_ARCHS[sdk=appletvsimulator*]" = "arm64";
            "ARCHS[sdk=appletvsimulator*]" = "arm64";
            "ONLY_ACTIVE_ARCH" = "YES";
            # Do not add $(SDKROOT)/System/Library/SubFrameworks on tvOS: it makes
            # the linker pick up UIUtilities / SwiftUICore as direct deps, which
            # tvOS app targets are not allowed to link.
            "OTHER_LDFLAGS[sdk=appletvos*]" = [
              "$(inherited)"
              "-L${strip (tvosDeps.libwayland or null)}/lib"
              "-L${strip (tvosDeps.xkbcommon or null)}/lib"
              "-L${strip (tvosDeps.libffi or null)}/lib"
              "-L${strip (tvosDeps.pixman or null)}/lib"
              "-L${strip (tvosDeps.zstd or null)}/lib"
              "-L${strip (tvosDeps.lz4 or null)}/lib"
              "-L${strip (tvosDeps.libssh2 or null)}/lib"
              "-L${strip (tvosDeps.mbedtls or null)}/lib"
              "-L${strip (tvosDeps.openssl or null)}/lib"
              "-L${strip (tvosDeps.epoll-shim or null)}/lib"
              "-L${strip (tvosDeps.weston-simple-shm or null)}/lib"
              "-L${strip (tvosDeps.weston or null)}/lib"
              "-L${strip (tvosDeps.foot or null)}/lib"
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
              "-lfoot"
              "${strip tvosBackend}/lib/libwawona.a"
            ];
            "OTHER_LDFLAGS[sdk=appletvsimulator*]" = [
              "$(inherited)"
              "-L${strip (tvosSimDeps.libwayland or null)}/lib"
              "-L${strip (tvosSimDeps.xkbcommon or null)}/lib"
              "-L${strip (tvosSimDeps.libffi or null)}/lib"
              "-L${strip (tvosSimDeps.pixman or null)}/lib"
              "-L${strip (tvosSimDeps.zstd or null)}/lib"
              "-L${strip (tvosSimDeps.lz4 or null)}/lib"
              "-L${strip (tvosSimDeps.libssh2 or null)}/lib"
              "-L${strip (tvosSimDeps.mbedtls or null)}/lib"
              "-L${strip (tvosSimDeps.openssl or null)}/lib"
              "-L${strip (tvosSimDeps.epoll-shim or null)}/lib"
              "-L${strip (tvosSimDeps.weston-simple-shm or null)}/lib"
              "-L${strip (tvosSimDeps.weston or null)}/lib"
              "-L${strip (tvosSimDeps.foot or null)}/lib"
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
              "-lfoot"
              "${strip tvosSimBackend}/lib/libwawona.a"
            ];
            GCC_PREPROCESSOR_DEFINITIONS = [
              "$(inherited)"
              "TARGET_OS_IPHONE=1"
              "TARGET_OS_TV=1"
              "PRODUCT_BUNDLE_IDENTIFIER=\\\"com.aspauldingcode.Wawona\\\""
            ] ++ versionDefs;
            "HEADER_SEARCH_PATHS[sdk=appletvos*]" = [
              "$(inherited)"
              "${strip (tvosDeps.libwayland or null)}/include"
              "${strip (tvosDeps.libwayland or null)}/include/wayland"
              "${strip (tvosDeps.xkbcommon or null)}/include"
              "${strip (tvosDeps.libssh2 or null)}/include"
            ];
            "HEADER_SEARCH_PATHS[sdk=appletvsimulator*]" = [
              "$(inherited)"
              "${strip (tvosSimDeps.libwayland or null)}/include"
              "${strip (tvosSimDeps.libwayland or null)}/include/wayland"
              "${strip (tvosSimDeps.xkbcommon or null)}/include"
              "${strip (tvosSimDeps.libssh2 or null)}/include"
            ];
          };
        };
        dependencies = [
          { target = "WawonaModel"; embed = true; codeSign = true; }
          { target = "WawonaUIContracts"; embed = true; codeSign = true; }
          { sdk = "UIKit.framework"; }
          { sdk = "SwiftUI.framework"; }
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
          { path = "Sources/WawonaUI"; excludes = [ "Skip/**" "VisionOS/**" ]; }
          { path = "src/platform/macos"; excludes = commonExcludes; }
          { path = "src/platform/macos/ui"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
          { path = "src/resources/macos"; type = "folder"; }
        ];
        preBuildScripts = [
          {
            path = preBuildScript;
            name = "Build Rust Backend via Nix";
            basedOnDependencyAnalysis = false;
            outputFiles = [ "$(BUILT_PRODUCTS_DIR)/libwawona.a" ];
          }
        ];
        postBuildScripts = [
          {
            name = "Bundle Executables";
            basedOnDependencyAnalysis = false;
            script = ''
              WAYPIPE_SRC="${strip (macosDeps.waypipe or null)}/bin/waypipe"
              SSHPASS_SRC="${strip (macosDeps.sshpass or null)}/bin/sshpass"
              WESTON_SRC="${strip macosWeston}/bin"
              FOOT_BIN="${strip macosFoot}/bin"

              BIN_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/bin"
              MACOS_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/MacOS"
              mkdir -p "$BIN_DEST"
              mkdir -p "$MACOS_DEST"

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
                    install -m 755 "$WESTON_SRC/$client" "$MACOS_DEST/$client"
                    echo "Bundled $client"
                  fi
                done
              fi

              # Bundle Foot terminal (wrapper script + real binary; see clients/foot/macos.nix postInstall)
              if [ -f "$FOOT_BIN/foot" ]; then
                install -m 755 "$FOOT_BIN/foot" "$BIN_DEST/foot"
                install -m 755 "$FOOT_BIN/foot" "$MACOS_DEST/foot"
                if [ -f "$FOOT_BIN/.foot-wrapped" ]; then
                  install -m 755 "$FOOT_BIN/.foot-wrapped" "$BIN_DEST/.foot-wrapped"
                  install -m 755 "$FOOT_BIN/.foot-wrapped" "$MACOS_DEST/.foot-wrapped"
                fi
                echo "Bundled foot"
              fi
            '';
          }
        ];
        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            SUPPORTED_PLATFORMS = "macosx";
            CODE_SIGN_STYLE = "Automatic";
            DEAD_CODE_STRIPPING = "YES";
            HEADER_SEARCH_PATHS = [
              "$(inherited)"
              "${strip (macosDeps.libwayland or null)}/include"
              "${strip (macosDeps.libwayland or null)}/include/wayland"
              "${strip (iosDeps.xkbcommon or null)}/include"
              "$(SRCROOT)/src"
              "$(SRCROOT)/src/platform/macos/ui"
              "$(SRCROOT)/src/platform/macos/ui/Machines"
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
          { target = "WawonaModel"; embed = true; codeSign = true; }
          { target = "WawonaUIContracts"; embed = true; codeSign = true; }
          { sdk = "Cocoa.framework"; }
          { sdk = "SwiftUI.framework"; }
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
      Wawona-visionOS = {
        type = "application";
        platform = "visionOS";
        sources = [
          {
            path = "src/platform/macos";
            excludes = commonExcludes ++ [
              "ui/**"
              "*Window*"
              "*Popup*"
              "*MacOS*"
              "WWNLaunchAgentManager.h"
              "WWNLaunchAgentManager.m"
            ];
          }
          { path = "src/platform/ios"; excludes = commonExcludes; }
          { path = "src/platform/ios/WWNWaypipeRunnerVisionStub.m"; type = "file"; }
          { path = "src/platform/macos/ui/Machines"; excludes = commonExcludes; }
          {
            path = "src/platform/macos/ui/Settings";
            excludes = commonExcludes ++ [ "WWNWaypipeRunner.m" ];
          }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ];
        preBuildScripts = [
          {
            path = preBuildScript;
            name = "Build Rust Backend via Nix";
            basedOnDependencyAnalysis = false;
            outputFiles = [ "$(BUILT_PRODUCTS_DIR)/libwawona.a" ];
          }
        ];
        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            ASSETCATALOG_COMPILER_APPICON_NAME = "Wawona";
            SUPPORTED_PLATFORMS = "xros xrsimulator";
            CODE_SIGN_STYLE = "Automatic";
            ENABLE_DEBUG_DYLIB = "NO";
            CODE_SIGNING_ALLOWED = "YES";
            CODE_SIGNING_REQUIRED = "YES";
            "CODE_SIGNING_ALLOWED[sdk=xrsimulator*]" = "NO";
            "CODE_SIGNING_REQUIRED[sdk=xrsimulator*]" = "NO";
            "VALID_ARCHS[sdk=xrsimulator*]" = "arm64";
            "ARCHS[sdk=xrsimulator*]" = "arm64";
            "ONLY_ACTIVE_ARCH" = "YES";
            "FRAMEWORK_SEARCH_PATHS[sdk=xros*]" = [
              "$(inherited)"
            ];
            "FRAMEWORK_SEARCH_PATHS[sdk=xrsimulator*]" = [
              "$(inherited)"
            ];
            "OTHER_LDFLAGS[sdk=xros*]" = [
              "$(inherited)"
              "-L${strip (visionosDeps.libwayland or null)}/lib"
              "-L${strip (visionosDeps.xkbcommon or null)}/lib"
              "-L${strip (visionosDeps.libffi or null)}/lib"
              "-L${strip (visionosDeps.pixman or null)}/lib"
              "-L${strip (visionosDeps.epoll-shim or null)}/lib"
              "-L${strip (visionosDeps.libssh2 or null)}/lib"
              "-L${strip (visionosDeps.openssl or null)}/lib"
              "-L${strip (visionosDeps.weston-simple-shm or null)}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lffi"
              "-lpixman-1"
              "-lepoll-shim"
              "-lssh2"
              "-lssl"
              "-lcrypto"
              "-lweston_simple_shm"
              "${strip visionosBackend}/lib/libwawona.a"
            ];
            "OTHER_LDFLAGS[sdk=xrsimulator*]" = [
              "$(inherited)"
              "-L${strip (visionosSimDeps.libwayland or null)}/lib"
              "-L${strip (visionosSimDeps.xkbcommon or null)}/lib"
              "-L${strip (visionosSimDeps.libffi or null)}/lib"
              "-L${strip (visionosSimDeps.pixman or null)}/lib"
              "-L${strip (visionosSimDeps.epoll-shim or null)}/lib"
              "-L${strip (visionosSimDeps.libssh2 or null)}/lib"
              "-L${strip (visionosSimDeps.openssl or null)}/lib"
              "-L${strip (visionosSimDeps.weston-simple-shm or null)}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lffi"
              "-lpixman-1"
              "-lepoll-shim"
              "-lssh2"
              "-lssl"
              "-lcrypto"
              "-lweston_simple_shm"
              "${strip visionosSimBackend}/lib/libwawona.a"
            ];
            GCC_PREPROCESSOR_DEFINITIONS = [
              "$(inherited)"
              "TARGET_OS_IPHONE=1"
              "TARGET_OS_VISION=1"
              "PRODUCT_BUNDLE_IDENTIFIER=\\\"com.aspauldingcode.Wawona\\\""
            ] ++ versionDefs;
            "HEADER_SEARCH_PATHS[sdk=xros*]" = [
              "$(inherited)"
              "${strip (visionosDeps.libwayland or null)}/include"
              "${strip (visionosDeps.libwayland or null)}/include/wayland"
              "${strip (visionosDeps.xkbcommon or null)}/include"
              "${strip (visionosDeps.libssh2 or null)}/include"
            ];
            "HEADER_SEARCH_PATHS[sdk=xrsimulator*]" = [
              "$(inherited)"
              "${strip (visionosSimDeps.libwayland or null)}/include"
              "${strip (visionosSimDeps.libwayland or null)}/include/wayland"
              "${strip (visionosSimDeps.xkbcommon or null)}/include"
              "${strip (visionosSimDeps.libssh2 or null)}/include"
            ];
          };
        };
        dependencies = [
          { target = "WawonaModel"; embed = true; codeSign = true; }
          { target = "WawonaUIContracts"; embed = true; codeSign = true; }
          { sdk = "UIKit.framework"; }
          { sdk = "SwiftUI.framework"; }
          { sdk = "Foundation.framework"; }
          { sdk = "CoreGraphics.framework"; }
          { sdk = "CoreVideo.framework"; }
          { sdk = "MetalKit.framework"; }
          { sdk = "IOSurface.framework"; }
          { sdk = "CoreMedia.framework"; }
          { sdk = "AVFoundation.framework"; }
          { sdk = "Security.framework"; }
          { sdk = "Network.framework"; }
          { sdk = "QuartzCore.framework"; }
          { sdk = "Metal.framework"; }
        ];
      };
      WawonaModel = {
        type = "framework";
        platform = "iOS";
        scheme = false;
        sources = [
          { path = "Sources/WawonaModel"; excludes = commonExcludes ++ [ "*.modulemap" ]; }
        ];
        settings = {
          base = {
            PRODUCT_NAME = "WawonaModel";
            PRODUCT_MODULE_NAME = "WawonaModel";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.WawonaModel";
            SUPPORTED_PLATFORMS = "macosx iphoneos iphonesimulator appletvos appletvsimulator xros xrsimulator watchos watchsimulator";
            TARGETED_DEVICE_FAMILY = "1,2,3,4,7";
            MACOSX_DEPLOYMENT_TARGET = "14.0";
            TVOS_DEPLOYMENT_TARGET = "17.0";
            SUPPORTS_MACCATALYST = "NO";
            SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = "NO";
            SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = "NO";
            WATCHOS_DEPLOYMENT_TARGET = "10.0";
            GENERATE_INFOPLIST_FILE = "YES";
            SWIFT_VERSION = "5.0";
            SWIFT_OBJC_BRIDGING_HEADER = "";
            SWIFT_INSTALL_OBJC_HEADER = "NO";
            DEFINES_MODULE = "YES";
            ENABLE_MODULE_VERIFIER = "NO";
            SKIP_INSTALL = "YES";
            BUILD_LIBRARY_FOR_DISTRIBUTION = "NO";
          };
        };
        dependencies = [ ];
      };
      WawonaUIContracts = {
        type = "framework";
        platform = "iOS";
        scheme = false;
        sources = [
          { path = "Sources/WawonaUIContracts"; excludes = commonExcludes ++ [ "Skip/**" ]; }
        ];
        settings = {
          base = {
            PRODUCT_NAME = "WawonaUIContracts";
            PRODUCT_MODULE_NAME = "WawonaUIContracts";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.WawonaUIContracts";
            SUPPORTED_PLATFORMS = "macosx iphoneos iphonesimulator appletvos appletvsimulator xros xrsimulator watchos watchsimulator";
            TARGETED_DEVICE_FAMILY = "1,2,3,4,7";
            MACOSX_DEPLOYMENT_TARGET = "14.0";
            TVOS_DEPLOYMENT_TARGET = "17.0";
            SUPPORTS_MACCATALYST = "NO";
            SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = "NO";
            SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = "NO";
            WATCHOS_DEPLOYMENT_TARGET = "10.0";
            GENERATE_INFOPLIST_FILE = "YES";
            SWIFT_VERSION = "5.0";
            SWIFT_OBJC_BRIDGING_HEADER = "";
            DEFINES_MODULE = "YES";
            ENABLE_MODULE_VERIFIER = "YES";
            SKIP_INSTALL = "YES";
            BUILD_LIBRARY_FOR_DISTRIBUTION = "NO";
          };
        };
        dependencies = [ ];
      };
      Wawona-watchOS = {
        type = "application";
        platform = "watchOS";
        sources = [
          { path = "Sources/WawonaWatch"; excludes = commonExcludes; }
          { path = "src/platform/watchos"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
        ];
        settings = {
          base = {
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona.watch";
            SUPPORTED_PLATFORMS = "watchos watchsimulator";
            WATCHOS_DEPLOYMENT_TARGET = "10.0";
            GENERATE_INFOPLIST_FILE = "YES";
            ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon";
            INFOPLIST_KEY_WKCompanionAppBundleIdentifier = "com.aspauldingcode.Wawona";
            SWIFT_OBJC_BRIDGING_HEADER = "src/platform/watchos/WWNWatch-Bridging-Header.h";
            SWIFT_INSTALL_OBJC_HEADER = "NO";
            CODE_SIGNING_ALLOWED = "NO";
            CODE_SIGNING_REQUIRED = "NO";
            LD_RUNPATH_SEARCH_PATHS = [ "$(inherited)" "@executable_path/Frameworks" ];
            GCC_PREPROCESSOR_DEFINITIONS = [ "$(inherited)" "TARGET_OS_WATCH=1" ];
            "VALID_ARCHS[sdk=watchos*]" = "arm64";
            "ARCHS[sdk=watchos*]" = "arm64";
            "VALID_ARCHS[sdk=watchsimulator*]" = "arm64";
            "ARCHS[sdk=watchsimulator*]" = "arm64";
            HEADER_SEARCH_PATHS = [
              "$(inherited)"
              "${strip (watchosDeps.libffi or null)}/include"
              "${strip (watchosDeps.libwayland or null)}/include"
              "${strip (watchosDeps.libwayland or null)}/include/wayland"
              "${strip (watchosDeps.libssh2 or null)}/include"
              "$(SRCROOT)/src/platform/watchos"
            ];
            # -force_load is needed for the Wayland client libraries because
            # WWNWatchStubs.c provides __attribute__((weak)) definitions of
            # weston_main / weston_simple_shm_main / etc.  Without -force_load
            # the linker sees the weak defs as "already defined" and never pulls
            # the strong versions from the .a archives.
            #
            # Order matters: libweston_simple_shm.a is force-loaded BEFORE
            # -lwayland-server because both archives contain xdg-shell-protocol.o.
            # The Apple linker accepts the force-loaded copy first and silently
            # skips the duplicate from normal -l archive linking.
            "OTHER_LDFLAGS[sdk=watchos*]" = [
              "$(inherited)"
              "-L${strip (watchosDeps.libffi or null)}/lib"
              "-L${strip (watchosDeps.libwayland or null)}/lib"
              "-L${strip (watchosDeps.epoll-shim or null)}/lib"
              "-L${strip (watchosDeps.pixman or null)}/lib"
              "-L${strip (watchosDeps.zstd or null)}/lib"
              "-L${strip (watchosDeps.lz4 or null)}/lib"
              "-L${strip (watchosDeps.libssh2 or null)}/lib"
              "-L${strip (watchosDeps.mbedtls or null)}/lib"
              "-L${strip (watchosDeps.openssl or null)}/lib"
              "-lffi"
              "-lwayland-client"
              "-lepoll-shim"
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
              # Force-load client libs (must come BEFORE -lwayland-server)
              "-force_load" "${strip (watchosDeps.weston-simple-shm or null)}/lib/libweston_simple_shm.a"
              "-force_load" "${strip (watchosDeps.weston or null)}/lib/libweston-13.a"
              "-force_load" "${strip (watchosDeps.weston or null)}/lib/libweston-terminal.a"
              "-force_load" "${strip (watchosDeps.weston or null)}/lib/libweston-desktop-13.a"
              "-force_load" "${strip (watchosDeps.foot or null)}/lib/libfoot.a"
              # Server lib after client force-loads (skips duplicate xdg-shell glue)
              "-lwayland-server"
            ] ++ lib.optionals (watchosDeps ? waypipe && watchosDeps.waypipe != null) [
              "-force_load" "${strip watchosDeps.waypipe}/lib/libwaypipe.a"
            ] ++ lib.optionals (watchosBackend != null && builtins.pathExists "${watchosBackend}/lib/libwawona.a") [
              "${watchosBackend}/lib/libwawona.a"
            ];
            "OTHER_LDFLAGS[sdk=watchsimulator*]" = [
              "$(inherited)"
              "-L${strip (watchosSimDeps.libffi or null)}/lib"
              "-L${strip (watchosSimDeps.libwayland or null)}/lib"
              "-L${strip (watchosSimDeps.epoll-shim or null)}/lib"
              "-L${strip (watchosSimDeps.pixman or null)}/lib"
              "-L${strip (watchosSimDeps.zstd or null)}/lib"
              "-L${strip (watchosSimDeps.lz4 or null)}/lib"
              "-L${strip (watchosSimDeps.libssh2 or null)}/lib"
              "-L${strip (watchosSimDeps.mbedtls or null)}/lib"
              "-L${strip (watchosSimDeps.openssl or null)}/lib"
              "-lffi"
              "-lwayland-client"
              "-lepoll-shim"
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
              # Force-load client libs (must come BEFORE -lwayland-server)
              "-force_load" "${strip (watchosSimDeps.weston-simple-shm or null)}/lib/libweston_simple_shm.a"
              "-force_load" "${strip (watchosSimDeps.weston or null)}/lib/libweston-13.a"
              "-force_load" "${strip (watchosSimDeps.weston or null)}/lib/libweston-terminal.a"
              "-force_load" "${strip (watchosSimDeps.weston or null)}/lib/libweston-desktop-13.a"
              "-force_load" "${strip (watchosSimDeps.foot or null)}/lib/libfoot.a"
              # Server lib after client force-loads (skips duplicate xdg-shell glue)
              "-lwayland-server"
            ] ++ lib.optionals (watchosSimDeps ? waypipe && watchosSimDeps.waypipe != null) [
              "-force_load" "${strip watchosSimDeps.waypipe}/lib/libwaypipe.a"
            ] ++ lib.optionals (watchosSimBackend != null && builtins.pathExists "${watchosSimBackend}/lib/libwawona.a") [
              "${watchosSimBackend}/lib/libwawona.a"
            ];
          };
        };
        dependencies = [
          { target = "WawonaModel"; embed = true; codeSign = true; }
          { target = "WawonaUIContracts"; embed = true; codeSign = true; }
          { sdk = "SwiftUI.framework"; }
          { sdk = "WatchKit.framework"; }
          { sdk = "Foundation.framework"; }
          { sdk = "CoreGraphics.framework"; }
          { sdk = "Security.framework"; }
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
    find_repo_root() {
      local dir="$PWD"
      while [ "$dir" != "/" ]; do
        if [ -f "$dir/flake.nix" ]; then
          printf '%s\n' "$dir"
          return 0
        fi
        dir="$(dirname "$dir")"
      done
      return 1
    }
    REPO_ROOT="$(find_repo_root || true)"
    if [ -z "$REPO_ROOT" ]; then
      echo "Error: could not locate repo root (missing flake.nix in parent chain)." >&2
      exit 1
    fi
    cd "$REPO_ROOT"
    echo "Using repo root: $REPO_ROOT"
    SPEC_PATH=${projectYamlFile}
    OUTPUT_ROOT="dependencies/generators/xcodegen/output"
    PROJECT_DIR="$OUTPUT_ROOT/Wawona.xcodeproj"

    if command -v nix >/dev/null 2>&1; then
      FLAKE_REF="."
      if [ -f "crates/Wawona/flake.nix" ]; then
        FLAKE_REF="./crates/Wawona"
      fi
      nix build --no-link "$FLAKE_REF#wawona-macos-backend" "$FLAKE_REF#wawona-ios-backend" "$FLAKE_REF#wawona-ios-sim-backend" "$FLAKE_REF#wawona-ipados-backend" "$FLAKE_REF#wawona-ipados-sim-backend" "$FLAKE_REF#wawona-tvos-backend" "$FLAKE_REF#wawona-tvos-sim-backend" "$FLAKE_REF#wawona-visionos-backend" "$FLAKE_REF#wawona-visionos-sim-backend" "$FLAKE_REF#wawona-watchos-backend" "$FLAKE_REF#wawona-watchos-sim-backend" >/dev/null
    fi

    if [ -d "$PROJECT_DIR" ]; then
      chmod -R u+w "$PROJECT_DIR" 2>/dev/null || true
      rm -rf "$PROJECT_DIR"
    fi
    if [ -d "Wawona.xcodeproj" ]; then
      chmod -R u+w "Wawona.xcodeproj" 2>/dev/null || true
      rm -rf "Wawona.xcodeproj"
    fi

    mkdir -p "$OUTPUT_ROOT"
    # Keep the mutable spec in the current project root so relative source
    # paths (e.g. src/... and Sources/...) resolve against the workspace,
    # not against dependencies/generators/xcodegen/output/.
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
      # Only apply team to iOS-family targets so macOS signing stays untouched.
      TMP_SPEC="$TMP_SPEC" EFFECTIVE_TEAM_ID="$EFFECTIVE_TEAM_ID" ${pkgs.python3}/bin/python3 <<'EOF'
import json
from pathlib import Path
import os

p = Path(os.environ["TMP_SPEC"])
data = json.loads(p.read_text())
team = os.environ.get("EFFECTIVE_TEAM_ID", "").strip()
if team:
    targets = data.setdefault("targets", {})
    for target_name in ("Wawona-iOS", "Wawona-iPadOS", "Wawona-tvOS"):
        target = targets.setdefault(target_name, {})
        base = target.setdefault("settings", {}).setdefault("base", {})
        base["DEVELOPMENT_TEAM"] = team
    p.write_text(json.dumps(data, indent=2))
EOF
      echo "Applied TEAM_ID=$EFFECTIVE_TEAM_ID to Wawona-iOS, Wawona-iPadOS, and Wawona-tvOS."
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
    <key>Wawona-iPadOS.xcscheme_^#shared#^_</key>
    <dict>
      <key>orderHint</key>
      <integer>1</integer>
    </dict>
    <key>Wawona-tvOS.xcscheme_^#shared#^_</key>
    <dict>
      <key>orderHint</key>
      <integer>2</integer>
    </dict>
    <key>Wawona-macOS.xcscheme_^#shared#^_</key>
    <dict>
      <key>orderHint</key>
      <integer>3</integer>
    </dict>
    <key>Wawona-watchOS.xcscheme_^#shared#^_</key>
    <dict>
      <key>orderHint</key>
      <integer>4</integer>
    </dict>
    <key>Wawona-visionOS.xcscheme_^#shared#^_</key>
    <dict>
      <key>orderHint</key>
      <integer>5</integer>
    </dict>
  </dict>
  <key>SuppressBuildableAutocreation</key>
  <dict>
    <key>1772EA6259C5CCC5A46065A5</key>
    <dict>
      <key>primary</key>
      <true/>
    </dict>
    <key>405F5CEFEA830E9D56650D4C</key>
    <dict>
      <key>primary</key>
      <true/>
    </dict>
  </dict>
</dict>
</plist>
EOF

    # Prevent framework-only model targets from showing up as runnable schemes.
    # Xcode can keep stale user schemes in xcuserdata, so clean those and
    # suppress auto-creation for the model target blueprint identifiers.
    ${pkgs.python3}/bin/python3 <<'EOF_PY'
import plistlib
import re
import os
from pathlib import Path

project_root = Path("Wawona.xcodeproj")
pbxproj = project_root / "project.pbxproj"
shared_plist = project_root / "xcshareddata" / "xcschemes" / "xcschememanagement.plist"

target_names = {"WawonaModel"}
target_ids = {}

if pbxproj.exists():
    text = pbxproj.read_text()
    for match in re.finditer(
        r"([A-F0-9]{24}) /\* (WawonaModel) \*/ = \{",
        text,
    ):
        target_id, target_name = match.groups()
        if target_name in target_names:
            target_ids[target_name] = target_id

if shared_plist.exists():
    data = plistlib.loads(shared_plist.read_bytes())
    suppress = data.setdefault("SuppressBuildableAutocreation", {})
    for target_id in target_ids.values():
        suppress[target_id] = {"primary": True}
    shared_plist.write_bytes(plistlib.dumps(data))

# Ensure user-level scheme management exists and suppresses model target
# auto-creation (this is what Xcode uses for local scheme lists).
user_scheme_dirs = list(project_root.glob("xcuserdata/*.xcuserdatad/xcschemes"))
if not user_scheme_dirs:
    fallback_user = os.environ.get("USER", "").strip() or "local"
    user_scheme_dir = project_root / "xcuserdata" / f"{fallback_user}.xcuserdatad" / "xcschemes"
    user_scheme_dir.mkdir(parents=True, exist_ok=True)
    user_scheme_dirs = [user_scheme_dir]

for user_scheme_dir in user_scheme_dirs:
    user_mgmt = user_scheme_dir / "xcschememanagement.plist"
    if user_mgmt.exists():
        user_data = plistlib.loads(user_mgmt.read_bytes())
    else:
        user_data = {}

    # Keep only app schemes in the visible user scheme list.
    user_data["SchemeUserState"] = {
        "Wawona-iOS.xcscheme_^#shared#^_": {"orderHint": 0},
        "Wawona-iPadOS.xcscheme_^#shared#^_": {"orderHint": 1},
        "Wawona-tvOS.xcscheme_^#shared#^_": {"orderHint": 2},
        "Wawona-macOS.xcscheme_^#shared#^_": {"orderHint": 3},
        "Wawona-watchOS.xcscheme_^#shared#^_": {"orderHint": 4},
        "Wawona-visionOS.xcscheme_^#shared#^_": {"orderHint": 5},
    }

    user_suppress = user_data.setdefault("SuppressBuildableAutocreation", {})
    for target_id in target_ids.values():
        user_suppress[target_id] = {"primary": True}

    for model_scheme in ("WawonaModel.xcscheme",):
        scheme_path = user_scheme_dir / model_scheme
        if scheme_path.exists():
            scheme_path.unlink()

    user_mgmt.write_bytes(plistlib.dumps(user_data))
EOF_PY

    if [ -d "Wawona.xcodeproj" ]; then
      rm -rf "$PROJECT_DIR"
      cp -R "Wawona.xcodeproj" "$PROJECT_DIR"
    fi
    echo "Wawona.xcodeproj generated at ./Wawona.xcodeproj (repo root)."
    echo "Mirror copy written to $PROJECT_DIR."
  '';

  # Script to generate AND open project
  openScript = pkgs.writeShellScriptBin "xcodegen-open" ''
    set -e
    find_repo_root() {
      local dir="$PWD"
      while [ "$dir" != "/" ]; do
        if [ -f "$dir/flake.nix" ]; then
          printf '%s\n' "$dir"
          return 0
        fi
        dir="$(dirname "$dir")"
      done
      return 1
    }
    REPO_ROOT="$(find_repo_root || true)"
    if [ -z "$REPO_ROOT" ]; then
      echo "Error: could not locate repo root (missing flake.nix in parent chain)." >&2
      exit 1
    fi
    cd "$REPO_ROOT"
    ${generateScript}/bin/xcodegen
    
    PROJECT_DIR="dependencies/generators/xcodegen/output/Wawona.xcodeproj"
    echo "Opening $PROJECT_DIR..."
    if [ -d "$PROJECT_DIR" ]; then
      open "$PROJECT_DIR"
      echo "Project opened in Xcode."
    else
      echo "Error: $PROJECT_DIR was not generated."
      exit 1
    fi
  '';
in {
  project = projectDrv;
  app = generateScript;
  inherit openScript;
}
