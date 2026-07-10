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
  macosNiri ? null,
  macosFuzzel ? null,
  # Bundled mobile VM guest (kernel + rootfs.img) and iOS-TCI QEMU engine sysroot.
  mobileGuestArtifacts ? null,
  mobileVmEngine ? null,
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
  derivedNvimLib = "$(DERIVED_FILE_DIR)/libwawona-neovim.a";
  derivedSshLib = "$(DERIVED_FILE_DIR)/libssh-inprocess.a";
  derivedFfLib = "$(DERIVED_FILE_DIR)/libfastfetch.a";
  # Prebuild copies and privatises (nmedit) the active SDK's archives here
  # (see scripts/xcode-prebuild.sh) so internal symbols don't collide.
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
  # Apple mobile also force_loads libweston-13.a (toytoolkit); lazy compositor
  # linking avoids duplicate generated protocol symbols (tearing-control-v1, etc.).
  westonCompositorLdflagsAppleMobile = deps:
    let
      flags = import westonCompositorLdflagsNix {
        inherit lib deps;
        forceLoadCompositor = false;
      };
    in
      map (x: if x == "-Wl,-u,weston_compositor_main" then "-Wl,-u,_weston_compositor_main" else x) flags;
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
      [ "-force_load" derivedFfLib ] ++ frameworkFlags;
  neovimLdflags = deps:
    let libnvim = "${strip (deps.neovim or null)}/lib/libwawona-neovim.a";
    in if (deps.neovim or null) == null || !builtins.pathExists libnvim then [] else [
      "-force_load" derivedNvimLib
    ];
  # openssh in-process static lib — provides ssh_main, ssh_keygen_main, scp_main
  # for in-process dispatch on iOS (App Store compliant, no fork/exec).
  # Weak on builds without openssh linked; wawona-dispatch.c symbols are weak.
  # -lresolv: openbsd-compat's getrrsetbyname.o (force-loaded with the rest of
  # the archive) calls res_query/res_init from libresolv.
  opensshInprocessLdflags = deps:
    let libssh = "${strip (deps.openssh or null)}/lib/libssh-inprocess.a";
    in if (deps.openssh or null) == null || !builtins.pathExists libssh then [] else [
      "-force_load" derivedSshLib "-lresolv"
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
      iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator)
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
      iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator)
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
    mkdir -p "$DEST"
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
  }
  # Layer-3 XCUITest (ci-l3-apple-xcuitest): only Wawona-iOS carries a UI-test
  # bundle, so wire its scheme `test` action to run it.
  // lib.optionalAttrs (targetName == "Wawona-iOS") {
    test = {
      targets = [ "Wawona-iOSUITests" ];
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
          ] ++ (mobileBaseLdflags deps) ++ westonToytoolkitLdflagsAppleMobile deps ++ westonCompositorLdflagsAppleMobile deps
          ++ (ilandGlLdflags { inherit deps; simulator = false; }) ++ footLdflags deps ++ extraDeviceLdflags
          ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
          ] ++ (mobileBaseLdflags simDeps) ++ westonToytoolkitLdflagsAppleMobile simDeps ++ westonCompositorLdflagsAppleMobile simDeps
          ++ (ilandGlLdflags { deps = simDeps; simulator = true; }) ++ footLdflags simDeps ++ extraSimLdflags
          ++ [ derivedRustLib ] ++ finalCxxLdflags;
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

  # platformGlob gates the phase on PLATFORM_NAME: both the Simulator and
  # Device ANGLE phases run on every build, and without the gate whichever ran
  # last clobbered the other's slice (device Mach-O in a simulator bundle ->
  # dyld "Library not loaded: @rpath/libEGL.framework/libEGL" at launch).
  angleEmbedScript = platformGlob: anglePkg: pkgs.writeShellScript "embed-angle-dylibs.sh" ''
    case "''${PLATFORM_NAME:-}" in
      ${platformGlob}) ;;
      *) exit 0 ;;
    esac
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
    if angleSimDylib != null then angleEmbedScript "*simulator" angleSimDylib
    else pkgs.writeShellScript "embed-angle-sim-dylibs-noop.sh" "exit 0";
  angleDeviceEmbedScript =
    if angleDeviceDylib != null then angleEmbedScript "iphoneos|appletvos|xros" angleDeviceDylib
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

  mobileVmEmbedPhases =
    lib.optionals (mobileGuestArtifacts != null) [ iosMobileGuestEmbedPhase ]
    ++ lib.optionals (mobileVmEngine != null) [ iosMobileVmEngineEmbedPhase ];

  iosPostBuildPhases = [ xkbEmbedPhase fontEmbedPhase westonDataEmbedPhase iosRootfsEmbedPhase iosNeovimRootfsEmbedPhase ]
    ++ mobileVmEmbedPhases
    ++ lib.optionals (angleSimDylib != null) [ angleSimEmbedPhase ]
    ++ lib.optionals (angleDeviceDylib != null) [ angleDeviceEmbedPhase ];

  westonDataIosEmbedScript = pkgs.writeShellScript "embed-weston-data-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator)
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
      mkdir -p "$ICONS_DEST"
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
      iphoneos|appletvos|xros)
        rootfsSrc="${strip deviceRootfs}/rootfs"
        ;;
      iphonesimulator|appletvsimulator|xrsimulator)
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

  # The guest kernel/rootfs are a large aarch64-linux NixOS image. Resolve the
  # path from the environment at xcodebuild time (like WAWONA_UTM_SYSROOT for the
  # engine) rather than baking a store path in, so generating the Xcode project
  # never forces building the (heavy, cross-arch) guest. A device build that wants
  # the bundled VM sets WAWONA_MOBILE_GUEST_DIR to the built artifacts.
  mobileGuestIosEmbedScript = _guestArtifacts: pkgs.writeShellScript "embed-mobile-guest-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|appletvos|xros)
        guestSrc="''${WAWONA_MOBILE_GUEST_DIR:-}"
        ;;
      *)
        exit 0
        ;;
    esac
    if [ -z "$guestSrc" ] || [ ! -d "$guestSrc" ]; then
      echo "note: wawona-mobile-guest-artifacts not provided; set WAWONA_MOBILE_GUEST_DIR to embed the bundled VM guest" >&2
      exit 0
    fi
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/wawona-mobile-guest"
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -f "$guestSrc"/* "$DEST/" 2>/dev/null || true
    for k in Image zImage vmlinuz vmlinux; do
      if [ -f "$guestSrc/$k" ]; then
        cp -f "$guestSrc/$k" "$DEST/$k"
      fi
    done
    if [ -f "$guestSrc/rootfs.img" ]; then
      cp -f "$guestSrc/rootfs.img" "$DEST/rootfs.img"
    fi
    echo "Embedded wawona-mobile-guest into $DEST"
  '';

  # No declared outputFiles: Xcode pre-creates declared output paths inside the
  # bundle even when the script no-ops (simulator), leaving empty directories
  # that installd rejects (e.g. a Frameworks/*.framework with no Info.plist).
  iosMobileGuestEmbedPhase = {
    path = mobileGuestIosEmbedScript mobileGuestArtifacts;
    name = "Embed wawona-mobile-guest (VM kernel + rootfs)";
    basedOnDependencyAnalysis = false;
  };

  # The QEMU-TCTI engine is a multi-GB sysroot built impurely (needs Xcode +
  # WAWONA_UTM_SYSROOT). Resolve it from the environment at xcodebuild time so
  # project generation never forces the impure engine build. A device build that
  # wants the bundled engine sets WAWONA_MOBILE_VM_ENGINE_DIR to the built sysroot.
  mobileVmEngineIosEmbedScript = _engineSysroot: pkgs.writeShellScript "embed-mobile-vm-engine-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|appletvos|xros)
        engineSrc="''${WAWONA_MOBILE_VM_ENGINE_DIR:-}"
        ;;
      *)
        exit 0
        ;;
    esac
    if [ -z "$engineSrc" ] || [ ! -d "$engineSrc/Frameworks" ]; then
      echo "note: wwn-vms-mobile-engine sysroot not provided; set WAWONA_MOBILE_VM_ENGINE_DIR to embed the bundled QEMU-TCTI engine" >&2
      exit 0
    fi
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/Frameworks"
    mkdir -p "$DEST"
    cp -R "$engineSrc/Frameworks/." "$DEST/"
    if [ -d "$engineSrc/vulkan" ]; then
      mkdir -p "$BUNDLE/vulkan"
      cp -R "$engineSrc/vulkan/." "$BUNDLE/vulkan/"
    fi
    echo "Embedded QEMU-TCTI engine frameworks into $DEST"
  '';

  # No declared outputFiles (see iosMobileGuestEmbedPhase note): Xcode
  # pre-created Frameworks/qemu-aarch64-softmmu.framework/ in simulator
  # bundles, which installd rejected for the missing Info.plist.
  iosMobileVmEngineEmbedPhase = {
    path = mobileVmEngineIosEmbedScript mobileVmEngine;
    name = "Embed QEMU-TCTI engine (mobile VM)";
    basedOnDependencyAnalysis = false;
  };

  neovimRootfsIosEmbedScript = deviceRootfs: simRootfs: pkgs.writeShellScript "embed-neovim-rootfs-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|appletvos|xros)
        rootfsSrc="${strip deviceRootfs}/rootfs"
        ;;
      iphonesimulator|appletvsimulator|xrsimulator)
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

  # tvOS rootfs/neovim-rootfs embed phases.  The underlying scripts gate on
  # PLATFORM_NAME; tvOS passes `appletvos` / `appletvsimulator` which the
  # rootfs script does not match today (only iphoneos/iphonesimulator).  Use
  # basedOnDependencyAnalysis=false so they always attempt; the scripts no-op
  # gracefully when the rootfs artifact is absent.
  tvosRootfsEmbedPhase = {
    path = rootfsIosEmbedScript (tvosDeps."wawona-rootfs" or null) (tvosSimDeps."wawona-rootfs" or null);
    name = "Embed wawona-rootfs (shell templates)";
    basedOnDependencyAnalysis = false;
  };

  tvosNeovimRootfsEmbedPhase = {
    path = neovimRootfsIosEmbedScript (tvosDeps."neovim-rootfs" or null) (tvosSimDeps."neovim-rootfs" or null);
    name = "Embed neovim-rootfs (runtime templates)";
    basedOnDependencyAnalysis = false;
  };

  # visionOS rootfs/neovim-rootfs embed phases.
  visionosRootfsEmbedPhase = {
    path = rootfsIosEmbedScript (visionosDeps."wawona-rootfs" or null) (visionosSimDeps."wawona-rootfs" or null);
    name = "Embed wawona-rootfs (shell templates)";
    basedOnDependencyAnalysis = false;
  };

  visionosNeovimRootfsEmbedPhase = {
    path = neovimRootfsIosEmbedScript (visionosDeps."neovim-rootfs" or null) (visionosSimDeps."neovim-rootfs" or null);
    name = "Embed neovim-rootfs (runtime templates)";
    basedOnDependencyAnalysis = false;
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

  # Utility ObjC source files that live outside the usual platform directories.
  # These must be listed explicitly because src/util also contains Rust sources
  # that xcodegen cannot compile.
  iosUtilSources = [
    { path = "src/util/WWNStartupLogger.m"; type = "file"; }
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
          "$(SRCROOT)/src/util"
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
          DEBUG_INFORMATION_FORMAT = "dwarf";
        };
      };
    };
    targets = {
      # Layer-3 XCUITest bundle (ci-l3-apple-xcuitest). Drives the running app
      # through accessibility identifiers (e.g. `wwn.compositor.surface`).
      Wawona-iOSUITests = {
        type = "bundle.ui-testing";
        platform = "iOS";
        sources = [ { path = "src/tests/xcuitest"; } ];
        dependencies = [ { target = "Wawona-iOS"; } ];
        settings = {
          base = {
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona.UITests";
            TEST_TARGET_NAME = "Wawona-iOS";
            SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            TARGETED_DEVICE_FAMILY = "1";
            CODE_SIGN_STYLE = "Automatic";
            "CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = "NO";
            "CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = "NO";
            "VALID_ARCHS[sdk=iphonesimulator*]" = "arm64";
            "ARCHS[sdk=iphonesimulator*]" = "arm64";
          };
        };
      };
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
          { path = "src/platform/macos/ui/Modules"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ] ++ iosUtilSources;
        preBuildScripts = [ stampBuildNumberPhase iosPreBuild ];
        postBuildScripts = iosPostBuildPhases;

        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            CODE_SIGN_ENTITLEMENTS = "src/resources/app-bundle/Wawona-iCloud.entitlements";
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
             ] ++ westonToytoolkitLdflagsAppleMobile iosDeps ++ westonCompositorLdflagsAppleMobile iosDeps
             ++ (ilandGlLdflags { deps = iosDeps; simulator = false; }) ++ footLdflags iosDeps ++ fastfetchLdflags iosDeps ++ neovimLdflags iosDeps
             ++ opensshInprocessLdflags iosDeps
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
             ] ++ westonToytoolkitLdflagsAppleMobile iosSimDeps ++ westonCompositorLdflagsAppleMobile iosSimDeps
             ++ (ilandGlLdflags { deps = iosSimDeps; simulator = true; }) ++ footLdflags iosSimDeps ++ fastfetchLdflags iosSimDeps ++ neovimLdflags iosSimDeps
             ++ opensshInprocessLdflags iosSimDeps
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
          { sdk = "StoreKit.framework"; }
          { sdk = "GameController.framework"; }
          { sdk = "CarPlay.framework"; }
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
          { path = "src/platform/macos/ui/Modules"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ] ++ iosUtilSources;
        preBuildScripts = [ stampBuildNumberPhase ipadosPreBuild ];
        postBuildScripts = [ xkbEmbedPhase fontEmbedPhase westonDataEmbedPhase ipadosRootfsEmbedPhase ipadosNeovimRootfsEmbedPhase ] ++ mobileVmEmbedPhases;

        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            CODE_SIGN_ENTITLEMENTS = "src/resources/app-bundle/Wawona-iCloud.entitlements";
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
            ] ++ westonToytoolkitLdflagsAppleMobile ipadosDeps ++ westonCompositorLdflagsAppleMobile ipadosDeps
            ++ (ilandGlLdflags { deps = ipadosDeps; simulator = false; }) ++ footLdflags ipadosDeps ++ fastfetchLdflags ipadosDeps ++ neovimLdflags ipadosDeps
            ++ opensshInprocessLdflags ipadosDeps
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
            ] ++ westonToytoolkitLdflagsAppleMobile ipadosSimDeps ++ westonCompositorLdflagsAppleMobile ipadosSimDeps
            ++ (ilandGlLdflags { deps = ipadosSimDeps; simulator = true; }) ++ footLdflags ipadosSimDeps ++ fastfetchLdflags ipadosSimDeps ++ neovimLdflags ipadosSimDeps
            ++ opensshInprocessLdflags ipadosSimDeps
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
          { sdk = "StoreKit.framework"; }
          { sdk = "GameController.framework"; }
          { sdk = "CarPlay.framework"; }
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
          { path = "src/platform/macos/ui/Modules"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ] ++ iosUtilSources;
        preBuildScripts = [ stampBuildNumberPhase tvosPreBuild ];
        postBuildScripts = [ xkbEmbedPhase fontEmbedPhase westonDataEmbedPhase tvosRootfsEmbedPhase tvosNeovimRootfsEmbedPhase ]
          ++ mobileVmEmbedPhases
          ++ lib.optionals (angleSimDylib != null) [ angleSimEmbedPhase ]
          ++ lib.optionals (angleDeviceDylib != null) [ angleDeviceEmbedPhase ];

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
            ] ++ westonToytoolkitLdflagsAppleMobile tvosDeps ++ westonCompositorLdflagsAppleMobile tvosDeps ++ footLdflags tvosDeps ++ fastfetchLdflags tvosDeps ++ neovimLdflags tvosDeps ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
            ] ++ westonToytoolkitLdflagsAppleMobile tvosSimDeps ++ westonCompositorLdflagsAppleMobile tvosSimDeps ++ footLdflags tvosSimDeps ++ fastfetchLdflags tvosSimDeps ++ neovimLdflags tvosSimDeps ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
          { sdk = "StoreKit.framework"; }
          { sdk = "GameController.framework"; }
        ];
      };
      Wawona-macOS = {
        type = "application";
        platform = "macOS";
        sources = [
          { path = "Sources/WawonaUI"; excludes = [ "Skip/**" "VisionOS/**" ]; }
          { path = "src/platform/macos"; excludes = commonExcludes; }
          { path = "src/platform/macos/WWNIlandPresenter.m"; type = "file"; }
          # Re-include WWNSettings.c (excluded from the glob via commonExcludes):
          # on macOS its `#if !TARGET_OS_IPHONE` block provides the NULL
          # wwn_startup_log_sink definition that WWNLog.h references. The config
          # functions are `#ifndef __APPLE__` so nothing else compiles here.
          { path = "src/platform/macos/WWNSettings.c"; type = "file"; }
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
              NIRI_BIN="${strip macosNiri}/bin"
              NIRI_CFG="${strip macosNiri}/share/niri/default-config.kdl"
              FUZZEL_BIN="${strip macosFuzzel}/bin"

              # Bundled helper binaries are copied out of the read-only Nix
              # store, so they carry no signature valid for this app. The final
              # CodeSign phase seals every nested Mach-O and aborts with "code
              # object is not signed at all" unless each one is signed here.
              # Use the target's resolved identity when signing is enabled,
              # otherwise ad-hoc so the bundle still seals for local runs.
              sign_bin() {
                target="$1"
                [ -f "$target" ] || return 0
                if [ "''${CODE_SIGNING_ALLOWED:-YES}" != "YES" ]; then
                  return 0
                fi
                identity="''${EXPANDED_CODE_SIGN_IDENTITY:-}"
                if [ -z "$identity" ]; then identity="-"; fi
                /usr/bin/codesign --force --timestamp=none --sign "$identity" "$target" 2>/dev/null \
                  || /usr/bin/codesign --force --timestamp=none --sign - "$target"
              }

              bundle_bin() {
                src="$1"
                name="$2"
                if [ -f "$src" ]; then
                  install -m 755 "$src" "$BIN_DEST/$name"
                  sign_bin "$BIN_DEST/$name"
                  echo "Bundled $name"
                fi
              }

              BIN_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/bin"
              MACOS_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/MacOS"
              mkdir -p "$BIN_DEST"
              mkdir -p "$MACOS_DEST"

              bundle_bin "$WAYPIPE_SRC" "waypipe"
              bundle_bin "$SSHPASS_SRC" "sshpass"

              # wwn-ssh macOS backend: regular OpenSSH client tools.
              OPENSSH_BIN_DIR="${strip (macosDeps.openssh or null)}/bin"
              if [ -d "$OPENSSH_BIN_DIR" ]; then
                for tool in ssh ssh-keygen scp sftp ssh-agent ssh-add; do
                  bundle_bin "$OPENSSH_BIN_DIR/$tool" "$tool"
                done
              fi

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

              # niri (wwn-niri): nested scrollable-tiling compositor. Ship the
              # binary plus its read-only KDL config, resolved at runtime via
              # WAWONA_SHARE_ROOT (Contents/Resources/share/niri).
              bundle_bin "$NIRI_BIN/niri" "niri"
              if [ -f "$NIRI_CFG" ]; then
                SHARE_NIRI="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/share/niri"
                mkdir -p "$SHARE_NIRI"
                install -m 644 "$NIRI_CFG" "$SHARE_NIRI/default-config.kdl"
                echo "Bundled niri default-config.kdl"
              fi

              # fuzzel (wwn-niri): niri's Mod+D launcher; must be on PATH when
              # niri spawns child processes (see WWNWaypipeRunner niri env).
              bundle_bin "$FUZZEL_BIN/fuzzel" "fuzzel"

              # Weston nested compositor runtime assets. The weston binaries are
              # bundled above, but nested weston also needs its data (PNGs), shell
              # + backend modules, TrueType fonts, and a cursor theme. The app
              # refuses to launch nested weston when WESTON_DATA_DIR /
              # WESTON_MODULE_DIR / WESTON_BACKEND_DIR are unset, and those are
              # derived at runtime from these bundle paths (Resources/share/weston,
              # Resources/lib/weston, Resources/lib/libweston-13). Mirrors macos.nix.
              WESTON_STORE="${strip macosWeston}"
              RES_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources"
              if [ -d "$WESTON_STORE/share/weston" ]; then
                mkdir -p "$RES_DEST/share/weston"
                cp -R "$WESTON_STORE/share/weston/." "$RES_DEST/share/weston/"
                chmod -R u+w "$RES_DEST/share/weston"
                if [ ! -f "$RES_DEST/share/weston/terminal.png" ] && [ -f "$RES_DEST/share/weston/icon_terminal.png" ]; then
                  ln -sf icon_terminal.png "$RES_DEST/share/weston/terminal.png"
                fi
                echo "Bundled share/weston assets"
              fi
              if [ -d "$WESTON_STORE/lib/weston" ]; then
                mkdir -p "$RES_DEST/lib/weston"
                cp -R "$WESTON_STORE/lib/weston/." "$RES_DEST/lib/weston/"
                chmod -R u+w "$RES_DEST/lib/weston"
                for _so in "$RES_DEST/lib/weston"/*.dylib; do sign_bin "$_so"; done
                echo "Bundled lib/weston modules"
              fi
              
              MOLTENVK_STORE="${strip (pkgs.moltenvk or null)}"
              if [ -n "$MOLTENVK_STORE" ] && [ -d "$MOLTENVK_STORE/share/vulkan/icd.d" ]; then
                mkdir -p "$RES_DEST/vulkan/icd.d"
                cp "$MOLTENVK_STORE/share/vulkan/icd.d/"*.json "$RES_DEST/vulkan/icd.d/"
                chmod -R u+w "$RES_DEST/vulkan"
                
                FRAMEWORKS_DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Frameworks"
                mkdir -p "$FRAMEWORKS_DEST"
                for mvk_dylib in "$MOLTENVK_STORE/lib/libMoltenVK"*.dylib; do
                  if [ -f "$mvk_dylib" ]; then
                    fname=$(basename "$mvk_dylib")
                    cp "$mvk_dylib" "$FRAMEWORKS_DEST/"
                    chmod u+w "$FRAMEWORKS_DEST/$fname"
                    sign_bin "$FRAMEWORKS_DEST/$fname"
                    sed -i "" -e "s|\"library_path\":.*|\"library_path\": \"../../../Frameworks/libMoltenVK.dylib\",|" "$RES_DEST/vulkan/icd.d/"*.json
                  fi
                done
                echo "Bundled MoltenVK Vulkan ICD"
              fi
              if [ -d "$WESTON_STORE/lib/libweston-13" ]; then
                mkdir -p "$RES_DEST/lib/libweston-13"
                cp -R "$WESTON_STORE/lib/libweston-13/." "$RES_DEST/lib/libweston-13/"
                chmod -R u+w "$RES_DEST/lib/libweston-13"
                for _so in "$RES_DEST/lib/libweston-13"/*.dylib; do sign_bin "$_so"; done
                echo "Bundled lib/libweston-13 backends"
              fi
              mkdir -p "$RES_DEST/share/fonts"
              cp -RL "${pkgs.dejavu_fonts}/share/fonts/." "$RES_DEST/share/fonts/"
              chmod -R u+w "$RES_DEST/share/fonts"
              echo "Bundled DejaVu fonts"
              CURSOR_SRC="${pkgs.adwaita-icon-theme}/share/icons/Adwaita/cursors"
              if [ -d "$CURSOR_SRC" ]; then
                mkdir -p "$RES_DEST/share/icons/Adwaita"
                cp -RL "$CURSOR_SRC" "$RES_DEST/share/icons/Adwaita/cursors"
                chmod -R u+w "$RES_DEST/share/icons/Adwaita/cursors"
                echo "Bundled Adwaita cursors"
              fi

              # ----------------------------------------------------------------
              # Make the app self-contained: copy every non-system dylib the
              # app + bundled helpers link by absolute /nix/store path into
              # Contents/Frameworks and rewrite the load commands to @rpath.
              # Xcode links Rust/native code against /nix/store/.../*.dylib
              # (pixman, cairo, pango, glib, openssl, weston, ...). Those paths
              # exist only on this build machine, so a copied/exported app — or
              # one run after `nix` GC removes the store path — aborts at launch
              # with dyld "Library not loaded: .../libpixman-1.0.dylib". The
              # pure macos.nix build already does this; mirror it here.
              CONTENTS="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH"
              FW="$CONTENTS/Frameworks"
              mkdir -p "$FW"

              # NOTE: Xcode run-script phases execute under /bin/sh, which lacks
              # process substitution (< <(...)) and needs plain temp-file reads.
              RELOC_TMP="$(mktemp -d)"
              MACHO_LIST="$RELOC_TMP/machos"
              DEP_LIST="$RELOC_TMP/deps"
              RPATH_LIST="$RELOC_TMP/rpaths"

              is_macho() { file "$1" 2>/dev/null | grep -q 'Mach-O'; }

              write_macho_list() {
                : > "$MACHO_LIST"
                raw="$RELOC_TMP/raw"
                : > "$raw"
                # find (not shell globs) so hidden Mach-Os like .foot-wrapped are
                # included. Only real files (not the weston .so symlinks) so each
                # .dylib target is rewritten once.
                for d in "$CONTENTS/MacOS" "$CONTENTS/Resources/bin" \
                         "$CONTENTS/Resources/lib/weston" "$CONTENTS/Resources/lib/libweston-13"; do
                  [ -d "$d" ] || continue
                  find "$d" -maxdepth 1 -type f 2>/dev/null >> "$raw"
                done
                for f in "$FW"/*.dylib; do
                  [ -f "$f" ] && echo "$f" >> "$raw"
                done
                while IFS= read -r f; do
                  if [ -n "$f" ] && is_macho "$f"; then
                    if [ "$f" != "$CONTENTS/MacOS/$EXECUTABLE_NAME" ]; then
                      echo "$f" >> "$MACHO_LIST"
                    fi
                  fi
                done < "$raw"
                sort -u "$MACHO_LIST" -o "$MACHO_LIST"
              }

              dep_is_bundlable() {
                case "$1" in
                  /usr/lib/*|/System/*|/Library/*|@*) return 1 ;;
                esac
                return 0
              }

              # Idempotent rpath add — repeated script runs (incremental builds)
              # must not accumulate duplicate LC_RPATHs or the bundle bytes keep
              # changing under Xcode's cached CodeSign.
              add_rpath_once() {
                m="$1"; rp="$2"
                otool -l "$m" 2>/dev/null \
                  | awk '/cmd LC_RPATH/{getline; getline; if ($1=="path") print $2}' \
                  | grep -qx "$rp" && return 0
                install_name_tool -add_rpath "$rp" "$m" 2>/dev/null || true
              }

              copy_dep() {
                dep="$1"
                dep_is_bundlable "$dep" || return 1
                [ -f "$dep" ] || return 1
                base="$(basename "$dep")"
                if [ ! -f "$FW/$base" ]; then
                  cp -L "$dep" "$FW/$base"
                  chmod 755 "$FW/$base"
                  install_name_tool -id "@rpath/$base" "$FW/$base" 2>/dev/null || true
                  echo "Bundled dylib: $base"
                  return 0
                fi
                return 1
              }

              round=0
              while [ "$round" -lt 32 ]; do
                round=$((round + 1))
                added=0
                write_macho_list
                while IFS= read -r macho; do
                  [ -n "$macho" ] || continue
                  otool -L "$macho" 2>/dev/null | awk 'NR>1 {print $1}' | grep '\.dylib' > "$DEP_LIST" || true
                  while IFS= read -r dep; do
                    [ -n "$dep" ] || continue
                    if copy_dep "$dep"; then added=1; fi
                  done < "$DEP_LIST"
                done < "$MACHO_LIST"
                [ "$added" -eq 1 ] || break
              done

              write_macho_list
              while IFS= read -r macho; do
                [ -n "$macho" ] || continue
                otool -L "$macho" 2>/dev/null | awk 'NR>1 {print $1}' | grep '\.dylib' > "$DEP_LIST" || true
                while IFS= read -r dep; do
                  [ -n "$dep" ] || continue
                  dep_is_bundlable "$dep" || continue
                  base="$(basename "$dep")"
                  if [ -f "$FW/$base" ]; then
                    install_name_tool -change "$dep" "@rpath/$base" "$macho" 2>/dev/null || true
                  fi
                done < "$DEP_LIST"

                otool -l "$macho" 2>/dev/null | awk '/cmd LC_RPATH/{getline; getline; if ($1=="path") print $2}' > "$RPATH_LIST" || true
                while IFS= read -r rpath; do
                  [ -n "$rpath" ] || continue
                  # Keep every @-relative rpath (@executable_path/@loader_path) —
                  # the Debug build needs @executable_path to find the sibling
                  # Wawona.debug.dylib. Only strip absolute filesystem rpaths
                  # (e.g. /nix/store/...), which are what break portability.
                  case "$rpath" in
                    @*) continue ;;
                  esac
                  install_name_tool -delete_rpath "$rpath" "$macho" 2>/dev/null || true
                done < "$RPATH_LIST"
                add_rpath_once "$macho" "@executable_path/../Frameworks"
                case "$macho" in
                  */Contents/Resources/bin/*)
                    add_rpath_once "$macho" "@executable_path/../../Frameworks" ;;
                  */Contents/Resources/lib/*)
                    add_rpath_once "$macho" "@executable_path/../../../Frameworks" ;;
                esac
              done < "$MACHO_LIST"

              # install_name_tool invalidates signatures; re-seal every Mach-O
              # we touched so the final app CodeSign phase does not abort.
              for dylib in "$FW"/*.dylib; do
                [ -f "$dylib" ] && sign_bin "$dylib"
              done
              write_macho_list
              while IFS= read -r macho; do
                [ -n "$macho" ] && sign_bin "$macho"
              done < "$MACHO_LIST"
              echo "Relocated $(ls "$FW"/*.dylib 2>/dev/null | wc -l | tr -d ' ') dylib(s) into Frameworks"
              rm -rf "$RELOC_TMP"


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
            CODE_SIGN_INJECT_BASE_ENTITLEMENTS = "YES";
            EAGER_LINKING = "NO";
            ENABLE_DEBUG_DYLIB = "NO";
            DEAD_CODE_STRIPPING = "YES";
            HEADER_SEARCH_PATHS = [
              "$(inherited)"
              "${strip (macosDeps.libwayland or null)}/include"
              "${strip (macosDeps.libwayland or null)}/include/wayland"
              "${strip (macosDeps.xkbcommon or null)}/include"
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
              # -lwayland-server is provided by westonCompositorLdflags below;
              # listing it here too triggers "ignoring duplicate libraries".
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
          configs = {
            Release = {
              CODE_SIGN_ENTITLEMENTS = "src/resources/app-bundle/Wawona-iCloud.entitlements";
            };
            Debug = {
              CODE_SIGN_IDENTITY = "-";
              CODE_SIGN_STYLE = "Manual";
            };
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
          { sdk = "StoreKit.framework"; }
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
          { path = "src/platform/macos/ui/Modules"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ] ++ iosUtilSources;
        preBuildScripts = [ stampBuildNumberPhase visionosPreBuild ];
        postBuildScripts = [ xkbEmbedPhase fontEmbedPhase westonDataEmbedPhase visionosRootfsEmbedPhase visionosNeovimRootfsEmbedPhase ]
          ++ mobileVmEmbedPhases
          ++ lib.optionals (angleSimDylib != null) [ angleSimEmbedPhase ]
          ++ lib.optionals (angleDeviceDylib != null) [ angleDeviceEmbedPhase ];
        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            CODE_SIGN_ENTITLEMENTS = "src/resources/app-bundle/Wawona-iCloud.entitlements";
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
            ] ++ westonToytoolkitLdflagsAppleMobile visionosDeps ++ westonCompositorLdflagsAppleMobile visionosDeps ++ fastfetchLdflags visionosDeps ++ neovimLdflags visionosDeps ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
            ] ++ westonToytoolkitLdflagsAppleMobile visionosSimDeps ++ westonCompositorLdflagsAppleMobile visionosSimDeps ++ fastfetchLdflags visionosSimDeps ++ neovimLdflags visionosSimDeps ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
          { sdk = "StoreKit.framework"; }
          { sdk = "GameController.framework"; }
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
            ] ++ westonToytoolkitLdflagsAppleMobile watchosDeps ++ westonCompositorLdflagsAppleMobile watchosDeps ++ footLdflags watchosDeps ++ fastfetchLdflags watchosDeps ++ neovimLdflags watchosDeps ++ [
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
            ] ++ westonToytoolkitLdflagsAppleMobile watchosSimDeps ++ westonCompositorLdflagsAppleMobile watchosSimDeps ++ footLdflags watchosSimDeps ++ fastfetchLdflags watchosSimDeps ++ neovimLdflags watchosSimDeps ++ [
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
    # UITest bundle lives/dies with the iOS app target (ci-l3-apple-xcuitest).
    Wawona-iOSUITests = "ios";
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

    # Preserve Wawona.xcodeproj to maintain Xcode's Index.noindex data.
    # XcodeGen will gracefully update project.pbxproj in place.
    if [ -d "$PROJECT_DIR" ]; then
      chmod -R u+w "$PROJECT_DIR" 2>/dev/null || true
    fi
    if [ -d "Wawona.xcodeproj" ]; then
      chmod -R u+w "Wawona.xcodeproj" 2>/dev/null || true
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
    EFFECTIVE_TEAM_ID="''${TEAM_ID:-}"
    if [ -n "$EFFECTIVE_TEAM_ID" ] && command -v security >/dev/null 2>&1; then
      if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "(''$EFFECTIVE_TEAM_ID)"; then
        echo "Warning: TEAM_ID=''$EFFECTIVE_TEAM_ID has no matching local Apple Development certificate."
        echo "Installed signing identities:"
        security find-identity -v -p codesigning 2>/dev/null || true
        echo "Keeping explicit TEAM_ID from environment; install matching cert/account for this team in Xcode."
      fi
    fi
    # Always run the Python materializer and team stamp script
    TMP_SPEC="$TMP_SPEC" EFFECTIVE_TEAM_ID="$EFFECTIVE_TEAM_ID" REPO_ROOT="$REPO_ROOT" ${pkgs.python3}/bin/python3 <<'EOF'
import json
from pathlib import Path
import os
import re
import shutil

p = Path(os.environ["TMP_SPEC"])
data = json.loads(p.read_text())
repo_root = Path(os.environ["REPO_ROOT"])
nix_deps_dir = repo_root / ".nix-deps"

# Clean old materialized deps
if nix_deps_dir.exists():
    os.system(f"chmod -R u+w '{nix_deps_dir}' 2>/dev/null || true")
    shutil.rmtree(nix_deps_dir, ignore_errors=True)
nix_deps_include = nix_deps_dir / "include"
nix_deps_lib = nix_deps_dir / "lib"
nix_deps_include.mkdir(parents=True, exist_ok=True)
nix_deps_lib.mkdir(parents=True, exist_ok=True)

def process_paths(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            obj[k] = process_paths(v)
    elif isinstance(obj, list):
        for i in range(len(obj)):
            obj[i] = process_paths(obj[i])
    elif isinstance(obj, str):
        matches = re.findall(r'(/nix/store/([a-zA-Z0-9]{32}-[a-zA-Z0-9_.-]+))', obj)
        for match, name in matches:
            dep_path = Path(match)
            if (dep_path / "include").exists():
                os.system(f"cp -R '{dep_path}/include' '{nix_deps_include}/{name}'")
                os.system(f"chmod -R u+w '{nix_deps_include}/{name}'")
            if (dep_path / "lib").exists():
                os.system(f"cp -R '{dep_path}/lib' '{nix_deps_lib}/{name}'")
                os.system(f"chmod -R u+w '{nix_deps_lib}/{name}'")
        obj = re.sub(r'/nix/store/([a-zA-Z0-9]{32}-[a-zA-Z0-9_.-]+)/include', r'$(SRCROOT)/.nix-deps/include/\1', obj)
        obj = re.sub(r'/nix/store/([a-zA-Z0-9]{32}-[a-zA-Z0-9_.-]+)/lib', r'$(SRCROOT)/.nix-deps/lib/\1', obj)
    return obj

data = process_paths(data)

team = os.environ.get("EFFECTIVE_TEAM_ID", "").strip()
if team:
    targets = data.setdefault("targets", {})
    for target_name in ("Wawona-iOS", "Wawona-iPadOS", "Wawona-tvOS"):
        target = targets.get(target_name)
        if target is None:
            continue
        base = target.setdefault("settings", {}).setdefault("base", {})
        base["DEVELOPMENT_TEAM"] = team
p.write_text(json.dumps(data, indent=2))
EOF
    if [ -n "$EFFECTIVE_TEAM_ID" ]; then
      echo "Applied TEAM_ID=$EFFECTIVE_TEAM_ID to Wawona-iOS, Wawona-iPadOS, and Wawona-tvOS."
    fi
    ${xcodeUtils.xcodeWrapper}/bin/xcode-wrapper ${pkgs.xcodegen}/bin/xcodegen generate --use-cache --spec "$TMP_SPEC"

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

    echo "Wawona.xcodeproj generated at ./Wawona.xcodeproj (repo root)."
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
    
    PROJECT_DIR="Wawona.xcodeproj"
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
