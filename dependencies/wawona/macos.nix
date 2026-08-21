{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  wawonaVersion ? null,
  rustBackend,
  weston,
  foot ? null,
  niri ? null,
  fuzzel ? null,
  # Swinging Bridge app-bridge static lib (libanowaw.a + anowaw_mac_shim.o) + headers,
  # from `toolchains.buildForMacOS "anowaw"`. When null the compositor still
  # builds; WWNSwingingBridgeController falls back to its no-op stub (see common.nix).
  anowaw ? null,
  # Mode B dylib (libwayland-mac.dylib) from `buildForMacOS "iland-baremetal"`.
  # When non-null, copy into Contents/Library/Wawona/iland/ for Desktop
  # Replacement. Store-safe / App Store builds MUST pass null.
  ilandBaremetal ? null,
  # Mode B IOWatchdog CLI from flake input wwn-iowatchdog (L3'). When non-null
  # with ilandBaremetal, copy bin/wwn-iowatchdog into Contents/Library/Wawona/.
  iowatchdog ? null,
  fastfetch ? null,
  phoon ? null,
  wawonaWasm ? null,
  neovim ? null,
  zsh ? null,
  kmscube ? null,
  modebTty ? null,
  waylandVersion ? "unknown",
  xkbcommonVersion ? "unknown",
  lz4Version ? "unknown",
  zstdVersion ? "unknown",
  libffiVersion ? "unknown",
  sshpassVersion ? "unknown",
  waypipeVersion ? "unknown",
  waypipe,
  moltenvk ? null,
  kosmickrisp ? null,
  xcodeProject ? null,
  applePath,
  westonToytoolkitLdflagsNix,
  westonCompositorLdflagsNix,
  ilandGlLdflagsNix,
  nativeDeps ? null,
}:

let
  common = import ./common.nix { inherit lib pkgs wawonaSrc; };

  # Freedesktop .desktop + hicolor icons for nested-niri fuzzel (issue #78).
  applicationsCatalog = pkgs.callPackage ../generators/applications-catalog.nix {
    inherit pkgs lib wawonaSrc;
  };

  # DejaVu (UI/CSD) + DejaVuSansM Nerd Font Mono (terminals / prompts).
  wawonaBundledFonts = pkgs.callPackage ../libs/fonts { };

  ilandGlLdflags = { deps, simulator ? false }: import ilandGlLdflagsNix {
    inherit lib deps simulator;
    forceLoad = true;
  };
  westonToytoolkitLdflags = deps: import westonToytoolkitLdflagsNix {
    inherit lib deps;
    forceLoadWeston = true;
  };
  # Self-contained compositor-macos embeds helpers; skip -lweston-13.
  westonToytoolkitLdflagsMacos = deps: import westonToytoolkitLdflagsNix {
    inherit lib deps;
    forceLoadWeston = true;
    linkWestonLib = false;
  };
  westonCompositorLdflags = deps: import westonCompositorLdflagsNix {
    inherit lib deps;
  };

  effectiveNativeDeps =
    {
      libwayland = buildModule.buildForMacOS "libwayland" { };
      xkbcommon = buildModule.buildForMacOS "xkbcommon" { };
      pixman = buildModule.buildForMacOS "pixman" { };
      iland = buildModule.buildForMacOS "iland" { };
      angle = buildModule.buildForMacOS "angle" { };
      inherit weston kmscube;
      "iland-gl-clients" = kmscube;
      "gbm-es2-demo" = buildModule.buildForMacOS "gbm-es2-demo" { };
      vkcube = buildModule.buildForMacOS "vkcube" { };
      "opengl-cube" = buildModule.buildForMacOS "opengl-cube" { };
      # Not part of the weston package: it is built outside weston's meson so it
      # can link iland's Wayland-EGL winsys rather than the wayland-egl stub.
      # Without this the Machines entry for it had no binary to launch.
      "weston-simple-egl" = buildModule.buildForMacOS "weston-simple-egl" { };
    } // (if nativeDeps != null then nativeDeps else { });

  appleGlWestonLinkFlags =
    ilandGlLdflags { deps = effectiveNativeDeps; simulator = false; }
    ++ lib.optionals (effectiveNativeDeps ? "weston-compositor" && effectiveNativeDeps."weston-compositor" != null) (
      (westonToytoolkitLdflagsMacos effectiveNativeDeps)
      ++ (westonCompositorLdflags effectiveNativeDeps)
    );
  
  xcodeUtils = import applePath { inherit lib pkgs; };
  xcodeEnv =
    platform: ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      fi
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        # Tahoe (26.0) SDK discovery
        export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.0.sdk"
        if [ ! -d "$SDKROOT" ]; then
           SDKROOT=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
        fi
        echo "Using SDK: $SDKROOT"
        if [ ! -d "$SDKROOT" ]; then
           echo "Error: SDK not found at $SDKROOT"
           exit 1
        fi
      fi
    '';

  copyDeps =
    dest: ''
      mkdir -p ${dest}/include ${dest}/lib ${dest}/libdata/pkgconfig
      for dep in $buildInputs; do
        if [ -d "$dep/include" ]; then cp -rn "$dep/include/"* ${dest}/include/ 2>/dev/null || true; fi
        if [ -d "$dep/lib" ]; then cp -rn "$dep/lib/"* ${dest}/lib/ 2>/dev/null || true; fi
        if [ -d "$dep/lib/pkgconfig" ]; then cp -rn "$dep/lib/pkgconfig/"* ${dest}/libdata/pkgconfig/ 2>/dev/null || true; fi
        if [ -d "$dep/libdata/pkgconfig" ]; then cp -rn "$dep/libdata/pkgconfig/"* ${dest}/libdata/pkgconfig/ 2>/dev/null || true; fi
      done
      
      # Copy UniFFI generated bindings from rustBackend output
      if [ -d "${rustBackend}/uniffi/swift" ]; then
        echo "📦 Copying UniFFI bindings from rustBackend output..."
        mkdir -p "${dest}/uniffi"
        # Check for contents to avoid cp failure when glob expands to nothing
        if [ -n "$(ls -A "${rustBackend}/uniffi/swift" 2>/dev/null)" ]; then
          cp -r "${rustBackend}/uniffi/swift"/* "${dest}/uniffi/"
        else
          echo "⚠️  UniFFI swift directory is empty"
        fi
        echo "✅ UniFFI bindings copied to ${dest}/uniffi/"
        ls -la "${dest}/uniffi/" 2>/dev/null || true
      else
        echo "⚠️  UniFFI bindings not found at ${rustBackend}/uniffi/swift"
      fi
    '';

  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;
  
  projectVersionPatch =
    let parts = lib.splitString "." projectVersion;
    in if parts == [] then "1" else lib.last parts;

  currentYear = lib.substring 0 4 (builtins.readFile (pkgs.runCommand "get-year" { } "date +%Y > $out"));

  macosDeps = [
    "waypipe"
  ];

  macosSources = common.commonSources ++ [
    # macOS-only window management (WWN prefix)
    "src/platform/macos/WWNWindow.m"
    "src/platform/macos/WWNWindow.h"
    "src/platform/macos/WWNWindowDelegate_macos.h"
    "src/platform/macos/WWNPopupHost.h"
    "src/platform/macos/WWNPopupWindow.m"
    "src/platform/macos/WWNPopupWindow.h"
    "src/platform/macos/WWNIlandPresenter.m"
    "src/platform/macos/WWNIlandPresenter.h"
    # Rootfs / iCloud sync. Referenced by WWNPreferences.m on all Apple targets.
    "src/platform/macos/WWNRootfsProvider.m"
    "src/platform/macos/WWNRootfsProvider.h"
    "src/platform/macos/WWNRootfsICloudSync.m"
    "src/platform/macos/WWNRootfsICloudSync.h"
    # Desktop Replacement / Swinging Bridge. MacOS + Android only (matrix).
    "src/platform/macos/ui/Machines/WWNSwingingBridgeController.m"
    "src/platform/macos/ui/Machines/WWNSwingingBridgeController.h"
    "src/platform/macos/ui/Machines/WWNDesktopReplacementController.m"
    "src/platform/macos/ui/Machines/WWNDesktopReplacementController.h"
    "src/platform/macos/ui/Settings/WWNSipStatus.m"
    "src/platform/macos/ui/Settings/WWNSipStatus.h"
  ];

  # Use full list: filterSources can empty the list when wawonaSrc is cleanSourceWith
  # (path doesn't exist at eval time). We skip missing files at build time instead.
  macosSourcesAll = lib.unique (macosSources ++ [
    "src/platform/macos/WWNPopupWindow.m"
    "src/platform/macos/WWNPopupWindow.h"
  ]);

  # Mirror iOS Wawona icon installation: same sources (AppIcon.appiconset,
  # Wawona.icon, About PNGs). macOS uses Contents/Resources; iOS uses app root.
  # Tahoe can use the Icon Composer .icon bundle; optionally compile to Assets.car
  # when actool is available for the dock icon.
  # Install phase runs in a separate shell from buildPhase, so we must set up
  # Xcode env here for iconutil and actool (needed for .icns and Tahoe Assets.car).
  # Use build directory (cwd in installPhase = unpacked source root).
  # macOS 26+ uses .icon (icon.json) → actool → Assets.car. Use explicit Xcode tool paths.
  # All shell variables must be escaped for Nix: use ''$VAR so the script gets literal $VAR.
  installMacOSIcons = ''
    ${xcodeEnv "macos"}
    RESOURCES="$out/Applications/Wawona.app/Contents/Resources"
    mkdir -p "''$RESOURCES"
    ICON_ROOT="src/resources"
    APPICONSET="''$ICON_ROOT/Assets.xcassets/AppIcon.appiconset"
    ICON_BUNDLE="''$ICON_ROOT/Wawona.icon"
    ACTOOL="''${DEVELOPER_DIR:-}/usr/bin/actool"
    ICONUTIL="''${DEVELOPER_DIR:-}/usr/bin/iconutil"

    # --- Fallback only: Wawona.icon (icon.json) → actool → Assets.car + .icns (26+ pipeline) ---
    # Prefer AppIcon.appiconset first so nix-run matches Xcode's icon source.
    if [ ! -d "''$APPICONSET" ] && [ -d "''$ICON_BUNDLE" ] && [ -f "''$ICON_BUNDLE/icon.json" ]; then
      if [ -n "''${DEVELOPER_DIR:-}" ] && [ -x "''$ACTOOL" ]; then
        ICON_TMP="''$TMPDIR/wawona-icon-compile"
        rm -rf "''$ICON_TMP"
        mkdir -p "''$ICON_TMP"
        cp -R "''$ICON_BUNDLE" "''$ICON_TMP/Wawona.icon"
        if [ -f "''$ICON_BUNDLE/Assets/wayland.png" ] && [ ! -f "''$ICON_TMP/Wawona.icon/wayland.png" ]; then
          cp "''$ICON_BUNDLE/Assets/wayland.png" "''$ICON_TMP/Wawona.icon/wayland.png"
        fi
        OUT_CAR="''$ICON_TMP/icons"
        mkdir -p "''$OUT_CAR"
        if "''$ACTOOL" "''$ICON_TMP/Wawona.icon" --compile "''$OUT_CAR" \
            --platform macosx --target-device mac \
            --minimum-deployment-target 26.0 \
            --app-icon Wawona --include-all-app-icons \
            --output-format human-readable-text --notices --warnings \
            --development-region en --enable-on-demand-resources NO \
            --output-partial-info-plist "''$OUT_CAR/assetcatalog_generated_info.plist"; then
          if [ -f "''$OUT_CAR/Assets.car" ]; then
            cp "''$OUT_CAR/Assets.car" "''$RESOURCES/"
            echo "Installed Assets.car (from Wawona.icon / icon.json)"
          fi
          for icns in "''$OUT_CAR"/Wawona.icns "''$OUT_CAR"/*.icns; do
            if [ -f "''$icns" ]; then
              cp "''$icns" "''$RESOURCES/AppIcon.icns"
              echo "Installed AppIcon.icns (from actool .icon)"
              break
            fi
          done
        fi
      else
        echo "Warning: actool not available (Xcode at DEVELOPER_DIR); macOS 26+ icon may be missing."
      fi
      cp -R "''$ICON_BUNDLE" "''$RESOURCES/"
      echo "Installed Wawona.icon bundle"
    fi

    # --- Fallback: AppIcon.icns from PNGs via iconutil ---
    if [ ! -f "''$RESOURCES/AppIcon.icns" ] && [ -d "''$APPICONSET" ] && [ -n "''${DEVELOPER_DIR:-}" ] && [ -x "''$ICONUTIL" ]; then
      ICON_TMP="''$TMPDIR/wawona-iconutil"
      rm -rf "''$ICON_TMP"
      mkdir -p "''$ICON_TMP/AppIcon.iconset"
      if [ -f "''$APPICONSET/AppIcon-16.png" ]; then cp "''$APPICONSET/AppIcon-16.png" "''$ICON_TMP/AppIcon.iconset/icon_16x16.png"; fi
      if [ -f "''$APPICONSET/AppIcon-32.png" ]; then cp "''$APPICONSET/AppIcon-32.png" "''$ICON_TMP/AppIcon.iconset/icon_16x16@2x.png"; cp "''$APPICONSET/AppIcon-32.png" "''$ICON_TMP/AppIcon.iconset/icon_32x32.png"; fi
      if [ -f "''$APPICONSET/AppIcon-64.png" ]; then cp "''$APPICONSET/AppIcon-64.png" "''$ICON_TMP/AppIcon.iconset/icon_32x32@2x.png"; fi
      if [ -f "''$APPICONSET/AppIcon-128.png" ]; then cp "''$APPICONSET/AppIcon-128.png" "''$ICON_TMP/AppIcon.iconset/icon_128x128.png"; fi
      if [ -f "''$APPICONSET/AppIcon-256.png" ]; then cp "''$APPICONSET/AppIcon-256.png" "''$ICON_TMP/AppIcon.iconset/icon_128x128@2x.png"; cp "''$APPICONSET/AppIcon-256.png" "''$ICON_TMP/AppIcon.iconset/icon_256x256.png"; fi
      if [ -f "''$APPICONSET/AppIcon-512.png" ]; then cp "''$APPICONSET/AppIcon-512.png" "''$ICON_TMP/AppIcon.iconset/icon_256x256@2x.png"; cp "''$APPICONSET/AppIcon-512.png" "''$ICON_TMP/AppIcon.iconset/icon_512x512.png"; fi
      if [ -f "''$APPICONSET/AppIcon-1024.png" ]; then
        cp "''$APPICONSET/AppIcon-1024.png" "''$ICON_TMP/AppIcon.iconset/icon_512x512@2x.png"
      elif [ -f "''$APPICONSET/AppIcon-Light-1024.png" ]; then
        cp "''$APPICONSET/AppIcon-Light-1024.png" "''$ICON_TMP/AppIcon.iconset/icon_512x512@2x.png"
      fi
      "''$ICONUTIL" -c icns "''$ICON_TMP/AppIcon.iconset" -o "''$RESOURCES/AppIcon.icns"
      echo "Installed AppIcon.icns (fallback via iconutil)"
    fi

    # --- Last resort: .icns from single 1024 PNG using sips + iconutil ---
    if [ ! -f "''$RESOURCES/AppIcon.icns" ] && [ -n "''${DEVELOPER_DIR:-}" ] && [ -x "''$ICONUTIL" ]; then
      SRC1024=""
      [ -f "''$APPICONSET/AppIcon-1024.png" ] && SRC1024="''$APPICONSET/AppIcon-1024.png"
      [ -z "''$SRC1024" ] && [ -f "''$APPICONSET/AppIcon-Light-1024.png" ] && SRC1024="''$APPICONSET/AppIcon-Light-1024.png"
      if [ -n "''$SRC1024" ]; then
        ICON_TMP="''$TMPDIR/wawona-iconutil-minimal"
        rm -rf "''$ICON_TMP"
        mkdir -p "''$ICON_TMP/AppIcon.iconset"
        SIPS="sips"
        [ -x "/usr/bin/sips" ] && SIPS="/usr/bin/sips"
        cp "''$SRC1024" "''$ICON_TMP/AppIcon.iconset/icon_512x512@2x.png"
        "''$SIPS" -z 16 16 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_16x16.png" 2>/dev/null || true
        "''$SIPS" -z 32 32 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_16x16@2x.png" 2>/dev/null || true
        "''$SIPS" -z 32 32 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_32x32.png" 2>/dev/null || true
        "''$SIPS" -z 64 64 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_32x32@2x.png" 2>/dev/null || true
        "''$SIPS" -z 128 128 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_128x128.png" 2>/dev/null || true
        "''$SIPS" -z 256 256 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_128x128@2x.png" 2>/dev/null || true
        "''$SIPS" -z 256 256 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_256x256.png" 2>/dev/null || true
        "''$SIPS" -z 512 512 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_256x256@2x.png" 2>/dev/null || true
        "''$SIPS" -z 512 512 "''$SRC1024" --out "''$ICON_TMP/AppIcon.iconset/icon_512x512.png" 2>/dev/null || true
        if [ -f "''$ICON_TMP/AppIcon.iconset/icon_512x512@2x.png" ]; then
          "''$ICONUTIL" -c icns "''$ICON_TMP/AppIcon.iconset" -o "''$RESOURCES/AppIcon.icns" 2>/dev/null && echo "Installed AppIcon.icns (minimal from 1024 PNG)"
        fi
      fi
    fi

    # Legacy PNG copies
    if [ -d "''$APPICONSET" ] && [ -f "''$APPICONSET/AppIcon-1024.png" ]; then
      cp "''$APPICONSET/AppIcon-1024.png" "''$RESOURCES/AppIcon.png"
    elif [ -d "''$APPICONSET" ] && [ -f "''$APPICONSET/AppIcon-Light-1024.png" ]; then
      cp "''$APPICONSET/AppIcon-Light-1024.png" "''$RESOURCES/AppIcon.png"
    fi
    if [ -f "''$ICON_ROOT/Wawona-iOS-Dark-1024x1024@1x.png" ]; then
      cp "''$ICON_ROOT/Wawona-iOS-Dark-1024x1024@1x.png" "''$RESOURCES/AppIcon-Dark.png"
      cp "''$ICON_ROOT/Wawona-iOS-Dark-1024x1024@1x.png" "''$RESOURCES/"
    fi
    if [ -f "''$ICON_ROOT/Wawona-iOS-Light-1024x1024@1x.png" ]; then
      cp "''$ICON_ROOT/Wawona-iOS-Light-1024x1024@1x.png" "''$RESOURCES/"
    fi

    # Wawona.png for [NSImage imageNamed:@"Wawona"] fallback
    for candidate in "Assets.xcassets/AppIcon.appiconset/AppIcon-Light-1024.png" \
                     "Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" \
                     "Wawona-iOS-Light-1024x1024@1x.png" \
                     "Wawona-iOS-Dark-1024x1024@1x.png"; do
      if [ -f "''$ICON_ROOT/''$candidate" ]; then
        cp "''$ICON_ROOT/''$candidate" "''$RESOURCES/Wawona.png"
        echo "Installed Wawona.png for About/Settings fallback"
        break
      fi
    done

    # Dedicated menubar glyph: Wayland W silhouette, no yellow disc / app-icon chrome.
    SILHOUETTE_SRC="src/resources/macos/Wawona-menubar-silhouette.png"
    if [ -f "''$SILHOUETTE_SRC" ]; then
      cp "''$SILHOUETTE_SRC" "''$RESOURCES/Wawona-menubar-silhouette.png"
      echo "Installed Wawona-menubar-silhouette.png"
    else
      echo "Error: missing ''$SILHOUETTE_SRC" >&2
      exit 1
    fi
  '';

  generateIcons = platform: ''
    mkdir -p "$out/Applications/Wawona.app/Contents/Resources"
  '';

  # Mode B dylib + wwn-iowatchdog. Desktop-host / full-dev only (never store-safe).
  bundleIlandBaremetalDylib = lib.optionalString (ilandBaremetal != null) ''
    bundle_iland_baremetal_dylib() {
      local app="$1"
      local src="${ilandBaremetal}/lib/libwayland-mac.dylib"
      if [ ! -f "$src" ]; then
        echo "ERROR: ilandBaremetal set but $src missing" >&2
        exit 1
      fi
      local dest="$app/Contents/Library/Wawona/iland"
      mkdir -p "$dest"
      cp -L "$src" "$dest/libwayland-mac.dylib"
      chmod 755 "$dest/libwayland-mac.dylib"
      if command -v codesign >/dev/null 2>&1; then
        codesign --force --sign - --timestamp=none "$dest/libwayland-mac.dylib" 2>/dev/null || true
      fi
      echo "Bundled Mode B dylib: $dest/libwayland-mac.dylib"

      # Kernel IOWatchdog tool from L3' wwn-iowatchdog (not in-tree source).
      local iow_bin="$app/Contents/Library/Wawona/wwn-iowatchdog"
      ${if iowatchdog != null then ''
      local iow_src="${iowatchdog}/bin/wwn-iowatchdog"
      if [ ! -x "$iow_src" ]; then
        echo "ERROR: missing $iow_src (Mode B IOWatchdog tool from wwn-iowatchdog)" >&2
        exit 1
      fi
      mkdir -p "$app/Contents/Library/Wawona"
      cp -L "$iow_src" "$iow_bin"
      chmod 755 "$iow_bin"
      if command -v codesign >/dev/null 2>&1; then
        codesign --force --sign - --timestamp=none "$iow_bin" 2>/dev/null || true
      fi
      echo "Bundled Mode B IOWatchdog tool: $iow_bin"
      # Path B arm + doctor (Classic Take Over requires sticky claim-ok).
      for _iow_extra in wwn-iowatchdog-claim-install wwn-iowatchdog-claim; do
        if [ -x "${iowatchdog}/bin/$_iow_extra" ]; then
          cp -L "${iowatchdog}/bin/$_iow_extra" \
            "$app/Contents/Library/Wawona/$_iow_extra"
          chmod 755 "$app/Contents/Library/Wawona/$_iow_extra"
          if command -v codesign >/dev/null 2>&1; then
            codesign --force --sign - --timestamp=none \
              "$app/Contents/Library/Wawona/$_iow_extra" 2>/dev/null || true
          fi
          echo "Bundled Mode B $_iow_extra"
        fi
      done
      # arm64e Path B hook (claim-install --path-b).
      local iow_hook_src="${iowatchdog}/lib/libwwn_watchdogd_hook.dylib"
      local iow_hook_dst="$app/Contents/Library/Wawona/libwwn_watchdogd_hook.dylib"
      if [ -f "$iow_hook_src" ]; then
        cp -L "$iow_hook_src" "$iow_hook_dst"
        chmod 755 "$iow_hook_dst"
        mkdir -p "$app/Contents/Library/Wawona/lib"
        cp -L "$iow_hook_src" \
          "$app/Contents/Library/Wawona/lib/libwwn_watchdogd_hook.dylib"
        chmod 755 "$app/Contents/Library/Wawona/lib/libwwn_watchdogd_hook.dylib"
        if command -v codesign >/dev/null 2>&1; then
          codesign --force --sign - --timestamp=none "$iow_hook_dst" 2>/dev/null || true
          codesign --force --sign - --timestamp=none \
            "$app/Contents/Library/Wawona/lib/libwwn_watchdogd_hook.dylib" \
            2>/dev/null || true
        fi
        echo "Bundled Mode B watchdogd hook (arm64e): $iow_hook_dst"
      fi
      '' else ''
      echo "ERROR: ilandBaremetal set but iowatchdog flake package is null" >&2
      exit 1
      ''}
    }
  '';

  # Copy non-system dylibs into Contents/Frameworks and rewrite load paths so the
  # app runs when copied out of the Nix store (Documents, DMG, launch agents).
  bundleMacOSAppDylibs = ''
    bundle_macos_app_dylibs() {
      local app="$1"
      [ -d "$app/Contents/MacOS" ] || return 0
      local fw="$app/Contents/Frameworks"
      mkdir -p "$fw"

      if ! command -v otool >/dev/null 2>&1 || ! command -v install_name_tool >/dev/null 2>&1; then
        echo "Warning: otool/install_name_tool unavailable; skipping dylib bundling"
        return 0
      fi

      is_macho() {
        file "$1" 2>/dev/null | grep -q 'Mach-O'
      }

      list_machos() {
        if [ -f "$app/Contents/MacOS/Wawona" ]; then
          echo "$app/Contents/MacOS/Wawona"
        fi
        for f in "$app/Contents/MacOS"/*; do
          [ -f "$f" ] && is_macho "$f" && echo "$f"
        done
        if [ -d "$app/Contents/Resources/bin" ]; then
          for f in "$app/Contents/Resources/bin"/*; do
            [ -f "$f" ] && is_macho "$f" && echo "$f"
          done
        fi
        for f in "$fw"/*.dylib; do
          [ -f "$f" ] && echo "$f"
        done
        if [ -d "$app/lib/libweston-13" ]; then
          for f in "$app/lib/libweston-13"/*; do
            [ -f "$f" ] && is_macho "$f" && echo "$f"
          done
        fi
        if [ -d "$app/lib/weston" ]; then
          for f in "$app/lib/weston"/*; do
            [ -f "$f" ] && is_macho "$f" && echo "$f"
          done
        fi
      }

      dep_is_bundlable() {
        case "$1" in
          /usr/lib/*|/System/*|/Library/*|@*) return 1 ;;
        esac
        return 0
      }

      copy_dep() {
        local dep="$1"
        dep_is_bundlable "$dep" || return 0
        [ -f "$dep" ] || return 0
        local base
        base="$(basename "$dep")"
        if [ ! -f "$fw/$base" ]; then
          cp -L "$dep" "$fw/$base"
          chmod 755 "$fw/$base"
          install_name_tool -id "@rpath/$base" "$fw/$base" 2>/dev/null || true
          echo "Bundled dylib: $base"
          return 0
        fi
        return 1
      }

      local round added dep macho
      round=0
      while [ "$round" -lt 32 ]; do
        round=$((round + 1))
        added=0
        while IFS= read -r macho; do
          [ -n "$macho" ] || continue
          while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            if copy_dep "$dep"; then
              added=1
            fi
          done < <(otool -L "$macho" 2>/dev/null | awk 'NR>1 {print $1}' | grep '\.dylib' || true)
        done < <(list_machos)
        [ "$added" -eq 1 ] || break
      done

      while IFS= read -r macho; do
        [ -n "$macho" ] || continue
        while IFS= read -r dep; do
          [ -n "$dep" ] || continue
          dep_is_bundlable "$dep" || continue
          local base
          base="$(basename "$dep")"
          if [ -f "$fw/$base" ]; then
            install_name_tool -change "$dep" "@rpath/$base" "$macho" 2>/dev/null || true
          fi
        done < <(otool -L "$macho" 2>/dev/null | awk 'NR>1 {print $1}' | grep '\.dylib' || true)

        while IFS= read -r rpath; do
          [ -n "$rpath" ] || continue
          case "$rpath" in
            @executable_path/../Frameworks|@executable_path/../../Frameworks) continue ;;
          esac
          install_name_tool -delete_rpath "$rpath" "$macho" 2>/dev/null || true
        done < <(otool -l "$macho" 2>/dev/null | awk '/cmd LC_RPATH/{getline; getline; if ($1=="path") print $2}' || true)
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$macho" 2>/dev/null || true
        # Resources/bin executables sit one level deeper than Contents/MacOS;
        # point them at Contents/Frameworks too.
        case "$macho" in
          */Contents/Resources/bin/*)
            install_name_tool -add_rpath "@executable_path/../../Frameworks" "$macho" 2>/dev/null || true
            ;;
        esac
      done < <(list_machos | sort -u)
    }
  '';

in
  pkgs.stdenv.mkDerivation rec {
    name = "wawona-macos";
    version = projectVersion;
    src = wawonaSrc;
    __noChroot = true;

    outputs = [ "out" "project" ];

    nativeBuildInputs = with pkgs; [
      clang
      pkg-config
      swift

      xcodeUtils.findXcodeScript
      rustBackend
    ];

    buildInputs = [
      (buildModule.buildForMacOS "pixman" { })
      pkgs.vulkan-headers
      pkgs.vulkan-loader
      (buildModule.buildForMacOS "xkbcommon" { })
      pkgs.openssl
      pkgs.zlib
      pkgs.libiconv
      (buildModule.buildForMacOS "libwayland" { })
      effectiveNativeDeps.iland
      effectiveNativeDeps.angle
      weston
      kmscube
      rustBackend
      waypipe
      # wwn-ssh macOS backend: regular OpenSSH + sshpass, bundled into
      # Resources/bin below so ssh/ssh-keygen work in the in-app terminal.
      (buildModule.buildForMacOS "openssh" { })
      (buildModule.buildForMacOS "sshpass" { })
    ];

    prePatch = ''
      if [ -f "src/platform/macos/WWNWindow.h" ]; then
        sed -i 's/UP_H//g' src/platform/macos/WWNWindow.h
      fi
    '';

    postPatch = "";

    preBuild = ''
      ${xcodeEnv "macos"}

      if command -v metal >/dev/null 2>&1; then
        true
      fi
    '';

    preConfigure = ''
      ${xcodeEnv "macos"}
      ${copyDeps "macos-dependencies"}

      export PKG_CONFIG_PATH="$PWD/macos-dependencies/libdata/pkgconfig:$PWD/macos-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"
      
      # Isolate environment from Nix wrapper flags to prevent linker conflicts
      unset DEVELOPER_DIR
      export NIX_CFLAGS_COMPILE=""
      export NIX_LDFLAGS=""

      # Bindgen and other target tools need to know about the sysroot via flags,
      # but we unset the env vars to avoid leaking them into host tools.
      export TARGET_CFLAGS="-isysroot $SDKROOT ${lib.concatStringsSep " " common.appleCFlags}"
      export TARGET_LDFLAGS="-isysroot $SDKROOT ${lib.concatStringsSep " " common.appleCFlags}"

      unset SDKROOT
    '';

    buildPhase = ''
      runHook preBuild
      # Prefer Xcode project build for SwiftPM module correctness (WawonaModel/WawonaUIContracts).
      if [ -n "${toString xcodeProject}" ] && [ -d "${xcodeProject}/Wawona.xcodeproj" ]; then
        echo "📦 Phase 0: Building via generated Xcode project..."
        cp -R "${xcodeProject}" ./_xcode_project
        chmod -R u+w ./_xcode_project || true
        mkdir -p "$TMPDIR/wawona-home/.cache" "$TMPDIR/wawona-home/.config"
        export HOME="$TMPDIR/wawona-home"
        export XDG_CACHE_HOME="$HOME/.cache"
        export XDG_CONFIG_HOME="$HOME/.config"
        # Keep Nix as the orchestrator, but isolate xcodebuild from cc-wrapper
        # and NIX_* flags that can leak invalid linker options into Apple's ld.
        # Pass HOME/XDG_* explicitly: xcodebuild script phases otherwise inherit
        # nixbld's /var/empty and nested nix dies on ~/.cache.
        if env \
          -u NIX_CFLAGS_COMPILE \
          -u NIX_CXXFLAGS_COMPILE \
          -u NIX_LDFLAGS \
          -u NIX_LDFLAGS_BEFORE \
          -u NIX_CC_WRAPPER_FLAGS_SET \
          -u NIX_DONT_SET_RPATH \
          -u CFLAGS \
          -u CXXFLAGS \
          -u CPPFLAGS \
          -u LDFLAGS \
          -u CC \
          -u CXX \
          -u LD \
          HOME="$HOME" \
          XDG_CACHE_HOME="$XDG_CACHE_HOME" \
          XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
          WAWONA_BACKEND_OUT="${rustBackend}" \
          WAWONA_BACKEND_OUT_Wawona_macOS="${rustBackend}" \
          xcodebuild \
          -project "./_xcode_project/Wawona.xcodeproj" \
          -scheme "Wawona-macOS" \
          -configuration Release \
          -derivedDataPath "./_xcode_project/DerivedData" \
          -destination "platform=macOS,arch=arm64" \
          CODE_SIGNING_ALLOWED=NO \
          CODE_SIGNING_REQUIRED=NO \
          ONLY_ACTIVE_ARCH=YES \
          build; then
          BUILT_APP="./_xcode_project/DerivedData/Build/Products/Release/Wawona.app"
          if [ -d "$BUILT_APP" ]; then
            mkdir -p xcodebuild-out
            cp -R "$BUILT_APP" "xcodebuild-out/Wawona.app"
            touch .use_xcodebuild_app
            echo "✅ Xcode project build produced Wawona.app"
          else
            echo "❌ Xcode project build completed but Wawona.app was not found."
            exit 1
          fi
        else
          echo "❌ Xcode project build failed."
          exit 1
        fi
      fi

      if [ -f .use_xcodebuild_app ]; then
        echo "✅ Skipping manual fallback; using Xcode-built app."
        runHook postBuild
      else
      # Build timestamp: 2026-01-17-09:00 - Added Swift compiler!

      # PHASE 1: Compile Swift bindings and SwiftUI machines views when present.
      # Some flake source snapshots can omit untracked Swift files; in that case
      # we keep building with the legacy Objective-C machines UI.
      echo "📦 Phase 1: Compiling Swift sources..."
      SWIFT_OBJ=""
      SWIFT_SOURCES=(
        # Shared View.wwnA11y(_:). Must stay unique with WWNAccessibilityIdentifiers.swift
        "Sources/WawonaUI/AccessibilityIdentifiers.swift"
        "src/platform/macos/ui/Machines/WWNAccessibilityIdentifiers.swift"
        "src/platform/macos/ui/Machines/WWNMachineCardView.swift"
        "src/platform/macos/ui/Machines/WWNMachineEditorView.swift"
        "src/platform/macos/ui/Machines/WWNMachinesViewModel.swift"
        "src/platform/macos/ui/Machines/WWNMachinesGridView.swift"
      )
      EXISTING_SWIFT_SOURCES=()
      for swift_src in "''${SWIFT_SOURCES[@]}"; do
        if [ -f "$swift_src" ]; then
          EXISTING_SWIFT_SOURCES+=("$swift_src")
        fi
      done
      if [ "''${#EXISTING_SWIFT_SOURCES[@]}" -gt 0 ]; then
        echo "   Swift sources:"
        for swift_src in "''${EXISTING_SWIFT_SOURCES[@]}"; do
          echo "     - $swift_src"
        done

        if [ -z "''${SDKROOT:-}" ] || [ ! -d "''${SDKROOT:-}" ]; then
          SDKROOT=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
        fi
        if [ -z "''${SDKROOT:-}" ] || [ ! -d "''${SDKROOT:-}" ]; then
          echo "❌ Could not resolve SDKROOT for Swift compile."
          exit 1
        else
          SWIFTC_BIN="''${DEVELOPER_DIR:-}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
          if [ ! -x "$SWIFTC_BIN" ]; then
            SWIFTC_BIN="$(command -v swiftc || true)"
          fi
          if [ -z "$SWIFTC_BIN" ]; then
            echo "❌ swiftc not available."
            exit 1
          else
            rm -f wawona_swift_all.o wawona-Swift.h wawona.swiftmodule
            rm -rf swift-build
            mkdir -p swift-build
            PROCESSED_SWIFT_SOURCES=()
            idx=0
            for swift_src in "''${EXISTING_SWIFT_SOURCES[@]}"; do
              idx=$((idx + 1))
              out_src="swift-build/''${idx}_$(basename "$swift_src")"
              cp "$swift_src" "$out_src"
              PROCESSED_SWIFT_SOURCES+=("$out_src")
            done
            if "$SWIFTC_BIN" -parse-as-library -whole-module-optimization -emit-object "''${PROCESSED_SWIFT_SOURCES[@]}" \
              -o wawona_swift_all.o \
              -import-objc-header "src/platform/macos/WWN-Bridging-Header.h" \
              -module-name wawona \
              -emit-objc-header \
              -emit-objc-header-path wawona-Swift.h \
              -emit-module \
              -emit-module-path wawona.swiftmodule \
              -sdk "$SDKROOT" \
              -I "${rustBackend}/include" \
              -I "macos-dependencies/uniffi" \
              -I "src/platform/macos" \
              -I "src" \
              -I "src/platform/macos/ui" \
              -I "src/platform/macos/ui/Machines" \
              -I "src/platform/macos/ui/Settings" \
              -L "${rustBackend}/lib" \
              -Xlinker -rpath -Xlinker "@executable_path"; then
              SWIFT_OBJ="wawona_swift_all.o"
            else
              echo "❌ Swift compile failed for SwiftUI sources."
              exit 1
            fi
          fi
        fi

        if [ -n "$SWIFT_OBJ" ] && [ -f "wawona-Swift.h" ]; then
          cat > _GEN-wawona-Swift.h << 'GEN_HEADER'
// WARNING: This is a GENERATED file - DO NOT EDIT
// 
// Generated by: swiftc (Swift Compiler)
// Source file:  multiple (UniFFI + SwiftUI)
// Build script: dependencies/wawona-macos.nix (Phase 1: Swift compilation)
// Command:      swiftc -emit-objc-header
// 
// Purpose: Allows Objective-C code to call Swift classes from UniFFI bindings
// 
// To regenerate this file:
//   nix build .#wawona-macos
// 
// DO NOT manually edit - changes will be overwritten on next build
//

GEN_HEADER
          cat wawona-Swift.h >> _GEN-wawona-Swift.h
          rm wawona-Swift.h

          echo "✅ Swift sources compiled - _GEN-wawona-Swift.h generated"
          echo "   Swift objects: $SWIFT_OBJ"
          echo "   Swift header: $(ls -lh _GEN-wawona-Swift.h)"
        else
          echo "❌ Swift compilation did not produce required objects/header."
          exit 1
        fi
      else
        echo "❌ No Swift sources found in source snapshot."
        exit 1
      fi

      SWIFT_FRAMEWORKS="-framework SwiftUI"
      echo "   SWIFT_OBJ variable: ''${SWIFT_OBJ:-EMPTY}"
      echo "   SWIFT_FRAMEWORKS: ''${SWIFT_FRAMEWORKS:-NONE}"

      # PHASE 2: Compile Objective-C and C files
      # Now _GEN-wawona-Swift.h is available in current directory
      echo "🔨 Phase 2: Compiling Objective-C and C files..."
      OBJ_FILES="$SWIFT_OBJ"
      ALL_SOURCES="${lib.concatStringsSep " " macosSourcesAll}"
      for src_file in $ALL_SOURCES; do
        if [[ "$src_file" == *.c ]] || [[ "$src_file" == *.m ]]; then
          [ -f "$src_file" ] || continue
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if [[ "$src_file" == *.m ]]; then
            $CC -c "$src_file" \
               -Isrc -Isrc/util -Isrc/platform/macos \
               -Isrc/platform/macos/ui -Isrc/platform/macos/ui/Helpers \
               -Isrc/platform/macos/ui/Machines -Isrc/platform/macos/ui/Settings \
               -Idependencies/clients/wawona-shell/src \
               -Imacos-dependencies/include \
               -Imacos-dependencies/uniffi \
               ${lib.optionalString (anowaw != null) "-I${anowaw}/include"} \
               -I. \
               -I${rustBackend}/include \
               -fobjc-arc -fPIC \
               ${lib.concatStringsSep " " common.commonObjCFlags} \
               ${lib.concatStringsSep " " common.appleCFlags} \
               ${lib.concatStringsSep " " common.releaseObjCFlags} \
               -fno-lto \
               -DUSE_RUST_CORE=1 \
                -DWAWONA_VERSION=\"${projectVersion}\" \
                -DWAWONA_WAYLAND_VERSION=\"${waylandVersion}\" \
                -DWAWONA_XKBCOMMON_VERSION=\"${xkbcommonVersion}\" \
                -DWAWONA_LZ4_VERSION=\"${lz4Version}\" \
                -DWAWONA_ZSTD_VERSION=\"${zstdVersion}\" \
                -DWAWONA_LIBFFI_VERSION=\"${libffiVersion}\" \
                -DWAWONA_SSHPASS_VERSION=\"${sshpassVersion}\" \
                -DWAWONA_WAYPIPE_VERSION=\"${waypipeVersion}\" \
                -o "$obj_file"
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/util -Isrc/platform/macos \
               -Isrc/platform/macos/ui -Isrc/platform/macos/ui/Helpers \
               -Idependencies/clients/wawona-shell/src \
               -Imacos-dependencies/include \
               -Imacos-dependencies/uniffi \
               -I${rustBackend}/include \
               -fPIC \
               $TARGET_CFLAGS \
               ${lib.concatStringsSep " " common.commonCFlags} \
               ${lib.concatStringsSep " " common.releaseCFlags} \
               -fno-lto \
               -DUSE_RUST_CORE=1 \
               -DWAWONA_VERSION=\"${projectVersion}\" \
               -DWAWONA_WAYLAND_VERSION=\"${waylandVersion}\" \
               -DWAWONA_XKBCOMMON_VERSION=\"${xkbcommonVersion}\" \
               -DWAWONA_LZ4_VERSION=\"${lz4Version}\" \
               -DWAWONA_ZSTD_VERSION=\"${zstdVersion}\" \
               -DWAWONA_LIBFFI_VERSION=\"${libffiVersion}\" \
               -DWAWONA_SSHPASS_VERSION=\"${sshpassVersion}\" \
               -o "$obj_file"
          fi
          OBJ_FILES="$OBJ_FILES $obj_file"
        fi
      done

      # Debug: Show all object files before linking
      echo ""
      echo "📊 Object files summary:"
      echo "   SWIFT_OBJ: ''${SWIFT_OBJ:-EMPTY}"
      echo "   OBJ_FILES count: $(echo $OBJ_FILES | wc -w)"
      echo "   First few: $(echo $OBJ_FILES | tr ' ' '\n' | head -3 | tr '\n' ' ')"
      if [ -n "$SWIFT_OBJ" ]; then
        first_swift_obj=$(echo "$SWIFT_OBJ" | awk '{print $1}')
        if [ -n "$first_swift_obj" ] && [ -f "$first_swift_obj" ]; then
          echo "   ✅ Swift object exists: $(ls -lh "$first_swift_obj")"
        else
          echo "   ❌ Swift object variable set but first object missing"
          exit 1
        fi
      fi
      echo ""

      # PHASE 3: Link everything together
      echo "🔗 Phase 3: Linking final binary..."

      # Swinging Bridge app-bridge: static core lib + ScreenCaptureKit/CGEvent shim object.
      # The shim (.o) is best-effort in Wawona-Swinging-Bridge (needs the macOS SDK frameworks
      # at dep-build time), so only add it when present. libanowaw.a is safe to
      # pass unconditionally. If WWNSwingingBridgeController compiled as a stub (header
      # not vendored) its symbols simply go unreferenced.
      ANOWAW_LINK=""
      ${lib.optionalString (anowaw != null) ''
        ANOWAW_LINK="${anowaw}/lib/libanowaw.a"
        if [ -f "${anowaw}/lib/anowaw_mac_shim.o" ]; then
          ANOWAW_LINK="$ANOWAW_LINK ${anowaw}/lib/anowaw_mac_shim.o"
        fi
        ANOWAW_LINK="$ANOWAW_LINK -framework ScreenCaptureKit -framework ApplicationServices"
      ''}

      XKBCOMMON_LIBS=$(pkg-config --libs xkbcommon 2>/dev/null || echo "-Lmacos-dependencies/lib -lxkbcommon")
      WAYLAND_LIBS=$(pkg-config --libs wayland-client wayland-server 2>/dev/null || echo "-Lmacos-dependencies/lib -lwayland-client -lwayland-server")
      OPENSSL_LIBS=$(pkg-config --libs openssl 2>/dev/null || echo "-Lmacos-dependencies/lib -lssl -lcrypto")
      ZLIB_LIBS=$(pkg-config --libs zlib 2>/dev/null || echo "-Lmacos-dependencies/lib -lz")
      LINKER_BIN="''${SWIFTC_BIN:-$CC}"
      LINK_SYSROOT_ARGS="$TARGET_LDFLAGS"
      LINK_OPT_FLAGS="-fobjc-arc -flto -O3"
      LINK_OBJC_FLAG="-ObjC"
      LINK_RPATH_FLAG="-Wl,-rpath,@executable_path/../Frameworks"
      ILAND_WESTON_FLAGS=(${lib.concatStringsSep " " (map (f: "\"${f}\"") appleGlWestonLinkFlags)})
      if [ -n "''${SWIFTC_BIN:-}" ] && [ "$LINKER_BIN" = "$SWIFTC_BIN" ]; then
        LINK_SYSROOT_ARGS="-sdk ''${SDKROOT:-}"
        LINK_OPT_FLAGS="-Xlinker -dead_strip"
        LINK_OBJC_FLAG="-Xlinker -ObjC"
        LINK_RPATH_FLAG="-Xlinker -rpath -Xlinker @executable_path/../Frameworks"
        EXPANDED_ILAND_WESTON_FLAGS=()
        idx=0
        while [ "$idx" -lt "''${#ILAND_WESTON_FLAGS[@]}" ]; do
          flag="''${ILAND_WESTON_FLAGS[$idx]}"
          idx=$((idx + 1))
          case "$flag" in
            -force_load)
              archive="''${ILAND_WESTON_FLAGS[$idx]}"
              idx=$((idx + 1))
              EXPANDED_ILAND_WESTON_FLAGS+=(-Xlinker -force_load -Xlinker "$archive")
              ;;
            -framework)
              name="''${ILAND_WESTON_FLAGS[$idx]}"
              idx=$((idx + 1))
              EXPANDED_ILAND_WESTON_FLAGS+=(-framework "$name")
              ;;
            -Wl,*)
              # swiftc does not understand GCC-style -Wl,<flag>,<arg>.
              # Split on commas and re-emit each token as -Xlinker <token>.
              inner="''${flag#-Wl,}"
              IFS=',' read -ra _wl_parts <<< "$inner"
              for _part in "''${_wl_parts[@]}"; do
                EXPANDED_ILAND_WESTON_FLAGS+=(-Xlinker "$_part")
              done
              ;;
            *)
              EXPANDED_ILAND_WESTON_FLAGS+=("$flag")
              ;;
          esac
        done
        ILAND_WESTON_FLAGS=("''${EXPANDED_ILAND_WESTON_FLAGS[@]}")
      fi
      "$LINKER_BIN" $OBJ_FILES \
         -Lmacos-dependencies/lib \
         -framework Cocoa -framework QuartzCore -framework CoreVideo \
         -framework CoreMedia -framework CoreGraphics -framework ColorSync \
         -framework Metal -framework MetalKit -framework IOSurface \
         $SWIFT_FRAMEWORKS \
         -framework VideoToolbox -framework AVFoundation -framework Network -framework Security \
         $(pkg-config --libs pixman-1) \
         $XKBCOMMON_LIBS \
         $WAYLAND_LIBS \
         $OPENSSL_LIBS \
         $ZLIB_LIBS \
         $ANOWAW_LINK \
         ${rustBackend}/lib/libwawona.a \
         $LINK_SYSROOT_ARGS \
         $LINK_OPT_FLAGS \
         $LINK_OBJC_FLAG \
         $LINK_RPATH_FLAG \
         "''${ILAND_WESTON_FLAGS[@]}" \
         -o Wawona

      runHook postBuild
      fi
    '';

    installPhase = ''
            runHook preInstall

            if [ -f .use_xcodebuild_app ] && [ -d "xcodebuild-out/Wawona.app" ]; then
              mkdir -p $out/Applications
              cp -R "xcodebuild-out/Wawona.app" "$out/Applications/Wawona.app"
              APP="$out/Applications/Wawona.app"

              # Same runtime assets as the manual install path. Xcode's .app does
              # not embed weston share/fonts; postInstall verifies these exist.
              mkdir -p "$APP/Contents/Resources/bin" "$APP/Contents/MacOS"
              if [ -d "${weston}/bin" ]; then
                for client in "${weston}/bin"/weston*; do
                  base="$(basename "$client")"
                  case "$base" in *.so|*.dylib) continue ;; esac
                  if [ -f "$client" ]; then
                    cp "$client" "$APP/Contents/Resources/bin/"
                    cp "$client" "$APP/Contents/MacOS/"
                    chmod +x "$APP/Contents/Resources/bin/$base" "$APP/Contents/MacOS/$base"
                  fi
                done
              fi
              if [ -d "${weston}/share/weston" ]; then
                mkdir -p "$APP/share/weston"
                cp -r "${weston}/share/weston/"* "$APP/share/weston/"
                if [ ! -f "$APP/share/weston/terminal.png" ] && [ -f "$APP/share/weston/icon_terminal.png" ]; then
                  ln -sf icon_terminal.png "$APP/share/weston/terminal.png"
                fi
              fi
              if [ -d "${weston}/lib/weston" ]; then
                mkdir -p "$APP/lib/weston"
                cp -r "${weston}/lib/weston/"* "$APP/lib/weston/"
              fi
              if [ -d "${weston}/lib/libweston-13" ]; then
                mkdir -p "$APP/lib/libweston-13"
                cp -r "${weston}/lib/libweston-13/"* "$APP/lib/libweston-13/"
              fi
              CURSOR_SRC="${pkgs.adwaita-icon-theme}/share/icons/Adwaita/cursors"
              if [ -d "$CURSOR_SRC" ]; then
                mkdir -p "$APP/share/icons/Adwaita"
                cp -r "$CURSOR_SRC" "$APP/share/icons/Adwaita/cursors"
              fi
              WA_FONTS="${wawonaBundledFonts}"
              rm -rf "$APP/share/fonts" "$APP/Contents/Resources/share/fonts"
              mkdir -p "$APP/share/fonts" "$APP/Contents/Resources/share/fonts"
              cp -RL "$WA_FONTS/share/fonts/." "$APP/share/fonts/"
              cp -RL "$WA_FONTS/share/fonts/." "$APP/Contents/Resources/share/fonts/"
              chmod -R u+w "$APP/share/fonts" "$APP/Contents/Resources/share/fonts"

              ${bundleMacOSAppDylibs}
              ${bundleIlandBaremetalDylib}
              echo "Bundling portable dylibs for Xcode-built Wawona.app..."
              bundle_macos_app_dylibs "$APP"
              ${lib.optionalString (ilandBaremetal != null) ''bundle_iland_baremetal_dylib "$APP"''}

              mkdir -p $project
              cp -r . "$project/"
              chmod -R u+w $project
              rm -rf "$project/_xcode_project/DerivedData" "$project/DerivedData"
              if [ -n "${toString xcodeProject}" ]; then
                cp -r ${xcodeProject}/* "$project/"
                chmod -R u+w $project
              fi

              runHook postInstall
              exit 0
            fi
            
            mkdir -p $out/Applications/Wawona.app/Contents/MacOS
            mkdir -p $out/Applications/Wawona.app/Contents/Resources
            
            cp Wawona $out/Applications/Wawona.app/Contents/MacOS/
            if [ -d src/resources/macos ]; then
              mkdir -p $out/Applications/Wawona.app/Contents/Resources/macos
              cp -R src/resources/macos/. $out/Applications/Wawona.app/Contents/Resources/macos/
            fi

            # Populate project output
            mkdir -p $project
            # Copy sources (current build dir)
            cp -r . "$project/"
            chmod -R u+w $project
            rm -rf "$project/_xcode_project/DerivedData" "$project/DerivedData"
            if [ -n "${toString xcodeProject}" ]; then
              cp -r ${xcodeProject}/* "$project/"
              chmod -R u+w $project
            fi
            
            if command -v codesign >/dev/null 2>&1; then
              echo "Signing Wawona main binary..."
              codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/MacOS/Wawona" || echo "Warning: Failed to sign Wawona main binary"
            fi
            
            if [ -f metal_shaders.metallib ]; then
              cp metal_shaders.metallib $out/Applications/Wawona.app/Contents/MacOS/
            fi
            
            echo "DEBUG: Looking for sshpass binary in buildInputs..."
            SSHPASS_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/sshpass" ]; then
                SSHPASS_BIN="$dep/bin/sshpass"
                break
              fi
            done
            
            if [ -n "$SSHPASS_BIN" ] && [ -f "$SSHPASS_BIN" ]; then
              install -m 755 "$SSHPASS_BIN" $out/Applications/Wawona.app/Contents/MacOS/sshpass
              mkdir -p $out/Applications/Wawona.app/Contents/Resources/bin
              install -m 755 "$SSHPASS_BIN" $out/Applications/Wawona.app/Contents/Resources/bin/sshpass
              
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/MacOS/sshpass" 2>/dev/null || echo "Warning: Failed to code sign sshpass"
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/Resources/bin/sshpass" 2>/dev/null || true
              fi
            fi
            
            echo "DEBUG: Looking for OpenSSH client tools in buildInputs (wwn-ssh macOS backend)..."
            OPENSSH_BIN_DIR=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/ssh" ] && [ -f "$dep/bin/ssh-keygen" ]; then
                OPENSSH_BIN_DIR="$dep/bin"
                break
              fi
            done

            if [ -n "$OPENSSH_BIN_DIR" ]; then
              mkdir -p $out/Applications/Wawona.app/Contents/Resources/bin
              for tool in ssh ssh-keygen scp sftp ssh-agent ssh-add; do
                if [ -f "$OPENSSH_BIN_DIR/$tool" ]; then
                  install -m 755 "$OPENSSH_BIN_DIR/$tool" $out/Applications/Wawona.app/Contents/Resources/bin/$tool
                  if command -v codesign >/dev/null 2>&1; then
                    codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/Resources/bin/$tool" 2>/dev/null || true
                  fi
                fi
              done
              echo "Bundled OpenSSH client tools from $OPENSSH_BIN_DIR"
            else
              echo "WARNING: OpenSSH client tools not found in buildInputs"
            fi

            echo "DEBUG: Looking for waypipe binary in buildInputs..."
            WAYPIPE_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/waypipe" ]; then
                WAYPIPE_BIN="$dep/bin/waypipe"
                break
              fi
            done
            
            if [ -n "$WAYPIPE_BIN" ] && [ -f "$WAYPIPE_BIN" ]; then
              mkdir -p $out/Applications/Wawona.app/Contents/Resources/bin
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/Contents/MacOS/waypipe
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/Contents/Resources/bin/waypipe
              
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/MacOS/waypipe" 2>/dev/null || echo "Warning: Failed to code sign waypipe"
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/Resources/bin/waypipe" 2>/dev/null || true
              fi
            fi
            
            # Bundle Weston clients (weston package postInstall verifies bin/ completeness).
            echo "DEBUG: Bundling Weston clients..."
            mkdir -p $out/Applications/Wawona.app/Contents/Resources/bin
            if [ -d "${weston}/bin" ]; then
              for client in "${weston}/bin"/weston*; do
                base="$(basename "$client")"
                case "$base" in *.so|*.dylib) continue ;; esac
                if [ -f "$client" ]; then
                  cp "$client" $out/Applications/Wawona.app/Contents/Resources/bin/
                  cp "$client" $out/Applications/Wawona.app/Contents/MacOS/
                  chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/"$base"
                  chmod +x $out/Applications/Wawona.app/Contents/MacOS/"$base"
                fi
              done
            else
               echo "Warning: Weston bin directory not found at ${weston}/bin"
            fi

            # Weston shell helpers (weston-desktop-shell / weston-keyboard /
            # weston-simple-im). desktop-shell.so spawns weston-desktop-shell from
            # a compiled-in libexec path that is a build-time-only nix output and
            # does not exist at runtime; bundle the helpers next to the app binary
            # and override [shell] client= in weston.ini (WWNWaypipeRunner).
            if [ -d "${weston}/libexec" ]; then
              for helper in "${weston}/libexec"/weston-*; do
                [ -f "$helper" ] || continue
                hbase="$(basename "$helper")"
                cp "$helper" $out/Applications/Wawona.app/Contents/Resources/bin/
                cp "$helper" $out/Applications/Wawona.app/Contents/MacOS/
                chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/"$hbase"
                chmod +x $out/Applications/Wawona.app/Contents/MacOS/"$hbase"
                echo "DEBUG: Bundled weston helper $hbase"
              done
            else
              echo "Warning: Weston libexec not found at ${weston}/libexec"
            fi

            # Weston nested compositor: shell/backends, PNG assets, cursors.
            APP="$out/Applications/Wawona.app"
            if [ -d "${weston}/share/weston" ]; then
              mkdir -p "$APP/share/weston"
              cp -r "${weston}/share/weston/"* "$APP/share/weston/"
              if [ ! -f "$APP/share/weston/terminal.png" ] && [ -f "$APP/share/weston/icon_terminal.png" ]; then
                ln -sf icon_terminal.png "$APP/share/weston/terminal.png"
              fi
              echo "DEBUG: Bundled share/weston assets"
            fi
            if [ -d "${weston}/lib/weston" ]; then
              mkdir -p "$APP/lib/weston"
              cp -r "${weston}/lib/weston/"* "$APP/lib/weston/"
              echo "DEBUG: Bundled lib/weston modules"
            fi
            if [ -d "${weston}/lib/libweston-13" ]; then
              mkdir -p "$APP/lib/libweston-13"
              cp -r "${weston}/lib/libweston-13/"* "$APP/lib/libweston-13/"
              echo "DEBUG: Bundled lib/libweston-13 backends"
            fi
            CURSOR_SRC="${pkgs.adwaita-icon-theme}/share/icons/Adwaita/cursors"
            if [ -d "$CURSOR_SRC" ]; then
              mkdir -p "$APP/share/icons/Adwaita"
              cp -r "$CURSOR_SRC" "$APP/share/icons/Adwaita/cursors"
              echo "DEBUG: Bundled Adwaita cursors"
            fi
            WA_FONTS="${wawonaBundledFonts}"
            rm -rf "$APP/share/fonts" "$APP/Contents/Resources/share/fonts"
            mkdir -p "$APP/share/fonts" "$APP/Contents/Resources/share/fonts"
            cp -RL "$WA_FONTS/share/fonts/." "$APP/share/fonts/"
            # Mirror under Contents/Resources/share for Resource-relative
            # lookups (foot/fcft + older ShareRoot layouts).
            cp -RL "$WA_FONTS/share/fonts/." "$APP/Contents/Resources/share/fonts/"
            chmod -R u+w "$APP/share/fonts" "$APP/Contents/Resources/share/fonts"
            echo "DEBUG: Bundled Wawona fonts (DejaVu + DejaVuSansM Nerd Font Mono)"

            # Bundle foot terminal
            ${if foot != null then ''
            if [ -f "${foot}/bin/foot" ]; then
              cp "${foot}/bin/foot" $out/Applications/Wawona.app/Contents/Resources/bin/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/foot
              if [ -f "${foot}/bin/.foot-wrapped" ]; then
                cp "${foot}/bin/.foot-wrapped" $out/Applications/Wawona.app/Contents/Resources/bin/
                chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/.foot-wrapped
              fi
              echo "DEBUG: Bundled foot terminal"
            else
              echo "Warning: foot binary not found at ${foot}/bin/foot"
            fi
            '' else ''
            echo "Warning: foot not provided, skipping foot bundling"
            ''}

            # Bundle niri (scrollable-tiling compositor, runs nested under Wawona)
            ${if niri != null then ''
            if [ -f "${niri}/bin/niri" ]; then
              cp "${niri}/bin/niri" $out/Applications/Wawona.app/Contents/Resources/bin/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/niri
              if [ -f "${niri}/share/niri/default-config.kdl" ]; then
                mkdir -p "$APP/share/niri"
                cp "${niri}/share/niri/default-config.kdl" "$APP/share/niri/default-config.kdl"
              fi
              echo "DEBUG: Bundled niri (nested compositor)"
            else
              echo "Warning: niri binary not found at ${niri}/bin/niri"
            fi
            '' else ''
            echo "Warning: niri not provided, skipping niri bundling"
            ''}

            # Bundle fuzzel (niri Mod+D launcher)
            ${if fuzzel != null then ''
            if [ -f "${fuzzel}/bin/fuzzel" ]; then
              cp "${fuzzel}/bin/fuzzel" $out/Applications/Wawona.app/Contents/Resources/bin/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/fuzzel
              echo "DEBUG: Bundled fuzzel launcher"
            else
              echo "Warning: fuzzel binary not found at ${fuzzel}/bin/fuzzel"
            fi
            '' else ''
            echo "Warning: fuzzel not provided, skipping fuzzel bundling"
            ''}

            # Freedesktop catalog for fuzzel (share/applications + hicolor icons).
            # Runtime prepends XDG_DATA_DIRS=$WAWONA_SHARE_ROOT (issue #78).
            # Install at both App/share (nix layout) and Contents/Resources/share
            # (Xcode Bundle Executables layout) so ShareRoot preference always
            # finds applications/ on either packaging path.
            if [ -d "${applicationsCatalog}/share/applications" ]; then
              mkdir -p "$APP/share/applications" "$APP/share/icons"
              cp -R "${applicationsCatalog}/share/applications/." "$APP/share/applications/"
              cp -R "${applicationsCatalog}/share/icons/hicolor" "$APP/share/icons/"
              mkdir -p "$APP/Contents/Resources/share/applications" \
                       "$APP/Contents/Resources/share/icons"
              cp -R "${applicationsCatalog}/share/applications/." \
                "$APP/Contents/Resources/share/applications/"
              cp -R "${applicationsCatalog}/share/icons/hicolor" \
                "$APP/Contents/Resources/share/icons/"
              echo "DEBUG: Bundled fuzzel applications catalog"
            fi

            # Bundle fastfetch
            ${if fastfetch != null then ''
            if [ -f "${fastfetch}/bin/fastfetch" ]; then
              cp "${fastfetch}/bin/fastfetch" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${fastfetch}/bin/fastfetch" $out/Applications/Wawona.app/Contents/MacOS/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/fastfetch
              chmod +x $out/Applications/Wawona.app/Contents/MacOS/fastfetch
              echo "DEBUG: Bundled fastfetch"
            else
              echo "Warning: fastfetch binary not found at ${fastfetch}/bin/fastfetch"
            fi
            '' else ''
            echo "Warning: fastfetch not provided, skipping fastfetch bundling"
            ''}

            # Bundle phoon (clean-room Rust moon-phase utility). macOS uses the
            # native process model, so the CLI is bundled on PATH like fastfetch;
            # the in-process dispatcher also resolves phoon_main when linked.
            ${if phoon != null then ''
            if [ -f "${phoon}/bin/phoon" ]; then
              cp "${phoon}/bin/phoon" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${phoon}/bin/phoon" $out/Applications/Wawona.app/Contents/MacOS/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/phoon
              chmod +x $out/Applications/Wawona.app/Contents/MacOS/phoon
              echo "DEBUG: Bundled phoon"
            else
              echo "Warning: phoon binary not found at ${phoon}/bin/phoon"
            fi
            '' else ''
            echo "Warning: phoon not provided, skipping phoon bundling"
            ''}

            # Bundle wasm Runtime CLI + wpm (wwn-wasm). macOS may fork/exec;
            # Apple mobile uses the in-process C ABI instead.
            ${if wawonaWasm != null then ''
            if [ -f "${wawonaWasm}/bin/wasm" ]; then
              cp "${wawonaWasm}/bin/wasm" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${wawonaWasm}/bin/wasm" $out/Applications/Wawona.app/Contents/MacOS/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/wasm
              chmod +x $out/Applications/Wawona.app/Contents/MacOS/wasm
              echo "DEBUG: Bundled wasm"
            else
              echo "Warning: wasm binary not found at ${wawonaWasm}/bin/wasm"
            fi
            if [ -f "${wawonaWasm}/bin/wpm" ]; then
              cp "${wawonaWasm}/bin/wpm" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${wawonaWasm}/bin/wpm" $out/Applications/Wawona.app/Contents/MacOS/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/wpm
              chmod +x $out/Applications/Wawona.app/Contents/MacOS/wpm
              echo "DEBUG: Bundled wpm"
            else
              echo "Warning: wpm binary not found at ${wawonaWasm}/bin/wpm"
            fi
            '' else ''
            echo "Warning: wawona-wasm not provided, skipping wasm/wpm bundling"
            ''}

            # Bundle neovim
            ${if neovim != null then ''
            if [ -f "${neovim}/bin/nvim" ]; then
              cp "${neovim}/bin/nvim" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${neovim}/bin/nvim" $out/Applications/Wawona.app/Contents/MacOS/
              cp "${neovim}/bin/nvim" $out/Applications/Wawona.app/Contents/Resources/bin/vi
              cp "${neovim}/bin/nvim" $out/Applications/Wawona.app/Contents/MacOS/vi
              cp "${neovim}/bin/nvim" $out/Applications/Wawona.app/Contents/Resources/bin/vim
              cp "${neovim}/bin/nvim" $out/Applications/Wawona.app/Contents/MacOS/vim
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/nvim \
                $out/Applications/Wawona.app/Contents/MacOS/nvim \
                $out/Applications/Wawona.app/Contents/Resources/bin/vi \
                $out/Applications/Wawona.app/Contents/MacOS/vi \
                $out/Applications/Wawona.app/Contents/Resources/bin/vim \
                $out/Applications/Wawona.app/Contents/MacOS/vim
              echo "DEBUG: Bundled neovim (nvim/vi/vim)"
            else
              echo "Warning: neovim binary not found at ${neovim}/bin/nvim"
            fi
            '' else ''
            echo "Warning: neovim not provided, skipping neovim bundling"
            ''}

            ${if zsh != null then ''
            if [ -f "${zsh}/bin/zsh" ]; then
              cp "${zsh}/bin/zsh" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${zsh}/bin/zsh" $out/Applications/Wawona.app/Contents/MacOS/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/zsh
              chmod +x $out/Applications/Wawona.app/Contents/MacOS/zsh
              echo "DEBUG: Bundled zsh"
            fi
            '' else ''
            ''}

            ${if kmscube != null then ''
            if [ -f "${kmscube}/bin/kmscube" ]; then
              cp "${kmscube}/bin/kmscube" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${kmscube}/bin/kmscube" $out/Applications/Wawona.app/Contents/MacOS/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/kmscube
              chmod +x $out/Applications/Wawona.app/Contents/MacOS/kmscube
              echo "DEBUG: Bundled kmscube"
            fi
            '' else ''
            ''}

            ${if modebTty != null then ''
            if [ -f "${modebTty}/bin/modeb-ttyd" ]; then
              cp "${modebTty}/bin/modeb-ttyd" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${modebTty}/bin/modeb-ttyd" $out/Applications/Wawona.app/Contents/MacOS/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/modeb-ttyd
              chmod +x $out/Applications/Wawona.app/Contents/MacOS/modeb-ttyd
              # CLI alias used by Desktop Machine NativeClientId=modeb-tty
              ln -sf modeb-ttyd $out/Applications/Wawona.app/Contents/Resources/bin/modeb-tty
              ln -sf modeb-ttyd $out/Applications/Wawona.app/Contents/MacOS/modeb-tty
              echo "DEBUG: Bundled modeb-ttyd"
            fi
            '' else ''
            ''}

            ${if effectiveNativeDeps."opengl-cube" or null != null then ''
            if [ -f "${effectiveNativeDeps."opengl-cube"}/bin/opengl-cube" ]; then
              cp "${effectiveNativeDeps."opengl-cube"}/bin/opengl-cube" $out/Applications/Wawona.app/Contents/Resources/bin/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/opengl-cube
              echo "DEBUG: Bundled opengl-cube"
            fi
            '' else ''
            ''}

            ${if effectiveNativeDeps.vkcube or null != null then ''
            if [ -f "${effectiveNativeDeps.vkcube}/bin/vkcube" ]; then
              cp "${effectiveNativeDeps.vkcube}/bin/vkcube" $out/Applications/Wawona.app/Contents/Resources/bin/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/vkcube
              echo "DEBUG: Bundled vkcube (Wayland)"
            fi
            '' else ''
            ''}

            ${if effectiveNativeDeps."weston-simple-egl" or null != null then ''
            if [ -f "${effectiveNativeDeps."weston-simple-egl"}/bin/weston-simple-egl" ]; then
              cp "${effectiveNativeDeps."weston-simple-egl"}/bin/weston-simple-egl" $out/Applications/Wawona.app/Contents/Resources/bin/
              cp "${effectiveNativeDeps."weston-simple-egl"}/bin/weston-simple-egl" $out/Applications/Wawona.app/Contents/MacOS/
              chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/weston-simple-egl
              chmod +x $out/Applications/Wawona.app/Contents/MacOS/weston-simple-egl
              echo "DEBUG: Bundled weston-simple-egl"
            fi
            '' else ''
            ''}
            
            if command -v codesign >/dev/null 2>&1; then
                find "$out/Applications/Wawona.app/Contents/Resources/bin" -type f -perm +111 -exec codesign --force --sign - --timestamp=none {} \; 2>/dev/null || true
            fi

            # Prepare directories for Vulkan drivers
            mkdir -p $out/Applications/Wawona.app/Contents/Frameworks
            mkdir -p $out/Applications/Wawona.app/Contents/Resources/vulkan/icd.d

            # Bundle MoltenVK Vulkan driver if available
            ${lib.optionalString (moltenvk != null) ''
              echo "DEBUG: Bundling MoltenVK Vulkan driver..."
              MVK_DYLIB=""
              for f in ${moltenvk}/lib/libMoltenVK*.dylib; do
                if [ -f "$f" ]; then
                  MVK_DYLIB="$f"
                  break
                fi
              done
              if [ -n "$MVK_DYLIB" ] && [ -f "$MVK_DYLIB" ]; then
                MVK_DYLIB_NAME=$(basename "$MVK_DYLIB")
                cp "$MVK_DYLIB" "$out/Applications/Wawona.app/Contents/Frameworks/$MVK_DYLIB_NAME"
                # Check for existing MoltenVK ICD manifest
                MVK_ICD=""
                for f in ${moltenvk}/share/vulkan/icd.d/MoltenVK_icd*.json; do
                  if [ -f "$f" ]; then
                    MVK_ICD="$f"
                    break
                  fi
                done
                if [ -n "$MVK_ICD" ]; then
                  cp "$MVK_ICD" "$out/Applications/Wawona.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json"
                  sed -i "s|\"library_path\":.*|\"library_path\": \"../../../Frameworks/$MVK_DYLIB_NAME\",|" \
                    "$out/Applications/Wawona.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json"
                else
                  cat > "$out/Applications/Wawona.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json" <<MVK_ICD_EOF
              {
                  "file_format_version": "1.0.1",
                  "ICD": {
                      "library_path": "../../../Frameworks/$MVK_DYLIB_NAME",
                      "api_version": "1.2.0",
                      "is_portability_driver": true
                  }
              }
MVK_ICD_EOF
                fi
                echo "Bundled MoltenVK: $MVK_DYLIB_NAME"
                if command -v codesign >/dev/null 2>&1; then
                  codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/Frameworks/$MVK_DYLIB_NAME" 2>/dev/null || echo "Warning: Failed to sign MoltenVK dylib"
                fi
              else
                echo "Info: MoltenVK .dylib not found, skipping"
              fi
            ''}

            # Bundle Mesa KosmicKrisp as an explicit alternative ICD.
            ${lib.optionalString (kosmickrisp != null) ''
              KK_DYLIB="${kosmickrisp}/lib/libvulkan_kosmickrisp.dylib"
              KK_ICD="${kosmickrisp}/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json"
              test -f "$KK_DYLIB"
              test -f "$KK_ICD"
              cp "$KK_DYLIB" "$out/Applications/Wawona.app/Contents/Frameworks/"
              cp "$KK_ICD" "$out/Applications/Wawona.app/Contents/Resources/vulkan/icd.d/kosmickrisp_icd.json"
              sed -i 's|"library_path":[[:space:]]*"[^"]*"|"library_path": "../../../Frameworks/libvulkan_kosmickrisp.dylib"|' \
                "$out/Applications/Wawona.app/Contents/Resources/vulkan/icd.d/kosmickrisp_icd.json"
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --sign - --timestamp=none \
                  "$out/Applications/Wawona.app/Contents/Frameworks/libvulkan_kosmickrisp.dylib"
              fi
            ''}
            
            cat > $out/Applications/Wawona.app/Contents/Info.plist <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Wawona</string>
    <key>CFBundleIdentifier</key>
    <string>com.aspauldingcode.Wawona</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Wawona</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${projectVersion}</string>
    <key>CFBundleVersion</key>
    <string>${projectVersionPatch}</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025-${currentYear} Alex Spaulding. All rights reserved.</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIcons</key>
    <dict>
        <key>CFBundlePrimaryIcon</key>
        <dict>
            <key>CFBundleIconName</key>
            <string>AppIcon</string>
        </dict>
    </dict>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Wawona needs access to your local network to connect to SSH hosts.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST_EOF

            ${installMacOSIcons}

            ${bundleMacOSAppDylibs}
            ${bundleIlandBaremetalDylib}
            echo "Bundling portable dylibs into Wawona.app..."
            bundle_macos_app_dylibs "$out/Applications/Wawona.app"
            ${lib.optionalString (ilandBaremetal != null) ''bundle_iland_baremetal_dylib "$out/Applications/Wawona.app"''}
            if command -v codesign >/dev/null 2>&1; then
              find "$out/Applications/Wawona.app/Contents/Frameworks" -type f -name '*.dylib' \
                -exec codesign --force --sign - --timestamp=none {} \; 2>/dev/null || true
              codesign --force --sign - --timestamp=none \
                "$out/Applications/Wawona.app/Contents/MacOS/Wawona" 2>/dev/null || true
            fi

            runHook postInstall
    '';

    postInstall = ''
      mkdir -p $out/bin
      ln -s $out/Applications/Wawona.app/Contents/MacOS/Wawona $out/bin/Wawona
      ln -s $out/Applications/Wawona.app/Contents/MacOS/Wawona $out/bin/wawona-macos

      APP="$out/Applications/Wawona.app"
      # Codesign / Gatekeeper: only Contents/ may sit at the .app root. Install
      # phases still stage FHS lib/ + share/ beside Contents for convenience;
      # relocate before sealing so Developer ID notarization can succeed.
      # Assets copied from the nix store are often mode 444. Chmod before rm.
      for d in lib share; do
        if [ -d "$APP/$d" ]; then
          mkdir -p "$APP/Contents/Resources/$d"
          chmod -R u+w "$APP/$d" "$APP/Contents/Resources/$d" 2>/dev/null || true
          cp -a "$APP/$d/." "$APP/Contents/Resources/$d/"
          chmod -R u+w "$APP/$d"
          rm -rf "$APP/$d"
        fi
      done
      for entry in "$APP"/*; do
        [ "$(basename "$entry")" = Contents ] && continue
        echo "ERROR: unexpected .app root entry (breaks codesign): $entry" >&2
        exit 1
      done
      ln -snf $out/Applications/Wawona.app/Contents/Resources/share $out/share
      ln -snf $out/Applications/Wawona.app/Contents/Resources/lib $out/lib

      ${lib.optionalString (kosmickrisp != null) ''
      mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources/vulkan/icd.d"
      cp "${kosmickrisp}/lib/libvulkan_kosmickrisp.dylib" "$APP/Contents/Frameworks/"
      cp "${kosmickrisp}/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json" \
        "$APP/Contents/Resources/vulkan/icd.d/kosmickrisp_icd.json"
      sed -i 's|"library_path":[[:space:]]*"[^"]*"|"library_path": "../../../Frameworks/libvulkan_kosmickrisp.dylib"|' \
        "$APP/Contents/Resources/vulkan/icd.d/kosmickrisp_icd.json"
      if command -v codesign >/dev/null 2>&1; then
        codesign --force --sign - --timestamp=none \
          "$APP/Contents/Frameworks/libvulkan_kosmickrisp.dylib"
        codesign --force --sign - --timestamp=none "$APP"
      fi
      ''}
      for req in \
        "$APP/Contents/Resources/share/weston/pattern.png" \
        "$APP/Contents/Resources/share/weston/terminal.png" \
        "$APP/Contents/Resources/share/fonts/truetype/DejaVuSans.ttf" \
        "$APP/Contents/Resources/share/fonts/truetype/DejaVuSansMNerdFontMono-Regular.ttf"; do
        if [ ! -e "$req" ]; then
          echo "ERROR: required bundled asset missing: $req" >&2
          exit 1
        fi
      done
      echo "Verified macOS bundled weston/fonts/backend assets"
      ${if ilandBaremetal != null then ''
      if [ ! -f "$APP/Contents/Library/Wawona/iland/libwayland-mac.dylib" ]; then
        echo "ERROR: desktop-host build missing Mode B dylib" >&2
        exit 1
      fi
      if [ ! -x "$APP/Contents/Library/Wawona/wwn-iowatchdog" ]; then
        echo "ERROR: desktop-host build missing wwn-iowatchdog" >&2
        exit 1
      fi
      if [ ! -x "$APP/Contents/Library/Wawona/wwn-iowatchdog-claim-install" ]; then
        echo "ERROR: desktop-host build missing wwn-iowatchdog-claim-install" >&2
        exit 1
      fi
      if [ ! -f "$APP/Contents/Library/Wawona/lib/libwwn_watchdogd_hook.dylib" ]; then
        echo "ERROR: desktop-host build missing Path B hook under lib/" >&2
        exit 1
      fi
      echo "Verified Mode B dylib + wwn-iowatchdog + claim-install + hook (desktop-host)"
      # Classic Mode B fork/exec needs shared DRM modules (macos-drm-shared.nix).
      _drm_so=
      for _cand in \
        "$APP/Contents/Resources/lib/libweston-13/drm-backend.so" \
        "$APP/Contents/Resources/lib/libweston-14/drm-backend.so" \
        "$APP/Contents/MacOS/lib/libweston-13/drm-backend.so"; do
        if [ -e "$_cand" ]; then _drm_so="$_cand"; break; fi
      done
      if [ -z "$_drm_so" ]; then
        _drm_so=$(find "$APP/Contents" -name 'drm-backend.so' 2>/dev/null | head -1)
      fi
      if [ -z "$_drm_so" ] || [ ! -e "$_drm_so" ]; then
        echo "ERROR: desktop-host missing libweston drm-backend.so (Mode B Classic)" >&2
        find "$APP/Contents" -path '*libweston*' -name '*backend*' 2>/dev/null || true
        exit 1
      fi
      if [ ! -e "$(dirname "$_drm_so")/gl-renderer.so" ]; then
        echo "ERROR: desktop-host missing gl-renderer.so next to drm-backend.so" >&2
        exit 1
      fi
      echo "Verified Mode B weston DRM modules: $_drm_so"
      '' else ''
      if [ -f "$APP/Contents/Library/Wawona/iland/libwayland-mac.dylib" ]; then
        echo "ERROR: store-safe/default macOS build must not ship Mode B dylib" >&2
        exit 1
      fi
      echo "Verified Mode B dylib absent (store-safe / Mode A)"
      ''}
    '';
  }
