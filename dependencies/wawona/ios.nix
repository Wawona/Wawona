{
  lib,
  pkgs,
  buildPackages,
  buildModule,
  wawonaSrc,
  wawonaVersion ? null,
  rustBackend,
  rustBackendSim ? null,
  weston,
  targetPkgs,
  simulator ? true,
  xcodeProject ? null,
  ...
}:

let
  common = import ./common.nix { inherit lib pkgs wawonaSrc; };
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit lib pkgs; };
  ensureIosSimSDK = xcodeUtils.ensureIosSimSDK;
  xcodeEnv =
    platform: ''
      # Strip Nix stdenv's DEVELOPER_DIR to bypass the apple-sdk-14.4 fallback
      unset DEVELOPER_DIR
      
      if [ "${platform}" = "ios-sim" ]; then
        # Use dynamic discovery via xcrun for the simulator
        IOS_SDK=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || {
          echo "Error: Failed to ensure iOS Simulator SDK."
          exit 1
        }
      else
        # Use dynamic discovery for the device
        IOS_SDK=$(${xcodeUtils.ensureIosSDK}/bin/ensure-ios-sdk) || {
          echo "Error: Failed to ensure iOS Device SDK."
          exit 1
        }
      fi
      export SDKROOT="$IOS_SDK"
      export DEVELOPER_DIR=$(echo "$SDKROOT" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
      [ "$DEVELOPER_DIR" = "$SDKROOT" ] && export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
      export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
      echo "Using SDK: $SDKROOT"
      echo "Using Developer Dir: $DEVELOPER_DIR"
    '';
  copyDeps =
    dest: ''
      mkdir -p ${dest}/include ${dest}/lib ${dest}/libdata/pkgconfig
      for dep in $buildInputs; do
        if [ -d "$dep/include" ]; then cp -rn "$dep/include/"* ${dest}/include/ 2>/dev/null || true; fi
        if [ -d "$dep/lib" ]; then
          for lib in "$dep"/lib/*.a; do
            if [ -f "$lib" ]; then
              cp -n "$lib" ${dest}/lib/ 2>/dev/null || true
            fi
          done
        fi
        if [ -d "$dep/lib/pkgconfig" ]; then cp -rn "$dep/lib/pkgconfig/"* ${dest}/libdata/pkgconfig/ 2>/dev/null || true; fi
        if [ -d "$dep/libdata/pkgconfig" ]; then cp -rn "$dep/libdata/pkgconfig/"* ${dest}/libdata/pkgconfig/ 2>/dev/null || true; fi
      done
    '';
  # HIAHKernel removed

  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;

  westonSimpleShmSrc = pkgs.callPackage ../libs/weston-simple-shm/patched-src.nix {};

  effectiveRustBackend = if rustBackendSim != null then rustBackendSim else rustBackend;

  # iOS build needs these copied into ios-dependencies for headers/libs used by
  # generated protocol code and for linking Weston/Waypipe clients.
  iosDeps = [
    "libwayland"
    "xkbcommon"
    "libffi"
    "pixman"
    "zstd"
    "lz4"
    "libssh2"
    "mbedtls"
    "openssl"
    "epoll-shim"
    "waypipe"
  ];

  getDeps =
    platform: depNames:
    map (
      name:
      if name == "pixman" then
        if platform == "ios" then
          buildModule.buildForIOS "pixman" { simulator = true; }
        else
          pkgs.pixman
      else if name == "vulkan-headers" then
        pkgs.vulkan-headers
      else if name == "vulkan-loader" then
        pkgs.vulkan-loader
      else if name == "xkbcommon" then
        if platform == "ios" then
          buildModule.buildForIOS "xkbcommon" { simulator = true; }
        else
          pkgs.libxkbcommon
      else if name == "libssh2" then
        buildModule.buildForIOS "libssh2" { simulator = true; }
      else if name == "mbedtls" then
        buildModule.buildForIOS "mbedtls" { simulator = true; }
      else
        buildModule.buildForIOS name { simulator = true; }
    ) depNames;

  iosSources = common.commonSources ++ [
    # iOS-only platform files (WWN prefix)
    "src/platform/ios/WWNCompositorView_ios.m"
    "src/platform/ios/WWNCompositorView_ios.h"
    "src/platform/ios/WWNSceneDelegate.m"
    "src/platform/ios/WWNSceneDelegate.h"
    "src/platform/ios/WWNIOSVersions.h"
    # Launcher client (requires generated Wayland headers from Nix build)
    "src/launcher/WWNLauncherClient.m"
    "src/launcher/WWNLauncherClient.h"
  ];

  iosSourcesFiltered = common.filterSources iosSources;

  commonCFlags = [
    "-Wall"
    "-Wextra"
    "-Wpedantic"
    "-Werror"
    "-Wstrict-prototypes"
    "-Wmissing-prototypes"
    "-Wold-style-definition"
    "-Wmissing-declarations"
    "-Wuninitialized"
    "-Winit-self"
    "-Wpointer-arith"
    "-Wcast-qual"
    "-Wwrite-strings"
    "-Wconversion"
    "-Wsign-conversion"
    "-Wformat=2"
    "-Wformat-security"
    "-Wundef"
    "-Wshadow"
    "-Wstrict-overflow=5"
    "-Wswitch-default"
    "-Wswitch-enum"
    "-Wunreachable-code"
    "-Wfloat-equal"
    "-Wstack-protector"
    "-fstack-protector-strong"
    "-fPIC"
    "-D_FORTIFY_SOURCE=2"
    "-DUSE_RUST_CORE=1"
    # Suppress warnings
    "-Wno-unused-parameter"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-sign-conversion"
    "-Wno-implicit-float-conversion"
    "-Wno-missing-field-initializers"
    "-Wno-format-nonliteral"
    "-Wno-deprecated-declarations"
    "-Wno-cast-qual"
    "-Wno-empty-translation-unit"
    "-Wno-format-pedantic"
  ];

  commonObjCFlags = [
    "-Wall"
    "-Wextra"
    "-Wpedantic"
    "-Wuninitialized"
    "-Winit-self"
    "-Wpointer-arith"
    "-Wcast-qual"
    "-Wformat=2"
    "-Wformat-security"
    "-Wundef"
    "-Wshadow"
    "-Wstack-protector"
    "-fstack-protector-strong"
    "-fobjc-arc"
    "-Wno-unused-parameter"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-implicit-float-conversion"
    "-Wno-deprecated-declarations"
    "-Wno-cast-qual"
    "-Wno-format-nonliteral"
    "-Wno-format-pedantic"
  ];

  debugCFlags = [
    "-O0"
    "-g"
    "-DDEBUG=1"
    "-fno-omit-frame-pointer"
  ];
  debugObjCFlags = [
    "-O0"
    "-g"
    "-DDEBUG=1"
    "-fno-omit-frame-pointer"
  ];

in
  pkgs.stdenv.mkDerivation { # Removed 'rec'
    name = "wawona-ios";
    version = wawonaVersion; # Changed to wawonaVersion
    src = wawonaSrc;

    outputs = [ "out" "project" ];

    dontStrip = true;
    
    # Allow access to Xcode SDKs and toolchain
    __noChroot = true;

    nativeBuildInputs = [ # Changed to list directly
      pkgs.pkg-config
      xcodeUtils.findXcodeScript
      xcodeUtils.ensureIosSimSDK
      buildPackages.wayland-scanner
    ];

    buildInputs =
      (getDeps "ios" iosDeps)
      ++ [
        weston
        effectiveRustBackend
        pkgs.darwin.apple_sdk.frameworks.Metal
        pkgs.darwin.apple_sdk.frameworks.QuartzCore
        pkgs.darwin.apple_sdk.frameworks.CoreFoundation
      ];

    # Fix gbm-wrapper.c include path and egl_buffer_handler.h for iOS
    postPatch = ''
            # Fix gbm-wrapper.c include path for metal_dmabuf.h
            substituteInPlace src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
              --replace-fail '#include "../../../../metal_dmabuf.h"' '#include "metal_dmabuf.h"'
            
            
            # Create iOS-compatible egl_buffer_handler.h stub
            # iOS doesn't use EGL, so we need to stub it out
            cat > src/stubs/egl_buffer_handler.h <<'EOF'
      #pragma once

      #include <wayland-server-core.h>
      #include <stdbool.h>

      // iOS stub: EGL is not available on iOS (we use Metal instead)
      // This provides stub definitions to avoid compilation errors

      typedef void* EGLDisplay;
      typedef void* EGLContext;
      typedef void* EGLConfig;
      typedef void* EGLImageKHR;
      typedef int EGLint;

      #define EGL_NO_DISPLAY ((EGLDisplay)0)
      #define EGL_NO_CONTEXT ((EGLContext)0)
      #define EGL_NO_IMAGE_KHR ((EGLImageKHR)0)

      struct egl_buffer_handler {
          EGLDisplay egl_display;
          EGLContext egl_context;
          EGLConfig egl_config;
          bool initialized;
          bool display_bound;
      };

      // Stub functions - return failure on iOS
      static inline int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
          (void)handler; (void)display;
          return -1; // EGL not available on iOS
      }

      static inline void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
          (void)handler;
      }

      static inline int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                                         struct wl_resource *buffer_resource,
                                                         int32_t *width, int32_t *height,
                                                         EGLint *texture_format) {
          (void)handler; (void)buffer_resource; (void)width; (void)height; (void)texture_format;
          return -1;
      }

      static inline EGLImageKHR egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                                                struct wl_resource *buffer_resource) {
          (void)handler; (void)buffer_resource;
          return EGL_NO_IMAGE_KHR;
      }

      static inline bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                                           struct wl_resource *buffer_resource) {
          (void)handler; (void)buffer_resource;
          return false;
      }
      EOF
      
      # Metal shader compilation
    '';

    # Metal shader compilation
    preBuild = ''
      ${xcodeEnv "ios-sim"}

      if command -v metal >/dev/null 2>&1; then
        metal -c src/rendering/metal_shaders.metal -o metal_shaders.air -isysroot "$SDKROOT" -mios-simulator-version-min=26.0 || true
        if [ -f metal_shaders.air ] && command -v metallib >/dev/null 2>&1; then
          metallib metal_shaders.air -o metal_shaders.metallib || true
        fi
      fi
    '';

    preConfigure = ''
      ${xcodeEnv "ios-sim"}

      ${copyDeps "ios-dependencies"}

      # Copy waypipe protocol headers (xdg-shell-client-protocol.h etc.)
      WAYPIPE_SRC="${pkgs.fetchFromGitLab {
        owner = "mstoeckl";
        repo = "waypipe";
        rev = "v0.10.6";
        sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
      }}"
      if [ -d "$WAYPIPE_SRC/protocols" ]; then
        # Generate needed protocol headers from XML
        wayland-scanner client-header "$WAYPIPE_SRC/protocols/xdg-shell.xml" ios-dependencies/include/xdg-shell-client-protocol.h
        wayland-scanner private-code "$WAYPIPE_SRC/protocols/xdg-shell.xml" ios-dependencies/include/xdg-shell-protocol.c
        echo "Generated xdg-shell protocol headers"
      else
        echo "WARNING: waypipe protocol headers not found at $WAYPIPE_SRC/protocols"
        ls -la "$WAYPIPE_SRC/" || true
      fi

      # Setup Weston Simple SHM
      mkdir -p deps/weston-simple-shm
      cp -r ${westonSimpleShmSrc}/* deps/weston-simple-shm/
      chmod -R u+w deps/weston-simple-shm

      export PKG_CONFIG_PATH="$PWD/ios-dependencies/libdata/pkgconfig:$PWD/ios-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"
      export NIX_CFLAGS_COMPILE=""
      export NIX_CXXFLAGS_COMPILE=""
      export NIX_LDFLAGS=""

      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
        # Unset Nix wrappers so they don't interfere
        unset CC CXX AR AS LD RANLIB STRIP NM OBJCOPY OBJDUMP READELF
      else
        echo "ERROR: Xcode toolchain not found at $DEVELOPER_DIR"
        exit 1
      fi
      # Determine architecture for simulator
      IOS_ARCH="arm64"
      if [ "$(uname -m)" = "x86_64" ]; then
        IOS_ARCH="x86_64"
      fi
      export CC="$IOS_CC"
      export CXX="$IOS_CXX"
      export CFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
      export CXXFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
      export LDFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -lobjc"
      export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

      # Unset SDKROOT and DEVELOPER_DIR to prevent leakage into host tools (wayland-scanner, etc.)
      # Target tools like $CC already have sysroot baked into their flags.
      unset SDKROOT
    '';

    buildPhase = ''
      runHook preBuild

      # Compile generated protocols
      $CC -c ios-dependencies/include/xdg-shell-protocol.c \
          -Iios-dependencies/include -Iios-dependencies/include/wayland \
          $CFLAGS \
          -o xdg-shell-protocol.o
      OBJ_FILES="xdg-shell-protocol.o"

      # Compile all source files
      for src_file in ${lib.concatStringsSep " " iosSourcesFiltered}; do
        if [[ "$src_file" == *.c ]] || [[ "$src_file" == *.m ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if [[ "$src_file" == *.m ]]; then
            $CC -c "$src_file" \
                -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
                -Isrc/platform/macos \
                -Isrc/platform/ios \
                -Isrc/logging -Isrc/launcher \
                -Isrc/extensions \
                -Iios-dependencies/include -Iios-dependencies/include/wayland \
                $CFLAGS \
                ${lib.concatStringsSep " " commonObjCFlags} \
                ${lib.concatStringsSep " " debugObjCFlags} \
               -DTARGET_OS_IPHONE=1 \
               -DUSE_RUST_CORE=1 \
               -o "$obj_file"
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
               -Isrc/platform/macos \
               -Isrc/logging -Isrc/launcher \
               -Iios-dependencies/include -Iios-dependencies/include/wayland \
               $CFLAGS \
               ${lib.concatStringsSep " " commonCFlags} \
               ${lib.concatStringsSep " " debugCFlags} \
               -DUSE_RUST_CORE=1 \
               -o "$obj_file"
          fi
          OBJ_FILES="$OBJ_FILES $obj_file"
        fi
      done

      # Ensure iOS entry point is always present for final executable.
      if [ ! -f platform_macos_main.m.o ]; then
        $CC -c "src/platform/macos/main.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
            $CFLAGS \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o platform_macos_main.m.o
      fi
      OBJ_FILES="$OBJ_FILES platform_macos_main.m.o"

      # Ensure bridge/settings objects exist for symbols referenced by main.m.
      if [ ! -f platform_macos_WWNCompositorBridge.m.o ]; then
        $CC -c "src/platform/macos/WWNCompositorBridge.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
            $CFLAGS \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o platform_macos_WWNCompositorBridge.m.o
      fi
      OBJ_FILES="$OBJ_FILES platform_macos_WWNCompositorBridge.m.o"

      if [ ! -f platform_macos_WWNSettings.c.o ]; then
        $CC -c "src/platform/macos/WWNSettings.c" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
            -fPIC \
            ${lib.concatStringsSep " " commonCFlags} \
            ${lib.concatStringsSep " " debugCFlags} \
            $CFLAGS \
            -DUSE_RUST_CORE=1 \
            -o platform_macos_WWNSettings.c.o
      fi
      OBJ_FILES="$OBJ_FILES platform_macos_WWNSettings.c.o"

      if [ ! -f platform_macos_WWNSettings.m.o ]; then
        $CC -c "src/platform/macos/WWNSettings.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o platform_macos_WWNSettings.m.o
      fi
      OBJ_FILES="$OBJ_FILES platform_macos_WWNSettings.m.o"

      if [ ! -f platform_ios_WWNCompositorView_ios.m.o ] && [ -f "src/platform/ios/WWNCompositorView_ios.m" ]; then
        $CC -c "src/platform/ios/WWNCompositorView_ios.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o platform_ios_WWNCompositorView_ios.m.o
      fi
      if [ -f platform_ios_WWNCompositorView_ios.m.o ]; then
        OBJ_FILES="$OBJ_FILES platform_ios_WWNCompositorView_ios.m.o"
      fi

      if [ ! -f platform_ios_WWNSceneDelegate.m.o ] && [ -f "src/platform/ios/WWNSceneDelegate.m" ]; then
        $CC -c "src/platform/ios/WWNSceneDelegate.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o platform_ios_WWNSceneDelegate.m.o
      fi
      if [ -f platform_ios_WWNSceneDelegate.m.o ]; then
        OBJ_FILES="$OBJ_FILES platform_ios_WWNSceneDelegate.m.o"
      fi

      if [ ! -f ui_Settings_WWNSettingsSplitViewController.m.o ] && [ -f "src/ui/Settings/WWNSettingsSplitViewController.m" ]; then
        $CC -c "src/ui/Settings/WWNSettingsSplitViewController.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o ui_Settings_WWNSettingsSplitViewController.m.o
      fi
      if [ -f ui_Settings_WWNSettingsSplitViewController.m.o ]; then
        OBJ_FILES="$OBJ_FILES ui_Settings_WWNSettingsSplitViewController.m.o"
      fi

      if [ ! -f ui_Settings_WWNSettingsSidebarViewController.m.o ] && [ -f "src/ui/Settings/WWNSettingsSidebarViewController.m" ]; then
        $CC -c "src/ui/Settings/WWNSettingsSidebarViewController.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o ui_Settings_WWNSettingsSidebarViewController.m.o
      fi
      if [ -f ui_Settings_WWNSettingsSidebarViewController.m.o ]; then
        OBJ_FILES="$OBJ_FILES ui_Settings_WWNSettingsSidebarViewController.m.o"
      fi

      if [ ! -f ui_Settings_WWNSettingsModel.m.o ] && [ -f "src/ui/Settings/WWNSettingsModel.m" ]; then
        $CC -c "src/ui/Settings/WWNSettingsModel.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o ui_Settings_WWNSettingsModel.m.o
      fi
      if [ -f ui_Settings_WWNSettingsModel.m.o ]; then
        OBJ_FILES="$OBJ_FILES ui_Settings_WWNSettingsModel.m.o"
      fi

      if [ ! -f ui_Settings_WWNPreferences.m.o ] && [ -f "src/ui/Settings/WWNPreferences.m" ]; then
        $CC -c "src/ui/Settings/WWNPreferences.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o ui_Settings_WWNPreferences.m.o
      fi
      if [ -f ui_Settings_WWNPreferences.m.o ]; then
        OBJ_FILES="$OBJ_FILES ui_Settings_WWNPreferences.m.o"
      fi

      if [ ! -f ui_Helpers_WWNImageLoader.m.o ] && [ -f "src/ui/Helpers/WWNImageLoader.m" ]; then
        $CC -c "src/ui/Helpers/WWNImageLoader.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o ui_Helpers_WWNImageLoader.m.o
      fi
      if [ -f ui_Helpers_WWNImageLoader.m.o ]; then
        OBJ_FILES="$OBJ_FILES ui_Helpers_WWNImageLoader.m.o"
      fi

      if [ ! -f ui_Settings_WWNPreferencesManager.m.o ] && [ -f "src/ui/Settings/WWNPreferencesManager.m" ]; then
        $CC -c "src/ui/Settings/WWNPreferencesManager.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o ui_Settings_WWNPreferencesManager.m.o
      fi
      if [ -f ui_Settings_WWNPreferencesManager.m.o ]; then
        OBJ_FILES="$OBJ_FILES ui_Settings_WWNPreferencesManager.m.o"
      fi

      if [ ! -f ui_Settings_WWNWaypipeRunner.m.o ] && [ -f "src/ui/Settings/WWNWaypipeRunner.m" ]; then
        $CC -c "src/ui/Settings/WWNWaypipeRunner.m" \
            -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
            -Isrc/platform/macos -Isrc/platform/ios -Isrc/logging -Isrc/launcher -Isrc/extensions \
            -Iios-dependencies/include -Iios-dependencies/include/wayland \
              \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " debugObjCFlags} \
            $CFLAGS \
            -DTARGET_OS_IPHONE=1 -DUSE_RUST_CORE=1 \
            -o ui_Settings_WWNWaypipeRunner.m.o
      fi
      if [ -f ui_Settings_WWNWaypipeRunner.m.o ]; then
        OBJ_FILES="$OBJ_FILES ui_Settings_WWNWaypipeRunner.m.o"
      fi

      # Compile weston-simple-shm
      for src_file in deps/weston-simple-shm/clients/simple-shm.c deps/weston-simple-shm/shared/os-compatibility.c deps/weston-simple-shm/fullscreen-shell-unstable-v1-protocol.c; do
        obj_file="''${src_file//\//_}.o"
        $CC -c "$src_file" \
           -Ideps/weston-simple-shm \
           -Ideps/weston-simple-shm/shared \
           -Ideps/weston-simple-shm/include \
           -Iios-dependencies/include -Iios-dependencies/include/wayland \
           -fPIC $CFLAGS \
           -o "$obj_file"
        OBJ_FILES="$OBJ_FILES $obj_file"
      done

      # Link executable with Rust backend
      $CC $OBJ_FILES \
          -o "wawona-ios" \
          $LDFLAGS \
          -framework Foundation \
          -framework UIKit \
          -framework IOSurface \
          -framework Metal \
          -framework QuartzCore \
          -framework CoreFoundation \
          -framework CoreVideo -framework CoreMedia -framework CoreGraphics \
          -framework MetalKit \
          -framework VideoToolbox -framework AVFoundation \
          -framework Security -framework Network \
          -Lios-dependencies/lib \
          -lxkbcommon -lwayland-client -lepoll-shim -lffi -lpixman-1 -lzstd -llz4 -lz \
          -lssh2 -lmbedcrypto -lmbedx509 -lmbedtls \
          -lssl -lcrypto \
          -lweston-13 -lweston-desktop-13 -lweston-terminal \
          ${effectiveRustBackend}/lib/libwawona.a \
          -fobjc-arc -g -O0 $CFLAGS \
          -Wl,-multiply_defined,suppress -Wl,-fatal_warnings \
          -o Wawona

      # Generate dSYM bundle for lldb attach
      if command -v dsymutil >/dev/null 2>&1; then
        dsymutil Wawona -o Wawona.dSYM || true
      fi

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/Applications/Wawona.app
      cp Wawona $out/Applications/Wawona.app/
      if [ -d Wawona.dSYM ]; then
        cp -R Wawona.dSYM $out/Applications/Wawona.app.dSYM
      fi

      # Populate project output
      mkdir -p $project
      # Copy sources (current build dir)
      cp -r . "$project/"
      chmod -R u+w $project
      if [ -n "${toString xcodeProject}" ]; then
        cp -r ${xcodeProject}/* "$project/"
        chmod -R u+w $project
      fi

      # Simulator/device install requires an Info.plist with a bundle identifier.
      cat > "$out/Applications/Wawona.app/Info.plist" <<'PLIST_EOF'
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
  <string>1</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>UILaunchStoryboardName</key>
  <string>LaunchScreen</string>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneConfigurationName</key>
          <string>Default Configuration</string>
          <key>UISceneDelegateClassName</key>
          <string>WWNSceneDelegate</string>
        </dict>
      </array>
    </dict>
  </dict>
  <key>UIRequiredDeviceCapabilities</key>
  <array>
    <string>arm64</string>
  </array>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconName</key>
      <string>AppIcon</string>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon</string>
      </array>
    </dict>
  </dict>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
</dict>
</plist>
PLIST_EOF
      
      ${xcodeEnv "ios"}

      # Copy Metal shader library
      if [ -f metal_shaders.metallib ]; then
        cp metal_shaders.metallib $out/Applications/Wawona.app/
      fi

      # Install app icons for iOS 26+ (Icon Composer) with PNG fallback.
      ICON_ROOT="$src/src/resources"
      APPICONSET="$ICON_ROOT/Assets.xcassets/AppIcon.appiconset"
      ICON_BUNDLE="$ICON_ROOT/Wawona.icon"
      ACTOOL="''${DEVELOPER_DIR:-}/usr/bin/actool"
      COMPILED_ASSET_CAR=0

      if [ ! -f "$APPICONSET/AppIcon-Light-1024.png" ] && [ ! -f "$ICON_BUNDLE/Assets/wayland.png" ] && [ ! -f "$ICON_ROOT/wayland.png" ]; then
        echo "ERROR: Missing iOS icon source PNG. Expected AppIcon-Light-1024.png or Wawona.icon/Assets/wayland.png"
        exit 1
      fi

      if [ -n "''${DEVELOPER_DIR:-}" ] && [ -x "$ACTOOL" ]; then
        ICON_TMP="$TMPDIR/wawona-ios-icon-compile"
        rm -rf "$ICON_TMP"
        mkdir -p "$ICON_TMP"

        # Primary path: iOS 26 icon-composer bundle (Wawona.icon/icon.json + PNG asset).
        if [ -d "$ICON_BUNDLE" ] && [ -f "$ICON_BUNDLE/icon.json" ]; then
          cp -R "$ICON_BUNDLE" "$ICON_TMP/Wawona.icon"
          if [ -f "$ICON_ROOT/wayland.png" ] && [ ! -f "$ICON_TMP/Wawona.icon/Assets/wayland.png" ]; then
            mkdir -p "$ICON_TMP/Wawona.icon/Assets"
            cp "$ICON_ROOT/wayland.png" "$ICON_TMP/Wawona.icon/Assets/wayland.png"
          fi
          OUT_CAR="$ICON_TMP/icon-composer-out"
          mkdir -p "$OUT_CAR"
          if "$ACTOOL" "$ICON_TMP/Wawona.icon" --compile "$OUT_CAR" \
              --platform iphoneos --target-device iphone --target-device ipad \
              --minimum-deployment-target 26.0 \
              --app-icon Wawona --include-all-app-icons \
              --output-format human-readable-text --notices --warnings \
              --development-region en --enable-on-demand-resources NO \
              --output-partial-info-plist "$OUT_CAR/assetcatalog_generated_info.plist"; then
            if [ -f "$OUT_CAR/Assets.car" ]; then
              cp "$OUT_CAR/Assets.car" "$out/Applications/Wawona.app/"
              COMPILED_ASSET_CAR=1
              echo "Installed Assets.car (from Wawona.icon / icon.json)"
            fi
          fi
        fi

        # Fallback path: classic AppIcon.appiconset compiles to Assets.car with AppIcon.
        if [ "$COMPILED_ASSET_CAR" -eq 0 ] && [ -d "$APPICONSET" ]; then
          mkdir -p "$ICON_TMP/Assets.xcassets/AppIcon.appiconset"
          cp -R "$APPICONSET/"* "$ICON_TMP/Assets.xcassets/AppIcon.appiconset/"
          OUT_CAR="$ICON_TMP/appiconset-out"
          mkdir -p "$OUT_CAR"
          if "$ACTOOL" "$ICON_TMP/Assets.xcassets" --compile "$OUT_CAR" \
              --platform iphoneos --target-device iphone --target-device ipad \
              --minimum-deployment-target 26.0 \
              --app-icon AppIcon --include-all-app-icons \
              --output-format human-readable-text --notices --warnings \
              --development-region en --enable-on-demand-resources NO \
              --output-partial-info-plist "$OUT_CAR/assetcatalog_generated_info.plist"; then
            if [ -f "$OUT_CAR/Assets.car" ]; then
              cp "$OUT_CAR/Assets.car" "$out/Applications/Wawona.app/"
              COMPILED_ASSET_CAR=1
              echo "Installed Assets.car (from AppIcon.appiconset)"
            fi
          fi
        fi
      else
        echo "Warning: actool not available; iOS icon may rely on PNG fallback only."
      fi

      # Legacy PNG copies for systems/tools that still inspect standalone images.
      if [ -d "$APPICONSET" ] && [ -f "$APPICONSET/AppIcon-Light-1024.png" ]; then
        cp "$APPICONSET/AppIcon-Light-1024.png" "$out/Applications/Wawona.app/AppIcon.png"
        echo "Installed AppIcon.png (light, opaque)"
      fi
      if [ -d "$APPICONSET" ] && [ -f "$APPICONSET/AppIcon-Dark-1024.png" ]; then
        cp "$APPICONSET/AppIcon-Dark-1024.png" "$out/Applications/Wawona.app/AppIcon-Dark.png"
        echo "Installed AppIcon-Dark.png (dark)"
      fi

      # Keep the source .icon bundle in-app for inspection/debugging.
      if [ -d "$ICON_BUNDLE" ]; then
        cp -R "$ICON_BUNDLE" "$out/Applications/Wawona.app/"
        echo "Installed Wawona.icon bundle"
      fi

      # Bundle the dark logo PNG for Settings About header.
      # Copy with BOTH the original @1x name AND without the scale suffix,
      # because iOS UIImage/NSBundle APIs interpret @1x as a scale modifier
      # and won't find the file by name on 2x/3x devices.
      if [ -f "$src/src/resources/Wawona-iOS-Dark-1024x1024@1x.png" ]; then
        cp "$src/src/resources/Wawona-iOS-Dark-1024x1024@1x.png" \
          "$out/Applications/Wawona.app/"
        cp "$src/src/resources/Wawona-iOS-Dark-1024x1024@1x.png" \
          "$out/Applications/Wawona.app/Wawona-iOS-Dark-1024x1024.png"
        echo "Bundled Wawona-iOS-Dark-1024x1024@1x.png (+ unsuffixed copy)"
      fi
      
      # Static-only policy for App Store-distributable iOS builds:
      # do not bundle third-party dylibs into the app.
      for dep in $buildInputs; do
         if [ -d "$dep/lib" ]; then
            found_dylib=0
            for dylib in "$dep"/lib/*.dylib; do
              if [ -f "$dylib" ]; then
                if [ "$found_dylib" -eq 0 ]; then
                  echo "ERROR: Found dynamic libraries in dependency: $dep/lib"
                  found_dylib=1
                fi
                echo "$dylib"
              fi
            done
            if [ "$found_dylib" -eq 1 ]; then
              exit 1
            fi
         fi
      done

      # No extra binaries to copy

      runHook postInstall
    '';

    passthru.automationScript = pkgs.writeShellScriptBin "wawona-ios-automat" ''
      set -e
      ${xcodeEnv "ios"}

      # Unset Nix compiler wrappers to allow xcodebuild to use the Xcode toolchain
      unset CC CXX AR AS LD RANLIB STRIP NM OBJCOPY OBJDUMP READELF
      unset NIX_CFLAGS_COMPILE NIX_CXXFLAGS_COMPILE NIX_LDFLAGS NIX_BINTOOLS

      echo "Generating Xcode project..."
      ${(pkgs.callPackage ../generators/xcodegen.nix {
         inherit pkgs wawonaSrc buildModule targetPkgs;
         rustBackendIOS = rustBackend;
         rustBackendIOSSim = rustBackendSim;
         includeMacOSTarget = false;
         rustPlatform = pkgs.rustPlatform;
         wawonaVersion = projectVersion;
         libwaylandIOS = buildModule.buildForIOS "libwayland" { };
         xkbcommonIOS = buildModule.buildForIOS "xkbcommon" { };
         pixmanIOS = buildModule.buildForIOS "pixman" { };
         libffiIOS = buildModule.buildForIOS "libffi" { };
         opensslIOS = buildModule.buildForIOS "openssl" { };
         libssh2IOS = buildModule.buildForIOS "libssh2" { };
         mbedtlsIOS = buildModule.buildForIOS "mbedtls" { };
         zstdIOS = buildModule.buildForIOS "zstd" { };
         lz4IOS = buildModule.buildForIOS "lz4" { };
         epollShimIOS = buildModule.buildForIOS "epoll-shim" { };
         waypipeIOS = buildModule.buildForIOS "waypipe" { };
         westonSimpleShmIOS = buildModule.buildForIOS "weston-simple-shm" { };
         westonIOS = buildModule.buildForIOS "weston" { };
         cairoIOS = null;
         pangoIOS = null;
         glibIOS = null;
         harfbuzzIOS = null;
         fontconfigIOS = null;
         freetypeIOS = null;
         libpngIOS = null;
       }).app}/bin/xcodegen

      if [ ! -d "Wawona.xcodeproj" ]; then
        echo "Error: Wawona.xcodeproj not generated."
        exit 1
      fi

      SIM_NAME="Wawona iOS Simulator"
      DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
      RUNTIME=$(xcrun simctl list runtimes | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1)
      if [ -z "$RUNTIME" ]; then
        echo "Error: No iOS runtime found."
        exit 1
      fi

      SIM_UDID=$(xcrun simctl list devices | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
      if [ -z "$SIM_UDID" ]; then
        echo "Creating '$SIM_NAME' ($DEV_TYPE, $RUNTIME)..."
        SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
      fi

      echo "Simulator UDID: $SIM_UDID"
      xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
      # Launch Simulator app
      SIM_APP_PATH=$(${xcodeUtils.findSimulatorScript}/bin/find-simulator)
      echo "Opening $SIM_APP_PATH..."
      open "$SIM_APP_PATH"

      echo "Building for iOS Simulator (real Rust core backend)..."
      if ! xcodebuild -scheme Wawona-iOS \
        -project Wawona.xcodeproj \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$SIM_UDID" \
        -derivedDataPath build/ios_sim_build \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        build; then
        echo ""
        echo "Simulator build failed."
        exit 1
      fi

      APP_PATH="build/ios_sim_build/Build/Products/Debug-iphonesimulator/Wawona.app"
      if [ ! -d "$APP_PATH" ]; then
        echo "Error: App not found at $APP_PATH"
        exit 1
      fi

      echo "Installing app to simulator..."
      # Kill any stale simctl install from previous runs (they block the socket)
      pkill -f "simctl install" 2>/dev/null || true
      sleep 1
      # Wait for simulator to be fully booted
      xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || {
        for i in $(seq 1 30); do
          STATUS=$(xcrun simctl list devices | grep "$SIM_UDID" | grep -o "Booted" || true)
          if [ "$STATUS" = "Booted" ]; then break; fi
          echo "  Waiting for simulator ($i/30)..."
          sleep 2
        done
      }
      xcrun simctl install "$SIM_UDID" "$APP_PATH"

      # Use a single log file for a cleaner unified stream
      APP_LOG="/tmp/wawona-ios.log"
      rm -f "$APP_LOG"
      touch "$APP_LOG"
      
      # Launch via simctl with --wait-for-debugger so we can attach LLDB
      LAUNCH_OUTPUT=$(xcrun simctl launch --wait-for-debugger --stdout="$APP_LOG" --stderr="$APP_LOG" "$SIM_UDID" com.aspauldingcode.Wawona 2>&1)
      
      # Extract PID (format: "com.aspauldingcode.Wawona: 12345")
      PID=$(echo "$LAUNCH_OUTPUT" | awk '/com.aspauldingcode.Wawona:/ {print $NF}')
      
      if [ -z "$PID" ]; then
          echo "Error: Could not extract PID from launch output."
          echo "Output: $LAUNCH_OUTPUT"
          exit 1
      fi
      
      # Start log streaming
      pkill -f "tail -f $APP_LOG" 2>/dev/null || true
      echo "--- Wawona iOS Logs (PID $PID) ---"
      tail -f "$APP_LOG" &
      TAIL_PID=$!
      trap "kill $TAIL_PID 2>/dev/null || true" EXIT INT TERM
      
      # Write LLDB command script:
      #   Phase 1 — Attach silently (suppress all frame/thread/disassembly output)
      #   Phase 2 — Register stop-hooks that fire on CRASH only (not during attach)
      #   Phase 3 — Continue the process (LLDB goes silent in --batch mode)
      #
      # On crash: stop-hooks kill the tail, restore display settings, show bt.
      # --batch then drops LLDB into interactive mode at the crash site.
      cat > /tmp/wawona_debug.lldb << LLDBEOF
settings set auto-confirm true
settings set stop-line-count-before 0
settings set stop-line-count-after 0
settings set stop-disassembly-display never
settings set frame-format ""
settings set thread-stop-format ""
process attach --pid $PID
process handle SIGPIPE -n true -p true -s false
target stop-hook add --one-liner "script import os; os.kill($TAIL_PID, 15)"
target stop-hook add --one-liner "settings set stop-line-count-after 5"
target stop-hook add --one-liner "settings set stop-disassembly-display always"
target stop-hook add --one-liner "thread backtrace"
continue
LLDBEOF
      
      # --batch: runs the script then stays SILENT (no (lldb) prompt).
      #          If the process crashes, LLDB becomes interactive automatically.
      # -Q:      suppresses the welcome banner.
      # This lets tail -f own the terminal during normal execution.
      lldb --batch -Q -s /tmp/wawona_debug.lldb
      
      # Cleanup if lldb exits normally (process quit without crash)
      kill $TAIL_PID 2>/dev/null || true
    '';

  }
