{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  wawonaVersion ? null,
  rustBackend,
  weston,
  foot ? null,
  waylandVersion ? "unknown",
  xkbcommonVersion ? "unknown",
  lz4Version ? "unknown",
  zstdVersion ? "unknown",
  libffiVersion ? "unknown",
  sshpassVersion ? "unknown",
  waypipeVersion ? "unknown",
  waypipe,
  moltenvk ? pkgs.moltenvk or null,
  xcodeProject ? null,
}:

let
  common = import ./common.nix { inherit lib pkgs wawonaSrc; };
  
  xcodeUtils = import ../apple/default.nix { inherit lib pkgs; };
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
    if [ -d "''$APPICONSET" ] && [ -f "''$APPICONSET/AppIcon-Dark-1024.png" ]; then
      cp "''$APPICONSET/AppIcon-Dark-1024.png" "''$RESOURCES/AppIcon-Dark.png"
    fi
    if [ -f "''$ICON_ROOT/Wawona-iOS-Dark-1024x1024@1x.png" ]; then
      cp "''$ICON_ROOT/Wawona-iOS-Dark-1024x1024@1x.png" "''$RESOURCES/"
    fi
    if [ -f "''$ICON_ROOT/Wawona-iOS-Light-1024x1024@1x.png" ]; then
      cp "''$ICON_ROOT/Wawona-iOS-Light-1024x1024@1x.png" "''$RESOURCES/"
    fi

    # Wawona.png for [NSImage imageNamed:@"Wawona"] fallback
    for candidate in "Assets.xcassets/AppIcon.appiconset/AppIcon-Light-1024.png" \
                     "Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png" \
                     "Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" \
                     "Wawona-iOS-Light-1024x1024@1x.png" \
                     "Wawona-iOS-Dark-1024x1024@1x.png"; do
      if [ -f "''$ICON_ROOT/''$candidate" ]; then
        cp "''$ICON_ROOT/''$candidate" "''$RESOURCES/Wawona.png"
        echo "Installed Wawona.png for About/Settings fallback"
        break
      fi
    done

    # Menubar icon must use the dedicated monochrome silhouette asset.
    if [ -f "''$ICON_BUNDLE/Assets/wayland.png" ]; then
      cp "''$ICON_BUNDLE/Assets/wayland.png" "''$RESOURCES/Wawona-menubar-silhouette.png"
      echo "Installed Wawona-menubar-silhouette.png from Wawona.icon/Assets/wayland.png"
    else
      # Fallback only if the dedicated silhouette is missing.
      for candidate in "Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png" \
                       "Wawona-iOS-Dark-1024x1024@1x.png" \
                       "Assets.xcassets/AppIcon.appiconset/AppIcon-Light-1024.png" \
                       "Wawona-iOS-Light-1024x1024@1x.png"; do
        if [ -f "''$ICON_ROOT/''$candidate" ]; then
          cp "''$ICON_ROOT/''$candidate" "''$RESOURCES/Wawona-menubar-silhouette.png"
          echo "Installed Wawona-menubar-silhouette.png from fallback source"
          break
        fi
      done
    fi
  '';

  generateIcons = platform: ''
    mkdir -p "$out/Applications/Wawona.app/Contents/Resources"
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
      rustBackend
      waypipe
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
        mkdir -p "$TMPDIR/wawona-home"
        export HOME="$TMPDIR/wawona-home"
        # Keep Nix as the orchestrator, but isolate xcodebuild from cc-wrapper
        # and NIX_* flags that can leak invalid linker options into Apple's ld.
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
          xcodebuild \
          -project "./_xcode_project/Wawona.xcodeproj" \
          -scheme "Wawona-macOS" \
          -configuration Release \
          -derivedDataPath "./_xcode_project/DerivedData" \
          -destination "platform=macOS" \
          CODE_SIGNING_ALLOWED=NO \
          CODE_SIGNING_REQUIRED=NO \
          build; then
          XCODE_APP="./_xcode_project/DerivedData/Build/Products/Release/Wawona.app"
          if [ -d "$XCODE_APP" ]; then
            mkdir -p xcodebuild-out
            cp -R "$XCODE_APP" "xcodebuild-out/Wawona.app"
            touch .use_xcodebuild_app
            echo "✅ Xcode project build produced Wawona.app"
          else
            echo "⚠️  Xcode project build completed but Wawona.app was not found; continuing with manual fallback."
          fi
        else
          echo "⚠️  Xcode project build failed; continuing with manual fallback."
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
               -Idependencies/clients/wawona-shell/src \
               -Imacos-dependencies/include \
               -Imacos-dependencies/uniffi \
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

      XKBCOMMON_LIBS=$(pkg-config --libs xkbcommon 2>/dev/null || echo "-Lmacos-dependencies/lib -lxkbcommon")
      WAYLAND_LIBS=$(pkg-config --libs wayland-client wayland-server 2>/dev/null || echo "-Lmacos-dependencies/lib -lwayland-client -lwayland-server")
      OPENSSL_LIBS=$(pkg-config --libs openssl 2>/dev/null || echo "-Lmacos-dependencies/lib -lssl -lcrypto")
      ZLIB_LIBS=$(pkg-config --libs zlib 2>/dev/null || echo "-Lmacos-dependencies/lib -lz")
      LINKER_BIN="''${SWIFTC_BIN:-$CC}"
      LINK_SYSROOT_ARGS="$TARGET_LDFLAGS"
      LINK_OPT_FLAGS="-fobjc-arc -flto -O3"
      LINK_OBJC_FLAG="-ObjC"
      LINK_RPATH_FLAG="-Wl,-rpath,\$PWD/macos-dependencies/lib"
      if [ -n "''${SWIFTC_BIN:-}" ] && [ "$LINKER_BIN" = "$SWIFTC_BIN" ]; then
        LINK_SYSROOT_ARGS="-sdk ''${SDKROOT:-}"
        LINK_OPT_FLAGS="-Xlinker -dead_strip"
        LINK_OBJC_FLAG="-Xlinker -ObjC"
        LINK_RPATH_FLAG="-Xlinker -rpath -Xlinker $PWD/macos-dependencies/lib"
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
         ${rustBackend}/lib/libwawona.a \
         $LINK_SYSROOT_ARGS \
         $LINK_OPT_FLAGS \
         $LINK_OBJC_FLAG \
         $LINK_RPATH_FLAG \
         -o Wawona

      runHook postBuild
      fi
    '';

    installPhase = ''
            runHook preInstall

            if [ -f .use_xcodebuild_app ] && [ -d "xcodebuild-out/Wawona.app" ]; then
              mkdir -p $out/Applications
              cp -R "xcodebuild-out/Wawona.app" "$out/Applications/Wawona.app"

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
            
            # Bundle Weston clients
            echo "DEBUG: Bundling Weston clients..."
            mkdir -p $out/Applications/Wawona.app/Contents/Resources/bin
            if [ -d "${weston}/bin" ]; then
              # Weston compositor and weston-terminal (used by Settings)
              for client in weston weston-terminal; do
                if [ -f "${weston}/bin/$client" ]; then
                  cp "${weston}/bin/$client" $out/Applications/Wawona.app/Contents/Resources/bin/
                  cp "${weston}/bin/$client" $out/Applications/Wawona.app/Contents/MacOS/
                  chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/$client
                  chmod +x $out/Applications/Wawona.app/Contents/MacOS/$client
                fi
              done
              # Other useful clients
              for client in weston-simple-egl weston-simple-shm weston-flower weston-smoke weston-resizor weston-scaler; do
                 if [ -f "${weston}/bin/$client" ]; then
                   cp "${weston}/bin/$client" $out/Applications/Wawona.app/Contents/Resources/bin/
                   cp "${weston}/bin/$client" $out/Applications/Wawona.app/Contents/MacOS/
                   chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/$client
                   chmod +x $out/Applications/Wawona.app/Contents/MacOS/$client
                 fi
              done
            else
               echo "Warning: Weston bin directory not found at ${weston}/bin"
            fi

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
                  sed -i "s|\"library_path\":.*|\"library_path\": \"../../Frameworks/$MVK_DYLIB_NAME\",|" \
                    "$out/Applications/Wawona.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json"
                else
                  cat > "$out/Applications/Wawona.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json" <<MVK_ICD_EOF
              {
                  "file_format_version": "1.0.1",
                  "ICD": {
                      "library_path": "../../Frameworks/$MVK_DYLIB_NAME",
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

            runHook postInstall
    '';

    postInstall = ''
      mkdir -p $out/bin
      ln -s $out/Applications/Wawona.app/Contents/MacOS/Wawona $out/bin/Wawona
      ln -s $out/Applications/Wawona.app/Contents/MacOS/Wawona $out/bin/wawona-macos
    '';
  }
