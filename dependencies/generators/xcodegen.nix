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
  macosFastfetch ? null,
  macosNeovim ? null,
  macosZsh ? null,
  macosKmscube ? null,
  # When set (e.g. [ "ios" "ipados" ]), only emit matching app targets (+ shared libs).
  platformFilter ? null,
  applePath,
  westonToytoolkitLdflagsNix,
  westonCompositorLdflagsNix,
  mobileBaseLdflagsNix,
  ilandGlLdflagsNix,
}:

let
  lib = pkgs.lib;
  strip = d: if d == null then "" else toString d;
  # Overridable via `nix build --impure` (Fastlane sets WAWONA_VERSION / WAWONA_BUILD_NUMBER).
  effectiveVersion =
    let
      envV = builtins.getEnv "WAWONA_VERSION";
      base = if wawonaVersion != null && wawonaVersion != "" then wawonaVersion else "0.0.1";
    in if envV != "" then lib.removePrefix "v" envV else base;
  wawonaBuildNumber =
    let
      bn = builtins.getEnv "WAWONA_BUILD_NUMBER";
      gh = builtins.getEnv "GITHUB_RUN_NUMBER";
    in
    if bn != "" then bn
    else if gh != "" then gh
    else "1";
  derivedRustLib = "$(DERIVED_FILE_DIR)/libwawona.a";
  derivedZshLib = "$(DERIVED_FILE_DIR)/libwawona-zsh.a";
  # Prebuild symlinks the active SDK's archives here (see scripts/xcode-prebuild.sh).
  mobileZshLdflags = [ derivedZshLib ];
  # Pin matches weston-compositor-apple-mobile (13.0.0). Do not use pkgs.weston on
  # Darwin — it pulls pipewire and fails eval (valgrind marked broken in nixpkgs).
  westonTerminalPng = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/terminal.png";
    sha256 = "sha256-ZxUcCQYM4kTNof+V5q2VAgKkR51S+YFiAOjrzUGqU7o=";
  };
  westonPatternPng = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/pattern.png";
    sha256 = "sha256-u1hqCRI7CpLaL1dvg1kwJ7lEmtNi/EnwjFxV/h3Hfgk=";
  };
  # Toytoolkit window frame decorations (window_frame_create / frame_create).
  westonIconWindowPng = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/icon_window.png";
    sha256 = "sha256-RrzYR/znpkBhJPDCkinwI5or9NiIgR3FMMF66f+QZ8I=";
  };
  westonSignClosePng = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/sign_close.png";
    sha256 = "sha256-BSBqUQGLP4lnT21VmMwWIPoThJB/Suriq+5xYPd+Vso=";
  };
  westonSignMaximizePng = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/sign_maximize.png";
    sha256 = "sha256-9wt0RB4xsCWCx6QQWUtO4tMPrb5NKlrrvMLFp8gBVDo=";
  };
  westonSignMinimizePng = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/sign_minimize.png";
    sha256 = "sha256-V5m+PYs9sh8kH5MhXQF+jLqWKvMsk+zyscdxEzU+ACc=";
  };
  westonPanelPng = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/panel.png";
    sha256 = "sha256-H7VQl7mklDJz9UMPZJDZ+7FD/Fi9s7X9pMkhl578QX4=";
  };
  westonBackgroundPng = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/background.png";
    sha256 = "sha256-MFxdcpF2/PYgx56bVXexTcC/m/H/KKkVtrN0ZMfd1R8=";
  };
  westonToytoolkitLdflags = deps: import westonToytoolkitLdflagsNix {
    inherit lib deps;
    forceLoadWeston = true;
  };
  # ios.nix already compiles weston-simple-shm into libweston-13.a; skip the
  # standalone libweston_simple_shm.a or the linker sees duplicate symbols.
  westonToytoolkitLdflagsAppleMobile = deps: import westonToytoolkitLdflagsNix {
    inherit lib deps;
    forceLoadWeston = true;
    linkWestonSimpleShm = false;
  };
  westonCompositorLdflags = deps: import westonCompositorLdflagsNix {
    inherit lib deps;
    forceLoadCompositor = true;
  };
  mobileBaseLdflags = deps: import mobileBaseLdflagsNix { inherit lib deps; };
  ilandGlLdflags = { deps, simulator ? false }: import ilandGlLdflagsNix {
    inherit lib deps simulator;
    forceLoad = true;
  };
  pixmanHeaderPaths = deps: lib.optionals (deps ? pixman && deps.pixman != null) [
    "${strip deps.pixman}/include"
    "${strip deps.pixman}/include/pixman-1"
  ];
  ilandGlHeaderPaths = deps: [
    "${strip (deps.iland or null)}/include"
    "${strip (deps.iland or null)}/include/EGL"
    "${strip (deps.iland or null)}/include/GLES2"
    "${strip (deps.angle or null)}/include"
    "${strip (deps.kmscube or deps."iland-gl-clients" or null)}/include"
  ];
  footLdflags = deps:
    let libfoot = "${strip (deps.foot or null)}/lib/libfoot.a";
    in if (deps.foot or null) == null || !builtins.pathExists libfoot then [] else [
      "-force_load" libfoot
    ];
  # fastfetch links its frameworks from the per-platform list emitted by
  # wwn-fastfetch ($out/nix-support/fastfetch-frameworks). This keeps Wawona free
  # of per-platform framework knowledge: watchOS (no Metal/VideoToolbox) linking
  # is driven by the archive it was built against, not hardcoded here.
  fastfetchLdflags = deps:
    let
      ff = deps.fastfetch or null;
      libff = "${strip ff}/lib/libfastfetch.a";
      fwFile = "${strip ff}/nix-support/fastfetch-frameworks";
      frameworks =
        if ff != null && builtins.pathExists fwFile
        then lib.filter (s: s != "") (lib.splitString "\n" (builtins.readFile fwFile))
        else [ "CoreFoundation" "Foundation" ];
      frameworkFlags = lib.concatMap (f: [ "-framework" f ]) frameworks;
    in if ff == null || !builtins.pathExists libff then [] else
      [ "-force_load" libff ] ++ frameworkFlags;
  neovimLdflags = deps:
    let libnvim = "${strip (deps.neovim or null)}/lib/libwawona-neovim.a";
    in if (deps.neovim or null) == null || !builtins.pathExists libnvim then [] else [
      "-force_load" libnvim
    ];
  # Static archives with C++ (ANGLE, Rust backend, fastfetch, …) need libc++
  # after every -force_load block; append once at the end of OTHER_LDFLAGS.
  finalCxxLdflags = [ "-lc++" "-lc++abi" "-ldl" "-framework" "IOKit" ];
  # iOS 26+ UIKit/SwiftUI modules embed LC_LINKER_OPTION auto-link entries for
  # header-only UIUtilities and private SwiftUICore. Failed autolink breaks -lc++.
  ios26ObjcAutolinkOff = [ "-fno-autolink" ];
  ios26SwiftAutolinkOff = [
    "-Xfrontend" "-disable-autolink-framework" "-Xfrontend" "UIUtilities"
    "-Xfrontend" "-disable-autolink-framework" "-Xfrontend" "SwiftUICore"
  ];
  ios26SwiftLibSearchPaths = [ "$(inherited)" "$(SDKROOT)/usr/lib/swift" ];
  # Link as SwiftUI client so SwiftUICore.tbd allowable_clients accepts autolink.
  ios26SwiftUiClientLdflags = [ ];
  # weston_simple_shm_main lives here; os-compatibility.c is omitted from this
  # archive because libweston-13.a already provides those symbols on iOS-family targets.
  westonSimpleShmLdflags = deps:
    let archive = "${strip (deps.weston-simple-shm or null)}/lib/libweston_simple_shm.a";
    in if (deps.weston-simple-shm or null) == null || !builtins.pathExists archive then [] else [
      "-force_load" archive
    ];
  xkbIosEmbedScript = pkgs.writeShellScript "embed-xkb-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|iphonesimulator|appletvos|appletvsimulator)
        ;;
      *)
        exit 0
        ;;
    esac
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/share/X11/xkb"
    mkdir -p "$DEST"
    cp -R "${pkgs.xkeyboard_config}/share/X11/xkb/." "$DEST/"
    echo "Embedded xkeyboard-config into $DEST"
  '';
  # Bundle TrueType fonts so the in-process weston toytoolkit clients
  # (weston-desktop-shell panel/clock, weston-terminal) have something for
  # Cairo/Pango/fontconfig to match. Without any font, desktop-shell aborts
  # during init and the nested compositor shows only a solid clear color.
  fontIosEmbedScript = pkgs.writeShellScript "embed-fonts-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|iphonesimulator|appletvos|appletvsimulator)
        ;;
      *)
        exit 0
        ;;
    esac
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/share/fonts"
    mkdir -p "$DEST"
    # Nix store font paths are often symlinks; iOS installd rejects symlinks in .app
    # bundles (MIInstallerErrorDomain Code 70). -L dereferences to real files.
    cp -RL "${pkgs.dejavu_fonts}/share/fonts/." "$DEST/"
    echo "Embedded DejaVu fonts into $DEST"
  '';
  xcodeUtils = import applePath { inherit lib pkgs TEAM_ID; };

  # Dependency version strings (must match tags/versions in wwn-toolchain / wwn-* libs)
  depVersions = {
    wayland   = "1.23.0";
    xkbcommon = "1.7.0";
    lz4       = "1.10.0";
    zstd      = "1.5.7";
    libffi    = "3.5.2";
    sshpass   = "1.10";
    waypipe   = "0.11.0";
  };

  # Build escaped preprocessor definitions for Xcode (string macros need escaped quotes)
  versionDefs = [
    "WAWONA_VERSION=\\\"${effectiveVersion}\\\""
    "WAWONA_WAYLAND_VERSION=\\\"${depVersions.wayland}\\\""
    "WAWONA_XKBCOMMON_VERSION=\\\"${depVersions.xkbcommon}\\\""
    "WAWONA_LZ4_VERSION=\\\"${depVersions.lz4}\\\""
    "WAWONA_ZSTD_VERSION=\\\"${depVersions.zstd}\\\""
    "WAWONA_LIBFFI_VERSION=\\\"${depVersions.libffi}\\\""
    "WAWONA_SSHPASS_VERSION=\\\"${depVersions.sshpass}\\\""
    "WAWONA_WAYPIPE_VERSION=\\\"${depVersions.waypipe}\\\""
  ];

  # Target-scoped pre-build: only realize the Rust backend(s) for the active Xcode
  # target, with input/output paths so Xcode skips the script on incremental builds.
  libwawonaOutputPaths = { withZsh ? false }:
    [ derivedRustLib ]
    ++ lib.optionals withZsh [ derivedZshLib ];

  nixPreBuildInputs = [
    "$(SRCROOT)/Cargo.lock"
    "$(SRCROOT)/flake.nix"
    "$(SRCROOT)/Cargo.toml"
  ];

  mkPreBuildPhase = { withZsh ? false }: {
    name = "Build Rust Backend via Nix";
    basedOnDependencyAnalysis = false;
    alwaysOutOfDate = true;
    inputFiles = nixPreBuildInputs ++ [ "$(SRCROOT)/scripts/xcode-prebuild.sh" ];
    outputFiles = libwawonaOutputPaths { inherit withZsh; };
    script = ''
      exec "''${SRCROOT}/scripts/xcode-prebuild.sh"
    '';
  };

  iosPreBuild = mkPreBuildPhase { withZsh = true; };

  ipadosPreBuild = mkPreBuildPhase { withZsh = true; };

  tvosPreBuild = mkPreBuildPhase { };

  macosPreBuild = mkPreBuildPhase { };

  visionosPreBuild = mkPreBuildPhase { };

  watchosPreBuild = mkPreBuildPhase { };

  # Runs before Nix prebuild; writes $(SRCROOT)/.build/wwn-build-number.xcconfig so
  # every Xcode build gets a fresh CURRENT_PROJECT_VERSION (timestamp locally, CI run id).
  stampBuildNumberPhase = {
    name = "Stamp Build Number";
    basedOnDependencyAnalysis = false;
    alwaysOutOfDate = true;
    inputFiles = [ "$(SRCROOT)/scripts/xcode-stamp-build-number.sh" ];
    outputFiles = [
      "$(SRCROOT)/.build/wwn-build-number.xcconfig"
      "$(DERIVED_FILE_DIR)/wwn-build-number.xcconfig"
    ];
    script = ''
      exec "''${SRCROOT}/scripts/xcode-stamp-build-number.sh"
    '';
  };

  # Scheme pre-actions run before build settings resolve; use ${SRCROOT} (shell
  # var), not $(SRCROOT) (command substitution — breaks with "SRCROOT: not found").
  stampPreActionScript = ''"''${SRCROOT}/scripts/xcode-stamp-build-number.sh"
'';

  mkAppScheme = targetName: {
    build = {
      targets = { "${targetName}" = "all"; };
      preActions = [
        {
          name = "Stamp Build Number";
          script = stampPreActionScript;
          settingsTarget = targetName;
        }
      ];
    };
  };

  appSchemeNames = [
    "Wawona-iOS"
    "Wawona-iPadOS"
    "Wawona-tvOS"
    "Wawona-macOS"
    "Wawona-watchOS"
    "Wawona-visionOS"
  ];

  schemesConfig = lib.genAttrs appSchemeNames mkAppScheme;

  # Shared helper for iOS-family application targets (iOS, iPadOS, tvOS).
  mkAppleMobileTarget =
    {
      name,
      xcodePlatform,
      filterKey,
      bundleId,
      deviceFamily ? "1",
      deps,
      simDeps,
      backend,
      simBackend,
      backendAttr,
      simBackendAttr,
      preBuild,
      postBuild ? [],
      sources,
      deviceSdk,
      simSdk,
      appIconName ? "AppIcon",
      extraDeviceLdflags ? [],
      extraSimLdflags ? [],
      extraDefines ? [],
      extraHeaderPaths ? [],
      bridgingHeader ? "src/platform/macos/WWN-Bridging-Header.h",
    }:
    {
      type = "application";
      platform = xcodePlatform;
      inherit sources;
      preBuildScripts = [ stampBuildNumberPhase preBuild ];
      postBuildScripts = postBuild;
      settings = {
        base = {
          INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
          GENERATE_INFOPLIST_FILE = "NO";
          PRODUCT_BUNDLE_IDENTIFIER = bundleId;
          ASSETCATALOG_COMPILER_APPICON_NAME = appIconName;
          ENABLE_ON_DEMAND_RESOURCES = "NO";
          CODE_SIGN_STYLE = "Automatic";
          ENABLE_DEBUG_DYLIB = "NO";
          CODE_SIGNING_ALLOWED = "YES";
          CODE_SIGNING_REQUIRED = "YES";
          "CODE_SIGNING_ALLOWED[sdk=${simSdk}*]" = "NO";
          "CODE_SIGNING_REQUIRED[sdk=${simSdk}*]" = "NO";
          "VALID_ARCHS[sdk=${simSdk}*]" = "arm64";
          "ARCHS[sdk=${simSdk}*]" = "arm64";
          "ONLY_ACTIVE_ARCH" = "YES";
          LD_RUNPATH_SEARCH_PATHS = [ "$(inherited)" "@executable_path/Frameworks" ];
          LD_CLIENT_NAME = "SwiftUI";
          "OTHER_CFLAGS[sdk=${deviceSdk}*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
          "OTHER_CFLAGS[sdk=${simSdk}*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
          "OTHER_SWIFT_FLAGS[sdk=${deviceSdk}*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
          "OTHER_SWIFT_FLAGS[sdk=${simSdk}*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
          "LIBRARY_SEARCH_PATHS[sdk=${deviceSdk}*]" = ios26SwiftLibSearchPaths;
          "LIBRARY_SEARCH_PATHS[sdk=${simSdk}*]" = ios26SwiftLibSearchPaths;
          "OTHER_LDFLAGS[sdk=${deviceSdk}*]" = [
            "$(inherited)"
          ] ++ ios26SwiftUiClientLdflags ++ [
            "-L${strip (deps.libwayland or null)}/lib"
            "-L${strip (deps.xkbcommon or null)}/lib"
            "-L${strip (deps.libffi or null)}/lib"
            "-L${strip (deps.pixman or null)}/lib"
            "-L${strip (deps.zstd or null)}/lib"
            "-L${strip (deps.lz4 or null)}/lib"
            "-L${strip (deps.epoll-shim or null)}/lib"
            "-lxkbcommon"
            "-lwayland-client"
            "-lffi"
            "-lpixman-1"
            "-lzstd"
            "-llz4"
            "-lepoll-shim"
          ] ++ (mobileBaseLdflags deps) ++ westonToytoolkitLdflagsAppleMobile deps ++ westonCompositorLdflags deps
          ++ (ilandGlLdflags { inherit deps; simulator = false; }) ++ footLdflags deps ++ fastfetchLdflags deps ++ neovimLdflags deps ++ extraDeviceLdflags
          ++ mobileZshLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
          "OTHER_LDFLAGS[sdk=${simSdk}*]" = [
            "$(inherited)"
          ] ++ ios26SwiftUiClientLdflags ++ [
            "-L${strip (simDeps.libwayland or null)}/lib"
            "-L${strip (simDeps.xkbcommon or null)}/lib"
            "-L${strip (simDeps.libffi or null)}/lib"
            "-L${strip (simDeps.pixman or null)}/lib"
            "-L${strip (simDeps.zstd or null)}/lib"
            "-L${strip (simDeps.lz4 or null)}/lib"
            "-L${strip (simDeps.epoll-shim or null)}/lib"
            "-lxkbcommon"
            "-lwayland-client"
            "-lffi"
            "-lpixman-1"
            "-lzstd"
            "-llz4"
            "-lepoll-shim"
          ] ++ (mobileBaseLdflags simDeps) ++ westonToytoolkitLdflagsAppleMobile simDeps ++ westonCompositorLdflags simDeps
          ++ (ilandGlLdflags { deps = simDeps; simulator = true; }) ++ footLdflags simDeps ++ fastfetchLdflags simDeps ++ neovimLdflags simDeps ++ extraSimLdflags
          ++ mobileZshLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
          GCC_PREPROCESSOR_DEFINITIONS = [ "$(inherited)" ] ++ extraDefines ++ versionDefs;
        };
      };
    };

  xkbEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/X11/xkb/rules/evdev"
  ];

  xkbEmbedPhase = {
    path = xkbIosEmbedScript;
    name = "Embed xkeyboard-config";
    basedOnDependencyAnalysis = true;
    outputFiles = xkbEmbedOutputs;
  };

  fontEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/fonts/truetype/DejaVuSans.ttf"
  ];

  fontEmbedPhase = {
    path = fontIosEmbedScript;
    name = "Embed fonts (fontconfig)";
    basedOnDependencyAnalysis = true;
    outputFiles = fontEmbedOutputs;
  };

  angleDylibDeps = deps:
    let a = deps.angle or null;
    in if a != null
         && builtins.pathExists (toString a + "/nix-support/link-kind")
         && lib.strings.trim (builtins.readFile (toString a + "/nix-support/link-kind")) == "dylib"
       then a
       else null;

  angleSimDylib = angleDylibDeps iosSimDeps;
  angleDeviceDylib = angleDylibDeps iosDeps;

  angleEmbedScript = anglePkg: pkgs.writeShellScript "embed-angle-dylibs.sh" ''
    DEST="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME/Frameworks"
    EGL_SRC="${strip anglePkg}/lib/libEGL.dylib"
    GLES_SRC="${strip anglePkg}/lib/libGLESv2.dylib"
    # Prebuilt XCFramework slices use LC_ID_DYLIB @rpath/libEGL.framework/libEGL.
    write_fw_plist() {
      local fw="$1" exe="$2"
      cat > "$DEST/$fw.framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$exe</string>
  <key>CFBundleIdentifier</key><string>org.khronos.$exe</string>
  <key>CFBundleName</key><string>$exe</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
    }
    mkdir -p "$DEST/libEGL.framework" "$DEST/libGLESv2.framework"
    cp -f "$EGL_SRC" "$DEST/libEGL.framework/libEGL"
    cp -f "$GLES_SRC" "$DEST/libGLESv2.framework/libGLESv2"
    write_fw_plist libEGL libEGL
    write_fw_plist libGLESv2 libGLESv2
    # iland dlopen also probes flat @executable_path/Frameworks/lib*.dylib.
    cp -f "$EGL_SRC" "$DEST/libEGL.dylib"
    cp -f "$GLES_SRC" "$DEST/libGLESv2.dylib"
    if [ -n "''${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "''${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
      for lib in \
        "$DEST/libEGL.framework/libEGL" \
        "$DEST/libGLESv2.framework/libGLESv2" \
        "$DEST/libEGL.dylib" \
        "$DEST/libGLESv2.dylib"; do
        /usr/bin/codesign --force --sign "''${EXPANDED_CODE_SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements,flags "$lib"
      done
    fi
    echo "Embedded ANGLE dylibs (framework + flat) into $DEST"
  '';

  angleSimEmbedScript =
    if angleSimDylib != null then angleEmbedScript angleSimDylib
    else pkgs.writeShellScript "embed-angle-sim-dylibs-noop.sh" "exit 0";
  angleDeviceEmbedScript =
    if angleDeviceDylib != null then angleEmbedScript angleDeviceDylib
    else pkgs.writeShellScript "embed-angle-device-dylibs-noop.sh" "exit 0";

  angleSimEmbedPhase = {
    path = angleSimEmbedScript;
    name = "Embed ANGLE (Simulator dylibs)";
    basedOnDependencyAnalysis = false;
  };

  angleDeviceEmbedPhase = {
    path = angleDeviceEmbedScript;
    name = "Embed ANGLE (Device dylibs)";
    basedOnDependencyAnalysis = false;
  };

  iosPostBuildPhases = [ xkbEmbedPhase fontEmbedPhase westonDataEmbedPhase iosRootfsEmbedPhase iosNeovimRootfsEmbedPhase ]
    ++ lib.optionals (angleSimDylib != null) [ angleSimEmbedPhase ]
    ++ lib.optionals (angleDeviceDylib != null) [ angleDeviceEmbedPhase ];

  westonDataIosEmbedScript = pkgs.writeShellScript "embed-weston-data-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|iphonesimulator|appletvos|appletvsimulator)
        ;;
      *)
        exit 0
        ;;
    esac
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    WESTON_DEST="$BUNDLE/share/weston"
    ICONS_DEST="$BUNDLE/share/icons/Adwaita/cursors"
    mkdir -p "$WESTON_DEST" "$ICONS_DEST"
    TERMINAL_SRC="${westonTerminalPng}"
    if [ -f "$TERMINAL_SRC" ]; then
      cp -L "$TERMINAL_SRC" "$WESTON_DEST/terminal.png"
      echo "Embedded weston terminal.png into $WESTON_DEST"
    else
      echo "warning: weston terminal.png not found at $TERMINAL_SRC" >&2
    fi
    PATTERN_SRC="${westonPatternPng}"
    if [ -f "$PATTERN_SRC" ]; then
      cp -L "$PATTERN_SRC" "$WESTON_DEST/pattern.png"
      echo "Embedded weston pattern.png into $WESTON_DEST"
    else
      echo "warning: weston pattern.png not found at $PATTERN_SRC" >&2
    fi
    for pair in \
      "${westonIconWindowPng}:icon_window.png" \
      "${westonSignClosePng}:sign_close.png" \
      "${westonSignMaximizePng}:sign_maximize.png" \
      "${westonSignMinimizePng}:sign_minimize.png" \
      "${westonPanelPng}:panel.png" \
      "${westonBackgroundPng}:background.png"; do
      SRC="''${pair%%:*}"
      NAME="''${pair##*:}"
      if [ -f "$SRC" ]; then
        cp -L "$SRC" "$WESTON_DEST/$NAME"
        echo "Embedded weston $NAME into $WESTON_DEST"
      else
        echo "warning: weston $NAME not found at $SRC" >&2
      fi
    done
    CURSOR_SRC="${pkgs.adwaita-icon-theme}/share/icons/Adwaita/cursors"
    if [ -d "$CURSOR_SRC" ]; then
      cp -RL "$CURSOR_SRC/." "$ICONS_DEST/"
      echo "Embedded Adwaita cursors into $ICONS_DEST"
    else
      echo "warning: Adwaita cursors not found at $CURSOR_SRC" >&2
    fi
  '';

  westonDataEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/weston/terminal.png"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/weston/pattern.png"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/weston/icon_window.png"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/weston/sign_close.png"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/weston/sign_maximize.png"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/weston/sign_minimize.png"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/weston/panel.png"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/weston/background.png"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/icons/Adwaita/cursors/default"
  ];

  westonDataEmbedPhase = {
    path = westonDataIosEmbedScript;
    name = "Embed Weston data (icons, cursors)";
    basedOnDependencyAnalysis = true;
    outputFiles = westonDataEmbedOutputs;
  };

  rootfsIosEmbedScript = deviceRootfs: simRootfs: pkgs.writeShellScript "embed-rootfs-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos)
        rootfsSrc="${strip deviceRootfs}/rootfs"
        ;;
      iphonesimulator)
        rootfsSrc="${strip simRootfs}/rootfs"
        ;;
      *)
        exit 0
        ;;
    esac
    if [ ! -d "$rootfsSrc" ]; then
      echo "warning: wawona-rootfs not built for this platform" >&2
      exit 0
    fi
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/wawona-rootfs"
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -R "$rootfsSrc/." "$DEST/"
    echo "Embedded wawona-rootfs into $DEST (template $(cat "$DEST/etc/zsh/.template-version" 2>/dev/null || echo unknown))"
  '';

  rootfsEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/wawona-rootfs/etc/zsh/zshrc.template"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/wawona-rootfs/etc/zsh/.template-version"
  ];

  iosRootfsEmbedPhase = {
    path = rootfsIosEmbedScript (iosDeps."wawona-rootfs" or null) (iosSimDeps."wawona-rootfs" or null);
    name = "Embed wawona-rootfs (shell templates)";
    basedOnDependencyAnalysis = true;
    outputFiles = rootfsEmbedOutputs;
  };

  ipadosRootfsEmbedPhase = {
    path = rootfsIosEmbedScript (ipadosDeps."wawona-rootfs" or null) (ipadosSimDeps."wawona-rootfs" or null);
    name = "Embed wawona-rootfs (shell templates)";
    basedOnDependencyAnalysis = true;
    outputFiles = rootfsEmbedOutputs;
  };

  neovimRootfsIosEmbedScript = deviceRootfs: simRootfs: pkgs.writeShellScript "embed-neovim-rootfs-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos)
        rootfsSrc="${strip deviceRootfs}/rootfs"
        ;;
      iphonesimulator)
        rootfsSrc="${strip simRootfs}/rootfs"
        ;;
      *)
        exit 0
        ;;
    esac
    if [ ! -d "$rootfsSrc" ]; then
      echo "warning: neovim-rootfs not built for this platform" >&2
      exit 0
    fi
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/neovim-rootfs"
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -R "$rootfsSrc/." "$DEST/"
    echo "Embedded neovim-rootfs into $DEST"
  '';

  neovimRootfsEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/neovim-rootfs/etc/nvim/init.lua.template"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/neovim-rootfs/usr/share/nvim/runtime"
  ];

  iosNeovimRootfsEmbedPhase = {
    path = neovimRootfsIosEmbedScript (iosDeps."neovim-rootfs" or null) (iosSimDeps."neovim-rootfs" or null);
    name = "Embed neovim-rootfs (runtime templates)";
    basedOnDependencyAnalysis = true;
    outputFiles = neovimRootfsEmbedOutputs;
  };

  ipadosNeovimRootfsEmbedPhase = {
    path = neovimRootfsIosEmbedScript (ipadosDeps."neovim-rootfs" or null) (ipadosSimDeps."neovim-rootfs" or null);
    name = "Embed neovim-rootfs (runtime templates)";
    basedOnDependencyAnalysis = true;
    outputFiles = neovimRootfsEmbedOutputs;
  };

  # src/core is entirely Rust (0 C/ObjC files) — excluded entirely
  # src/stubs depend on system headers (wayland, vulkan) that are only
  # available from the Nix build environment, so they stay out of Xcode.
  # The Xcode build compiles only the platform ObjC layer and links libwawona.a
  commonExcludes = ["**/*.rs" "**/*.toml" "**/*.md" "**/Cargo.lock" "**/.DS_Store" "**/renderer_android.*" "**/WWNSettings.c" "**/Skip/**"];
  # Mobile targets ship src/platform/ios/WWNIlandPresenter.*; omit macOS copies.
  mobileMacPlatformExcludes = commonExcludes ++ [
    "WWNIlandPresenter.m"
    "WWNIlandPresenter.h"
  ];

  # Xcode “Update to recommended settings” for framework targets with Swift/ObjC clients.
  moduleVerifierFrameworkSettings = {
    ENABLE_MODULE_VERIFIER = "YES";
    MODULE_VERIFIER_SUPPORTED_LANGUAGES = "objective-c objective-c++";
    MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS = "gnu11 gnu++14";
  };

  projectConfig = {
    name = "Wawona";
    configFiles = {
      Debug = "src/resources/xcode/wwn-version.xcconfig";
      Release = "src/resources/xcode/wwn-version.xcconfig";
    };
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
        MARKETING_VERSION = effectiveVersion;
        CODE_SIGN_STYLE = "Automatic";
        SWIFT_VERSION = "5.0";
        SWIFT_OBJC_BRIDGING_HEADER = "src/platform/macos/WWN-Bridging-Header.h";
        CLANG_ENABLE_MODULES = "YES";
        CLANG_ENABLE_OBJC_ARC = "YES";
        DEAD_CODE_STRIPPING = "YES";
        STRING_CATALOG_GENERATE_SYMBOLS = "YES";
        ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS = "YES";
        ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = "YES";
        ENABLE_BITCODE = "NO";
        # Xcode 15+ default enables script sandbox; breaks swift-plugin-server / macros under some builds (sandbox_apply EPERM).
        ENABLE_USER_SCRIPT_SANDBOXING = "NO";
        # Avoid Metal.xctoolchain shadowing Swift/stdlib search paths on Xcode 26+ CI.
        TOOLCHAINS = "com.apple.dt.toolchain.XcodeDefault";
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
      configs = {
        Debug = {
          STRING_CATALOG_GENERATE_SYMBOLS = "NO";
        };
      };
    };
    targets = {
      Wawona-iOS = {
        type = "application";
        platform = "iOS";
        sources = [
          {
            path = "src/platform/macos";
            excludes = mobileMacPlatformExcludes ++ [
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
        preBuildScripts = [ stampBuildNumberPhase iosPreBuild ];
        postBuildScripts = iosPostBuildPhases;

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
            CODE_SIGNING_ALLOWED = "YES";
            CODE_SIGNING_REQUIRED = "YES";
            "CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = "NO";
            "CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = "NO";
            "VALID_ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ONLY_ACTIVE_ARCH" = "YES";
            LD_RUNPATH_SEARCH_PATHS = [ "$(inherited)" "@executable_path/Frameworks" ];
            LD_CLIENT_NAME = "SwiftUI";
            "OTHER_CFLAGS[sdk=iphoneos*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_CFLAGS[sdk=iphonesimulator*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=iphoneos*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=iphonesimulator*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "LIBRARY_SEARCH_PATHS[sdk=iphoneos*]" = ios26SwiftLibSearchPaths;
            "LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]" = ios26SwiftLibSearchPaths;
            # Do not add SubFrameworks (UIUtilities / SwiftUICore) — same as tvOS.
            "OTHER_LDFLAGS[sdk=iphoneos*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
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
             ] ++ westonToytoolkitLdflagsAppleMobile iosDeps ++ westonCompositorLdflags iosDeps
             ++ (ilandGlLdflags { deps = iosDeps; simulator = false; }) ++ footLdflags iosDeps ++ fastfetchLdflags iosDeps ++ neovimLdflags iosDeps
             ++ mobileZshLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
            "OTHER_LDFLAGS[sdk=iphonesimulator*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
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
             ] ++ westonToytoolkitLdflagsAppleMobile iosSimDeps ++ westonCompositorLdflags iosSimDeps
             ++ (ilandGlLdflags { deps = iosSimDeps; simulator = true; }) ++ footLdflags iosSimDeps ++ fastfetchLdflags iosSimDeps ++ neovimLdflags iosSimDeps
             ++ mobileZshLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
            ] ++ (pixmanHeaderPaths iosDeps) ++ (ilandGlHeaderPaths iosDeps);
            "HEADER_SEARCH_PATHS[sdk=iphonesimulator*]" = [
              "$(inherited)"
              "${strip (iosSimDeps.libwayland or null)}/include"
              "${strip (iosSimDeps.libwayland or null)}/include/wayland"
              "${strip (iosSimDeps.xkbcommon or null)}/include"
              "${strip (iosSimDeps.libssh2 or null)}/include"
            ] ++ (pixmanHeaderPaths iosSimDeps) ++ (ilandGlHeaderPaths iosSimDeps);
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
          { sdk = "Accelerate.framework"; }
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
            excludes = mobileMacPlatformExcludes ++ [
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
        preBuildScripts = [ stampBuildNumberPhase ipadosPreBuild ];
        postBuildScripts = [ xkbEmbedPhase fontEmbedPhase westonDataEmbedPhase ipadosRootfsEmbedPhase ipadosNeovimRootfsEmbedPhase ];

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
            CODE_SIGNING_ALLOWED = "YES";
            CODE_SIGNING_REQUIRED = "YES";
            "CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = "NO";
            "CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = "NO";
            "VALID_ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ONLY_ACTIVE_ARCH" = "YES";
            LD_RUNPATH_SEARCH_PATHS = [ "$(inherited)" "@executable_path/Frameworks" ];
            "OTHER_CFLAGS[sdk=iphoneos*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_CFLAGS[sdk=iphonesimulator*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=iphoneos*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=iphonesimulator*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "LIBRARY_SEARCH_PATHS[sdk=iphoneos*]" = ios26SwiftLibSearchPaths;
            "LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]" = ios26SwiftLibSearchPaths;
            # Do not add SubFrameworks (UIUtilities / SwiftUICore) — same as tvOS.
            "OTHER_LDFLAGS[sdk=iphoneos*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
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
            ] ++ westonToytoolkitLdflagsAppleMobile ipadosDeps ++ westonCompositorLdflags ipadosDeps
            ++ (ilandGlLdflags { deps = ipadosDeps; simulator = false; }) ++ footLdflags ipadosDeps ++ fastfetchLdflags ipadosDeps ++ neovimLdflags ipadosDeps
            ++ mobileZshLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
            "OTHER_LDFLAGS[sdk=iphonesimulator*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
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
            ] ++ westonToytoolkitLdflagsAppleMobile ipadosSimDeps ++ westonCompositorLdflags ipadosSimDeps
            ++ (ilandGlLdflags { deps = ipadosSimDeps; simulator = true; }) ++ footLdflags ipadosSimDeps ++ fastfetchLdflags ipadosSimDeps ++ neovimLdflags ipadosSimDeps
            ++ mobileZshLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
            ] ++ (pixmanHeaderPaths ipadosDeps) ++ (ilandGlHeaderPaths ipadosDeps);
            "HEADER_SEARCH_PATHS[sdk=iphonesimulator*]" = [
              "$(inherited)"
              "${strip (ipadosSimDeps.libwayland or null)}/include"
              "${strip (ipadosSimDeps.libwayland or null)}/include/wayland"
              "${strip (ipadosSimDeps.xkbcommon or null)}/include"
              "${strip (ipadosSimDeps.libssh2 or null)}/include"
            ] ++ (pixmanHeaderPaths ipadosSimDeps) ++ (ilandGlHeaderPaths ipadosSimDeps);
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
          { sdk = "Accelerate.framework"; }
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
            excludes = mobileMacPlatformExcludes ++ [
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
        preBuildScripts = [ stampBuildNumberPhase tvosPreBuild ];

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
            "OTHER_CFLAGS[sdk=appletvos*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_CFLAGS[sdk=appletvsimulator*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=appletvos*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=appletvsimulator*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "LIBRARY_SEARCH_PATHS[sdk=appletvos*]" = ios26SwiftLibSearchPaths;
            "LIBRARY_SEARCH_PATHS[sdk=appletvsimulator*]" = ios26SwiftLibSearchPaths;
            # Do not add $(SDKROOT)/System/Library/SubFrameworks on tvOS: it makes
            # the linker pick up UIUtilities / SwiftUICore as direct deps, which
            # tvOS app targets are not allowed to link.
            "OTHER_LDFLAGS[sdk=appletvos*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
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
            ] ++ westonToytoolkitLdflagsAppleMobile tvosDeps ++ westonCompositorLdflags tvosDeps ++ footLdflags tvosDeps ++ fastfetchLdflags tvosDeps ++ neovimLdflags tvosDeps ++ [ derivedRustLib ] ++ finalCxxLdflags;
            "OTHER_LDFLAGS[sdk=appletvsimulator*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
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
            ] ++ westonToytoolkitLdflagsAppleMobile tvosSimDeps ++ westonCompositorLdflags tvosSimDeps ++ footLdflags tvosSimDeps ++ fastfetchLdflags tvosSimDeps ++ neovimLdflags tvosSimDeps ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
            ] ++ (pixmanHeaderPaths tvosDeps);
            "HEADER_SEARCH_PATHS[sdk=appletvsimulator*]" = [
              "$(inherited)"
              "${strip (tvosSimDeps.libwayland or null)}/include"
              "${strip (tvosSimDeps.libwayland or null)}/include/wayland"
              "${strip (tvosSimDeps.xkbcommon or null)}/include"
              "${strip (tvosSimDeps.libssh2 or null)}/include"
            ] ++ (pixmanHeaderPaths tvosSimDeps);
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
          { sdk = "Accelerate.framework"; }
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
          { path = "src/platform/macos/WWNIlandPresenter.m"; type = "file"; }
          { path = "src/platform/macos/ui"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
          { path = "src/resources/macos"; type = "folder"; }
        ];
        preBuildScripts = [ stampBuildNumberPhase macosPreBuild ];
        postBuildScripts = [
          {
            name = "Bundle Executables";
            basedOnDependencyAnalysis = false;
            script = ''
              WAYPIPE_SRC="${strip (macosDeps.waypipe or null)}/bin/waypipe"
              SSHPASS_SRC="${strip (macosDeps.sshpass or null)}/bin/sshpass"
              WESTON_SRC="${strip macosWeston}/bin"
              FOOT_BIN="${strip macosFoot}/bin"
              FASTFETCH_BIN="${strip macosFastfetch}/bin"
              NEOVIM_BIN="${strip macosNeovim}/bin"
              ZSH_BIN="${strip macosZsh}/bin"
              KMSCUBE_BIN="${strip macosKmscube}/bin"

              bundle_bin() {
                src="$1"
                name="$2"
                if [ -f "$src" ]; then
                  install -m 755 "$src" "$BIN_DEST/$name"
                  install -m 755 "$src" "$MACOS_DEST/$name"
                  echo "Bundled $name"
                fi
              }

              BIN_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/bin"
              MACOS_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/MacOS"
              mkdir -p "$BIN_DEST"
              mkdir -p "$MACOS_DEST"

              bundle_bin "$WAYPIPE_SRC" "waypipe"
              bundle_bin "$SSHPASS_SRC" "sshpass"

              if [ -d "$WESTON_SRC" ]; then
                for client in "$WESTON_SRC"/weston*; do
                  [ -f "$client" ] || continue
                  case "$client" in *.so|*.dylib) continue ;; esac
                  bundle_bin "$client" "$(basename "$client")"
                done
              fi

              bundle_bin "$FOOT_BIN/foot" "foot"
              if [ -f "$FOOT_BIN/.foot-wrapped" ]; then
                bundle_bin "$FOOT_BIN/.foot-wrapped" ".foot-wrapped"
              fi
              bundle_bin "$FASTFETCH_BIN/fastfetch" "fastfetch"
              bundle_bin "$NEOVIM_BIN/nvim" "nvim"
              bundle_bin "$NEOVIM_BIN/nvim" "vi"
              bundle_bin "$NEOVIM_BIN/nvim" "vim"
              bundle_bin "$ZSH_BIN/zsh" "zsh"
              bundle_bin "$KMSCUBE_BIN/kmscube" "kmscube"
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
            ] ++ (pixmanHeaderPaths macosDeps) ++ (ilandGlHeaderPaths macosDeps);
            OTHER_LDFLAGS = [
              "$(inherited)"
              "-L${strip (macosDeps.libwayland or null)}/lib"
              "-L${strip (macosDeps.xkbcommon or null)}/lib"
              "-L${strip (macosDeps.pixman or null)}/lib"
              "-L${pkgs.openssl.out}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lwayland-server"
              "-lpixman-1"
              "-lssl"
              "-lcrypto"
              "-lz"
              derivedRustLib
            ] ++ (ilandGlLdflags { deps = macosDeps; simulator = false; })
              ++ (westonToytoolkitLdflags macosDeps)
              ++ (westonCompositorLdflags macosDeps)
              ++ finalCxxLdflags;
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
          { sdk = "Accelerate.framework"; }
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
            excludes = mobileMacPlatformExcludes ++ [
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
        preBuildScripts = [ stampBuildNumberPhase visionosPreBuild ];
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
            LD_CLIENT_NAME = "SwiftUI";
            "OTHER_CFLAGS[sdk=xros*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_CFLAGS[sdk=xrsimulator*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=xros*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=xrsimulator*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "LIBRARY_SEARCH_PATHS[sdk=xros*]" = ios26SwiftLibSearchPaths;
            "LIBRARY_SEARCH_PATHS[sdk=xrsimulator*]" = ios26SwiftLibSearchPaths;
            "FRAMEWORK_SEARCH_PATHS[sdk=xros*]" = [
              "$(inherited)"
            ];
            "FRAMEWORK_SEARCH_PATHS[sdk=xrsimulator*]" = [
              "$(inherited)"
            ];
            "OTHER_LDFLAGS[sdk=xros*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
              "-L${strip (visionosDeps.libwayland or null)}/lib"
              "-L${strip (visionosDeps.xkbcommon or null)}/lib"
              "-L${strip (visionosDeps.libffi or null)}/lib"
              "-L${strip (visionosDeps.pixman or null)}/lib"
              "-L${strip (visionosDeps.epoll-shim or null)}/lib"
              "-L${strip (visionosDeps.libssh2 or null)}/lib"
              "-L${strip (visionosDeps.openssl or null)}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lffi"
              "-lpixman-1"
              "-lepoll-shim"
              "-lssh2"
              "-lssl"
              "-lcrypto"
            ] ++ westonToytoolkitLdflagsAppleMobile visionosDeps ++ westonCompositorLdflags visionosDeps ++ fastfetchLdflags visionosDeps ++ neovimLdflags visionosDeps ++ [ derivedRustLib ] ++ finalCxxLdflags;
            "OTHER_LDFLAGS[sdk=xrsimulator*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
              "-L${strip (visionosSimDeps.libwayland or null)}/lib"
              "-L${strip (visionosSimDeps.xkbcommon or null)}/lib"
              "-L${strip (visionosSimDeps.libffi or null)}/lib"
              "-L${strip (visionosSimDeps.pixman or null)}/lib"
              "-L${strip (visionosSimDeps.epoll-shim or null)}/lib"
              "-L${strip (visionosSimDeps.libssh2 or null)}/lib"
              "-L${strip (visionosSimDeps.openssl or null)}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lffi"
              "-lpixman-1"
              "-lepoll-shim"
              "-lssh2"
              "-lssl"
              "-lcrypto"
            ] ++ westonToytoolkitLdflagsAppleMobile visionosSimDeps ++ westonCompositorLdflags visionosSimDeps ++ fastfetchLdflags visionosSimDeps ++ neovimLdflags visionosSimDeps ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
            ] ++ (pixmanHeaderPaths visionosDeps);
            "HEADER_SEARCH_PATHS[sdk=xrsimulator*]" = [
              "$(inherited)"
              "${strip (visionosSimDeps.libwayland or null)}/include"
              "${strip (visionosSimDeps.libwayland or null)}/include/wayland"
              "${strip (visionosSimDeps.xkbcommon or null)}/include"
              "${strip (visionosSimDeps.libssh2 or null)}/include"
            ] ++ (pixmanHeaderPaths visionosSimDeps);
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
          { sdk = "Accelerate.framework"; }
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
          base = moduleVerifierFrameworkSettings // {
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
          base = moduleVerifierFrameworkSettings // {
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
          { path = "src/platform/watchos/ui/Settings/WWNWatchSettings.storyboard"; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
        ];
        preBuildScripts = [ stampBuildNumberPhase watchosPreBuild ];
        settings = {
          base = {
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona.watch";
            SUPPORTED_PLATFORMS = "watchos watchsimulator";
            WATCHOS_DEPLOYMENT_TARGET = "10.0";
            GENERATE_INFOPLIST_FILE = "YES";
            # watch icon assets are generated outside this shared AppIcon set.
            ASSETCATALOG_COMPILER_APPICON_NAME = "";
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
            ] ++ (pixmanHeaderPaths watchosDeps);
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
            ] ++ westonToytoolkitLdflagsAppleMobile watchosDeps ++ westonCompositorLdflags watchosDeps ++ footLdflags watchosDeps ++ fastfetchLdflags watchosDeps ++ neovimLdflags watchosDeps ++ [
              "-lwayland-server"
            ] ++ lib.optionals (watchosDeps ? waypipe && watchosDeps.waypipe != null) [
              "-force_load" "${strip watchosDeps.waypipe}/lib/libwaypipe.a"
            ] ++ lib.optionals (watchosBackend != null) [
              derivedRustLib
            ] ++ finalCxxLdflags;
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
            ] ++ westonToytoolkitLdflagsAppleMobile watchosSimDeps ++ westonCompositorLdflags watchosSimDeps ++ footLdflags watchosSimDeps ++ fastfetchLdflags watchosSimDeps ++ neovimLdflags watchosSimDeps ++ [
              "-lwayland-server"
            ] ++ lib.optionals (watchosSimDeps ? waypipe && watchosSimDeps.waypipe != null) [
              "-force_load" "${strip watchosSimDeps.waypipe}/lib/libwaypipe.a"
            ] ++ lib.optionals (watchosSimBackend != null) [
              derivedRustLib
            ] ++ finalCxxLdflags;
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
    schemes = schemesConfig;
  };

  targetPlatformKeys = {
    Wawona-iOS = "ios";
    Wawona-iPadOS = "ipados";
    Wawona-tvOS = "tvos";
    Wawona-watchOS = "watchos";
    Wawona-visionOS = "visionos";
    Wawona-macOS = "macos";
  };

  sharedXcodeTargets = [ "WawonaModel" "WawonaUIContracts" ];

  filteredProjectConfig =
    let
      filteredTargets =
        if platformFilter == null then
          projectConfig.targets
        else
          lib.filterAttrs (
            name: _target:
            lib.elem name sharedXcodeTargets
            || lib.elem (targetPlatformKeys.${name} or "") platformFilter
          ) projectConfig.targets;
    in
    projectConfig
    // {
      targets = filteredTargets;
      schemes = lib.filterAttrs (name: _scheme: filteredTargets ? ${name}) projectConfig.schemes;
    };

  projectYamlFile = pkgs.writeText "project.yml" (builtins.toJSON filteredProjectConfig);
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
        target = targets.get(target_name)
        # Only stamp targets that survived platformFilter; setdefault would
        # otherwise fabricate an empty (platform-less) target and xcodegen would
        # abort with "Unknown Target platform:".
        if target is None:
            continue
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
