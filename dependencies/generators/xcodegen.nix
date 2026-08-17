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
  macosPhoon ? null,
  macosNeovim ? null,
  macosZsh ? null,
  macosKmscube ? null,
  macosOpenglCube ? null,
  macosVkcube ? null,
  macosWestonSimpleEgl ? null,
  macosNiri ? null,
  macosFuzzel ? null,
  # Bundled mobile VM guest (kernel + rootfs.img) and iOS-TCI QEMU engine sysroot.
  mobileGuestArtifacts ? null,
  mobileVmEngine ? null,
  # Prefer SDK-gated construction: only emit matching app targets (+ shared libs).
  # Combined with flake `mkXcodegen` passing empty unused platform deps, filtered
  # targets do not realize device/macOS/tvOS closures for ios-sim CI.
  platformFilter ? null,
  # When true, omit iphoneos* ldflags/headers and device-side embed strip() so
  # realizing the project does not force the device native closure (CI sim path).
  simulatorOnly ? false,
  applePath,
  westonToytoolkitLdflagsNix,
  westonCompositorLdflagsNix,
  mobileBaseLdflagsNix,
  ilandGlLdflagsNix,
}:

let
  lib = pkgs.lib;
  strip = d: if d == null then "" else toString d;
  # Device store paths are omitted entirely for simulator-only project gens.
  deviceStrip = d: if simulatorOnly then "" else strip d;
  wantPlatform = p: platformFilter == null || builtins.elem p platformFilter;
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

  # Simulator slices on Apple Silicon CI: never compile x86_64. App targets
  # already set ARCHS[sdk=*simulator*]=arm64; shared frameworks did not, so
  # generic/platform destinations still built WawonaUIContracts for x86_64.
  appleSimArchSettings = {
    "ARCHS[sdk=iphonesimulator*]" = "arm64";
    "VALID_ARCHS[sdk=iphonesimulator*]" = "arm64";
    "EXCLUDED_ARCHS[sdk=iphonesimulator*]" = "x86_64 i386";
    "ARCHS[sdk=appletvsimulator*]" = "arm64";
    "VALID_ARCHS[sdk=appletvsimulator*]" = "arm64";
    "EXCLUDED_ARCHS[sdk=appletvsimulator*]" = "x86_64 i386";
    "ARCHS[sdk=xrsimulator*]" = "arm64";
    "VALID_ARCHS[sdk=xrsimulator*]" = "arm64";
    "EXCLUDED_ARCHS[sdk=xrsimulator*]" = "x86_64 i386";
    "ARCHS[sdk=watchsimulator*]" = "arm64";
    "VALID_ARCHS[sdk=watchsimulator*]" = "arm64";
    "EXCLUDED_ARCHS[sdk=watchsimulator*]" = "x86_64 i386";
    ONLY_ACTIVE_ARCH = "YES";
  };
  derivedZshLib = "$(DERIVED_FILE_DIR)/libwawona-zsh.a";
  derivedNvimLib = "$(DERIVED_FILE_DIR)/libwawona-neovim.a";
  derivedSshCliLib = "$(DERIVED_FILE_DIR)/libwwn-ssh-cli.a";
  derivedFfLib = "$(DERIVED_FILE_DIR)/libfastfetch.a";
  # foot / fuzzel are Wayland clients whose static archives embed their own copy
  # of the generated protocol marshalling (xdg_toplevel_interface, …). Prebuild
  # privatises them here (single merged .o, only the *_main entry exported) so
  # those symbols become local and never collide with weston's copies.
  derivedFootLib = "$(DERIVED_FILE_DIR)/libfoot.a";
  derivedFuzzelLib = "$(DERIVED_FILE_DIR)/libfuzzel.a";
  derivedGetprognameLib = "$(DERIVED_FILE_DIR)/libwawona-getprogname.a";
  # Prebuild copies and privatises (nmedit) the active SDK's archives here
  # (see scripts/xcode-prebuild.sh) so internal symbols don't collide.
  # -force_load: WWNWatchStubs (and any weak fallback) must not satisfy
  # wawona_zsh_main before the privatized archive is pulled in.
  mobileZshLdflags = [ "-force_load" derivedZshLib ];
  # Force-load before weston/fontconfig so getprogname resolves locally and
  # App Store Connect never sees libSystem's private ___progname import.
  mobileGetprognameLdflags = [
    "-force_load" derivedGetprognameLib
  ];
  # Force the in-process dispatch entry points out of libwawona.a / privatized
  # archives.  Weak refs from libwwn-pty.a alone do not pull these symbols.
  mobileDispatchLdflags = [
    "-Wl,-u,_wawona_coreutils_main"
    "-Wl,-u,_fastfetch_main"
    "-Wl,-u,_phoon_main"
    "-Wl,-u,_wawona_nvim_main"
    "-Wl,-u,_waypipe_main"
    "-Wl,-u,_niri_main"
    "-Wl,-u,_fuzzel_main"
    "-Wl,-u,_wawona_dispatch_can_handle"
    "-Wl,-u,_wawona_dispatch_inprocess"
    "-Wl,-u,_wawona_dispatch_spawn_async"
  ];
  # Pin matches weston-compositor-apple-mobile (13.0.0). Do not use pkgs.weston on
  # Darwin. It pulls pipewire and fails eval (valgrind marked broken in nixpkgs).
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
  # macOS: compositor-macos keeps helpers/protocols in libweston-compositor-13.a;
  # only need cairo/pango -L/-l from toytoolkit, not -lweston-13.
  westonToytoolkitLdflagsMacos = deps: import westonToytoolkitLdflagsNix {
    inherit lib deps;
    forceLoadWeston = true;
    linkWestonLib = false;
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
  moltenvkLdflags = deps:
    let
      mvk = deps.moltenvk or null;
      archive = "${strip mvk}/lib/libMoltenVK.a";
    in
      if mvk == null || !builtins.pathExists archive then [ ] else [
        "-force_load" archive
        "-framework" "Metal"
        "-framework" "Foundation"
        "-framework" "QuartzCore"
        "-framework" "CoreGraphics"
        "-framework" "IOSurface"
        "-framework" "UIKit"
      ];
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
  ]
  ++ lib.optional (deps.vkcube or null != null) "${strip deps.vkcube}/include"
  ++ lib.optional (deps."opengl-cube" or null != null) "${strip deps."opengl-cube"}/include";
  # foot: force-load the privatized $(DERIVED_FILE_DIR) copy (see xcode-prebuild.sh),
  # not the raw store archive. Its embedded protocol symbols must be localised so
  # they do not collide with weston / fuzzel at final link.
  footLdflags = deps:
    let
      libfoot = "${strip (deps.foot or null)}/lib/libfoot.a";
      fcft = deps.fcft or null;
    in if (deps.foot or null) == null || !builtins.pathExists libfoot then [] else
      [ "-force_load" derivedFootLib ]
      # foot depends on fcft (font shaping). On iOS/iPadOS/visionOS fuzzel also
      # pulls fcft, but tvOS/watchOS link foot without fuzzel, so foot must own
      # it. Duplicate -lfcft with fuzzel is harmless (ld dedups library refs).
      ++ lib.optionals (fcft != null) [ "-L${strip fcft}/lib" "-lfcft" ];
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
  # wwn-phoon-rs: pure-Rust static lib + phoon_main C ABI (in-process shell
  # tool), bundled on EVERY Apple target (whole family, incl. tvOS/watchOS).
  #
  # LAZY archive link, NOT -force_load. Exactly the waypipe treatment: niri is
  # -force_load'd on every target and libphoon_rs.a (like libniri.a) statically
  # embeds a full copy of Rust std/core/gimli. Force-loading BOTH pulls two std
  # copies and yields thousands of duplicate symbols (ld: 2134 duplicate symbols
  # on watchOS. The real failure this replaces). Instead: put phoon on the link
  # line AFTER niri as a plain `-lphoon_rs`, and keep phoon_main alive with an
  # explicit `-Wl,-u,_phoon_main`. The linker then pulls only phoon's own objects
  # (phoon_main + its private code); std/core symbols are already defined by
  # niri's force-load, so phoon's std objects are never pulled → no duplicates.
  #
  # DO NOT privatize (no nmedit/ld -r): Rust name-mangles everything except the
  # phoon_main C entry, so there is nothing to collide with weston/foot. There
  # must be NO weak phoon_main stub on any target. A weak definition would
  # satisfy the -u and stop the real archive member from being pulled. phoon is
  # mandatory, so a null dep is the only legitimate opt-out.
  phoonLdflags = deps:
    let
      ph = deps.phoon or null;
    in if ph == null then [] else [
      "-L${strip ph}/lib"
      "-Wl,-u,_phoon_main"
      "-lphoon_rs"
    ];

  # wwn-wasm: Pulley/Cranelift Runtime. Lazy -l like phoon (Wasmtime embeds
  # Rust std). watchOS is size-gated off (no archive). Never -force_load.
  # Do not gate libwawona_wasm on pathExists (same niri pitfall). wpm_main lives
  # in a separate libwpm.a that older flake tips omit; only force-link when the
  # archive is present so Xcode Run is not blocked on a missing symbol.
  wasmLdflags = deps:
    let
      w = deps.wawona-wasm or null;
      libwpm = if w == null then null else "${strip w}/lib/libwpm.a";
      hasWpm = libwpm != null && builtins.pathExists libwpm;
    in if w == null then [] else [
      "-L${strip w}/lib"
      "-Wl,-u,_wawona_wasm_run"
      "-Wl,-u,_wawona_wasm_can_run"
      "-lwawona_wasm"
    ] ++ lib.optionals hasWpm [
      "-Wl,-u,_wpm_main"
      "-lwpm"
    ];
  neovimLdflags = deps:
    let libnvim = "${strip (deps.neovim or null)}/lib/libwawona-neovim.a";
    in if (deps.neovim or null) == null || !builtins.pathExists libnvim then [] else [
      "-force_load" derivedNvimLib
    ];
  # wwn-niri: static lib + niri_main C ABI (in-process nested compositor).
  niriLdflags = deps:
    let
      niri = deps.niri or null;
      libniri = "${strip niri}/lib/libniri.a";
      cg = deps."cairo-gobject" or null;
      cgLib = "${strip cg}/lib/libcairo-gobject.a";
    in
      # Deliberately no builtins.pathExists on the output: that only reports
      # whether the archive is *already realised*, so a target that had never
      # built niri silently dropped -force_load while still emitting
      # -Wl,-u,_niri_main, and failed to link. Niri is mandatory on every Apple
      # target, so a null dep is the only legitimate way to opt out.
      (if niri == null then [] else [
        "-L${strip niri}/lib"
        "-Wl,-u,_niri_main"
        "-force_load" libniri
      ])
      ++ lib.optionals (cg != null) [
        "-L${strip cg}/lib"
        "-lcairo-gobject"
      ];
  # wwn-niri fuzzel: static lib + fuzzel_main (niri spawns via mobile posix_spawn).
  fuzzelLdflags = deps:
    let
      fuzzel = deps.fuzzel or null;
      libfuzzel = "${strip fuzzel}/lib/libfuzzel.a";
      fcft = deps.fcft or null;
    in
      (if fuzzel == null || !builtins.pathExists libfuzzel then [] else [
        "-Wl,-u,_fuzzel_main"
        "-force_load" derivedFuzzelLib
      ])
      ++ lib.optionals (fcft != null) [
        "-L${strip fcft}/lib"
        "-lfcft"
      ];
  # Apple mobile SSH CLI: libwwn-ssh-cli.a from wwn-ssh (libssh2 + OpenSSL).
  # Never OpenSSH-inprocess archives on App Store targets (libssh2 CLI only).
  # Force-load the nix-store archive directly (no prebuild privatize needed).
  sshCliLdflags = deps:
    let
      cli = deps."ssh-cli" or null;
      archive = "${strip cli}/lib/libwwn-ssh-cli.a";
    in if cli == null || !builtins.pathExists archive then [] else [
      "-force_load" archive
      "-Wl,-u,_ssh_main"
      "-Wl,-u,_ssh_keygen_main"
      "-Wl,-u,_scp_main"
    ];
  # glib/gio (res_9_*) needs libresolv on Apple even with zero OpenSSH.
  appleMobileResolvLdflags = [ "-lresolv" ];
  # Static archives with C++ (ANGLE, Rust backend, fastfetch, …) need libc++
  # after every -force_load block; append once at the end of OTHER_LDFLAGS.
  # IOKit is in iOS/macOS/visionOS SDKs but absent from tvOS/watchOS.
  finalCxxLdflagsBase = [ "-lc++" "-lc++abi" "-ldl" ];
  finalCxxLdflags = finalCxxLdflagsBase ++ [ "-framework" "IOKit" ];
  finalCxxLdflagsNoIokit = finalCxxLdflagsBase;
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
      iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator|watchos|watchsimulator)
        ;;
      *)
        exit 0
        ;;
    esac
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/share/X11/xkb"
    mkdir -p "$DEST"
    # -L: dereference symlinks. Preserving xorg→base links makes
    # `simctl install` fail with NSPOSIXErrorDomain/13 (copyfile EPERM)
    # on modern iOS Simulator installd.
    cp -RL "${pkgs.xkeyboard_config}/share/X11/xkb/." "$DEST/"
    chmod -R u+w "$DEST" 2>/dev/null || true
    find "$DEST" -type l -delete 2>/dev/null || true
    echo "Embedded xkeyboard-config into $DEST"
  '';
  # DejaVu (UI/CSD) + DejaVuSansM Nerd Font Mono (terminals / prompts).
  # See dependencies/libs/fonts. Without any font, desktop-shell aborts during
  # init and the nested compositor shows only a solid clear color.
  wawonaBundledFonts = pkgs.callPackage ../libs/fonts { };
  fontIosEmbedScript = pkgs.writeShellScript "embed-fonts-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator|watchos|watchsimulator)
        ;;
      *)
        exit 0
        ;;
    esac
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/share/fonts"
    rm -rf "$DEST"
    mkdir -p "$DEST"
    # Nix store font paths are often symlinks; iOS installd rejects symlinks in .app
    # bundles (MIInstallerErrorDomain Code 70). -L dereferences to real files.
    cp -RL "${wawonaBundledFonts}/share/fonts/." "$DEST/"
    echo "Embedded Wawona fonts (DejaVu + DejaVuSansM Nerd Font Mono) into $DEST"
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
  libwawonaOutputPaths = { withZsh ? false, withGetprogname ? false, withFoot ? false, withFuzzel ? false }:
    [ derivedRustLib ]
    ++ lib.optionals withZsh [
      derivedZshLib
      derivedNvimLib
      derivedFfLib
    ]
    # foot/fuzzel are privatized into $(DERIVED_FILE_DIR) by xcode-prebuild.sh;
    # declare them as outputs so Xcode's linker input check finds them. foot ships
    # on every Apple-mobile target; fuzzel only on iOS/iPadOS/visionOS.
    ++ lib.optionals withFoot [ derivedFootLib ]
    ++ lib.optionals withFuzzel [ derivedFuzzelLib ]
    ++ lib.optionals withGetprogname [ derivedGetprognameLib ];

  nixPreBuildInputs = [
    "$(SRCROOT)/Cargo.lock"
    "$(SRCROOT)/flake.nix"
    "$(SRCROOT)/Cargo.toml"
  ];

  mkPreBuildPhase = { withZsh ? false, withGetprogname ? false, withFoot ? false, withFuzzel ? false }: {
    name = "Build Rust Backend via Nix";
    basedOnDependencyAnalysis = false;
    inputFiles = nixPreBuildInputs ++ [
      "$(SRCROOT)/scripts/xcode-prebuild.sh"
      "$(SRCROOT)/src/platform/ios/WWNGetprognameStub.c"
    ];
    outputFiles = libwawonaOutputPaths { inherit withZsh withGetprogname withFoot withFuzzel; };
    script = ''
      exec "''${SRCROOT}/scripts/xcode-prebuild.sh"
    '';
  };

  iosPreBuild = mkPreBuildPhase { withZsh = true; withGetprogname = true; withFoot = true; withFuzzel = true; };

  ipadosPreBuild = mkPreBuildPhase { withZsh = true; withGetprogname = true; withFoot = true; withFuzzel = true; };

  tvosPreBuild = mkPreBuildPhase { withZsh = true; withGetprogname = true; withFoot = true; };

  macosPreBuild = mkPreBuildPhase { };

  visionosPreBuild = mkPreBuildPhase { withZsh = true; withGetprogname = true; withFoot = true; withFuzzel = true; };

  watchosPreBuild = mkPreBuildPhase { withZsh = true; withFoot = true; };

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
  # var), not $(SRCROOT) (command substitution. Breaks with "SRCROOT: not found").
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
          "OTHER_CFLAGS[sdk=${simSdk}*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
          "OTHER_SWIFT_FLAGS[sdk=${simSdk}*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
          "LIBRARY_SEARCH_PATHS[sdk=${simSdk}*]" = ios26SwiftLibSearchPaths;
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
          ++ (ilandGlLdflags { deps = simDeps; simulator = true; }) ++ moltenvkLdflags simDeps ++ footLdflags simDeps ++ extraSimLdflags
          ++ [ derivedRustLib ] ++ finalCxxLdflags;
          GCC_PREPROCESSOR_DEFINITIONS = [ "$(inherited)" ] ++ extraDefines ++ versionDefs;
        } // lib.optionalAttrs (!simulatorOnly) {
          "OTHER_CFLAGS[sdk=${deviceSdk}*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
          "OTHER_SWIFT_FLAGS[sdk=${deviceSdk}*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
          "LIBRARY_SEARCH_PATHS[sdk=${deviceSdk}*]" = ios26SwiftLibSearchPaths;
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
          ++ (ilandGlLdflags { inherit deps; simulator = false; }) ++ moltenvkLdflags deps ++ footLdflags deps ++ extraDeviceLdflags
          ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/fonts/truetype/DejaVuSansMNerdFontMono-Regular.ttf"
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
  # Skip device ANGLE IFD when generating a simulator-only project.
  angleDeviceDylib = if simulatorOnly then null else angleDylibDeps iosDeps;

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
    # Local builds often have GC'd /nix/store paths; fall back to mirrored .nix-deps.
    if [ ! -f "$EGL_SRC" ] || [ ! -f "$GLES_SRC" ]; then
      HASH=$(basename "${strip anglePkg}")
      FALLBACK_DIR="$SRCROOT/.nix-deps/lib/$HASH"
      if [ -f "$FALLBACK_DIR/lib/libEGL.dylib" ]; then
        EGL_SRC="$FALLBACK_DIR/lib/libEGL.dylib"
        GLES_SRC="$FALLBACK_DIR/lib/libGLESv2.dylib"
      elif [ -f "$FALLBACK_DIR/libEGL.dylib" ]; then
        EGL_SRC="$FALLBACK_DIR/libEGL.dylib"
        GLES_SRC="$FALLBACK_DIR/libGLESv2.dylib"
      else
        echo "error: ANGLE dylibs missing at ${strip anglePkg}/lib and $FALLBACK_DIR" >&2
        exit 1
      fi
      echo "ANGLE embed: using .nix-deps fallback ($FALLBACK_DIR)"
    fi
    # Prebuilt XCFramework slices use LC_ID_DYLIB @rpath/libEGL.framework/libEGL.
    write_fw_plist() {
      local fw="$1" exe="$2"
      # App Store Connect (altool 90360) requires MinimumOSVersion on embedded
      # frameworks; match the app deployment target for the active platform.
      local min_os="''${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
      case "''${PLATFORM_NAME:-}" in
        appletvos|appletvsimulator)
          min_os="''${TVOS_DEPLOYMENT_TARGET:-''${min_os}}"
          ;;
        xros|xrsimulator)
          min_os="''${XROS_DEPLOYMENT_TARGET:-1.0}"
          ;;
        iphonesimulator|iphoneos)
          min_os="''${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
          ;;
      esac
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
  <key>MinimumOSVersion</key><string>$min_os</string>
</dict></plist>
PLIST
    }
    mkdir -p "$DEST/libEGL.framework" "$DEST/libGLESv2.framework"
    cp -f "$EGL_SRC" "$DEST/libEGL.framework/libEGL"
    cp -f "$GLES_SRC" "$DEST/libGLESv2.framework/libGLESv2"
    write_fw_plist libEGL libEGL
    write_fw_plist libGLESv2 libGLESv2
    SIGN_LIBS="$DEST/libEGL.framework/libEGL $DEST/libGLESv2.framework/libGLESv2"
    # Flat @executable_path/Frameworks/lib*.dylib copies are SIMULATOR-ONLY
    # dev conveniences. Loose .dylib files inside a device Frameworks/ are
    # forbidden in App Store bundles (TN2435). App Store Connect's Swift
    # Support validator misreads any loose dylib as a pre-ABI-stability
    # Swift runtime dylib and rejects the ipa with rotating ITMS-90426/
    # 90429/90433 (every iOS upload from build 60 through 120 failed this
    # way while dylib-free tvOS/visionOS ipas from the same commits were
    # accepted). iland's EGL shim probes the framework-wrapped binaries
    # first (wwn-iland egl.c load_angle/gles candidates), so devices only
    # need libEGL.framework/libGLESv2.framework.
    case "''${PLATFORM_NAME:-}" in
      *simulator)
        cp -f "$EGL_SRC" "$DEST/libEGL.dylib"
        cp -f "$GLES_SRC" "$DEST/libGLESv2.dylib"
        SIGN_LIBS="$SIGN_LIBS $DEST/libEGL.dylib $DEST/libGLESv2.dylib"
        ;;
    esac
    # /nix/store objects are mode 444; cp preserves that. InstallCoordination's
    # copyfile then fails with NSPOSIXErrorDomain 13 (Permission denied) when
    # Xcode / simctl installs the .app into the Simulator.
    chmod -R u+w "$DEST"
    if [ -n "''${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "''${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
      for lib in $SIGN_LIBS; do
        /usr/bin/codesign --force --sign "''${EXPANDED_CODE_SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements,flags "$lib"
      done
    fi
    echo "Embedded ANGLE dylibs into $DEST (flat copies: simulator only)"
  '';

  angleSimEmbedScript =
    if angleSimDylib != null then angleEmbedScript "iphonesimulator" angleSimDylib
    else pkgs.writeShellScript "embed-angle-sim-dylibs-noop.sh" "exit 0";
  angleDeviceEmbedScript =
    # No appletvos. TvOS must not ship ANGLE (platform-targets matrix).
    if angleDeviceDylib != null then angleEmbedScript "iphoneos" angleDeviceDylib
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

  # SwiftShader CPU Vulkan ICD. IOS Simulator ONLY. On the headless CI simulator
  # MoltenVK's Metal pipeline bring-up kills the app (Metal domain 102), so vkcube
  # needs a pure-CPU Vulkan device to fall back to. Loaded at runtime by vkcube's
  # dlopen dispatch (WWN_VULKAN_LIBRARY), so a flat Frameworks/*.dylib is fine. And
  # this only ever runs for *simulator (the same TN2435 loose-dylib rule that keeps
  # ANGLE flat copies off device also keeps SwiftShader off device; device store
  # builds must not contain it at all, enforced by verify-iland-graphics-bundle).
  swiftshaderSimLib = iosSimDeps.swiftshader or null;
  swiftshaderSimEmbedScript =
    if swiftshaderSimLib != null then
      pkgs.writeShellScript "embed-swiftshader-sim.sh" ''
        case "''${PLATFORM_NAME:-}" in
          *simulator*) ;;
          *) exit 0 ;;
        esac
        BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
        DEST="$BUNDLE/Frameworks"
        ICD_DEST="$BUNDLE/vulkan/icd.d"
        SS_SRC="${strip swiftshaderSimLib}/lib/libvk_swiftshader.dylib"
        if [ ! -f "$SS_SRC" ]; then
          HASH=$(basename "${strip swiftshaderSimLib}")
          FALLBACK_DIR="$SRCROOT/.nix-deps/lib/$HASH"
          if [ -f "$FALLBACK_DIR/lib/libvk_swiftshader.dylib" ]; then
            SS_SRC="$FALLBACK_DIR/lib/libvk_swiftshader.dylib"
          fi
        fi
        if [ ! -f "$SS_SRC" ]; then
          echo "warning: SwiftShader ICD missing at $SS_SRC" >&2
          exit 0
        fi
        mkdir -p "$DEST" "$ICD_DEST"
        cp -f "$SS_SRC" "$DEST/libvk_swiftshader.dylib"
        cat > "$ICD_DEST/vk_swiftshader_icd.json" <<'ICDJSON'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "../../Frameworks/libvk_swiftshader.dylib",
    "api_version": "1.3.0"
  }
}
ICDJSON
        chmod -R u+w "$DEST/libvk_swiftshader.dylib" "$ICD_DEST" 2>/dev/null || true
        if [ -n "''${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "''${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
          /usr/bin/codesign --force --sign "''${EXPANDED_CODE_SIGN_IDENTITY}" \
            --preserve-metadata=identifier,entitlements,flags \
            "$DEST/libvk_swiftshader.dylib"
        fi
        echo "Embedded SwiftShader CPU Vulkan ICD into $DEST (simulator only)"
      ''
    else
      pkgs.writeShellScript "embed-swiftshader-sim-noop.sh" "exit 0";

  swiftshaderSimEmbedPhase = {
    path = swiftshaderSimEmbedScript;
    name = "Embed SwiftShader (Simulator CPU Vulkan ICD)";
    basedOnDependencyAnalysis = false;
  };

  mobileVmEmbedPhases =
    lib.optionals (mobileGuestArtifacts != null) [ iosMobileGuestEmbedPhase ]
    ++ lib.optionals (mobileVmEngine != null) [ iosMobileVmEngineEmbedPhase ];

  # Freedesktop .desktop + hicolor icons for nested-niri fuzzel (issue #78).
  applicationsCatalog = pkgs.callPackage ./applications-catalog.nix {
    inherit pkgs lib wawonaSrc;
  };

  appsCatalogIosEmbedScript = pkgs.writeShellScript "embed-applications-catalog-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator|watchos|watchsimulator)
        ;;
      *)
        exit 0
        ;;
    esac
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    CATALOG="${applicationsCatalog}"
    if [ ! -d "$CATALOG/share/applications" ]; then
      echo "warning: applications catalog missing at $CATALOG" >&2
      exit 0
    fi
    mkdir -p "$BUNDLE/share/applications" "$BUNDLE/share/icons"
    cp -R "$CATALOG/share/applications/." "$BUNDLE/share/applications/"
    cp -R "$CATALOG/share/icons/hicolor" "$BUNDLE/share/icons/"
    chmod -R u+w "$BUNDLE/share/applications" "$BUNDLE/share/icons/hicolor" 2>/dev/null || true
    echo "Embedded fuzzel applications catalog into $BUNDLE/share"
  '';

  appsCatalogEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/applications/foot.desktop"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/icons/hicolor/index.theme"
  ];

  appsCatalogEmbedPhase = {
    path = appsCatalogIosEmbedScript;
    name = "Embed fuzzel applications catalog";
    basedOnDependencyAnalysis = true;
    outputFiles = appsCatalogEmbedOutputs;
  };

  # Last post-build step for GPU Apple-mobile targets: nix-copied resources
  # (ANGLE, weston share, neovim-rootfs, …) arrive mode 444 / with
  # com.apple.provenance. InstallCoordination copyfile then fails with
  # NSPOSIXErrorDomain 13 when installing into the Simulator. Make the whole
  # .app writable and strip copy-blocking xattrs before Xcode's install step.
  simInstallWritableBundleScript = pkgs.writeShellScript "sim-install-writable-bundle.sh" ''
    case "''${PLATFORM_NAME:-}" in
      *simulator*)
        ;;
      *)
        exit 0
        ;;
    esac
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    if [ ! -d "$BUNDLE" ]; then
      exit 0
    fi
    chmod -R u+w "$BUNDLE" 2>/dev/null || true
    /usr/bin/xattr -cr "$BUNDLE" 2>/dev/null || true
    echo "Simulator install prep: writable + cleared xattrs on $BUNDLE"
  '';

  simInstallWritableBundlePhase = {
    path = simInstallWritableBundleScript;
    name = "Prep bundle for Simulator install (chmod/xattr)";
    basedOnDependencyAnalysis = false;
  };

  # Single source of truth for the GPU-capable Apple-mobile targets
  # (iOS, iPadOS, visionOS. The three that must ship niri/fuzzel data, the
  # VM/container embeds, and bundled ANGLE per wawona-platform-targets).
  # ALWAYS call this from those three targets' postBuildScripts instead of
  # hand-listing phases per target: a hand-maintained per-target list is
  # exactly how Wawona-iPadOS silently drifted from Wawona-iOS and shipped
  # without libEGL/libGLESv2 (dyld "Library not loaded: @rpath/libEGL...").
  # tvOS/watchOS intentionally do NOT call this. They must never get
  # ANGLE/Vulkan/OpenGL or VM/container embeds (native + remote only).
  mkAppleGpuPostBuildPhases = { rootfsEmbedPhase, neovimRootfsEmbedPhase }:
    [ xkbEmbedPhase fontEmbedPhase westonDataEmbedPhase niriDataEmbedPhase appsCatalogEmbedPhase rootfsEmbedPhase neovimRootfsEmbedPhase ]
    ++ mobileVmEmbedPhases
    ++ lib.optionals (angleSimDylib != null) [ angleSimEmbedPhase ]
    ++ lib.optionals (angleDeviceDylib != null) [ angleDeviceEmbedPhase ]
    ++ lib.optionals (swiftshaderSimLib != null) [ swiftshaderSimEmbedPhase ]
    ++ [ simInstallWritableBundlePhase ];

  iosPostBuildPhases = mkAppleGpuPostBuildPhases {
    rootfsEmbedPhase = iosRootfsEmbedPhase;
    neovimRootfsEmbedPhase = iosNeovimRootfsEmbedPhase;
  };

  # #138 root cause: src/resources/app-bundle/Info.plist is shared verbatim
  # (GENERATE_INFOPLIST_FILE=NO) across iOS/iPadOS/tvOS/macOS/visionOS and
  # used to hardcode CFBundleSupportedPlatforms=[iPhoneOS] + LSRequiresIPhoneOS
  # =true. `xcodebuild -exportArchive` reads CFBundleSupportedPlatforms. NOT
  # DTPlatformName/DTSDKName, both of which are correctly appletvos in a tvOS
  # .xcarchive. To decide the archive's "current platform". A tvOS archive
  # whose Info.plist still said iPhoneOS made exportArchive believe it was
  # exporting an iOS archive, so it rejected the (correctly tvOS) provisioning
  # profile: "has platform tvOS, which does not match the current platform
  # iOS". CFBundleSupportedPlatforms is now removed from the shared source
  # plist entirely (see Info.plist) so ProcessInfoPlistFile auto-injects the
  # correct per-target value (iPhoneOS/AppleTVOS/MacOSX/XROS) instead. This
  # also fixed a second, same-root-cause bug where Xcode's own
  # ValidateEmbeddedBinary misread an iOS-Simulator host as plain "iOS"
  # device because of the hardcoded value, and rejected the (correctly
  # watchOS-Simulator) embedded WawonaWatch.app. LSRequiresIPhoneOS +
  # UISupportedInterfaceOrientations~ipad are iOS/iPadOS-only keys that stay
  # hardcoded in source (iOS/iPadOS correctly need them); strip them here for
  # every non-iOS/-iPadOS app target. Same bug class already fixed for
  # watchOS below ("Strip iOS-only keys from Watch Info.plist").
  stripIOSOnlyInfoPlistKeysPhase = {
    name = "Strip iOS-only keys from Info.plist (#138)";
    basedOnDependencyAnalysis = false;
    script = ''
      PLIST="''${TARGET_BUILD_DIR}/''${INFOPLIST_PATH}"
      if [ -f "$PLIST" ]; then
        /usr/libexec/PlistBuddy -c 'Delete :LSRequiresIPhoneOS' "$PLIST" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c 'Delete :UISupportedInterfaceOrientations~ipad' "$PLIST" 2>/dev/null || true
      fi
    '';
  };

  westonDataIosEmbedScript = pkgs.writeShellScript "embed-weston-data-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator|watchos|watchsimulator)
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
    chmod -R u+w "$WESTON_DEST" "$ICONS_DEST" 2>/dev/null || true
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

  niriDataIosEmbedScript = deviceNiri: simNiri: pkgs.writeShellScript "embed-niri-data-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator|watchos|watchsimulator)
        ;;
      *)
        exit 0
        ;;
    esac
    case "''${PLATFORM_NAME:-}" in
      *simulator*)
        niriSrc="${strip simNiri}/share/niri/default-config.kdl"
        ;;
      *)
        niriSrc="${strip deviceNiri}/share/niri/default-config.kdl"
        ;;
    esac
    if [ ! -f "$niriSrc" ]; then
      echo "warning: niri default-config.kdl not built for this platform" >&2
      exit 0
    fi
    BUNDLE="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
    DEST="$BUNDLE/share/niri"
    mkdir -p "$DEST"
    cp -L "$niriSrc" "$DEST/default-config.kdl"
    chmod -R u+w "$DEST" 2>/dev/null || true
    echo "Embedded niri default-config.kdl into $DEST"
  '';

  niriDataEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/share/niri/default-config.kdl"
  ];

  mkNiriDataEmbedPhase = deviceDeps: simDeps: {
    path = niriDataIosEmbedScript
      (if simulatorOnly then null else (deviceDeps.niri or null))
      (simDeps.niri or null);
    name = "Embed niri config (default-config.kdl)";
    basedOnDependencyAnalysis = true;
    outputFiles = niriDataEmbedOutputs;
  };
  niriDataEmbedPhase = mkNiriDataEmbedPhase iosDeps iosSimDeps;
  tvosNiriDataEmbedPhase = mkNiriDataEmbedPhase tvosDeps tvosSimDeps;
  watchosNiriDataEmbedPhase = mkNiriDataEmbedPhase watchosDeps watchosSimDeps;

  rootfsIosEmbedScript = deviceRootfs: simRootfs: pkgs.writeShellScript "embed-rootfs-ios.sh" ''
    case "''${PLATFORM_NAME:-}" in
      iphoneos|appletvos|xros|watchos)
        rootfsSrc="${strip deviceRootfs}/rootfs"
        ;;
      iphonesimulator|appletvsimulator|xrsimulator|watchsimulator)
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
    # /nix/store is read-only (dr-xr-xr-x dirs, -r--r--r-- files) by design;
    # plain cp -R preserves that mode verbatim into the embedded copy. A
    # read-only *directory* in the app bundle then breaks anything that later
    # needs to add/replace entries under it. Notably the iOS Simulator's own
    # install/copy machinery (MobileInstallation), which fails the whole
    # `simctl install` with a bare "Permission denied" deep inside this tree
    # (no relation to code signing). Make the embedded copy writable so it
    # behaves like a normal bundle resource, not a read-only store path.
    chmod -R u+w "$DEST"
    # App Store Connect treats +x files under the app as unsigned code objects
    # (altool 90034 on zsh Functions/* when the watch companion embeds rootfs).
    # Rootfs is resource data. Strip execute bits after copy.
    find "$DEST" -type f -exec chmod a-x {} + 2>/dev/null || true
    # Watch companion IPAs are scanned more aggressively: ASC flags share
    # scripts (Etc/*.pl, Functions, …) as unsigned code even without +x.
    # Keep etc/zsh templates; drop the entire usr/share/zsh tree and any
    # leftover interpreter scripts under the watch rootfs.
    case "''${PLATFORM_NAME:-}" in
      watchos|watchsimulator)
        rm -rf "$DEST/usr/share/zsh" 2>/dev/null || true
        find "$DEST" \( \
          -name '*.pl' -o -name '*.py' -o -name '*.rb' -o \
          -name '*.sh' -o -name '*.bash' -o -name '*.zsh' \
        \) -type f -delete 2>/dev/null || true
        ;;
    esac
    echo "Embedded wawona-rootfs into $DEST (template $(cat "$DEST/etc/zsh/.template-version" 2>/dev/null || echo unknown))"
  '';

  rootfsEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/wawona-rootfs/etc/zsh/zshrc.template"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/wawona-rootfs/etc/zsh/.template-version"
  ];

  iosRootfsEmbedPhase = {
    path = rootfsIosEmbedScript
      (if simulatorOnly then null else (iosDeps."wawona-rootfs" or null))
      (iosSimDeps."wawona-rootfs" or null);
    name = "Embed wawona-rootfs (shell templates)";
    basedOnDependencyAnalysis = true;
    outputFiles = rootfsEmbedOutputs;
  };

  ipadosRootfsEmbedPhase = {
    path = rootfsIosEmbedScript
      (if simulatorOnly then null else (ipadosDeps."wawona-rootfs" or null))
      (ipadosSimDeps."wawona-rootfs" or null);
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
      iphoneos|appletvos|xros|watchos)
        rootfsSrc="${strip deviceRootfs}/rootfs"
        ;;
      iphonesimulator|appletvsimulator|xrsimulator|watchsimulator)
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
    # See the matching comment in rootfsIosEmbedScript: /nix/store dirs are
    # read-only and cp -R preserves that mode, which breaks Simulator install
    # (MobileInstallation "Permission denied") and any later rebuild that
    # needs to overwrite this tree. Make the embedded copy writable.
    chmod -R u+w "$DEST"
    echo "Embedded neovim-rootfs into $DEST"
  '';

  neovimRootfsEmbedOutputs = [
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/neovim-rootfs/etc/nvim/init.lua.template"
    "$(BUILT_PRODUCTS_DIR)/$(FULL_PRODUCT_NAME)/neovim-rootfs/usr/share/nvim/runtime"
  ];

  iosNeovimRootfsEmbedPhase = {
    path = neovimRootfsIosEmbedScript
      (if simulatorOnly then null else (iosDeps."neovim-rootfs" or null))
      (iosSimDeps."neovim-rootfs" or null);
    name = "Embed neovim-rootfs (runtime templates)";
    basedOnDependencyAnalysis = true;
    outputFiles = neovimRootfsEmbedOutputs;
  };

  ipadosNeovimRootfsEmbedPhase = {
    path = neovimRootfsIosEmbedScript
      (if simulatorOnly then null else (ipadosDeps."neovim-rootfs" or null))
      (ipadosSimDeps."neovim-rootfs" or null);
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
    # Built via buildForVisionOS. Do not embed the iOS rootfs tree as a
    # fallback (same "one archive per platform" rule as OTHER_LDFLAGS).
    path = rootfsIosEmbedScript
      (visionosDeps."wawona-rootfs" or null)
      (visionosSimDeps."wawona-rootfs" or null);
    name = "Embed wawona-rootfs (shell templates)";
    basedOnDependencyAnalysis = false;
  };

  visionosNeovimRootfsEmbedPhase = {
    path = neovimRootfsIosEmbedScript (visionosDeps."neovim-rootfs" or null) (visionosSimDeps."neovim-rootfs" or null);
    name = "Embed neovim-rootfs (runtime templates)";
    basedOnDependencyAnalysis = false;
  };

  # watchOS rootfs embed (in-process zsh; neovim-rootfs optional / often absent).
  watchosRootfsEmbedPhase = {
    path = rootfsIosEmbedScript
      (watchosDeps."wawona-rootfs" or iosDeps."wawona-rootfs" or null)
      (watchosSimDeps."wawona-rootfs" or iosSimDeps."wawona-rootfs" or null);
    name = "Embed wawona-rootfs (shell templates)";
    basedOnDependencyAnalysis = false;
  };

  # src/core is entirely Rust (0 C/ObjC files). Excluded entirely
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

  # WWNMachineEditorView (src/platform/macos/ui/Machines) uses EnvironmentVariablesView.
  # That type lives under Sources/WawonaUI, which macOS embeds as a whole tree but
  # Apple-mobile app targets do not. Compile the minimal Settings UI pieces so
  # iOS/iPadOS/tvOS/visionOS resolve the type (and ObjC can NSClassFromString the
  # presenter). Do not add these to macOS (already covered by Sources/WawonaUI)
  # or watchOS (no WWNMachineEditorView).
  appleMobileEnvUISources = [
    { path = "Sources/WawonaUI/Settings/EnvironmentVariablesView.swift"; type = "file"; }
    { path = "Sources/WawonaUI/Settings/WWNEnvironmentSettingsPresenter.swift"; type = "file"; }
    { path = "Sources/WawonaUI/View+WawonaTextField.swift"; type = "file"; }
    { path = "Sources/WawonaUI/MachineRuntimeSettingsApplicator.swift"; type = "file"; }
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
          # WWNGetprognameStub.c is force-loaded via prebuild archive (not compiled here).
          { path = "src/platform/ios"; excludes = commonExcludes ++ [ "WWNWaypipeRunnerVisionStub.m" "WWNGetprognameStub.c" ]; }
          {
            path = "src/platform/macos/ui/Machines";
            excludes = commonExcludes ++ [
              "WWNSwingingBridgeController.m" "WWNSwingingBridgeController.h"
              "WWNDesktopReplacementController.m" "WWNDesktopReplacementController.h"
            ];
          }
          {
            path = "src/platform/macos/ui/Settings";
            excludes = commonExcludes ++ [ "WWNSipStatus.m" "WWNSipStatus.h" ];
          }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          # Required-reason API manifest (UserDefaults / boot time / file timestamps).
          # Missing this makes ASC accept the IPA then discard the build (never listed).
          { path = "src/resources/app-bundle/PrivacyInfo.xcprivacy"; type = "file"; buildPhase = "resources"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ] ++ iosUtilSources ++ appleMobileEnvUISources;
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
            # Universal phone+iPad so TestFlight does not need a second IPA with the
            # same bundle id / CFBundleVersion (duplicate ASC build number).
            TARGETED_DEVICE_FAMILY = "1,2";
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
            # App target only (never the WawonaModel/WawonaUIContracts framework
            # targets. Mixed settings there causes ASC ITMS-90429/90427: Xcode's
            # real "Embed Frameworks" phase must run swift-stdlib-tool so the
            # exported IPA gets Frameworks/libswift*.dylib matching whatever
            # SwiftSupport/ the export step (or our toolchain fallback) produces.
            ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = "YES";
            LD_RUNPATH_SEARCH_PATHS = [ "$(inherited)" "@executable_path/Frameworks" ];
            LD_CLIENT_NAME = "SwiftUI";
            "OTHER_CFLAGS[sdk=iphonesimulator*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=iphonesimulator*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]" = ios26SwiftLibSearchPaths;
            # Do not add SubFrameworks (UIUtilities / SwiftUICore). Same as tvOS.
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
             ++ (ilandGlLdflags { deps = iosSimDeps; simulator = true; }) ++ moltenvkLdflags iosSimDeps ++ footLdflags iosSimDeps ++ fastfetchLdflags iosSimDeps ++ phoonLdflags iosSimDeps ++ wasmLdflags iosSimDeps ++ neovimLdflags iosSimDeps ++ niriLdflags iosSimDeps ++ fuzzelLdflags iosSimDeps
             ++ sshCliLdflags iosSimDeps
             ++ appleMobileResolvLdflags
             ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
            GCC_PREPROCESSOR_DEFINITIONS = [
              "$(inherited)"
              "TARGET_OS_IPHONE=1"
              "PRODUCT_BUNDLE_IDENTIFIER=\\\"com.aspauldingcode.Wawona\\\""
            ] ++ versionDefs;
            "HEADER_SEARCH_PATHS[sdk=iphonesimulator*]" = [
              "$(inherited)"
              "${strip (iosSimDeps.libwayland or null)}/include"
              "${strip (iosSimDeps.libwayland or null)}/include/wayland"
              "${strip (iosSimDeps.xkbcommon or null)}/include"
              "${strip (iosSimDeps.libssh2 or null)}/include"
            ] ++ (pixmanHeaderPaths iosSimDeps) ++ (ilandGlHeaderPaths iosSimDeps);
          } // lib.optionalAttrs (!simulatorOnly) {
            "OTHER_CFLAGS[sdk=iphoneos*]" = [ "$(inherited)" ] ++ ios26ObjcAutolinkOff;
            "OTHER_SWIFT_FLAGS[sdk=iphoneos*]" = [ "$(inherited)" ] ++ ios26SwiftAutolinkOff;
            "LIBRARY_SEARCH_PATHS[sdk=iphoneos*]" = ios26SwiftLibSearchPaths;
            "OTHER_LDFLAGS[sdk=iphoneos*]" = [
              "$(inherited)"
            ] ++ mobileGetprognameLdflags ++ ios26SwiftUiClientLdflags ++ [
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
             ++ (ilandGlLdflags { deps = iosDeps; simulator = false; }) ++ moltenvkLdflags iosDeps ++ footLdflags iosDeps ++ fastfetchLdflags iosDeps ++ phoonLdflags iosDeps ++ wasmLdflags iosDeps ++ neovimLdflags iosDeps ++ niriLdflags iosDeps ++ fuzzelLdflags iosDeps
             ++ sshCliLdflags iosDeps
             ++ appleMobileResolvLdflags
             ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
            "HEADER_SEARCH_PATHS[sdk=iphoneos*]" = [
              "$(inherited)"
              "${strip (iosDeps.libwayland or null)}/include"
              "${strip (iosDeps.libwayland or null)}/include/wayland"
              "${strip (iosDeps.xkbcommon or null)}/include"
              "${strip (iosDeps.libssh2 or null)}/include"
            ] ++ (pixmanHeaderPaths iosDeps) ++ (ilandGlHeaderPaths iosDeps);
          };
        };
        dependencies = [
          { target = "WawonaModel"; embed = true; codeSign = true; }
          { target = "WawonaUIContracts"; embed = true; codeSign = true; }
          # Companion for TestFlight/App Store (bare watch archive has no
          # app-store export on Xcode 26). Do not also embed into iPadOS.
          { target = "Wawona-watchOS"; embed = true; codeSign = true; }
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
          { sdk = "WatchConnectivity.framework"; }
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
          # WWNGetprognameStub.c is force-loaded via prebuild archive (not compiled here).
          { path = "src/platform/ios"; excludes = commonExcludes ++ [ "WWNWaypipeRunnerVisionStub.m" "WWNGetprognameStub.c" ]; }
          {
            path = "src/platform/macos/ui/Machines";
            excludes = commonExcludes ++ [
              "WWNSwingingBridgeController.m" "WWNSwingingBridgeController.h"
              "WWNDesktopReplacementController.m" "WWNDesktopReplacementController.h"
            ];
          }
          {
            path = "src/platform/macos/ui/Settings";
            excludes = commonExcludes ++ [ "WWNSipStatus.m" "WWNSipStatus.h" ];
          }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          # Required-reason API manifest (UserDefaults / boot time / file timestamps).
          # Missing this makes ASC accept the IPA then discard the build (never listed).
          { path = "src/resources/app-bundle/PrivacyInfo.xcprivacy"; type = "file"; buildPhase = "resources"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ] ++ iosUtilSources ++ appleMobileEnvUISources;
        preBuildScripts = [ stampBuildNumberPhase ipadosPreBuild ];
        # mkAppleGpuPostBuildPhases keeps this permanently in sync with
        # Wawona-iOS/Wawona-visionOS (niri data / fuzzel apps catalog / VM
        # embeds / ANGLE). See its definition for why this must never go
        # back to a hand-maintained per-target list.
        postBuildScripts = mkAppleGpuPostBuildPhases {
          rootfsEmbedPhase = ipadosRootfsEmbedPhase;
          neovimRootfsEmbedPhase = ipadosNeovimRootfsEmbedPhase;
        };

        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            CODE_SIGN_ENTITLEMENTS = "src/resources/app-bundle/Wawona-iCloud.entitlements";
            # Must match AppIcon.appiconset (iPad 152x152 etc). Empty name → ITMS-90713/90023.
            ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon";
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
            # Do not add SubFrameworks (UIUtilities / SwiftUICore). Same as tvOS.
            "OTHER_LDFLAGS[sdk=iphoneos*]" = [
              "$(inherited)"
            ] ++ mobileGetprognameLdflags ++ ios26SwiftUiClientLdflags ++ [
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
            ++ (ilandGlLdflags { deps = ipadosDeps; simulator = false; }) ++ moltenvkLdflags ipadosDeps ++ footLdflags ipadosDeps ++ fastfetchLdflags ipadosDeps ++ phoonLdflags ipadosDeps ++ wasmLdflags ipadosDeps ++ neovimLdflags ipadosDeps ++ niriLdflags ipadosDeps ++ fuzzelLdflags ipadosDeps
            ++ sshCliLdflags ipadosDeps
             ++ appleMobileResolvLdflags
            ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
            ++ (ilandGlLdflags { deps = ipadosSimDeps; simulator = true; }) ++ moltenvkLdflags ipadosSimDeps ++ footLdflags ipadosSimDeps ++ fastfetchLdflags ipadosSimDeps ++ phoonLdflags ipadosSimDeps ++ wasmLdflags ipadosSimDeps ++ neovimLdflags ipadosSimDeps ++ niriLdflags ipadosSimDeps ++ fuzzelLdflags ipadosSimDeps
            ++ sshCliLdflags ipadosSimDeps
             ++ appleMobileResolvLdflags
            ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
          { sdk = "WatchConnectivity.framework"; }
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
          # Real WWNIlandPresenter.m pulls ANGLE/iland; use the tv/watch stub.
          # Optional C stubs cover dispatch symbols Darwin will not leave undefined.
          { path = "src/platform/ios"; excludes = commonExcludes ++ [
            "WWNWaypipeRunnerVisionStub.m"
            "WWNGetprognameStub.c"
            "WWNIlandPresenter.m"
          ]; }
          {
            path = "src/platform/macos/ui/Machines";
            excludes = commonExcludes ++ [
              "WWNSwingingBridgeController.m" "WWNSwingingBridgeController.h"
              "WWNDesktopReplacementController.m" "WWNDesktopReplacementController.h"
            ];
          }
          {
            path = "src/platform/macos/ui/Settings";
            excludes = commonExcludes ++ [ "WWNSipStatus.m" "WWNSipStatus.h" ];
          }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          # Required-reason API manifest (UserDefaults / boot time / file timestamps).
          # Missing this makes ASC accept the IPA then discard the build (never listed).
          { path = "src/resources/app-bundle/PrivacyInfo.xcprivacy"; type = "file"; buildPhase = "resources"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ] ++ iosUtilSources ++ appleMobileEnvUISources;
        preBuildScripts = [ stampBuildNumberPhase tvosPreBuild ];
        # No ANGLE embed / no VM guest on tvOS (platform-targets: no GL, no VM).
        # appsCatalogEmbedPhase is cheap and already gates on appletvos|appletvsimulator
        # so nested niri/fuzzel can resolve .desktop entries from the share tree.
        postBuildScripts = [ xkbEmbedPhase fontEmbedPhase westonDataEmbedPhase tvosNiriDataEmbedPhase appsCatalogEmbedPhase tvosRootfsEmbedPhase tvosNeovimRootfsEmbedPhase simInstallWritableBundlePhase stripIOSOnlyInfoPlistKeysPhase ];

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
            ] ++ mobileGetprognameLdflags ++ ios26SwiftUiClientLdflags ++ [
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
              # niri's wayland-egl crate references wl_egl_window_* even on the
              # software-only tvOS surface.
              "-lwayland-egl"
            # phoon lazy-linked (see phoonLdflags): -lphoon_rs after niri's
            # force-load so std/core dedupe (no duplicate symbols) while phoon is
            # still bundled on tvOS.
            ] ++ westonToytoolkitLdflagsAppleMobile tvosDeps ++ westonCompositorLdflagsAppleMobile tvosDeps ++ niriLdflags tvosDeps ++ footLdflags tvosDeps ++ fastfetchLdflags tvosDeps ++ phoonLdflags tvosDeps ++ wasmLdflags tvosDeps
            ++ sshCliLdflags tvosDeps
             ++ appleMobileResolvLdflags
            ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ "-liconv" derivedRustLib ] ++ finalCxxLdflagsNoIokit;
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
              "-lwayland-egl"
            # phoon lazy-linked on tvOS sim too (see tvOS device block).
            ] ++ westonToytoolkitLdflagsAppleMobile tvosSimDeps ++ westonCompositorLdflagsAppleMobile tvosSimDeps ++ niriLdflags tvosSimDeps ++ footLdflags tvosSimDeps ++ fastfetchLdflags tvosSimDeps ++ phoonLdflags tvosSimDeps ++ wasmLdflags tvosSimDeps
            ++ sshCliLdflags tvosSimDeps
             ++ appleMobileResolvLdflags
            ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ "-liconv" derivedRustLib ] ++ finalCxxLdflagsNoIokit;
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
          # Required-reason API manifest (UserDefaults / boot time / file timestamps).
          # Missing this makes ASC accept the IPA then discard the build (never listed).
          { path = "src/resources/app-bundle/PrivacyInfo.xcprivacy"; type = "file"; buildPhase = "resources"; }
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
              PHOON_BIN="${strip macosPhoon}/bin"
              NEOVIM_BIN="${strip macosNeovim}/bin"
              ZSH_BIN="${strip macosZsh}/bin"
              KMSCUBE_BIN="${strip macosKmscube}/bin"
              OPENGL_CUBE_BIN="${strip macosOpenglCube}/bin"
              VKCUBE_BIN="${strip macosVkcube}/bin"
              WESTON_SIMPLE_EGL_BIN="${strip macosWestonSimpleEgl}/bin"
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

              # Fail the build when a required nested-client binary is missing
              # from the Nix store path baked into this script (silent skip left
              # macOS Debug apps without niri/fuzzel).
              require_bin() {
                src="$1"
                name="$2"
                if [ ! -f "$src" ]; then
                  echo "error: required bundled binary missing: $name ($src)" >&2
                  exit 1
                fi
                bundle_bin "$src" "$name"
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
              [ -f "$PHOON_BIN/phoon" ] && bundle_bin "$PHOON_BIN/phoon" "phoon"
              bundle_bin "$NEOVIM_BIN/nvim" "nvim"
              bundle_bin "$NEOVIM_BIN/nvim" "vi"
              bundle_bin "$NEOVIM_BIN/nvim" "vim"
              bundle_bin "$ZSH_BIN/zsh" "zsh"
              require_bin "$KMSCUBE_BIN/kmscube" "kmscube"
              # Wayland clients: Machines Start launches these as NSTasks against
              # the compositor socket. Archives (opengl_cube_main / vkcube_main)
              # remain linked for the iOS-family in-process path.
              if [ -f "$OPENGL_CUBE_BIN/opengl-cube" ]; then
                bundle_bin "$OPENGL_CUBE_BIN/opengl-cube" "opengl-cube"
              fi
              require_bin "$VKCUBE_BIN/vkcube" "vkcube"
              require_bin "$WESTON_SIMPLE_EGL_BIN/weston-simple-egl" "weston-simple-egl"

              # niri (wwn-niri): nested scrollable-tiling compositor. Ship the
              # binary plus its read-only KDL config, resolved at runtime via
              # WAWONA_SHARE_ROOT (Contents/Resources/share/niri).
              require_bin "$NIRI_BIN/niri" "niri"
              if [ ! -f "$NIRI_CFG" ]; then
                echo "error: required niri config missing: $NIRI_CFG" >&2
                exit 1
              fi
              SHARE_NIRI="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/share/niri"
              mkdir -p "$SHARE_NIRI"
              install -m 644 "$NIRI_CFG" "$SHARE_NIRI/default-config.kdl"
              echo "Bundled niri default-config.kdl"

              # fuzzel (wwn-niri): niri's Mod+D launcher; must be on PATH when
              # niri spawns child processes (see WWNWaypipeRunner niri env).
              require_bin "$FUZZEL_BIN/fuzzel" "fuzzel"

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
              rm -rf "$RES_DEST/share/fonts"
              mkdir -p "$RES_DEST/share/fonts"
              cp -RL "${wawonaBundledFonts}/share/fonts/." "$RES_DEST/share/fonts/"
              chmod -R u+w "$RES_DEST/share/fonts"
              echo "Bundled Wawona fonts (DejaVu + DejaVuSansM Nerd Font Mono)"
              CURSOR_SRC="${pkgs.adwaita-icon-theme}/share/icons/Adwaita/cursors"
              if [ -d "$CURSOR_SRC" ]; then
                mkdir -p "$RES_DEST/share/icons/Adwaita"
                cp -RL "$CURSOR_SRC" "$RES_DEST/share/icons/Adwaita/cursors"
                chmod -R u+w "$RES_DEST/share/icons/Adwaita/cursors"
                echo "Bundled Adwaita cursors"
              fi

              # Freedesktop catalog for fuzzel Mod+D (issue #78).
              # macOS .app may only have Contents/ at the bundle root -
              # app-root share/ makes codesign fail with "unsealed contents".
              # WWNWawonaShareRoot already prefers Contents/Resources/share
              # when it contains applications/.
              APPS_CATALOG="${applicationsCatalog}"
              if [ -d "$APPS_CATALOG/share/applications" ]; then
                mkdir -p "$RES_DEST/share/applications" "$RES_DEST/share/icons"
                cp -R "$APPS_CATALOG/share/applications/." "$RES_DEST/share/applications/"
                cp -R "$APPS_CATALOG/share/icons/hicolor" "$RES_DEST/share/icons/"
                chmod -R u+w "$RES_DEST/share/applications" "$RES_DEST/share/icons/hicolor"
                echo "Bundled fuzzel applications catalog"
              fi

              # ----------------------------------------------------------------
              # Make the app self-contained: copy every non-system dylib the
              # app + bundled helpers link by absolute /nix/store path into
              # Contents/Frameworks and rewrite the load commands to @rpath.
              # Xcode links Rust/native code against /nix/store/.../*.dylib
              # (pixman, cairo, pango, glib, openssl, weston, ...). Those paths
              # exist only on this build machine, so a copied/exported app. Or
              # one run after `nix` GC removes the store path. Aborts at launch
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

              # Idempotent rpath add. Repeated script runs (incremental builds)
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
                  # Keep every @-relative rpath (@executable_path/@loader_path) -
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
          stripIOSOnlyInfoPlistKeysPhase
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
              "-L${strip (macosDeps.epoll-shim or null)}/lib"
              "-L${pkgs.openssl.out}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              # -lwayland-server is provided by westonCompositorLdflags below;
              # listing it here too triggers "ignoring duplicate libraries".
              "-lpixman-1"
              "-lepoll-shim"
              "-lssl"
              "-lcrypto"
              "-lz"
              derivedRustLib
            ] ++ (ilandGlLdflags { deps = macosDeps; simulator = false; })
              ++ (westonToytoolkitLdflagsMacos macosDeps)
              ++ (westonCompositorLdflags macosDeps)
              ++ (wasmLdflags macosDeps)
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
          # Real waypipe runner (not VisionStub). VisionOS macOS-parity remote.
          { path = "src/platform/ios"; excludes = commonExcludes ++ [ "WWNGetprognameStub.c" "WWNWaypipeRunnerVisionStub.m" ]; }
          {
            path = "src/platform/macos/ui/Machines";
            excludes = commonExcludes ++ [
              "WWNSwingingBridgeController.m"
              "WWNSwingingBridgeController.h"
              "WWNDesktopReplacementController.m"
              "WWNDesktopReplacementController.h"
            ];
          }
          {
            path = "src/platform/macos/ui/Settings";
            excludes = commonExcludes ++ [
              "WWNSipStatus.m"
              "WWNSipStatus.h"
            ];
          }
          { path = "src/platform/macos/ui/Helpers"; excludes = commonExcludes; }
          { path = "src/resources/Assets.xcassets"; }
          # Required-reason API manifest (UserDefaults / boot time / file timestamps).
          # Missing this makes ASC accept the IPA then discard the build (never listed).
          { path = "src/resources/app-bundle/PrivacyInfo.xcprivacy"; type = "file"; buildPhase = "resources"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
          { path = "src/resources/Wawona-iOS-Dark-1024x1024@1x.png"; type = "file"; }
        ] ++ iosUtilSources ++ appleMobileEnvUISources;
        preBuildScripts = [ stampBuildNumberPhase visionosPreBuild ];
        # mkAppleGpuPostBuildPhases. See Wawona-iOS/-iPadOS. This also fixes
        # visionOS previously missing niri data / fuzzel apps catalog, which
        # macOS-parity (wawona-platform-targets) requires it to have.
        postBuildScripts = mkAppleGpuPostBuildPhases {
          rootfsEmbedPhase = visionosRootfsEmbedPhase;
          neovimRootfsEmbedPhase = visionosNeovimRootfsEmbedPhase;
        } ++ [ stripIOSOnlyInfoPlistKeysPhase ];
        settings = {
          base = {
            INFOPLIST_FILE = "src/resources/app-bundle/Info.plist";
            GENERATE_INFOPLIST_FILE = "NO";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona";
            CODE_SIGN_ENTITLEMENTS = "src/resources/app-bundle/Wawona-iCloud.entitlements";
            # visionOS uses AppIcon.solidimagestack (not tvOS Wawona.brandassets).
            ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon";
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
            # Network stack is built via buildForVisionOS (zstd/lz4/mbedtls
            # visionos.nix). Do not fall back to iosDeps here. Mixing iOS and
            # visionOS archives in one Ld pulls two copies of shared objects.
            "OTHER_LDFLAGS[sdk=xros*]" = [
              "$(inherited)"
            ] ++ mobileGetprognameLdflags ++ ios26SwiftUiClientLdflags ++ [
              "-L${strip (visionosDeps.libwayland or null)}/lib"
              "-L${strip (visionosDeps.xkbcommon or null)}/lib"
              "-L${strip (visionosDeps.libffi or null)}/lib"
              "-L${strip (visionosDeps.pixman or null)}/lib"
              "-L${strip (visionosDeps.zstd or null)}/lib"
              "-L${strip (visionosDeps.lz4 or null)}/lib"
              "-L${strip (visionosDeps.epoll-shim or null)}/lib"
              "-L${strip (visionosDeps.libssh2 or null)}/lib"
              "-L${strip (visionosDeps.mbedtls or null)}/lib"
              "-L${strip (visionosDeps.openssl or null)}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lffi"
              "-lpixman-1"
              "-lzstd"
              "-llz4"
              "-lz"
              "-lepoll-shim"
              "-lssh2"
              "-lmbedcrypto"
              "-lmbedx509"
              "-lmbedtls"
              "-lssl"
              "-lcrypto"
              "-lwayland-egl"
            ] ++ westonToytoolkitLdflagsAppleMobile visionosDeps ++ westonCompositorLdflagsAppleMobile visionosDeps
            ++ (ilandGlLdflags { deps = visionosDeps; simulator = false; }) ++ moltenvkLdflags visionosDeps ++ footLdflags visionosDeps ++ fastfetchLdflags visionosDeps ++ phoonLdflags visionosDeps ++ wasmLdflags visionosDeps ++ neovimLdflags visionosDeps ++ niriLdflags visionosDeps ++ fuzzelLdflags visionosDeps
            ++ sshCliLdflags visionosDeps
             ++ appleMobileResolvLdflags
            ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
            "OTHER_LDFLAGS[sdk=xrsimulator*]" = [
              "$(inherited)"
            ] ++ ios26SwiftUiClientLdflags ++ [
              "-L${strip (visionosSimDeps.libwayland or null)}/lib"
              "-L${strip (visionosSimDeps.xkbcommon or null)}/lib"
              "-L${strip (visionosSimDeps.libffi or null)}/lib"
              "-L${strip (visionosSimDeps.pixman or null)}/lib"
              "-L${strip (visionosSimDeps.zstd or null)}/lib"
              "-L${strip (visionosSimDeps.lz4 or null)}/lib"
              "-L${strip (visionosSimDeps.epoll-shim or null)}/lib"
              "-L${strip (visionosSimDeps.libssh2 or null)}/lib"
              "-L${strip (visionosSimDeps.mbedtls or null)}/lib"
              "-L${strip (visionosSimDeps.openssl or null)}/lib"
              "-lxkbcommon"
              "-lwayland-client"
              "-lffi"
              "-lpixman-1"
              "-lzstd"
              "-llz4"
              "-lz"
              "-lepoll-shim"
              "-lssh2"
              "-lmbedcrypto"
              "-lmbedx509"
              "-lmbedtls"
              "-lssl"
              "-lcrypto"
              "-lwayland-egl"
            ] ++ westonToytoolkitLdflagsAppleMobile visionosSimDeps ++ westonCompositorLdflagsAppleMobile visionosSimDeps
            ++ (ilandGlLdflags { deps = visionosSimDeps; simulator = true; }) ++ moltenvkLdflags visionosSimDeps ++ footLdflags visionosSimDeps ++ fastfetchLdflags visionosSimDeps ++ phoonLdflags visionosSimDeps ++ wasmLdflags visionosSimDeps ++ neovimLdflags visionosSimDeps ++ niriLdflags visionosSimDeps ++ fuzzelLdflags visionosSimDeps
            ++ sshCliLdflags visionosSimDeps
             ++ appleMobileResolvLdflags
            ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ derivedRustLib ] ++ finalCxxLdflags;
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
            ] ++ (pixmanHeaderPaths visionosDeps) ++ (ilandGlHeaderPaths visionosDeps);
            "HEADER_SEARCH_PATHS[sdk=xrsimulator*]" = [
              "$(inherited)"
              "${strip (visionosSimDeps.libwayland or null)}/include"
              "${strip (visionosSimDeps.libwayland or null)}/include/wayland"
              "${strip (visionosSimDeps.xkbcommon or null)}/include"
              "${strip (visionosSimDeps.libssh2 or null)}/include"
            ] ++ (pixmanHeaderPaths visionosSimDeps) ++ (ilandGlHeaderPaths visionosSimDeps);
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
          base = moduleVerifierFrameworkSettings // appleSimArchSettings // {
            PRODUCT_NAME = "WawonaModel";
            PRODUCT_MODULE_NAME = "WawonaModel";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.WawonaModel";
            SUPPORTED_PLATFORMS = "macosx iphoneos iphonesimulator appletvos appletvsimulator xros xrsimulator watchos watchsimulator";
            # Do NOT set SDKROOT / SDKROOT[sdk=*]. Xcode ignores SDK-conditioned
            # SDKROOT at the target level (warning: "SDK condition on SDKROOT is
            # unsupported"). A forced SDKROOT=iphoneos made Embed Frameworks
            # install iOS-simulator WawonaModel into watch apps (ISSUE-017 dyld
            # "have iOS-simulator, need watchOS-simulator"). Inherit SDKROOT
            # from the dependent app destination instead.
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
            # Never on framework targets (ASC ITMS-90429/90427): only the app
            # target's "Embed Frameworks" phase should run swift-stdlib-tool.
            ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = "NO";
            # Frameworks are re-signed on embed; a global Manual
            # PROVISIONING_PROFILE_SPECIFIER from IPA CI must not apply here.
            CODE_SIGNING_ALLOWED = "NO";
            CODE_SIGNING_REQUIRED = "NO";
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
          base = moduleVerifierFrameworkSettings // appleSimArchSettings // {
            PRODUCT_NAME = "WawonaUIContracts";
            PRODUCT_MODULE_NAME = "WawonaUIContracts";
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.WawonaUIContracts";
            SUPPORTED_PLATFORMS = "macosx iphoneos iphonesimulator appletvos appletvsimulator xros xrsimulator watchos watchsimulator";
            # Inherit SDKROOT from dependent destination (see WawonaModel / ISSUE-017).
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
            CODE_SIGNING_ALLOWED = "NO";
            CODE_SIGNING_REQUIRED = "NO";
            BUILD_LIBRARY_FOR_DISTRIBUTION = "NO";
            # Never on framework targets (ASC ITMS-90429/90427): only the app
            # target's "Embed Frameworks" phase should run swift-stdlib-tool.
            ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = "NO";
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
          # Shared SSH keygen / GPG-SSH import (libwwn-ssh-cli).
          { path = "src/platform/macos/ui/Helpers/WWNSSHKeygen.m"; type = "file"; }
          { path = "src/platform/macos/ui/Helpers/WWNSSHKeygen.h"; type = "file"; }
          # Startup log sink (same as iOS/tvOS). SwiftUI overlay on watch.
        ] ++ iosUtilSources ++ [
          { path = "src/platform/watchos/ui/Settings/WWNWatchSettings.storyboard"; }
          { path = "src/resources/Assets.xcassets"; }
          # Required-reason API manifest (UserDefaults / boot time / file timestamps).
          # Missing this makes ASC accept the IPA then discard the build (never listed).
          { path = "src/resources/app-bundle/PrivacyInfo.xcprivacy"; type = "file"; buildPhase = "resources"; }
          { path = "src/resources/Wawona.icon"; type = "folder"; }
          { path = "src/resources/Wawona.icon/Assets/wayland.png"; type = "file"; }
        ];
        preBuildScripts = [
          # Do not run stampBuildNumberPhase here: when embedded under
          # Wawona-iOS (#136) both targets would claim
          # .build/wwn-build-number.xcconfig ("Multiple commands produce").
          # Standalone Wawona-watchOS scheme still stamps via scheme preActions.
          {
            name = "Ensure Watch Framework Modules";
            basedOnDependencyAnalysis = false;
            inputFiles = [ "$(SRCROOT)/scripts/watchos-ensure-framework-modules.sh" ];
            script = ''
              exec "''${SRCROOT}/scripts/watchos-ensure-framework-modules.sh"
            '';
          }
          watchosPreBuild
        ];
        postBuildScripts = [
          # Share trees so weston-terminal/foot render (fonts for Cairo/Pango,
          # xkb for keymap resolution, weston PNGs/cursors). Without these the
          # watch terminal comes up blank. Scripts are platform-gated and
          # include watchos|watchsimulator; deps are platform-agnostic pkgs.
          xkbEmbedPhase
          fontEmbedPhase
          westonDataEmbedPhase
          watchosNiriDataEmbedPhase
          appsCatalogEmbedPhase
          watchosRootfsEmbedPhase
          {
            # Copies watch-platform WawonaModel/UIContracts (Xcode Embed is
            # off; ISSUE-017) and re-signs them with the app identity.
            # Device installd rejects unsigned Frameworks/ (0xe800801c).
            name = "Fix Watch Embedded Frameworks";
            basedOnDependencyAnalysis = false;
            inputFiles = [ "$(SRCROOT)/scripts/watchos-fix-embedded-frameworks.sh" ];
            script = ''
              exec "''${SRCROOT}/scripts/watchos-fix-embedded-frameworks.sh"
            '';
          }
          {
            # GENERATE_INFOPLIST_FILE under an iOS host project can leak
            # MinimumOSVersion~ipad / iPhone-only keys into the watch plist.
            # ASC accepts+validates then silently discards the build (never listed).
            name = "Strip iOS-only keys from Watch Info.plist";
            basedOnDependencyAnalysis = false;
            script = ''
              PLIST="''${TARGET_BUILD_DIR}/''${INFOPLIST_PATH}"
              if [ -f "$PLIST" ]; then
                /usr/libexec/PlistBuddy -c 'Delete :MinimumOSVersion~ipad' "$PLIST" 2>/dev/null || true
                /usr/libexec/PlistBuddy -c 'Delete :LSRequiresIPhoneOS' "$PLIST" 2>/dev/null || true
                /usr/libexec/PlistBuddy -c 'Delete :UISupportedInterfaceOrientations~ipad' "$PLIST" 2>/dev/null || true
              fi
            '';
          }
          simInstallWritableBundlePhase
        ];
        settings = {
          base = {
            PRODUCT_BUNDLE_IDENTIFIER = "com.aspauldingcode.Wawona.watch";
            # Distinct Swift module from the iOS host (project PRODUCT_NAME=Wawona).
            PRODUCT_NAME = "WawonaWatch";
            PRODUCT_MODULE_NAME = "WawonaWatch";
            SUPPORTED_PLATFORMS = "watchos watchsimulator";
            SDKROOT = "watchos";
            TARGETED_DEVICE_FAMILY = "4";
            # ASC 90733: MinimumOSVersion < 27.0 requires arm64_32 + arm64.
            # watchOS SDK 26.5 max deployment is 26.5 (cannot set 27.0). Ship
            # ARCHS_STANDARD; arm64_32 links weak WWNWatchStubs only (Nix
            # watch libs are arm64-only). Full native stack is arm64.
            WATCHOS_DEPLOYMENT_TARGET = "10.0";
            # Do not inherit project IPHONEOS_DEPLOYMENT_TARGET into watch Info.plist.
            IPHONEOS_DEPLOYMENT_TARGET = "";
            GENERATE_INFOPLIST_FILE = "YES";
            # Embedded companion: stay out of the iOS archive's root Products
            # so the archive remains an iOS App Store export (see #136).
            SKIP_INSTALL = "YES";
            # watch slots live in the shared AppIcon.appiconset (watch + watch-marketing).
            ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon";
            INFOPLIST_KEY_WKCompanionAppBundleIdentifier = "com.aspauldingcode.Wawona";
            INFOPLIST_KEY_CFBundleDisplayName = "Wawona";
            INFOPLIST_KEY_WKApplication = "YES";
            INFOPLIST_KEY_CFBundlePackageType = "APPL";
            SWIFT_OBJC_BRIDGING_HEADER = "src/platform/watchos/WWNWatch-Bridging-Header.h";
            SWIFT_INSTALL_OBJC_HEADER = "NO";
            # Every other app target (iOS/tvOS/macOS/visionOS) disables the
            # Simulator-only "debug dylib" launch accelerator; Wawona-watchOS
            # never got it. With it on, Xcode additionally links a
            # WawonaWatch.debug.dylib against the SAME flat, single-platform
            # WawonaModel.framework used by every platform in Nix's
            # build-app.nix (CONFIGURATION_BUILD_DIR=$out is forced globally),
            # so linking always fails: "building for watchOS-simulator, but
            # linking in dylib ... built for iOS-simulator". Even though the
            # real WawonaWatch.app link (below) succeeds because
            # watchos-ensure-framework-modules.sh merges the watchos-simulator
            # swiftmodule slice into that same $out for the *compile* step.
            # This dylib is a Debug+Simulator quick-launch optimization only
            # (never produced for Release/Archive); skipping it does not
            # affect what ships.
            ENABLE_DEBUG_DYLIB = "NO";
            # Xcode 26 explicit modules flake when the watch companion is built
            # under an iOS archive destination before framework swiftmodules exist.
            SWIFT_ENABLE_EXPLICIT_MODULES = "NO";
            CODE_SIGN_STYLE = "Automatic";
            CODE_SIGNING_ALLOWED = "YES";
            CODE_SIGNING_REQUIRED = "YES";
            "CODE_SIGNING_ALLOWED[sdk=watchsimulator*]" = "NO";
            "CODE_SIGNING_REQUIRED[sdk=watchsimulator*]" = "NO";
            # App target only (see Wawona-iOS). Required so ASC ITMS-90427
            # ("expected dylibs missing from .../WawonaWatch.app") does not fire.
            ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = "YES";
            LD_RUNPATH_SEARCH_PATHS = [ "$(inherited)" "@executable_path/Frameworks" ];
            GCC_PREPROCESSOR_DEFINITIONS = [
              "$(inherited)"
              "TARGET_OS_IPHONE=1"
              "TARGET_OS_WATCH=1"
            ];
            "VALID_ARCHS[sdk=watchos*]" = "arm64_32 arm64";
            "ARCHS[sdk=watchos*]" = "arm64_32 arm64";
            "VALID_ARCHS[sdk=watchsimulator*]" = "arm64";
            "ARCHS[sdk=watchsimulator*]" = "arm64";
            # Mini server needs libwayland-server (arm64 Nix only). arm64_32
            # uses weak wwn_wls_* stubs in WWNWatchStubs.c instead.
            "EXCLUDED_SOURCE_FILE_NAMES[arch=arm64_32]" = [
              "WWNMiniWaylandServer.c"
            ];
            HEADER_SEARCH_PATHS = [
              "$(inherited)"
              "${strip (watchosDeps.libffi or null)}/include"
              "${strip (watchosDeps.libwayland or null)}/include"
              "${strip (watchosDeps.libwayland or null)}/include/wayland"
              "${strip (watchosDeps.libssh2 or null)}/include"
              "$(SRCROOT)/src/platform/watchos"
              "$(SRCROOT)/src/platform/macos/ui/Helpers"
              "$(SRCROOT)/src/util"
            ] ++ (pixmanHeaderPaths watchosDeps);
            # WawonaModel/WawonaUIContracts are embed=false, link=false above
            # (see dependencies comment): Xcode unconditionally adds
            # -F$(CONFIGURATION_BUILD_DIR) for every target's *own* build
            # products dir regardless of dependency link/embed settings. In
            # this nix build that is the shared, single-platform $out. So
            # `-framework WawonaModel` would still resolve through -F search
            # order to whichever platform happened to build there first.
            # Bypass -framework/-F search for these two entirely: link the
            # watchos-ensure-framework-modules.sh-installed Mach-O directly by
            # absolute path (a real, never-shared-with-iOS watch build under
            # BUILD_DIR/CONFIGURATION-PLATFORM_NAME). The dylib's own
            # LC_ID_DYLIB install name (@rpath/<fw>.framework/<fw>) is what
            # ends up in WawonaWatch's load commands, so at runtime it still
            # resolves against the embedded (watch-platform, via "Fix Watch
            # Embedded Frameworks") copy in WawonaWatch.app/Frameworks. This
            # path is only ever consulted to satisfy the link step.
            OTHER_LDFLAGS = [
              "$(inherited)"
              "$(BUILD_DIR)/$(CONFIGURATION)-$(PLATFORM_NAME)/WawonaModel.framework/WawonaModel"
              "$(BUILD_DIR)/$(CONFIGURATION)-$(PLATFORM_NAME)/WawonaUIContracts.framework/WawonaUIContracts"
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
            # Full native stack is arm64-only (Nix watch libs). arm64_32 uses
            # weak WWNWatchStubs.c so the fat binary satisfies ASC 90733.
            "OTHER_LDFLAGS[sdk=watchos*][arch=arm64]" = [
              "$(inherited)"
              "-L${strip (watchosDeps.libffi or null)}/lib"
              "-L${strip (watchosDeps.libwayland or null)}/lib"
              "-L${strip (watchosDeps.epoll-shim or null)}/lib"
              "-L${strip (watchosDeps.pixman or null)}/lib"
              "-L${strip (watchosDeps.zstd or iosDeps.zstd or null)}/lib"
              "-L${strip (watchosDeps.lz4 or iosDeps.lz4 or null)}/lib"
              "-L${strip (watchosDeps.libssh2 or null)}/lib"
              "-L${strip (watchosDeps.mbedtls or iosDeps.mbedtls or null)}/lib"
              "-L${strip (watchosDeps.openssl or null)}/lib"
              "-L${strip (watchosDeps.xkbcommon or iosDeps.xkbcommon or null)}/lib"
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
              "-lxkbcommon"
              # niri's wayland-egl crate references wl_egl_window_*, which lives
              # in libwayland-egl even on the software-only watchOS surface.
              "-lwayland-egl"
            # phoon lazy-linked (see phoonLdflags), same rationale as the waypipe
            # lazy link just below: niri is force-loaded, so -lphoon_rs after it
            # dedupes std/core (no 2134 duplicate symbols) while keeping phoon
            # bundled on watchOS.
            ] ++ westonToytoolkitLdflagsAppleMobile watchosDeps ++ westonCompositorLdflagsAppleMobile watchosDeps ++ niriLdflags watchosDeps ++ footLdflags watchosDeps ++ fastfetchLdflags watchosDeps ++ phoonLdflags watchosDeps ++ neovimLdflags watchosDeps ++ [
              "-lwayland-server"
            ] ++ lib.optionals (watchosDeps ? waypipe && watchosDeps.waypipe != null) [
              # Lazy archive link, not -force_load: niri is already force-loaded
              # and both are Rust staticlibs bundling std/core, so forcing both
              # yields thousands of duplicate symbols. _waypipe_main is kept
              # alive by the global -Wl,-u in mobileDispatchLdflags.
              "-L${strip watchosDeps.waypipe}/lib"
              "-lwaypipe"
            ] ++ sshCliLdflags watchosDeps
            ++ appleMobileResolvLdflags ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ "-liconv" ] ++ lib.optionals (watchosBackend != null) [
              derivedRustLib
            ] ++ finalCxxLdflagsNoIokit;
            "OTHER_LDFLAGS[sdk=watchos*][arch=arm64_32]" = [
              "$(inherited)"
              "-liconv"
            ];
            "OTHER_LDFLAGS[sdk=watchsimulator*]" = [
              "$(inherited)"
              "-L${strip (watchosSimDeps.libffi or null)}/lib"
              "-L${strip (watchosSimDeps.libwayland or null)}/lib"
              "-L${strip (watchosSimDeps.epoll-shim or null)}/lib"
              "-L${strip (watchosSimDeps.pixman or null)}/lib"
              "-L${strip (watchosSimDeps.zstd or iosSimDeps.zstd or null)}/lib"
              "-L${strip (watchosSimDeps.lz4 or iosSimDeps.lz4 or null)}/lib"
              "-L${strip (watchosSimDeps.libssh2 or null)}/lib"
              "-L${strip (watchosSimDeps.mbedtls or iosSimDeps.mbedtls or null)}/lib"
              "-L${strip (watchosSimDeps.openssl or null)}/lib"
              # weston toytoolkit needs xkb; watch deps often omit it. Fall back to iOS.
              "-L${strip (watchosSimDeps.xkbcommon or iosSimDeps.xkbcommon or null)}/lib"
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
              "-lxkbcommon"
              "-lwayland-egl"
            # phoon lazy-linked on watchOS sim too (see watchOS device block).
            ] ++ westonToytoolkitLdflagsAppleMobile watchosSimDeps ++ westonCompositorLdflagsAppleMobile watchosSimDeps ++ niriLdflags watchosSimDeps ++ footLdflags watchosSimDeps ++ fastfetchLdflags watchosSimDeps ++ phoonLdflags watchosSimDeps ++ neovimLdflags watchosSimDeps ++ [
              "-lwayland-server"
            ] ++ lib.optionals (watchosSimDeps ? waypipe && watchosSimDeps.waypipe != null) [
              "-L${strip watchosSimDeps.waypipe}/lib"
              "-lwaypipe"
            ] ++ sshCliLdflags watchosSimDeps
            ++ appleMobileResolvLdflags ++ mobileZshLdflags ++ mobileDispatchLdflags ++ [ "-liconv" ] ++ lib.optionals (watchosSimBackend != null) [
              derivedRustLib
            ] ++ finalCxxLdflagsNoIokit;
          };
        };
        dependencies = [
          # link=false, embed=false: Nix's build-app.nix forces
          # CONFIGURATION_BUILD_DIR=$out globally, so Xcode's implicit
          # "-F$(BUILT_PRODUCTS_DIR)" for a linked-or-embedded target
          # dependency always resolves to whatever platform built
          # WawonaModel/WawonaUIContracts there first (iOS-simulator, in a
          # Wawona-iOS-embeds-Wawona-watchOS build) and keeps injecting that
          # -F ahead of anything this target's own FRAMEWORK_SEARCH_PATHS
          # adds, however link/embed are set individually. So `ld` fails:
          # "building for watchOS-simulator, but linking in dylib ... built
          # for iOS-simulator". Only turning off *both* stops Xcode adding
          # -F$out at all. Linking instead goes through the explicit
          # OTHER_LDFLAGS/FRAMEWORK_SEARCH_PATHS entries below, pointing at
          # watchos-ensure-framework-modules.sh's own per-platform install
          # (BUILD_DIR/CONFIGURATION-PLATFORM_NAME, a real watch Mach-O, never
          # shared with iOS); embedding into WawonaWatch.app/Frameworks is
          # handled by "Fix Watch Embedded Frameworks" below, which already
          # finds that same install (or rebuilds it) independent of Xcode's
          # own Embed Frameworks phase.
          { target = "WawonaModel"; embed = false; link = false; codeSign = true; }
          { target = "WawonaUIContracts"; embed = false; link = false; codeSign = true; }
          { sdk = "SwiftUI.framework"; }
          { sdk = "WatchKit.framework"; }
          { sdk = "WatchConnectivity.framework"; }
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
          # Note: filterAttrs forces attr values. Callers that care about eval
          # cost should pass empty/null unused platform deps (see flake mkXcodegen)
          # and/or simulatorOnly so forced targets do not realize heavy closures.
          lib.filterAttrs (
            name: _target:
            lib.elem name sharedXcodeTargets
            || lib.elem (targetPlatformKeys.${name} or "") platformFilter
            # iOS host embeds the watch companion for App Store / TF (#136).
            || (name == "Wawona-watchOS" && lib.elem "ios" platformFilter)
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
    for target_name in ("Wawona-iOS", "Wawona-iPadOS", "Wawona-tvOS", "Wawona-watchOS"):
        target = targets.get(target_name)
        if target is None:
            continue
        base = target.setdefault("settings", {}).setdefault("base", {})
        base["DEVELOPMENT_TEAM"] = team
p.write_text(json.dumps(data, indent=2))
EOF
    if [ -n "$EFFECTIVE_TEAM_ID" ]; then
      echo "Applied TEAM_ID=$EFFECTIVE_TEAM_ID to Wawona-iOS, Wawona-iPadOS, Wawona-tvOS, and Wawona-watchOS."
    fi
    ${xcodeUtils.xcodeWrapper}/bin/xcode-wrapper ${pkgs.xcodegen}/bin/xcodegen generate --use-cache --spec "$TMP_SPEC"

    # #ITMS-90426-watch (2026-08-08): three embed-location variants tried for
    # the "Embed Watch Content" copy phase, in order:
    #
    #  1. Legacy Watch/ (dstSubfolderSpec=16, dstPath="$(CONTENTS_FOLDER_PATH)/Watch")
    #. XcodeGen 2.44.1's own default (see
    #     https://github.com/yonaskolb/XcodeGen/issues/1613, filed against
    #     Xcode 26.4, unmerged fix in PR #1614, which claims Xcode 26 wants
    #     PlugIns/ instead). Builds 89-110 shipped this way: local archive,
    #     export, AND `xcrun altool`/`upload_to_testflight` upload all
    #     succeeded every time. ASC's *async* binary-processing pipeline
    #     rejected them, but purely over SwiftSupport/Frameworks content
    #     (ITMS-90426/90429/90433). Never over embed location or directory
    #     naming. That rotating rejection was a separate, since-fixed bug: see
    #     `embed_swift_runtime_into_archive!`/`inject_swift_support_from_archive!`
    #     in fastlane/Fastfile (SWIFT_BACKDEPLOY_LIB_NAMES). Wawona's
    #     deployment targets need zero back-deployment dylibs, so the correct
    #     IPA has no SwiftSupport/ at all, which builds 89-104 did not ship.
    #  2. Numeric dstSubfolderSpec=13/dstPath="" (PlugIns/, commit c7e3304):
    #     archives and exports fine locally, but `xcrun altool`/
    #     `upload_to_testflight` then fails immediately and locally with
    #     "[altool.CBF038400] Cannot determine the 'platform' from the
    #     info.plist. (19)". Before the ipa ever reaches ASC's servers.
    #     altool's platform detection does not expect a *different-platform*
    #     nested .app (WatchOS) under PlugIns/, which it treats as an
    #     extension-style dir sharing the host's own platform.
    #  3. String enum `dstSubfolder = PlugIns;` (some real Xcode-26-resaved
    #     projects in the wild use this, e.g. tuist/XcodeProj#1038): CocoaPods'
    #     `xcodeproj` gem (used by Fastlane's update_code_signing_settings)
    #     warns but does NOT drop it on re-save. However `xcodebuild archive`
    #     itself (Xcode 26.6 GM, this runner) does not understand it either,
    #     and fails outright ("Unknown Distribution Error", exportArchive exit
    #     70) before ever reaching ASC. Not usable on this toolchain.
    #
    # Verdict: variant 1 (XcodeGen's own unmodified default) is the only one
    # that gets all the way through `xcrun altool` upload; no real rejection
    # from Apple has ever named the Watch/ directory or embed location as a
    # problem. Leave XcodeGen's generated project.pbxproj untouched. No
    # postGenCommand patch here. If a future Xcode really enforces PlugIns/
    # at *install* time (the XcodeGen issue's claim, not yet observed against
    # this app), that will show up as a distinct, differently-worded failure
    # and should be re-diagnosed rather than reapplying variant 2 blind.

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

    # ISSUE-017: XcodeGen still emits SDKROOT=iphoneos for platform=iOS
    # frameworks even when the project.json omits it. Strip SDKROOT from
    # WawonaModel / WawonaUIContracts so Embed Frameworks inherits the app
    # destination SDK (watchsimulator → WATCHOSSIMULATOR products).
    ${pkgs.python3}/bin/python3 <<'EOF_SDK'
import re
from pathlib import Path

pbx = Path("Wawona.xcodeproj/project.pbxproj")
if pbx.exists():
    text = pbx.read_text()

    def strip_sdkroot(body: str) -> str:
        body = re.sub(r'^[ \t]*SDKROOT = [^;]+;\n', "", body, flags=re.M)
        body = re.sub(r'^[ \t]*"SDKROOT\[sdk=[^\]]+\]" = [^;]+;\n', "", body, flags=re.M)
        return body

    def repl(m: re.Match) -> str:
        header, body, footer = m.group(1), m.group(2), m.group(3)
        if re.search(r"PRODUCT_NAME = Wawona(Model|UIContracts);", body):
            body = strip_sdkroot(body)
        return header + body + footer

    text2 = re.sub(
        r"(/\* [^*]+ \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = \{)(.*?)(\n\t\t\t\};\n\t\t\tname = [^;]+;)",
        repl,
        text,
        flags=re.S,
    )
    if text2 != text:
        pbx.write_text(text2)
        print("Stripped SDKROOT from WawonaModel/WawonaUIContracts (ISSUE-017).")
EOF_SDK

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
