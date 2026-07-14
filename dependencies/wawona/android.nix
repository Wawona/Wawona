{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  # Filtered source for the APK derivation `src` (cleanSourceWith). Defaults to
  # wawonaSrc for callers that don't pass it, but the flake passes the filtered
  # `srcFor pkgs` so working-tree churn (target/, .git/, editor dirs) does not
  # force a full APK rebuild. Path lookups (VERSION, subdirs) stay on wawonaSrc.
  srcFiltered ? wawonaSrc,
  wawonaVersion ? null,
  androidSDK ? null,
  androidUtils ? null,
  androidToolchain ? null,
  rustBackend ? null,
  glslang ? pkgs.glslang,
  jdk17 ? pkgs.jdk17,
  gradle ? pkgs.gradle,
  targetPkgs,
  androidToolchainNix,
  westonSimpleShmPatchedSrcNix,
  westonToytoolkitLdflagsNix,
  westonCompositorLdflagsNix,
  ilandGlAndroidLdflagsNix,
  androidConfigNix,
  westonAndroidSignalPolyfill ? null,
  releaseArtifact ? "debug",
  ...
}:

let
  common = import ./common.nix { inherit lib pkgs wawonaSrc; };
  androidConfig = import androidConfigNix {
    inherit lib androidSDK;
    system = pkgs.stdenv.buildPlatform.system;
  };
  provisionScript = if androidUtils != null then "${androidUtils.provisionAndroidScript}/bin/provision-android" else "";

  androidToolchainResolved = if androidToolchain != null then androidToolchain else import androidToolchainNix { inherit lib androidSDK; pkgs = targetPkgs; };
  
  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;
  gradleSupport = pkgs.callPackage ../gradle-deps.nix {
    inherit wawonaSrc androidSDK androidConfigNix;
    inherit (pkgs) gradle jdk17;
  };

  westonSimpleShmSrc = pkgs.callPackage westonSimpleShmPatchedSrcNix {};
  libwaylandAndroid = buildModule.buildForAndroid "libwayland" { };
  opensshBin = buildModule.buildForAndroid "openssh" { };
  sshpassBin = buildModule.buildForAndroid "sshpass" { };
  # Real local shell for Android (fork/exec allowed); spawned by the PTY shim.
  zshAndroid = buildModule.buildForAndroid "zsh" { };
  footAndroid = buildModule.buildForAndroid "foot" { };
  fastfetchAndroid = buildModule.buildForAndroid "fastfetch" { };
  neovimAndroid = buildModule.buildForAndroid "neovim" { };
  waypipeAndroid = buildModule.buildForAndroid "waypipe" { };
  # niri (wwn-niri): nested scrollable-tiling compositor (Wayland client of
  # the Wawona compositor); ships as lib/libniri_bin.so (exec'd, waypipe pattern).
  niriAndroid = buildModule.buildForAndroid "niri" { };
  # anowaW app bridge: libanowaw.so + staged Kotlin/JNI shims (share/anowaw).
  anowawAndroid = buildModule.buildForAndroid "anowaw" { };
  mobileToytoolkitDeps = import ./mobile-toytoolkit-deps.nix {
    buildFn = buildModule.buildForAndroid;
  };
  westonAndroid = buildModule.buildForAndroid "weston" { enableGlClients = true; };
  westonSimpleShmAndroid = buildModule.buildForAndroid "weston-simple-shm" { };
  libintlAndroid = buildModule.buildForAndroid "libintl" { };
  westonToytoolkitLdflags = import westonToytoolkitLdflagsNix {
    inherit (pkgs) lib;
    deps = mobileToytoolkitDeps // {
      weston = westonAndroid;
      libintl = libintlAndroid;
    };
    forceLoadWeston = true;
    linkMode = "whole_archive";
  };
  westonCompositorAndroid = buildModule.buildForAndroid "weston-compositor" { };
  ilandAndroid = buildModule.buildForAndroid "iland" { };
  angleAndroid = buildModule.buildForAndroid "angle" { };
  kmscubeAndroid = buildModule.buildForAndroid "kmscube" { };
  westonCompositorLdflags = import westonCompositorLdflagsNix {
    inherit (pkgs) lib;
    deps = {
      weston-compositor = westonCompositorAndroid;
      libwayland = libwaylandAndroid;
      expat = buildModule.buildForAndroid "expat" { };
    };
    forceLoadCompositor = false;
    linkMode = "whole_archive";
  };
  ilandGlLdflags = import ilandGlAndroidLdflagsNix {
    inherit (pkgs) lib;
    deps = {
      iland = ilandAndroid;
      angle = angleAndroid;
      kmscube = kmscubeAndroid;
      "iland-gl-clients" = kmscubeAndroid;
    };
  };
  rustBackendPath = if rustBackend != null then toString rustBackend else "";
  androidQuadVert = ../../src/platform/android/rendering/shaders/android_quad.vert;
  androidQuadFrag = ../../src/platform/android/rendering/shaders/android_quad.frag;

  shellTools = import ./android-shell-tools.nix {
    inherit lib zshAndroid fastfetchAndroid neovimAndroid waypipeAndroid niriAndroid;
  };
  westonData = import ./android-weston-data.nix { inherit lib pkgs; };
  bundledClients = import ./android-bundled-clients.nix {
    androidCC = androidToolchainResolved.androidCC;
    inherit libwaylandAndroid westonAndroid footAndroid;
  };

  androidDeps = common.commonDeps ++ [
    "swiftshader"
    "pixman"
    "libwayland"
    "expat"
    "libffi"
    "libxml2"
    "xkbcommon"
    "openssl"
    "anowaw"
  ] ++ (lib.attrNames mobileToytoolkitDeps) ++ [
    "weston"
    "weston-compositor"
    "libintl"
    "iland"
    "angle"
    "kmscube"
    "iland-gl-clients"
  ];
  gradleTask =
    if releaseArtifact == "release-aab" then ":Wawona:bundleRelease"
    else if releaseArtifact == "release-apk" then ":Wawona:assembleRelease"
    else ":Wawona:assembleDebug";
  isReleaseBuild = releaseArtifact == "release-aab" || releaseArtifact == "release-apk";

  getDeps =
    platform: depNames:
    map (
      name:
      if name == "pixman" then
        if platform == "android" then
          buildModule.buildForAndroid "pixman" { }
        else
          pkgs.pixman
      else if name == "vulkan-headers" then
        pkgs.vulkan-headers
      else if name == "vulkan-loader" then
        pkgs.vulkan-loader
      else if name == "xkbcommon" then
        buildModule.buildForAndroid "xkbcommon" { }
      else if name == "openssl" then
        buildModule.buildForAndroid "openssl" { }
      else if name == "libssh2" then
        buildModule.buildForAndroid "libssh2" { }
      else
        buildModule.buildForAndroid name { }
    ) depNames;

  # Filter commonSources for Android: remove .m files and Apple-only headers
  androidCommonSources =
    lib.filter (
      f:
      !(lib.hasSuffix ".m" f)
      && f != "src/compositor_implementations/wayland_color_management.c"
      && f != "src/compositor_implementations/wayland_color_management.h"
      && f != "src/stubs/egl_buffer_handler.h"
      && f != "src/core/main.m"
    ) common.commonSources;

  # Android-specific sources (not filtered by pathExists since some are
  # generated at build time by postPatch, or are shared .c files that
  # filterSources may fail to resolve on Nix store paths)
  androidExtraSources = [
    "src/stubs/egl_buffer_handler.c"
    "src/platform/android/android_jni.c"
    "src/platform/android/input_android.c"
    "src/platform/android/rendering/renderer_android.c"
    "src/platform/android/rendering/renderer_android.h"
    "src/platform/android/iland_presenter_android.c"
    "src/platform/android/iland_presenter_android.h"
    "src/platform/macos/WWNSettings.c"
    "src/platform/macos/WWNSettings.h"
  ];

  androidSourcesFiltered = (common.filterSources androidCommonSources) ++ androidExtraSources;

  nixSdkPath = lib.makeBinPath (
    [
      androidSDK.platformTools
      androidSDK.cmdlineTools
      androidSDK.androidsdk
      pkgs.util-linux
      pkgs.jdk17
      pkgs.lldb
    ]
    ++ lib.optionals androidConfig.emulatorSupported [ androidSDK.emulator ]
  );

  nixSdkRoot = androidConfig.sdkRoot;

  runnerScript = pkgs.writeShellScript "wawona-android-run" ''
    set +e

    NIX_SDK_PATH="${nixSdkPath}"
    NDK_ROOT="${androidToolchainResolved.androidndkRoot}"
    DEBUG_MODE=false
    TEST_MODE=false
    USE_SYSTEM_SDK=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --debug) DEBUG_MODE=true; shift ;;
        --test) TEST_MODE=true; shift ;;
        --impure-system-sdk) USE_SYSTEM_SDK=true; shift ;;
        *) break ;;
      esac
    done

    export PATH="$NIX_SDK_PATH:$PATH"
    export ANDROID_SDK_ROOT="${nixSdkRoot}"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"

    if [ "$USE_SYSTEM_SDK" = "true" ]; then
      if [ "$(uname -m)" != "arm64" ] || [ "$(uname -s)" != "Darwin" ]; then
        echo "[Wawona] ERROR: --impure-system-sdk is only supported on macOS arm64."
        exit 1
      fi

      REAL_USER=$(whoami)
      REAL_HOME="/Users/$REAL_USER"
      SYSTEM_SDK=""
      if [ -d "$HOME/Library/Android/sdk/emulator" ] && [ -f "$HOME/Library/Android/sdk/emulator/emulator" ]; then
        SYSTEM_SDK="$HOME/Library/Android/sdk"
      elif [ -d "$REAL_HOME/Library/Android/sdk/emulator" ] && [ -f "$REAL_HOME/Library/Android/sdk/emulator/emulator" ]; then
        SYSTEM_SDK="$REAL_HOME/Library/Android/sdk"
      fi

      if [ -z "$SYSTEM_SDK" ]; then
        echo "[Wawona] ERROR: No system Android SDK found."
        echo "[Wawona] Re-run without --impure-system-sdk to use the Nix-packaged SDK."
        exit 1
      fi

      echo "[Wawona] Using impure system Android SDK at $SYSTEM_SDK"
      export PATH="$SYSTEM_SDK/emulator:$SYSTEM_SDK/platform-tools:$SYSTEM_SDK/cmdline-tools/latest/bin:$NIX_SDK_PATH:$PATH"
      export ANDROID_SDK_ROOT="$SYSTEM_SDK"
      export ANDROID_HOME="$SYSTEM_SDK"
    else
      echo "[Wawona] Using Nix-packaged Android SDK at $ANDROID_SDK_ROOT"
    fi

    APK_PATH="$1"
    if [ -z "$APK_PATH" ]; then
      APK_PATH="$(dirname "$0")/Wawona.apk"
    fi

    if [ ! -f "$APK_PATH" ]; then
      echo "[Wawona] ERROR: APK not found at $APK_PATH"
      exit 1
    fi
    echo "[Wawona] APK: $APK_PATH"

    if ! command -v adb >/dev/null 2>&1; then
      echo "[Wawona] ERROR: adb not found in PATH"
      exit 1
    fi

    adb start-server 2>/dev/null || true

    # Prefer a USB-attached device (serial not matching emulator-*) when present.
    pick_usb_serial() {
      adb devices | awk '
        /^[^#]/ && $2 == "device" && $1 !~ /^emulator-/ { print $1; exit }
      '
    }

    DEVICE_SERIAL="$(pick_usb_serial || true)"
    if [ -n "$DEVICE_SERIAL" ]; then
      BOOT_COMPLETE=$(adb -s "$DEVICE_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "0")
      if [ "$BOOT_COMPLETE" = "1" ]; then
        echo "[Wawona] Using USB device: $DEVICE_SERIAL"
        export ADB_SERIAL="$DEVICE_SERIAL"
        adb() { command adb -s "$ADB_SERIAL" "$@"; }
        DEVICE_READY=true
      else
        echo "[Wawona] USB device $DEVICE_SERIAL found but not booted yet (sys.boot_completed=$BOOT_COMPLETE)"
      fi
    fi

    if [ "''${DEVICE_READY:-false}" != "true" ] && ! command -v emulator >/dev/null 2>&1; then
      echo "[Wawona] ERROR: No booted USB device and emulator not found in PATH"
      exit 1
    fi

    if [ "''${DEVICE_READY:-false}" != "true" ]; then
      echo "[Wawona] Using emulator: $(which emulator)"
    fi
    echo "[Wawona] Using adb: $(which adb)"

    if [ "''${DEVICE_READY:-false}" != "true" ]; then
    export ANDROID_USER_HOME="$HOME/.android"
    export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
    mkdir -p "$ANDROID_AVD_HOME"

    AVD_NAME="WawonaEmulator"

    SYSTEM_IMAGE=""
    case "$(uname -m)" in
      x86_64) PREFERRED_ABI="x86_64" ;;
      aarch64|arm64) PREFERRED_ABI="arm64-v8a" ;;
      *) PREFERRED_ABI="arm64-v8a" ;;
    esac
    if [ "$USE_SYSTEM_SDK" = "true" ]; then
      SYS_IMG_DIR="$ANDROID_SDK_ROOT/system-images"
      # Keep API 36 (Android 16) as the pinned emulator target; only fall
      # back to other images when android-36 is absent.
      for api_dir in android-36 android-36.1 android-35; do
        if [ -d "$SYS_IMG_DIR/$api_dir/google_apis_playstore/$PREFERRED_ABI" ]; then
          SYSTEM_IMAGE="system-images;$api_dir;google_apis_playstore;$PREFERRED_ABI"
          AVD_NAME="WawonaEmulator_$PREFERRED_ABI_$(echo $api_dir | tr '.' '_' | tr '-' '_')"
          echo "[Wawona] Found system image: $SYSTEM_IMAGE"
          break
        elif [ -d "$SYS_IMG_DIR/$api_dir/google_apis/$PREFERRED_ABI" ]; then
          SYSTEM_IMAGE="system-images;$api_dir;google_apis;$PREFERRED_ABI"
          AVD_NAME="WawonaEmulator_$PREFERRED_ABI_$(echo $api_dir | tr '.' '_' | tr '-' '_')"
          echo "[Wawona] Found system image: $SYSTEM_IMAGE"
          break
        fi
      done
      if [ -z "$SYSTEM_IMAGE" ]; then
        echo "[Wawona] ERROR: No compatible system image found in $SYS_IMG_DIR"
        echo "[Wawona] Please install a system image via Android Studio."
        exit 1
      fi
    else
      SYSTEM_IMAGE="${androidConfig.systemImageId}"
      SYSTEM_IMAGE_ABI="''${SYSTEM_IMAGE##*;}"
      AVD_NAME="WawonaEmulator_''${SYSTEM_IMAGE_ABI}_API36"
    fi

    echo "[Wawona] AVD: $AVD_NAME"

    if ! emulator -list-avds 2>/dev/null | grep -q "^$AVD_NAME$"; then
      if [ "$USE_SYSTEM_SDK" = "true" ]; then
        echo "[Wawona] Creating AVD '$AVD_NAME' manually for system SDK..."
        AVD_DIR="$ANDROID_AVD_HOME/$AVD_NAME.avd"
        mkdir -p "$AVD_DIR"

        IFS=';' read -r _ SYS_API SYS_TYPE SYS_ABI <<< "$SYSTEM_IMAGE"
        SYS_IMG_REL="system-images/$SYS_API/$SYS_TYPE/$SYS_ABI/"
        if [ "$SYS_ABI" = "x86_64" ]; then
          CPU_ARCH="x86_64"
        else
          CPU_ARCH="arm64"
        fi

        printf '%s\n' \
          "avd.ini.encoding=UTF-8" \
          "path=$AVD_DIR" \
          "path.rel=avd/$AVD_NAME.avd" \
          "target=$SYS_API" \
          > "$ANDROID_AVD_HOME/$AVD_NAME.ini"

        printf '%s\n' \
          "AvdId=$AVD_NAME" \
          "PlayStore.enabled=true" \
          "abi.type=$SYS_ABI" \
          "avd.ini.displayname=Wawona Emulator" \
          "avd.ini.encoding=UTF-8" \
          "disk.dataPartition.size=6442450944" \
          "hw.accelerometer=yes" \
          "hw.arc=false" \
          "hw.audioInput=yes" \
          "hw.battery=yes" \
          "hw.camera.back=emulated" \
          "hw.camera.front=emulated" \
          "hw.cpu.arch=$CPU_ARCH" \
          "hw.cpu.ncore=4" \
          "hw.dPad=no" \
          "hw.device.manufacturer=Google" \
          "hw.device.name=pixel_9" \
          "hw.gps=yes" \
          "hw.gpu.enabled=yes" \
          "hw.gpu.mode=swiftshader_indirect" \
          "hw.keyboard=yes" \
          "hw.lcd.density=420" \
          "hw.lcd.height=2424" \
          "hw.lcd.width=1080" \
          "hw.mainKeys=no" \
          "hw.ramSize=4096" \
          "hw.sdCard=yes" \
          "hw.sensors.orientation=yes" \
          "hw.sensors.proximity=yes" \
          "hw.trackBall=no" \
          "image.sysdir.1=$SYS_IMG_REL" \
          "tag.display=Google Play" \
          "tag.id=$SYS_TYPE" \
          > "$AVD_DIR/config.ini"

        echo "[Wawona] AVD created at $AVD_DIR"
      elif command -v avdmanager >/dev/null 2>&1; then
        echo "[Wawona] Creating AVD '$AVD_NAME' with avdmanager..."
        echo "no" | avdmanager create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" --force
      else
        echo "[Wawona] ERROR: Cannot create AVD."
        exit 1
      fi
    fi

    # Repair avdmanager-created AVD defaults (idempotent, also fixes
    # previously created AVDs; takes effect on the next emulator boot):
    # - hw.keyboard=no drops physical key events from the host, so host
    #   keyboard passthrough needs hw.keyboard=yes;
    # - the 320x640@160 fallback display is too small for realistic UI
    #   testing and makes the camera hole-punch cutout emulation overlay
    #   render at the wrong geometry — use a Pixel-like panel instead.
    AVD_CONFIG_INI="$ANDROID_AVD_HOME/$AVD_NAME.avd/config.ini"
    if [ -f "$AVD_CONFIG_INI" ]; then
      if grep -qE '^hw\.keyboard *= *no' "$AVD_CONFIG_INI"; then
        sed -i.bak -E 's/^hw\.keyboard *= *no/hw.keyboard = yes/' "$AVD_CONFIG_INI" && rm -f "$AVD_CONFIG_INI.bak"
        echo "[Wawona] Enabled host keyboard passthrough (hw.keyboard=yes) in $AVD_CONFIG_INI"
      elif ! grep -qE '^hw\.keyboard' "$AVD_CONFIG_INI"; then
        printf 'hw.keyboard = yes\n' >> "$AVD_CONFIG_INI"
        echo "[Wawona] Added hw.keyboard=yes to $AVD_CONFIG_INI"
      fi
      if grep -qE '^hw\.lcd\.width *= *320$' "$AVD_CONFIG_INI"; then
        sed -i.bak -E \
          -e 's/^hw\.lcd\.width *=.*/hw.lcd.width = 1080/' \
          -e 's/^hw\.lcd\.height *=.*/hw.lcd.height = 2424/' \
          -e 's/^hw\.lcd\.density *=.*/hw.lcd.density = 420/' \
          -e 's/^hw\.mainKeys *=.*/hw.mainKeys = no/' \
          "$AVD_CONFIG_INI" && rm -f "$AVD_CONFIG_INI.bak"
        echo "[Wawona] Upgraded AVD display to 1080x2424@420 (Pixel-like) in $AVD_CONFIG_INI"
      fi
    fi

    adb start-server 2>/dev/null || true
    
    # ── Surgical Device Detection ──
    # If a device is already online and booted, we skip EVERYTHING except install/launch
    RUNNING_EMULATORS=$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | wc -l | tr -d ' ')
    DEVICE_READY=false
    if [ "$RUNNING_EMULATORS" -gt 0 ]; then
      EMULATOR_SERIAL=$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | head -n 1 | awk '{print $1}')
      BOOT_COMPLETE=$(adb -s "$EMULATOR_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "0")
      if [ "$BOOT_COMPLETE" = "1" ]; then
        echo "[Wawona] Reusing running emulator: $EMULATOR_SERIAL"
        DEVICE_READY=true
      fi
    fi

    if [ "$DEVICE_READY" = "false" ]; then
      echo "[Wawona] Checking for running emulator process '$AVD_NAME'..."
      EMULATOR_PROCESS=$(pgrep -i -f "$AVD_NAME" 2>/dev/null | head -n 1)

      if [ -n "$EMULATOR_PROCESS" ]; then
        echo "[Wawona] Found potential emulator process: $EMULATOR_PROCESS (waiting for ADB connection...)"
      else
        # Automated Provisioning (Licenses, AVD) only when starting fresh
        if [ -n "${provisionScript}" ]; then
           "${provisionScript}"
        fi

        # Clean up stale locks IF no process is actually running
        rm -f "$ANDROID_AVD_HOME/$AVD_NAME.avd/*.lock" 2>/dev/null || true

        echo "[Wawona] Starting emulator '$AVD_NAME'..."
        EMU_GPU_MODE="auto"
        if [ "$(uname -s)" = "Linux" ]; then
          EMU_GPU_MODE="swiftshader_indirect"
        fi
        if [ -n "''${WAWONA_EMULATOR_GPU:-}" ]; then
          EMU_GPU_MODE="''${WAWONA_EMULATOR_GPU}"
        fi
        EMU_ACCEL_FLAGS=""
        if [ -n "''${WAWONA_EMULATOR_ACCEL:-}" ]; then
          EMU_ACCEL_FLAGS="-accel ''${WAWONA_EMULATOR_ACCEL}"
        fi
        EMU_EXTRA_FLAGS="-no-snapshot-load -no-snapshot-save -no-boot-anim -netfast"
        echo "[Wawona] Emulator GPU mode: $EMU_GPU_MODE"
        # We use setsid (from util-linux) to create a new session leader.
        # On macOS, we wrap this in a subshell for a "double-fork" to ensure 
        # it remains attached to the Aqua GUI session while being orphaned from the terminal.
        echo "[Wawona] Detaching emulator process (setsid + double-fork)..."
        if [ "$USE_SYSTEM_SDK" = "true" ] && [ "$(uname -m)" = "arm64" ]; then
          # On Apple Silicon, host GPU is much faster and more reliable
          (setsid nohup emulator -avd "$AVD_NAME" -gpu host $EMU_EXTRA_FLAGS $EMU_ACCEL_FLAGS < /dev/null > /tmp/emulator.log 2>&1 &)
        else
          (setsid nohup emulator -avd "$AVD_NAME" -gpu "$EMU_GPU_MODE" $EMU_EXTRA_FLAGS $EMU_ACCEL_FLAGS < /dev/null > /tmp/emulator.log 2>&1 &)
        fi
        sleep 3
        if [ -f /tmp/emulator.log ] && grep -q "FATAL" /tmp/emulator.log; then
          echo "[Wawona] ERROR: Emulator exited immediately."
          echo "[Wawona] Last emulator log lines:"
          tail -n 40 /tmp/emulator.log
          exit 1
        fi
      fi

      # ── Wait for Boot ──
      TIMEOUT=300
      ELAPSED=0
      while [ $ELAPSED -lt $TIMEOUT ]; do
        if adb devices | grep -E "emulator-[0-9]+" | grep -q "device$"; then
          BOOT_COMPLETE=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "0")
          if [ "$BOOT_COMPLETE" = "1" ]; then
            DEVICE_READY=true
            break
          fi
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
      done
      
      if [ "$DEVICE_READY" = "false" ]; then
        echo "[Wawona] ERROR: Emulator failed to boot within $TIMEOUT seconds."
        exit 1
      fi
    fi
    fi

    # Center-top display cutout for Wawona safe-area testing on the emulator.
    # Stock "hole" is a top-LEFT punch hole (@left) and does not paint visibly on
    # API 36 Play images; "tall" is a center-top notch with fill=true (visible +
    # top inset).  Override: WAWONA_EMULATOR_CUTOUT=tall|hole|emu01|corner|off
    CUTOUT_MODE="''${WAWONA_EMULATOR_CUTOUT:-tall}"
    if [ "$CUTOUT_MODE" != "off" ] && [ -z "''${ADB_SERIAL:-}" ]; then
      EMULATOR_SERIAL=$(adb devices | awk '/emulator-[0-9]+[[:space:]]+device$/ {print $1; exit}')
      if [ -n "$EMULATOR_SERIAL" ]; then
        case "$CUTOUT_MODE" in
          on) CUTOUT_MODE=tall ;;  # legacy alias
          hole|tall|corner|double|emu01|waterfall)
            CUTOUT_PKG="com.android.internal.display.cutout.emulation.''${CUTOUT_MODE}"
            echo "[Wawona] Enabling display cutout emulation ($CUTOUT_MODE) on $EMULATOR_SERIAL..."
            if adb -s "$EMULATOR_SERIAL" shell cmd overlay enable-exclusive --user 0 --category "$CUTOUT_PKG" >/dev/null 2>&1; then
              adb -s "$EMULATOR_SERIAL" shell am crash com.android.systemui >/dev/null 2>&1 || true
              sleep 2
              CUTOUT_SPEC=$(adb -s "$EMULATOR_SERIAL" shell cmd overlay lookup android android:string/config_mainBuiltInDisplayCutout 2>/dev/null | tr -d '\r' || true)
              CUTOUT_INSETS=$(adb -s "$EMULATOR_SERIAL" shell dumpsys display 2>/dev/null | sed -n 's/.*cutout DisplayCutout{insets=Rect(\([^)]*\)).*/\1/p' | head -n1 || true)
              echo "[Wawona] Cutout overlay active: $CUTOUT_PKG"
              echo "[Wawona] Cutout insets (L,T,R,B): ''${CUTOUT_INSETS:-unknown}"
              echo "[Wawona] Cutout spec: ''${CUTOUT_SPEC:0:80}''${CUTOUT_SPEC:+...}"
            else
              echo "[Wawona] WARNING: Could not enable cutout overlay $CUTOUT_PKG"
            fi
            ;;
          *)
            echo "[Wawona] WARNING: Unknown WAWONA_EMULATOR_CUTOUT=$CUTOUT_MODE (use tall|hole|emu01|corner|off)"
            ;;
        esac
      fi
    fi

    graceful_exit() {
      echo ""
      echo "[Wawona] Script terminated. Emulator continues running in background."
      exit 0
    }
    trap graceful_exit SIGTERM SIGINT

    adb logcat -c 2>/dev/null || true

    echo "[Wawona] Installing APK (preserving app data)..."
    if ! adb install -r "$APK_PATH" 2>/dev/null; then
      echo "[Wawona] Upgrade install failed (signature mismatch?). Performing clean install..."
      adb uninstall com.aspauldingcode.wawona 2>/dev/null || true
      adb install "$APK_PATH"
    fi

    PKG="com.aspauldingcode.wawona"

    resolve_app_pid() {
      PIDS_RAW=$(adb shell pidof $PKG 2>/dev/null | tr -d '\r')
      if [ -z "$PIDS_RAW" ]; then
        echo ""
        return 0
      fi

      set -- $PIDS_RAW
      if [ $# -gt 1 ]; then
        echo "[Wawona] Multiple app PIDs detected: $PIDS_RAW (using newest)"
      fi

      echo "$PIDS_RAW" | tr ' ' '\n' | awk 'NF { last=$1 } END { print last }'
    }

    if [ "$DEBUG_MODE" = "true" ]; then
      # ── Debug launch: am start -D, deploy lldb-server, attach LLDB ──

      start_lldb_server_for_pid() {
        TARGET_PID="$1"
        adb forward tcp:8700 jdwp:$TARGET_PID 2>/dev/null || true

        if adb shell "run-as $PKG ls ./lldb-server" 2>/dev/null | grep -q "lldb-server"; then
          echo "[Wawona] Starting lldb-server (app sandbox, pid $TARGET_PID)..."
          adb shell "run-as $PKG sh -c './lldb-server gdbserver --attach $TARGET_PID 0.0.0.0:$LLDB_PORT >/dev/null 2>&1'" &
        else
          echo "[Wawona] Starting lldb-server (/data/local/tmp, pid $TARGET_PID)..."
          adb shell "/data/local/tmp/lldb-server gdbserver --attach $TARGET_PID 0.0.0.0:$LLDB_PORT >/dev/null 2>&1" &
        fi

        LLDB_SERVER_HOST_PID=$!
        sleep 2
      }

      echo "[Wawona] Launching Wawona in debug mode..."
      adb shell am start -D -n $PKG/.MainActivity

      echo "[Wawona] Waiting for process..."
      PID=""
      for i in $(seq 1 30); do
        PID=$(resolve_app_pid)
        if [ -n "$PID" ]; then break; fi
        sleep 0.5
      done

      if [ -z "$PID" ]; then
        echo "[Wawona] ERROR: Could not get process PID. App may have crashed."
        adb logcat -d -v time | grep -i -E "(wawona|androidruntime|fatal|exception|error)" | tail -100
        exit 1
      fi

      echo "[Wawona] App PID: $PID (paused — no code has run yet)"

      LLDB_SERVER=$(find "$NDK_ROOT/toolchains/llvm/prebuilt" -name "lldb-server" -path "*/aarch64/*" -type f 2>/dev/null | head -1)
      if [ -z "$LLDB_SERVER" ]; then
        echo "[Wawona] ERROR: Could not find aarch64 lldb-server in NDK at $NDK_ROOT"
        exit 1
      fi

      LLDB_BIN="$(which lldb)"
      if [ -z "$LLDB_BIN" ]; then
        echo "[Wawona] ERROR: lldb not found in PATH"
        exit 1
      fi

      adb shell "pkill -9 lldb-server" 2>/dev/null || true
      sleep 0.5
      adb push "$LLDB_SERVER" /data/local/tmp/lldb-server 2>/dev/null
      adb shell "chmod 755 /data/local/tmp/lldb-server"
      adb shell "run-as $PKG sh -c 'cat /data/local/tmp/lldb-server > ./lldb-server && chmod 700 ./lldb-server'" 2>/dev/null

      LLDB_PORT=5039
      adb forward tcp:$LLDB_PORT tcp:$LLDB_PORT 2>/dev/null || true

      start_lldb_server_for_pid "$PID"

      CURRENT_PID=$(resolve_app_pid)
      if [ -n "$CURRENT_PID" ] && [ "$CURRENT_PID" != "$PID" ]; then
        echo "[Wawona] App PID changed before LLDB attach: $PID -> $CURRENT_PID"
        PID="$CURRENT_PID"
        kill $LLDB_SERVER_HOST_PID 2>/dev/null || true
        adb shell "pkill -9 lldb-server" 2>/dev/null || true
        start_lldb_server_for_pid "$PID"
        echo "[Wawona] Reattached lldb-server to PID $PID"
      fi

      if ! kill -0 $LLDB_SERVER_HOST_PID 2>/dev/null; then
        echo "[Wawona] ERROR: lldb-server failed to start. Falling back to logcat."
        adb logcat -c 2>/dev/null || true
        echo "resume" | jdb -connect sun.jdi.SocketAttach:hostname=localhost,port=8700 2>/dev/null &
        echo "--- Wawona Android Crash Monitor ---"
        adb logcat -v time -s Wawona:D WawonaJNI:D WawonaNative:D AndroidRuntime:E DEBUG:I
        exit 0
      fi

      APP_LOG="/tmp/wawona-android.log"
      rm -f "$APP_LOG"
      touch "$APP_LOG"
      adb logcat -c 2>/dev/null || true
      adb logcat -v time -s Wawona:D WawonaJNI:D WawonaNative:D AndroidRuntime:E DEBUG:I >> "$APP_LOG" &
      LOGCAT_PID=$!

      echo "--- Wawona Android Logs (PID $PID) ---"
      tail -f "$APP_LOG" &
      TAIL_PID=$!

      trap "kill $TAIL_PID $LOGCAT_PID $LLDB_SERVER_HOST_PID 2>/dev/null || true; adb shell 'pkill -9 lldb-server' 2>/dev/null || true" EXIT INT TERM

      (sleep 4 && \
       echo "resume" | jdb -connect sun.jdi.SocketAttach:hostname=localhost,port=8700 2>/dev/null; \
       true) &
      JDB_PID=$!

      echo "[Wawona] LLDB connecting to PID $PID on port $LLDB_PORT..."
      echo "[Wawona] Java VM will resume in 4s (native code hasn't run yet)."
      echo "[Wawona] On crash, LLDB stops and you get an interactive prompt."
      echo ""

      exec "$LLDB_BIN" -Q \
        -o "gdb-remote $LLDB_PORT" \
        -o "process handle SIGSEGV -n true -p false -s true" \
        -o "process handle SIGPIPE -n false -p true -s false" \
        -o "process handle SIGABRT -n true -p false -s true" \
        -o "process handle SIGBUS  -n true -p false -s true" \
        -o "process handle SIGFPE  -n true -p false -s true" \
        -o "process handle SIGILL  -n true -p false -s true" \
        -o "continue"

    else
      # ── Normal launch: am start, stream logcat ──

      echo "[Wawona] Launching Wawona..."
      adb shell am start -n $PKG/.MainActivity

      echo "[Wawona] Waiting for process..."
      PID=""
      for i in $(seq 1 15); do
        PID=$(resolve_app_pid)
        if [ -n "$PID" ]; then break; fi
        sleep 0.5
      done

      if [ -n "$PID" ]; then
        echo "[Wawona] App PID: $PID"
      else
        echo "[Wawona] Warning: Could not resolve app PID (app may still be starting)"
      fi

      if [ "$TEST_MODE" = "true" ]; then
        echo "[Wawona] Running in CI Test Mode. Waiting 10 seconds to verify stability..."
        sleep 10
        if adb shell pidof $PKG >/dev/null 2>&1; then
          echo "[Wawona] SUCCESS: App is running stably."
          exit 0
        else
          echo "[Wawona] ERROR: App crashed or exited prematurely!"
          adb logcat -d -v time -s Wawona:D WawonaJNI:D WawonaNative:D AndroidRuntime:E DEBUG:I | tail -n 50
          exit 1
        fi
      fi

      echo "--- Wawona Android Logs ---"
      echo "[Wawona] Tip: use 'nix run .#wawona-android -- --debug' to attach LLDB"
      adb logcat -v time -s Wawona:D WawonaJNI:D WawonaNative:D AndroidRuntime:E DEBUG:I
    fi
  '';

in
  pkgs.stdenv.mkDerivation (finalAttrs: rec {
    name = "wawona-android";
    version = projectVersion;
    src = srcFiltered;

    outputs = [ "out" "project" ];

    # Skip fixup phase - Android binaries can't execute on macOS
    dontFixup = true;
    dontUseGradleBuild = true;
    dontUseGradleCheck = true;
    __darwinAllowLocalNetworking = true;

    mitmCache = gradleSupport.mitmCache;
    gradleFlags = gradleSupport.gradleFlags;
    gradleUpdateTask = ":Wawona:assembleDebug";
    enableParallelUpdating = false;

    nativeBuildInputs = (with pkgs; [
      clang
      pkg-config
      jdk17 # Full JDK needed for Gradle
      gradle
      unzip
      zip
      file
      util-linux # Provides setsid for creating new process groups
      glslang # For compiling Vulkan shaders to SPIR-V
    ]) ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.patchelf ];

    buildInputs = (getDeps "android" androidDeps) ++ [
      pkgs.mesa
    ];

    # Files are now tracked directly in the repository, so we only need to
    # verify they exist before the build begins.
    prePatch = ''
      if [ ! -f src/platform/android/input_android.h ] || [ ! -f src/platform/android/input_android.c ]; then
        echo "ERROR: Missing input_android files in src/platform/android/"
        exit 1
      fi
      if [ ! -f android/app/src/main/java/com/aspauldingcode/wawona/ScreencopyHelper.kt ]; then
        echo "ERROR: Missing ScreencopyHelper.kt"
        exit 1
      fi
      if [ ! -f android/app/src/main/java/com/aspauldingcode/wawona/ModifierAccessoryBar.kt ]; then
        echo "ERROR: Missing ModifierAccessoryBar.kt"
        exit 1
      fi
    '';

    # Fix egl_buffer_handler for Android (create Android-compatible stubs)
    postPatch = ''
      if [ ! -f src/stubs/egl_buffer_handler.h ] || [ ! -f src/stubs/egl_buffer_handler.c ]; then
        echo "ERROR: Missing egl_buffer_handler stubs"
        exit 1
      fi
    '';

    preBuild = ''
      ndk_root="${androidToolchainResolved.androidndkRoot}"

      # Embed Vulkan shaders as C byte arrays for textured quad pipeline
      mkdir -p build/shaders
      if [ -f "${androidQuadVert}" ] && [ -f "${androidQuadFrag}" ]; then
        ${glslang}/bin/glslangValidator -V "${androidQuadVert}" -o build/shaders/quad.vert.spv
        ${glslang}/bin/glslangValidator -V "${androidQuadFrag}" -o build/shaders/quad.frag.spv
        echo '/* Auto-generated - do not edit */' > build/shaders/shader_spv.h
        echo '#pragma once' >> build/shaders/shader_spv.h
        echo '#include <stddef.h>' >> build/shaders/shader_spv.h
        echo '#include <stdint.h>' >> build/shaders/shader_spv.h
        echo 'static const unsigned char g_quad_vert_spv[] = {' >> build/shaders/shader_spv.h
        od -A n -t x1 -v build/shaders/quad.vert.spv | awk '{for(i=1;i<=NF;i++) printf " 0x%s,", $i}' | sed '$ s/,$//' >> build/shaders/shader_spv.h
        echo '};' >> build/shaders/shader_spv.h
        echo 'static const size_t g_quad_vert_spv_len = sizeof(g_quad_vert_spv);' >> build/shaders/shader_spv.h
        echo "" >> build/shaders/shader_spv.h
        echo 'static const unsigned char g_quad_frag_spv[] = {' >> build/shaders/shader_spv.h
        od -A n -t x1 -v build/shaders/quad.frag.spv | awk '{for(i=1;i<=NF;i++) printf " 0x%s,", $i}' | sed '$ s/,$//' >> build/shaders/shader_spv.h
        echo '};' >> build/shaders/shader_spv.h
        echo 'static const size_t g_quad_frag_spv_len = sizeof(g_quad_frag_spv);' >> build/shaders/shader_spv.h
        mkdir -p dependencies/generators/gradlegen/generated
        cp build/shaders/shader_spv.h dependencies/generators/gradlegen/generated/shader_spv.h
      else
        echo "ERROR: Shader sources not found at ${androidQuadVert} / ${androidQuadFrag}."
        exit 1
      fi

      # Setup Weston Simple SHM (CMakeLists.txt expects this)
      mkdir -p deps/weston-simple-shm
      cp -r ${westonSimpleShmSrc}/* deps/weston-simple-shm/
      chmod -R u+w deps/weston-simple-shm
      ${lib.optionalString (westonAndroidSignalPolyfill != null) ''
        cp ${westonAndroidSignalPolyfill} deps/weston-simple-shm/wwn-android-signal-polyfill.h
      ''}

      # Flatten the Android project into the repo root so the CMake relative
      # paths still point at the Nix-filtered source tree.
      echo "=== Phase 25: Preparing Android Project ==="
      ${gradleSupport.prepareProject}
      ${gradleSupport.prepareEnvironment}

      # Normalize daemon/jvmargs so --no-daemon stays in-process. A mismatched
      # jvmargs profile forks a single-use daemon that needs localhost TCP and
      # fails in the Nix sandbox (DaemonConnectionException / Operation not permitted).
      # Re-append matching jvmargs + daemon=false; heap must match GRADLE_OPTS below
      # (defaults are only 512m and OOM on assembleDebug).
      if [ -f gradle.properties ]; then
        grep -v -E '^org\.gradle\.(jvmargs|daemon)=' gradle.properties > gradle.properties.nix
        mv gradle.properties.nix gradle.properties
        echo 'org.gradle.daemon=false' >> gradle.properties
        # Include -Xms64m: the gradle launcher always sets it on the client JVM;
        # omit it from Wanted and Gradle forks a single-use daemon.
        echo 'org.gradle.jvmargs=-Xms64m -Xmx6144m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8' >> gradle.properties
      fi

      # Bundle Nix-built shared libraries into the APK so the Android loader
      # can resolve libwawona.so runtime dependencies on-device.
      JNI_LIB_DIR="app/src/main/jniLibs/arm64-v8a"
      mkdir -p "$JNI_LIB_DIR"
      rm -f "$JNI_LIB_DIR"/*.so "$JNI_LIB_DIR"/*.so.*
      shopt -s nullglob
      for libdir in ${lib.concatMapStringsSep " " (d: "${d}/lib") (getDeps "android" androidDeps)}; do
        for so in "$libdir"/*.so "$libdir"/*.so.*; do
          base_so="$(basename "$so")"
          case "$base_so" in
            # These upstream prebuilts are not 16KB-page aligned.
            # Do not bundle them; Android provides Vulkan/SwiftShader runtime paths.
            libvk_swiftshader.so|libSPIRV-Tools-shared.so)
              continue
              ;;
          esac
          cp -L "$so" "$JNI_LIB_DIR/$(basename "$so")"
        done
      done
      shopt -u nullglob

      # ANGLE ships as libEGL.so / libGLESv2.so but with SONAMEs
      # libEGL_angle.so / libGLESv2_angle.so; libwawona.so links against the
      # SONAME, so stage SONAME-named copies too or the loader fails at launch.
      [ -f "$JNI_LIB_DIR/libEGL.so" ] && cp -f "$JNI_LIB_DIR/libEGL.so" "$JNI_LIB_DIR/libEGL_angle.so"
      [ -f "$JNI_LIB_DIR/libGLESv2.so" ] && cp -f "$JNI_LIB_DIR/libGLESv2.so" "$JNI_LIB_DIR/libGLESv2_angle.so"

      # Bundle SSH client helpers with stable names expected by android_jni.c.
      # We ship Dropbear dbclient as libssh_bin.so and sshpass as libsshpass_bin.so
      # in jniLibs so runtime path resolution can execute them directly.
      if [ -f "${opensshBin}/bin/ssh" ]; then
        cp -L "${opensshBin}/bin/ssh" "$JNI_LIB_DIR/libssh_bin.so"
        chmod +x "$JNI_LIB_DIR/libssh_bin.so"
      else
        echo "WARNING: Missing Android ssh binary at ${opensshBin}/bin/ssh"
      fi

      # Key management (wwn-ssh): dropbearkey ships as ssh-keygen (same
      # -t/-f/-y CLI for ed25519), plus scp and dropbearconvert.
      if [ -f "${opensshBin}/bin/ssh-keygen" ]; then
        cp -L "${opensshBin}/bin/ssh-keygen" "$JNI_LIB_DIR/libssh_keygen_bin.so"
        chmod +x "$JNI_LIB_DIR/libssh_keygen_bin.so"
      else
        echo "WARNING: Missing Android ssh-keygen binary at ${opensshBin}/bin/ssh-keygen"
      fi

      if [ -f "${opensshBin}/bin/scp" ]; then
        cp -L "${opensshBin}/bin/scp" "$JNI_LIB_DIR/libscp_bin.so"
        chmod +x "$JNI_LIB_DIR/libscp_bin.so"
      fi

      if [ -f "${opensshBin}/bin/dropbearconvert" ]; then
        cp -L "${opensshBin}/bin/dropbearconvert" "$JNI_LIB_DIR/libdropbearconvert_bin.so"
        chmod +x "$JNI_LIB_DIR/libdropbearconvert_bin.so"
      fi

      if [ -f "${sshpassBin}/bin/sshpass" ]; then
        cp -L "${sshpassBin}/bin/sshpass" "$JNI_LIB_DIR/libsshpass_bin.so"
        chmod +x "$JNI_LIB_DIR/libsshpass_bin.so"
      else
        echo "WARNING: Missing Android sshpass binary at ${sshpassBin}/bin/sshpass"
      fi

      # Bundled interactive shell tools (zsh, fastfetch, neovim); see
      # android-shell-tools.nix.
      ${shellTools.preBuildFragment}

      # xkeyboard-config: extracted from assets into wawona-rootfs by WawonaShellRootfs.
      mkdir -p app/src/main/assets/xkb
      cp -RL ${pkgs.xkeyboard_config}/share/X11/xkb/. app/src/main/assets/xkb/
      chmod -R u+w app/src/main/assets/xkb

      # DejaVu fonts for the in-process weston toytoolkit clients (cairo/
      # fontconfig text rendering). iOS embeds the same tree under share/fonts;
      # android_jni.c writes a fonts.conf pointing here at runtime.
      mkdir -p app/src/main/assets/fonts/truetype
      cp -L ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf \
            ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf \
            ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf \
            ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono-Bold.ttf \
            app/src/main/assets/fonts/truetype/
      chmod -R u+w app/src/main/assets/fonts

      # Weston toytoolkit PNGs (sign_close.png, icon_window.png, …) for CSD clients.
      ${westonData.preBuildFragment}

      # In-process Wayland clients (weston-simple-shm, foot); see
      # android-bundled-clients.nix.
      ${bundledClients.preBuildFragment}

      # anowaW app bridge: stage the Kotlin shims into the app sourceSet and the
      # JNI glue next to android_jni.c so CMake picks it up. libanowaw.so is
      # bundled into jniLibs by the androidDeps .so copy loop above.
      if [ -d "${anowawAndroid}/share/anowaw/kotlin" ]; then
        ANOWAW_KT_DIR="app/src/main/kotlin/com/aspauldingcode/wawona/anowaw"
        mkdir -p "$ANOWAW_KT_DIR"
        cp -L ${anowawAndroid}/share/anowaw/kotlin/*.kt "$ANOWAW_KT_DIR/"
        chmod -R u+w "$ANOWAW_KT_DIR"
      fi
      if [ -f "${anowawAndroid}/share/anowaw/jni/anowaw_jni.c" ]; then
        cp -L ${anowawAndroid}/share/anowaw/jni/anowaw_jni.c \
              src/platform/android/anowaw_jni.c
        chmod u+w src/platform/android/anowaw_jni.c
      fi

      # Prefer the Rust shared library for Android linking; the static archive
      # can be malformed on some host toolchain combinations.
      RUST_BACKEND_LINK_LIB="${rustBackendPath}/lib/libwawona.a"
      if [ -f "${rustBackendPath}/lib/libwawona_core.so" ]; then
        cp -L "${rustBackendPath}/lib/libwawona_core.so" "$JNI_LIB_DIR/libwawona_core.so"
        RUST_BACKEND_LINK_LIB="${rustBackendPath}/lib/libwawona_core.so"
      fi

      # Inject Nix dependencies via Environment Variables for Gradle/CMake
      export ANDROID_NDK_ROOT="$ndk_root"
      export ANDROID_NDK_HOME="$ndk_root"
      export DEP_INCLUDES="${lib.concatMapStringsSep " " (d: "-I${d}/include") (getDeps "android" androidDeps)} -I${buildModule.buildForAndroid "pixman" { }}/include/pixman-1 -I${westonAndroid}/include/weston-gen"
      export DEP_LIBS="${lib.concatMapStringsSep " " (d: "-L${d}/lib") (getDeps "android" androidDeps)} ${lib.concatStringsSep " " (westonToytoolkitLdflags ++ westonCompositorLdflags ++ ilandGlLdflags)}"
      export RUST_BACKEND_LIB="$RUST_BACKEND_LINK_LIB"
    '';

    buildPhase = ''
      runHook preBuild

      if [ "${if isReleaseBuild then "1" else "0"}" = "1" ]; then
        if [ -n "''${ANDROID_KEYSTORE_BASE64:-}" ]; then
          KEYSTORE_PATH="''${ANDROID_KEYSTORE_PATH:-$TMPDIR/wawona-upload.jks}"
          echo "''${ANDROID_KEYSTORE_BASE64}" | base64 -d > "$KEYSTORE_PATH"
          export ANDROID_KEYSTORE_PATH="$KEYSTORE_PATH"
        fi
        : "''${ANDROID_KEYSTORE_PATH:?Set ANDROID_KEYSTORE_PATH or ANDROID_KEYSTORE_BASE64 for release builds}"
        : "''${ANDROID_KEYSTORE_PASSWORD:?Missing ANDROID_KEYSTORE_PASSWORD}"
        : "''${ANDROID_KEY_ALIAS:?Missing ANDROID_KEY_ALIAS}"
        : "''${ANDROID_KEY_PASSWORD:?Missing ANDROID_KEY_PASSWORD}"
      fi

      # Build APK/AAB using Gradle.
      # Always use Nix gradle here: ./gradlew forceFetches the wrapper zip and
      # fails in the sandbox (SocketException: Operation not permitted).
      #
      # Keep --no-daemon truly in-process: client GRADLE_OPTS must match
      # org.gradle.jvmargs (above) plus mitm trustStore that gradle-setup-hook
      # injects via -D flags. Do not pass -Dorg.gradle.jvmargs on the CLI
      # (that forces a mismatch/fork → DaemonConnectionException in CI).
      GRADLE_OPTS="-Xms64m -Xmx6144m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8"
      if [ -n "''${MITM_CACHE_KEYSTORE-}" ] && [ -n "''${MITM_CACHE_KS_PWD-}" ]; then
        GRADLE_OPTS="''${GRADLE_OPTS} -Djavax.net.ssl.trustStore=''${MITM_CACHE_KEYSTORE} -Djavax.net.ssl.trustStorePassword=''${MITM_CACHE_KS_PWD}"
      fi
      export GRADLE_OPTS
      gradle ${gradleTask} --no-build-cache --no-watch-fs --no-daemon --max-workers=1 \
        -Dorg.gradle.parallel=false \
        -Dorg.gradle.workers.max=1 \
        -Dorg.gradle.daemon=false \
        -Dkotlin.daemon.enabled=false \
        -Dkotlin.compiler.execution.strategy=in-process \
        -Dkotlin.incremental=false \
        --info --stacktrace || {
        echo "=== Gradle Build Failed! Accessing Diagnostic Reports ==="
        REPORT_PATH="app/build/outputs/logs/manifest-merger-debug-report.txt"
        if [ -f "$REPORT_PATH" ]; then
          echo "=== Manifest Merger Debug Report ==="
          cat "$REPORT_PATH"
        fi
        exit 1
      }
      
      # Verify bundled client .so files are packaged; see android-bundled-clients.nix.
      ${bundledClients.verifyApkFragment}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      mkdir -p $out/lib

      ${if releaseArtifact == "release-aab" then ''
      AAB_PATH=""
      shopt -s nullglob globstar
      for candidate in \
        app/build/outputs/bundle/**/*.aab \
        android/app/build/outputs/bundle/**/*.aab \
        build/outputs/bundle/**/*.aab
      do
        if [ -f "$candidate" ]; then
          AAB_PATH="$candidate"
          break
        fi
      done
      shopt -u nullglob globstar
      if [ -z "$AAB_PATH" ]; then
        echo "Error: No AAB found!"
        exit 1
      fi
      mkdir -p $out/share/android
      cp "$AAB_PATH" $out/share/android/Wawona.aab
      ln -sf ../share/android/Wawona.aab $out/bin/Wawona.aab
      '' else ''
      # Gradle builds from the flattened root project in Nix, but some callers
      # still expect the nested `android/` layout. Probe both to find the APK.
      APK_PATH=""
      shopt -s nullglob globstar
      for candidate in \
        app/build/outputs/apk/**/*.apk \
        android/app/build/outputs/apk/**/*.apk \
        build/outputs/apk/**/*.apk
      do
        if [ -f "$candidate" ]; then
          APK_PATH="$candidate"
          break
        fi
      done
      shopt -u nullglob globstar

      if [ -z "$APK_PATH" ]; then
        echo "Error: No APK found!"
        exit 1
      fi
      cp "$APK_PATH" $out/bin/Wawona.apk
      
      # Copy the runner script
      cp ${runnerScript} $out/bin/wawona-android-run
      chmod +x $out/bin/wawona-android-run
      ''}

      # Expose full project for gradlegen (IDE support)
      mkdir -p $project
      cp -r . "$project/"
      
      runHook postInstall
    '';
  })
