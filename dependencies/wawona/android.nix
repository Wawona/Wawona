{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  wawonaVersion ? null,
  androidSDK ? null,
  androidUtils ? null,
  androidToolchain ? null,
  rustBackend ? null,
  glslang ? pkgs.glslang,
  targetPkgs,
  ...
}:

let
  common = import ./common.nix { inherit lib pkgs wawonaSrc; };
  provisionScript = if androidUtils != null then "${androidUtils.provisionAndroidScript}/bin/provision-android" else "";

  androidToolchainEffective = if androidToolchain != null then androidToolchain else import ../toolchains/android.nix { inherit lib androidSDK; pkgs = targetPkgs; };
  androidToolchain = androidToolchainEffective;
  
  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;
  gradleDeps = pkgs.callPackage ../gradle-deps.nix {
    inherit wawonaSrc androidSDK;
    inherit (pkgs) gradle jdk17;
    gradlegen = android_gradlegen_internal.generateScript;
  };

  android_gradlegen_internal = pkgs.callPackage ../generators/gradlegen.nix { wawonaVersion = projectVersion; };

  androidIconAssets =
    if builtins.pathExists ../generators/android-icon-assets.nix then
      pkgs.callPackage ../generators/android-icon-assets.nix {
        inherit wawonaSrc;
      }
    else
      null;

  westonSimpleShmSrc = pkgs.callPackage ../libs/weston-simple-shm/patched-src.nix {};

  opensshBin = buildModule.buildForAndroid "openssh" { };
  sshpassBin = buildModule.buildForAndroid "sshpass" { };
  # Disable Weston on Android as building its GUI dependencies (cairo/pango) triggers 
  # Nixpkgs pkgsCross.aarch64-android which currently fails on compiler-rt (missing pthread.h).
  # Wawona is its own Wayland server and doesn't actually need Weston to run.
  westonBin = "";
  rustBackendPath = if rustBackend != null then toString rustBackend else "";

  androidDeps = common.commonDeps ++ [
    "swiftshader"
    "pixman"
    "libwayland"
    "expat"
    "libffi"
    "libxml2"
    "xkbcommon"
    "openssl"
  ];

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
    "src/rendering/renderer_android.c"
    "src/rendering/renderer_android.h"
    "src/platform/macos/WWNSettings.c"
    "src/platform/macos/WWNSettings.h"
  ];

  androidSourcesFiltered = (common.filterSources androidCommonSources) ++ androidExtraSources;

  nixSdkPath = lib.makeBinPath [
    androidSDK.platform-tools
    androidSDK.emulator
    androidSDK.androidsdk
    pkgs.util-linux
    pkgs.jdk17
    pkgs.lldb
  ];

  nixSdkRoot = "${androidSDK.androidsdk}/libexec/android-sdk";

  runnerScript = pkgs.writeShellScript "wawona-android-run" ''
    set +e

    NIX_SDK_PATH="${nixSdkPath}"
    NDK_ROOT="${androidToolchain.androidndkRoot}"

    USE_SYSTEM_SDK=false
    if [ "$(uname -m)" = "arm64" ] && [ "$(uname -s)" = "Darwin" ]; then
      echo "[Wawona] Detected Apple Silicon (arm64) macOS"
      
      # Nix can override $HOME, so we should check the actual user's home directory too
      REAL_USER=$(whoami)
      REAL_HOME="/Users/$REAL_USER"
      
      SYSTEM_SDK=""
      if [ -d "$HOME/Library/Android/sdk/emulator" ] && [ -f "$HOME/Library/Android/sdk/emulator/emulator" ]; then
        SYSTEM_SDK="$HOME/Library/Android/sdk"
      elif [ -d "$REAL_HOME/Library/Android/sdk/emulator" ] && [ -f "$REAL_HOME/Library/Android/sdk/emulator/emulator" ]; then
        SYSTEM_SDK="$REAL_HOME/Library/Android/sdk"
      fi

      if [ -z "$SYSTEM_SDK" ] || [ ! -d "$REAL_HOME/Library/Android/sdk/system-images/android-36" ]; then
        echo "[Wawona] arm64 native Android emulator or android-36 image not found."
        echo "[Wawona] Downloading and setting up arm64 Android SDK automatically..."
        
        # We will install it in the standard macOS location
        SYSTEM_SDK="$REAL_HOME/Library/Android/sdk"
        mkdir -p "$SYSTEM_SDK"
        
        # Use Nix's sdkmanager to provision the system SDK
        export PATH="$NIX_SDK_PATH:$PATH"
        yes | sdkmanager --install "system-images;android-36;google_apis_playstore;arm64-v8a" "platform-tools" "platforms;android-36" --sdk_root="$SYSTEM_SDK" > /dev/null
        echo "[Wawona] System Android SDK installed to $SYSTEM_SDK."
      fi

      if [ -n "$SYSTEM_SDK" ]; then
        echo "[Wawona] Using system Android SDK emulator (arm64 native) at $SYSTEM_SDK"
        
        # We still need the Nix SDK for adb and other tools, but we want the system emulator first
        export PATH="$SYSTEM_SDK/emulator:$SYSTEM_SDK/platform-tools:$SYSTEM_SDK/cmdline-tools/latest/bin:$NIX_SDK_PATH:$PATH"
        export ANDROID_SDK_ROOT="$SYSTEM_SDK"
        export ANDROID_HOME="$SYSTEM_SDK"
        USE_SYSTEM_SDK=true
      fi
    fi

    if [ "$USE_SYSTEM_SDK" = "false" ]; then
      export PATH="$NIX_SDK_PATH:$PATH"
      export ANDROID_SDK_ROOT="${nixSdkRoot}"
      export ANDROID_HOME="$ANDROID_SDK_ROOT"
    fi


    DEBUG_MODE=false
    TEST_MODE=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --debug) DEBUG_MODE=true; shift ;;
        --test) TEST_MODE=true; shift ;;
        *) break ;;
      esac
    done

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

    if ! command -v emulator >/dev/null 2>&1; then
      echo "[Wawona] ERROR: emulator not found in PATH"
      exit 1
    fi

    echo "[Wawona] Using emulator: $(which emulator)"
    echo "[Wawona] Using adb: $(which adb)"

    export ANDROID_USER_HOME="$HOME/.android"
    export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
    mkdir -p "$ANDROID_AVD_HOME"

    AVD_NAME="WawonaEmulator"

    SYSTEM_IMAGE=""
    if [ "$USE_SYSTEM_SDK" = "true" ]; then
      SYS_IMG_DIR="$ANDROID_SDK_ROOT/system-images"
      for api_dir in android-36.1 android-36 android-35; do
        if [ -d "$SYS_IMG_DIR/$api_dir/google_apis_playstore/arm64-v8a" ]; then
          SYSTEM_IMAGE="system-images;$api_dir;google_apis_playstore;arm64-v8a"
          AVD_NAME="WawonaEmulator_$(echo $api_dir | tr '.' '_' | tr '-' '_')"
          echo "[Wawona] Found system image: $SYSTEM_IMAGE"
          break
        elif [ -d "$SYS_IMG_DIR/$api_dir/google_apis/arm64-v8a" ]; then
          SYSTEM_IMAGE="system-images;$api_dir;google_apis;arm64-v8a"
          AVD_NAME="WawonaEmulator_$(echo $api_dir | tr '.' '_' | tr '-' '_')"
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
      SYSTEM_IMAGE="system-images;android-36;google_apis_playstore;arm64-v8a"
      AVD_NAME="WawonaEmulator_API36"
    fi

    echo "[Wawona] AVD: $AVD_NAME"

    if ! emulator -list-avds 2>/dev/null | grep -q "^$AVD_NAME$"; then
      if [ "$USE_SYSTEM_SDK" = "true" ]; then
        echo "[Wawona] Creating AVD '$AVD_NAME' manually for system SDK..."
        AVD_DIR="$ANDROID_AVD_HOME/$AVD_NAME.avd"
        mkdir -p "$AVD_DIR"

        IFS=';' read -r _ SYS_API SYS_TYPE SYS_ABI <<< "$SYSTEM_IMAGE"
        SYS_IMG_REL="system-images/$SYS_API/$SYS_TYPE/$SYS_ABI/"

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
          "hw.cpu.arch=arm64" \
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
        # We use setsid (from util-linux) to create a new session leader.
        # On macOS, we wrap this in a subshell for a "double-fork" to ensure 
        # it remains attached to the Aqua GUI session while being orphaned from the terminal.
        echo "[Wawona] Detaching emulator process (setsid + double-fork)..."
        if [ "$USE_SYSTEM_SDK" = "true" ] && [ "$(uname -m)" = "arm64" ]; then
          # On Apple Silicon, host GPU is much faster and more reliable
          (setsid nohup emulator -avd "$AVD_NAME" -gpu host < /dev/null > /tmp/emulator.log 2>&1 &)
        else
          (setsid nohup emulator -avd "$AVD_NAME" -gpu auto < /dev/null > /tmp/emulator.log 2>&1 &)
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
  pkgs.stdenv.mkDerivation rec {
    name = "wawona-android";
    version = projectVersion;
    src = wawonaSrc;

    outputs = [ "out" "project" ];

    # Skip fixup phase - Android binaries can't execute on macOS
    dontFixup = true;

    nativeBuildInputs = with pkgs; [
      clang
      pkg-config
      jdk17 # Full JDK needed for Gradle
      gradle
      unzip
      zip
      patchelf
      file
      util-linux # Provides setsid for creating new process groups
      glslang # For compiling Vulkan shaders to SPIR-V
    ];

    buildInputs = (getDeps "android" androidDeps) ++ [
      pkgs.mesa
    ];

    # Ensure input_android, shaders exist (untracked or filtered by flake)
    prePatch = ''
      mkdir -p src/platform/android
      mkdir -p src/rendering/shaders
      if [ ! -f src/platform/android/input_android.h ]; then
        cat > src/platform/android/input_android.h <<'INPUT_H'
#pragma once

#include <stdint.h>

uint32_t android_keycode_to_linux(uint32_t android_keycode);
INPUT_H
      fi
      if [ ! -f src/platform/android/input_android.c ]; then
        cat > src/platform/android/input_android.c <<'INPUT_C'
/**
 * Android input helpers - keycode mapping and modifier tracking
 *
 * Maps Android KeyEvent keycodes to Linux evdev/XKB keycodes.
 * Android keycodes are similar but not identical to Linux.
 */

#include "input_android.h"
#include <stdint.h>

/* Linux evdev key codes (from input-event-codes.h) */
#define KEY_RESERVED        0
#define KEY_ESC             1
#define KEY_1               2
#define KEY_2               3
#define KEY_3               4
#define KEY_4               5
#define KEY_5               6
#define KEY_6               7
#define KEY_7               8
#define KEY_8               9
#define KEY_9               10
#define KEY_0               11
#define KEY_MINUS           12
#define KEY_EQUAL           13
#define KEY_BACKSPACE       14
#define KEY_TAB             15
#define KEY_Q               16
#define KEY_W               17
#define KEY_E               18
#define KEY_R               19
#define KEY_T               20
#define KEY_Y               21
#define KEY_U               22
#define KEY_I               23
#define KEY_O               24
#define KEY_P               25
#define KEY_LEFTBRACE       26
#define KEY_RIGHTBRACE      27
#define KEY_ENTER           28
#define KEY_LEFTCTRL        29
#define KEY_A               30
#define KEY_S               31
#define KEY_D               32
#define KEY_F               33
#define KEY_G               34
#define KEY_H               35
#define KEY_J               36
#define KEY_K               37
#define KEY_L               38
#define KEY_SEMICOLON       39
#define KEY_APOSTROPHE      40
#define KEY_GRAVE           41
#define KEY_LEFTSHIFT       42
#define KEY_BACKSLASH       43
#define KEY_Z               44
#define KEY_X               45
#define KEY_C               46
#define KEY_V               47
#define KEY_B               48
#define KEY_N               49
#define KEY_M               50
#define KEY_COMMA           51
#define KEY_DOT             52
#define KEY_SLASH           53
#define KEY_RIGHTSHIFT      54
#define KEY_LEFTALT         56
#define KEY_SPACE           57
#define KEY_RIGHTALT        100
#define KEY_RIGHTCTRL       97
#define KEY_LEFTMETA        125
#define KEY_RIGHTMETA       126
#define KEY_DELETE          111
#define KEY_FORWARD_DEL     119
#define KEY_HOME            102
#define KEY_END             107
#define KEY_INSERT          110
#define KEY_PAGEUP          104
#define KEY_PAGEDOWN        109
#define KEY_UP              103
#define KEY_DOWN            108
#define KEY_LEFT            105
#define KEY_RIGHT           106

/* Android KeyEvent keycodes - same values as in android/view/KeyEvent.java */
#define AKEYCODE_SOFT_LEFT       1
#define AKEYCODE_SOFT_RIGHT     2
#define AKEYCODE_HOME           3
#define AKEYCODE_BACK           4
#define AKEYCODE_CALL           5
#define AKEYCODE_ENDCALL        6
#define AKEYCODE_0              7
#define AKEYCODE_1              8
#define AKEYCODE_2              9
#define AKEYCODE_3              10
#define AKEYCODE_4              11
#define AKEYCODE_5              12
#define AKEYCODE_6              13
#define AKEYCODE_7              14
#define AKEYCODE_8              15
#define AKEYCODE_9              16
#define AKEYCODE_STAR           17
#define AKEYCODE_POUND          18
#define AKEYCODE_DPAD_UP        19
#define AKEYCODE_DPAD_DOWN      20
#define AKEYCODE_DPAD_LEFT      21
#define AKEYCODE_DPAD_RIGHT     22
#define AKEYCODE_DPAD_CENTER    23
#define AKEYCODE_VOLUME_UP      24
#define AKEYCODE_VOLUME_DOWN    25
#define AKEYCODE_POWER          26
#define AKEYCODE_CAMERA         27
#define AKEYCODE_CLEAR          28
#define AKEYCODE_A              29
#define AKEYCODE_B              30
#define AKEYCODE_C              31
#define AKEYCODE_D              32
#define AKEYCODE_E              33
#define AKEYCODE_F              34
#define AKEYCODE_G              35
#define AKEYCODE_H              36
#define AKEYCODE_I              37
#define AKEYCODE_J              38
#define AKEYCODE_K              39
#define AKEYCODE_L              40
#define AKEYCODE_M              41
#define AKEYCODE_N              42
#define AKEYCODE_O              43
#define AKEYCODE_P              44
#define AKEYCODE_Q              45
#define AKEYCODE_R              46
#define AKEYCODE_S              47
#define AKEYCODE_T              48
#define AKEYCODE_U              49
#define AKEYCODE_V              50
#define AKEYCODE_W              51
#define AKEYCODE_X              52
#define AKEYCODE_Y              53
#define AKEYCODE_Z              54
#define AKEYCODE_COMMA          55
#define AKEYCODE_PERIOD         56
#define AKEYCODE_ALT_LEFT       57
#define AKEYCODE_ALT_RIGHT      58
#define AKEYCODE_SHIFT_LEFT     59
#define AKEYCODE_SHIFT_RIGHT    60
#define AKEYCODE_TAB            61
#define AKEYCODE_SPACE          62
#define AKEYCODE_SYMBOL         63
#define AKEYCODE_EXPLORER       64
#define AKEYCODE_ENVELOPE       65
#define AKEYCODE_ENTER          66
#define AKEYCODE_DEL            67
#define AKEYCODE_GRAVE          68
#define AKEYCODE_MINUS          69
#define AKEYCODE_EQUALS         70
#define AKEYCODE_LEFT_BRACKET   71
#define AKEYCODE_RIGHT_BRACKET  72
#define AKEYCODE_BACKSLASH      73
#define AKEYCODE_SEMICOLON      74
#define AKEYCODE_APOSTROPHE     75
#define AKEYCODE_SLASH          76
#define AKEYCODE_AT             77
#define AKEYCODE_NUM            78
#define AKEYCODE_HEADPHONEHOOK  79
#define AKEYCODE_FOCUS          80
#define AKEYCODE_PLUS           81
#define AKEYCODE_MENU           82
#define AKEYCODE_NOTIFICATION   83
#define AKEYCODE_SEARCH         84
#define AKEYCODE_DPAD_UP_2      85
#define AKEYCODE_DPAD_DOWN_2    86
#define AKEYCODE_DPAD_LEFT_2    87
#define AKEYCODE_DPAD_RIGHT_2   88
#define AKEYCODE_DPAD_CENTER_2  89
#define AKEYCODE_CTRL_LEFT      113
#define AKEYCODE_CTRL_RIGHT     114
#define AKEYCODE_ESCAPE         111
#define AKEYCODE_FORWARD_DEL    112
#define AKEYCODE_META_LEFT      117
#define AKEYCODE_META_RIGHT     118

uint32_t android_keycode_to_linux(uint32_t android_keycode) {
    switch (android_keycode) {
    case AKEYCODE_A: return KEY_A;
    case AKEYCODE_B: return KEY_B;
    case AKEYCODE_C: return KEY_C;
    case AKEYCODE_D: return KEY_D;
    case AKEYCODE_E: return KEY_E;
    case AKEYCODE_F: return KEY_F;
    case AKEYCODE_G: return KEY_G;
    case AKEYCODE_H: return KEY_H;
    case AKEYCODE_I: return KEY_I;
    case AKEYCODE_J: return KEY_J;
    case AKEYCODE_K: return KEY_K;
    case AKEYCODE_L: return KEY_L;
    case AKEYCODE_M: return KEY_M;
    case AKEYCODE_N: return KEY_N;
    case AKEYCODE_O: return KEY_O;
    case AKEYCODE_P: return KEY_P;
    case AKEYCODE_Q: return KEY_Q;
    case AKEYCODE_R: return KEY_R;
    case AKEYCODE_S: return KEY_S;
    case AKEYCODE_T: return KEY_T;
    case AKEYCODE_U: return KEY_U;
    case AKEYCODE_V: return KEY_V;
    case AKEYCODE_W: return KEY_W;
    case AKEYCODE_X: return KEY_X;
    case AKEYCODE_Y: return KEY_Y;
    case AKEYCODE_Z: return KEY_Z;
    case AKEYCODE_0: return KEY_0;
    case AKEYCODE_1: return KEY_1;
    case AKEYCODE_2: return KEY_2;
    case AKEYCODE_3: return KEY_3;
    case AKEYCODE_4: return KEY_4;
    case AKEYCODE_5: return KEY_5;
    case AKEYCODE_6: return KEY_6;
    case AKEYCODE_7: return KEY_7;
    case AKEYCODE_8: return KEY_8;
    case AKEYCODE_9: return KEY_9;
    case AKEYCODE_CTRL_LEFT:  return KEY_LEFTCTRL;
    case AKEYCODE_CTRL_RIGHT: return KEY_RIGHTCTRL;
    case AKEYCODE_SHIFT_LEFT: return KEY_LEFTSHIFT;
    case AKEYCODE_SHIFT_RIGHT: return KEY_RIGHTSHIFT;
    case AKEYCODE_ALT_LEFT:   return KEY_LEFTALT;
    case AKEYCODE_ALT_RIGHT:  return KEY_RIGHTALT;
    case AKEYCODE_META_LEFT:  return KEY_LEFTMETA;
    case AKEYCODE_META_RIGHT: return KEY_RIGHTMETA;
    case AKEYCODE_DPAD_UP:
    case AKEYCODE_DPAD_UP_2:  return KEY_UP;
    case AKEYCODE_DPAD_DOWN:
    case AKEYCODE_DPAD_DOWN_2: return KEY_DOWN;
    case AKEYCODE_DPAD_LEFT:
    case AKEYCODE_DPAD_LEFT_2: return KEY_LEFT;
    case AKEYCODE_DPAD_RIGHT:
    case AKEYCODE_DPAD_RIGHT_2: return KEY_RIGHT;
    case AKEYCODE_ENTER:
    case AKEYCODE_DPAD_CENTER:
    case AKEYCODE_DPAD_CENTER_2: return KEY_ENTER;
    case AKEYCODE_TAB:  return KEY_TAB;
    case AKEYCODE_SPACE: return KEY_SPACE;
    case AKEYCODE_ESCAPE: return KEY_ESC;
    case AKEYCODE_DEL: return KEY_BACKSPACE;
    case AKEYCODE_FORWARD_DEL: return KEY_DELETE;
    case AKEYCODE_HOME: return KEY_HOME;
    case AKEYCODE_ENDCALL: return KEY_END;
    case AKEYCODE_COMMA: return KEY_COMMA;
    case AKEYCODE_PERIOD: return KEY_DOT;
    case AKEYCODE_SLASH: return KEY_SLASH;
    case AKEYCODE_MINUS: return KEY_MINUS;
    case AKEYCODE_EQUALS: return KEY_EQUAL;
    case AKEYCODE_LEFT_BRACKET: return KEY_LEFTBRACE;
    case AKEYCODE_RIGHT_BRACKET: return KEY_RIGHTBRACE;
    case AKEYCODE_BACKSLASH: return KEY_BACKSLASH;
    case AKEYCODE_SEMICOLON: return KEY_SEMICOLON;
    case AKEYCODE_APOSTROPHE: return KEY_APOSTROPHE;
    case AKEYCODE_GRAVE: return KEY_GRAVE;
    default:
        return android_keycode;
    }
}
INPUT_C
      fi
      if [ ! -f src/rendering/shaders/android_quad.vert ]; then
        cat > src/rendering/shaders/android_quad.vert <<'SHADER_VERT'
#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inTexCoord;

layout(location = 0) out vec2 fragTexCoord;

layout(push_constant) uniform PushConstants {
    float pos_x;
    float pos_y;
    float size_x;
    float size_y;
    float extent_x;
    float extent_y;
    float opacity;
    float _pad;
} pc;

void main() {
    float ndc_x = (pc.pos_x + inPosition.x * pc.size_x) / pc.extent_x * 2.0 - 1.0;
    float ndc_y = 1.0 - (pc.pos_y + inPosition.y * pc.size_y) / pc.extent_y * 2.0;
    gl_Position = vec4(ndc_x, ndc_y, 0.0, 1.0);
    fragTexCoord = inTexCoord;
}
SHADER_VERT
      fi
      if [ ! -f src/rendering/shaders/android_quad.frag ]; then
        cat > src/rendering/shaders/android_quad.frag <<'SHADER_FRAG'
#version 450

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

layout(binding = 0) uniform sampler2D texSampler;

layout(push_constant) uniform PushConstants {
    float pos_x;
    float pos_y;
    float size_x;
    float size_y;
    float extent_x;
    float extent_y;
    float opacity;
    float _pad;
} pc;

void main() {
    outColor = texture(texSampler, fragTexCoord) * pc.opacity;
}
SHADER_FRAG
      fi
      # ScreencopyHelper.kt may be untracked
      if [ ! -f src/platform/android/java/com/aspauldingcode/wawona/ScreencopyHelper.kt ]; then
        mkdir -p src/platform/android/java/com/aspauldingcode/wawona
        cat > src/platform/android/java/com/aspauldingcode/wawona/ScreencopyHelper.kt <<'SCREENCOPY'
package com.aspauldingcode.wawona

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Window
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import java.nio.ByteBuffer

object ScreencopyHelper {
    suspend fun pollAndCapture(window: Window?) {
        if (window == null) return
        withContext(Dispatchers.Main) {
            pollOne(window, true)
            pollOne(window, false)
        }
    }
    private suspend fun pollOne(window: Window, screencopy: Boolean) {
        val whs = IntArray(3)
        val captureId = if (screencopy) {
            WawonaNative.nativeGetPendingScreencopy(whs)
        } else {
            WawonaNative.nativeGetPendingImageCopyCapture(whs)
        }
        if (captureId == 0L) return
        val width = whs[0]
        val height = whs[1]
        val dstStride = if (whs.size >= 3 && whs[2] > 0) whs[2] else width * 4
        if (width <= 0 || height <= 0) {
            if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
            else WawonaNative.nativeImageCopyCaptureFailed(captureId)
            return
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            val result = suspendCancellableCoroutine<Int> { cont ->
                @Suppress("DEPRECATION")
                PixelCopy.request(window, bitmap, { r -> cont.resume(r) }, Handler(Looper.getMainLooper()))
            }
            if (result == PixelCopy.SUCCESS) {
                val srcStride = bitmap.rowBytes
                val dstSize = dstStride * height
                val buf = ByteBuffer.allocate(bitmap.rowBytes * height)
                bitmap.copyPixelsToBuffer(buf)
                buf.rewind()
                val srcArr = ByteArray(buf.remaining())
                buf.get(srcArr)
                val dstArr = if (srcStride == dstStride) srcArr else {
                    val copyW = minOf(srcStride, dstStride)
                    ByteArray(dstSize).also { out ->
                        for (row in 0 until height) {
                            srcArr.copyInto(out, row * dstStride, row * srcStride, row * srcStride + copyW)
                        }
                    }
                }
                if (screencopy) WawonaNative.nativeScreencopyComplete(captureId, dstArr)
                else WawonaNative.nativeImageCopyCaptureComplete(captureId, dstArr)
            } else {
                if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
                else WawonaNative.nativeImageCopyCaptureFailed(captureId)
            }
        } catch (e: Exception) {
            WLog.e("SCREENCOPY", "PixelCopy failed: ''${e.message}")
            if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
            else WawonaNative.nativeImageCopyCaptureFailed(captureId)
        } finally {
            bitmap.recycle()
        }
    }
}
SCREENCOPY
      fi
      # ModifierAccessoryBar.kt may be untracked
      if [ ! -f src/platform/android/java/com/aspauldingcode/wawona/ModifierAccessoryBar.kt ]; then
        mkdir -p src/platform/android/java/com/aspauldingcode/wawona
        cat > src/platform/android/java/com/aspauldingcode/wawona/ModifierAccessoryBar.kt <<'MODBAR'
package com.aspauldingcode.wawona

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private object LinuxKey {
    const val ESC = 1
    const val GRAVE = 41
    const val TAB = 15
    const val SLASH = 53
    const val MINUS = 12
    const val HOME = 102
    const val UP = 103
    const val END = 107
    const val PAGEUP = 104
    const val LEFTSHIFT = 42
    const val LEFTCTRL = 29
    const val LEFTALT = 56
    const val LEFTMETA = 125
    const val LEFT = 105
    const val DOWN = 108
    const val RIGHT = 106
    const val PAGEDOWN = 109
}

private object XkbMod {
    const val SHIFT = 1 shl 0
    const val CTRL = 1 shl 2
    const val ALT = 1 shl 3
    const val LOGO = 1 shl 6
}

private const val DOUBLE_TAP_THRESHOLD_MS = 400L

@Composable
fun ModifierAccessoryBar(
    modifier: Modifier = Modifier,
    onDismissKeyboard: () -> Unit
) {
    val ts = System.currentTimeMillis().toInt() and 0x7FFF_FFFF

    var modShiftActive by remember { mutableStateOf(false) }
    var modShiftLocked by remember { mutableStateOf(false) }
    var modCtrlActive by remember { mutableStateOf(false) }
    var modCtrlLocked by remember { mutableStateOf(false) }
    var modAltActive by remember { mutableStateOf(false) }
    var modAltLocked by remember { mutableStateOf(false) }
    var modSuperActive by remember { mutableStateOf(false) }
    var modSuperLocked by remember { mutableStateOf(false) }

    var lastModShiftTap by remember { mutableLongStateOf(0L) }
    var lastModCtrlTap by remember { mutableLongStateOf(0L) }
    var lastModAltTap by remember { mutableLongStateOf(0L) }
    var lastModSuperTap by remember { mutableLongStateOf(0L) }

    fun clearStickyModifiers() {
        if (modShiftActive && !modShiftLocked) modShiftActive = false
        if (modCtrlActive && !modCtrlLocked) modCtrlActive = false
        if (modAltActive && !modAltLocked) modAltActive = false
        if (modSuperActive && !modSuperLocked) modSuperActive = false
    }

    fun handleModifierTap(
        active: Boolean,
        locked: Boolean,
        lastTap: Long,
        onActive: (Boolean) -> Unit,
        onLocked: (Boolean) -> Unit,
        onLastTap: (Long) -> Unit
    ) {
        val now = System.currentTimeMillis()
        val elapsed = now - lastTap
        onLastTap(now)

        when {
            locked -> {
                onActive(false)
                onLocked(false)
            }
            active && elapsed < DOUBLE_TAP_THRESHOLD_MS -> {
                onLocked(true)
            }
            active -> {
                onActive(false)
                onLocked(false)
            }
            else -> {
                onActive(true)
                onLocked(false)
            }
        }
    }

    fun sendAccessoryKey(keycode: Int) {
        var mods = 0
        if (modShiftActive) {
            mods = mods or XkbMod.SHIFT
            WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, true, ts)
        }
        if (modCtrlActive) {
            mods = mods or XkbMod.CTRL
            WawonaNative.nativeInjectKey(LinuxKey.LEFTCTRL, true, ts)
        }
        if (modAltActive) {
            mods = mods or XkbMod.ALT
            WawonaNative.nativeInjectKey(LinuxKey.LEFTALT, true, ts)
        }
        if (modSuperActive) {
            mods = mods or XkbMod.LOGO
            WawonaNative.nativeInjectKey(LinuxKey.LEFTMETA, true, ts)
        }
        if (mods != 0) {
            WawonaNative.nativeInjectModifiers(mods, 0, 0, 0)
        }
        WawonaNative.nativeInjectKey(keycode, true, ts)
        WawonaNative.nativeInjectKey(keycode, false, ts)
        if (modShiftActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, false, ts)
        if (modCtrlActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTCTRL, false, ts)
        if (modAltActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTALT, false, ts)
        if (modSuperActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTMETA, false, ts)
        if (mods != 0) WawonaNative.nativeInjectModifiers(0, 0, 0, 0)
        clearStickyModifiers()
    }

    val barBg = Color(0xFF1C1C1E)
    val keyInactive = Color(0xFF3A3A3C)
    val keySticky = Color(0xFF0A84FF).copy(alpha = 0.6f)
    val keyLocked = Color(0xFF0A84FF).copy(alpha = 0.85f)
    val keyText = Color.White

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = barBg,
        contentColor = keyText
    ) {
        val rowMod = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 2.dp)
            .height(36.dp)

        Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = rowMod,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            listOf(
                "ESC" to { sendAccessoryKey(LinuxKey.ESC) },
                "`" to { sendAccessoryKey(LinuxKey.GRAVE) },
                "TAB" to { sendAccessoryKey(LinuxKey.TAB) },
                "/" to { sendAccessoryKey(LinuxKey.SLASH) },
                "—" to { sendAccessoryKey(LinuxKey.MINUS) },
                "HOME" to { sendAccessoryKey(LinuxKey.HOME) },
                "↑" to { sendAccessoryKey(LinuxKey.UP) },
                "END" to { sendAccessoryKey(LinuxKey.END) },
                "PGUP" to { sendAccessoryKey(LinuxKey.PAGEUP) }
            ).forEach { (label, action) ->
                AccessoryKey(
                    label, keyInactive, keyText,
                    onClick = { action() },
                    modifier = Modifier.weight(1f)
                )
            }
        }

        Row(
            modifier = rowMod,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AccessoryModKey(
                label = "⇧",
                active = modShiftActive,
                locked = modShiftLocked,
                inactiveColor = keyInactive,
                stickyColor = keySticky,
                lockedColor = keyLocked
            ) {
                handleModifierTap(
                    modShiftActive, modShiftLocked, lastModShiftTap,
                    { modShiftActive = it },
                    { modShiftLocked = it },
                    { lastModShiftTap = it }
                )
            }
            AccessoryModKey(
                label = "CTRL",
                active = modCtrlActive,
                locked = modCtrlLocked,
                inactiveColor = keyInactive,
                stickyColor = keySticky,
                lockedColor = keyLocked
            ) {
                handleModifierTap(
                    modCtrlActive, modCtrlLocked, lastModCtrlTap,
                    { modCtrlActive = it },
                    { modCtrlLocked = it },
                    { lastModCtrlTap = it }
                )
            }
            AccessoryModKey(
                label = "ALT",
                active = modAltActive,
                locked = modAltLocked,
                inactiveColor = keyInactive,
                stickyColor = keySticky,
                lockedColor = keyLocked
            ) {
                handleModifierTap(
                    modAltActive, modAltLocked, lastModAltTap,
                    { modAltActive = it },
                    { modAltLocked = it },
                    { lastModAltTap = it }
                )
            }
            AccessoryModKey(
                label = "⌘",
                active = modSuperActive,
                locked = modSuperLocked,
                inactiveColor = keyInactive,
                stickyColor = keySticky,
                lockedColor = keyLocked
            ) {
                handleModifierTap(
                    modSuperActive, modSuperLocked, lastModSuperTap,
                    { modSuperActive = it },
                    { modSuperLocked = it },
                    { lastModSuperTap = it }
                )
            }
            listOf(
                "←" to LinuxKey.LEFT,
                "↓" to LinuxKey.DOWN,
                "→" to LinuxKey.RIGHT,
                "PGDN" to LinuxKey.PAGEDOWN
            ).forEach { (label, keycode) ->
                AccessoryKey(
                    label, keyInactive, keyText,
                    onClick = { sendAccessoryKey(keycode) },
                    modifier = Modifier.weight(1f)
                )
            }
            AccessoryKey(
                "⌨↓", keyInactive, keyText,
                onClick = onDismissKeyboard,
                modifier = Modifier.weight(1f)
            )
        }
        }
    }
}

@Composable
private fun AccessoryKey(
    label: String,
    bgColor: Color,
    textColor: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    TextButton(
        onClick = onClick,
        modifier = modifier.height(32.dp).padding(0.dp),
        colors = ButtonDefaults.textButtonColors(
            containerColor = bgColor,
            contentColor = textColor
        ),
        contentPadding = PaddingValues(0.dp),
        shape = RoundedCornerShape(6.dp)
    ) {
        Text(
            text = label,
            fontSize = 12.sp,
            maxLines = 1
        )
    }
}

@Composable
private fun RowScope.AccessoryModKey(
    label: String,
    active: Boolean,
    locked: Boolean,
    inactiveColor: Color,
    stickyColor: Color,
    lockedColor: Color,
    onClick: () -> Unit
) {
    val bg = when {
        locked -> lockedColor
        active -> stickyColor
        else -> inactiveColor
    }
    val borderMod = if (locked) {
        Modifier.border(2.dp, Color(0xFF0A84FF), RoundedCornerShape(6.dp))
    } else {
        Modifier
    }
    Box(modifier = Modifier.weight(1f).then(borderMod)) {
        AccessoryKey(
            label, bg, Color.White,
            onClick = onClick,
            modifier = Modifier.fillMaxWidth()
        )
    }
}
MODBAR
      fi
    '';

    # Fix egl_buffer_handler for Android (create Android-compatible stubs)
    postPatch = ''
            mkdir -p src/stubs

            # Create header
            cat > src/stubs/egl_buffer_handler.h <<'EOF'
      #pragma once
      #include <stdbool.h>
      #include <stdint.h>
      struct egl_buffer_handler;
      struct wl_display;
      struct wl_resource;
      int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display);
      void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler);
      int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                           struct wl_resource *buffer_resource,
                                           int32_t *width, int32_t *height,
                                           int *texture_format);
      void* egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                            struct wl_resource *buffer_resource);
      bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                             struct wl_resource *buffer_resource);
      EOF

            # Create stub implementation
            cat > src/stubs/egl_buffer_handler.c <<'EOF'
      #include "egl_buffer_handler.h"
      #include <stdbool.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

      // Android stub: EGL Wayland extensions are not available on Android
      // This provides stub implementations to avoid compilation errors

      static void egl_buffer_handler_translation_unit_silence(void) {}

      int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
          (void)handler; (void)display;
          // EGL Wayland extensions not available on Android
          return -1;
      }

      void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
          (void)handler;
      }

      int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                           struct wl_resource *buffer_resource,
                                           int32_t *width, int32_t *height,
                                           int *texture_format) {
          (void)handler; (void)buffer_resource; (void)width; (void)height; (void)texture_format;
          return -1;
      }

      void* egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                            struct wl_resource *buffer_resource) {
          (void)handler; (void)buffer_resource;
          return NULL;
      }

      bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                             struct wl_resource *buffer_resource) {
          (void)handler; (void)buffer_resource;
          return false;
      }
      EOF
    '';

    buildPhase = ''
      runHook preBuild

      # Embed Vulkan shaders as C byte arrays for textured quad pipeline
      # (inlined - scripts/embed-android-shaders.sh may be untracked in flake)
      mkdir -p build/shaders
      if [ -f src/rendering/shaders/android_quad.vert ] && [ -f src/rendering/shaders/android_quad.frag ]; then
        ${glslang}/bin/glslangValidator -V src/rendering/shaders/android_quad.vert -o build/shaders/quad.vert.spv
        ${glslang}/bin/glslangValidator -V src/rendering/shaders/android_quad.frag -o build/shaders/quad.frag.spv
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
        cp build/shaders/shader_spv.h src/rendering/
      else
        echo "ERROR: Shader sources not found. Need src/rendering/shaders/android_quad.vert and .frag"
        exit 1
      fi

      # Setup Weston Simple SHM
      mkdir -p deps/weston-simple-shm
      cp -r ${westonSimpleShmSrc}/* deps/weston-simple-shm/
      chmod -R u+w deps/weston-simple-shm

      # Setup Android toolchain
      export CC="${androidToolchain.androidCC}"
      export CXX="${androidToolchain.androidCXX}"
      export AR="${androidToolchain.androidAR}"
      export STRIP="${androidToolchain.androidSTRIP}"
      export RANLIB="${androidToolchain.androidRANLIB}"
      export CFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
      export CXXFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
      export LDFLAGS="--target=${androidToolchain.androidTarget}"

      # Android dependencies setup
      mkdir -p android-dependencies/include
      mkdir -p android-dependencies/lib
      mkdir -p android-dependencies/lib/pkgconfig

      for dep in $buildInputs; do
         if [ -d "$dep/include" ]; then
           cp -rn "$dep/include/"* android-dependencies/include/ 2>/dev/null || true
         fi
         if [ -d "$dep/lib" ]; then
           cp -rn "$dep/lib/"* android-dependencies/lib/ 2>/dev/null || true
         fi
         if [ -d "$dep/lib/pkgconfig" ]; then
            cp -rn "$dep/lib/pkgconfig/"* android-dependencies/lib/pkgconfig/ 2>/dev/null || true
         fi
      done

      export PKG_CONFIG_PATH="$PWD/android-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"

      # Compile C/C++ code for Android (native library)
      OBJ_FILES=""
      for src_file in ${lib.concatStringsSep " " androidSourcesFiltered}; do
        if [[ "$src_file" == *.c ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if $CC -c "$src_file" \
             -Isrc -Isrc/core -Isrc/compositor_implementations \
             -Isrc/rendering -Isrc/input -Isrc/ui \
             -Isrc/logging -Isrc/stubs -Isrc/protocols \
             -Isrc/platform/macos -Isrc/platform/android \
             -Iandroid-dependencies/include \
             -fPIC \
             ${lib.concatStringsSep " " common.commonCFlags} \
             ${lib.concatStringsSep " " common.debugCFlags} \
             --target=${androidToolchain.androidTarget} \
             -o "$obj_file"; then
            OBJ_FILES="$OBJ_FILES $obj_file"
          else
            exit 1
          fi
        fi
      done

      # Compile weston-simple-shm
      for src_file in deps/weston-simple-shm/clients/simple-shm.c deps/weston-simple-shm/shared/os-compatibility.c deps/weston-simple-shm/xdg-shell-protocol.c deps/weston-simple-shm/fullscreen-shell-unstable-v1-protocol.c; do
        obj_file="''${src_file//\//_}.o"
        if $CC -c "$src_file" \
           -D_GNU_SOURCE \
           -Ideps/weston-simple-shm \
           -Ideps/weston-simple-shm/shared \
           -Ideps/weston-simple-shm/include \
           -Iandroid-dependencies/include \
           -fPIC \
           --target=${androidToolchain.androidTarget} \
           -o "$obj_file"; then
          OBJ_FILES="$OBJ_FILES $obj_file"
        else
          exit 1
        fi
      done

      # Link shared library with Rust backend
      RUST_LIB_FLAGS=""
      if [ -n "${rustBackendPath}" ] && [ -f "${rustBackendPath}/lib/libwawona_core.so" ]; then
        echo "Linking against Rust backend shared library: libwawona_core.so"
        cp "${rustBackendPath}/lib/libwawona_core.so" .
        RUST_LIB_FLAGS="-L. -lwawona_core"
      elif [ -n "${rustBackendPath}" ] && [ -f "${rustBackendPath}/lib/libwawona.a" ]; then
        echo "Linking against Rust static backend: libwawona.a"
        cp "${rustBackendPath}/lib/libwawona.a" .
        RUST_LIB_FLAGS="-L. -lwawona"
      else
        echo "WARNING: Rust backend not available, building without it"
      fi

      echo "=== Checking android-dependencies/lib contents ==="
      ls android-dependencies/lib/*.a 2>/dev/null || echo "No .a files found"
      echo "=== Checking for missing libs ==="
      for lib in xkbcommon ffi expat xml2 ssl crypto zstd lz4 wayland-server wayland-client pixman-1; do
        if [ -f "android-dependencies/lib/lib''${lib}.a" ]; then
          echo "  Found: lib''${lib}.a"
        else
          echo "  MISSING: lib''${lib}.a"
        fi
      done

      $CC -shared $OBJ_FILES \
         $RUST_LIB_FLAGS \
         -Landroid-dependencies/lib \
         $(pkg-config --libs wayland-server wayland-client pixman-1 2>/dev/null || echo "-lwayland-server -lwayland-client -lpixman-1") \
         -lxkbcommon -lffi -lexpat \
         -lssl -lcrypto \
         -lzstd -llz4 \
         -llog -landroid -lvulkan -lm -ldl -lz \
         -g --target=${androidToolchain.androidTarget} \
         -o libwawona.so
         
      # Setup Gradle and dependencies
      export GRADLE_USER_HOME=$(pwd)/.gradle_home
      export ANDROID_USER_HOME=$(pwd)/.android_home
      mkdir -p $ANDROID_USER_HOME

      # Copy gradleDeps to writable location
      cp -r ${gradleDeps} $GRADLE_USER_HOME
      chmod -R u+w $GRADLE_USER_HOME

      export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
      export ANDROID_HOME="$ANDROID_SDK_ROOT"
      
      # Prepare source directory for Gradle build (emulating project root)
      mkdir -p project-root
      cd project-root
      
      # Copy Android sources from patched build dir (includes prePatch additions)
      cp -r ../src/platform/android/java .
      cp -r ../src/platform/android/res .
      cp ../src/platform/android/AndroidManifest.xml .

      # Merge Wawona launcher icon assets (adaptive + monochrome for Android 16+)
      if [ -n "${toString androidIconAssets}" ] && [ -d "${androidIconAssets}/res" ]; then
        cp -r ${androidIconAssets}/res/* res/
      fi
      
      # Place native libs where Gradle expects them (jniLibs)
      mkdir -p jniLibs/arm64-v8a
      cp ../libwawona.so jniLibs/arm64-v8a/
      # Copy Rust core shared library if it exists
      if [ -f ../libwawona_core.so ]; then
        cp ../libwawona_core.so jniLibs/arm64-v8a/
      fi

      # Copy other shared libs (dependencies)
      if [ -d ../android-dependencies/lib ]; then
        find ../android-dependencies/lib -name "*.so*" -exec cp -L {} jniLibs/arm64-v8a/ \;
      fi

      # Also copy libc++_shared.so
      NDK_ROOT="${androidToolchain.androidndkRoot}"
      LIBCPP_SHARED=$(find "$NDK_ROOT" -name "libc++_shared.so" | grep "aarch64" | head -n 1)
      if [ -f "$LIBCPP_SHARED" ]; then
        cp "$LIBCPP_SHARED" jniLibs/arm64-v8a/
      fi

      # Bundle OpenSSH and sshpass executables (named as .so for Android extraction)
      if [ -f "${opensshBin}/bin/ssh" ]; then
        cp "${opensshBin}/bin/ssh" jniLibs/arm64-v8a/libssh_bin.so
        chmod +x jniLibs/arm64-v8a/libssh_bin.so
        echo "Bundled ssh executable as libssh_bin.so"
      else
        echo "WARNING: openssh binary not found at ${opensshBin}/bin/ssh"
      fi
      if [ -f "${sshpassBin}/bin/sshpass" ]; then
        cp "${sshpassBin}/bin/sshpass" jniLibs/arm64-v8a/libsshpass_bin.so
        chmod +x jniLibs/arm64-v8a/libsshpass_bin.so
        echo "Bundled sshpass executable as libsshpass_bin.so"
      else
        echo "WARNING: sshpass binary not found at ${sshpassBin}/bin/sshpass"
      fi

      # Bundle weston executables
      if [ -d "${westonBin}/lib/arm64-v8a" ]; then
        for lib in ${westonBin}/lib/arm64-v8a/*.so; do
           if [ -f "$lib" ]; then
              base=$(basename "$lib" .so)
              # Normalize libweston*.so -> weston* so runtime lookups match
              # MainActivity ProcessBuilder("$libDir/libweston*_bin.so")
              norm_base="''${base#lib}"
              out_name="lib''${norm_base}_bin.so"
              cp "$lib" "jniLibs/arm64-v8a/''${out_name}"
              chmod +x "jniLibs/arm64-v8a/''${out_name}"
              echo "Bundled weston executable as ''${out_name}"
           fi
        done
      else
        echo "WARNING: weston lib directory not found"
      fi

      # Fix SONAMEs in copied libs
      chmod +w -R jniLibs
      cd jniLibs/arm64-v8a

      # Remove non-ELF files (linker scripts, .a files, etc.) that may have been copied
      for f in *.so*; do
        [ -f "$f" ] || continue
        if ! file "$f" | grep -q "ELF"; then
          echo "Removing non-ELF file from jniLibs: $f"
          rm -f "$f"
        fi
      done

      for lib in *.so*; do
          [ -f "$lib" ] || continue
          if [[ "$lib" =~ \.so\.[0-9]+ ]]; then
             newname=$(echo "$lib" | sed -E 's/\.so\.[0-9.]*$/.so/')
             if [ "$lib" != "$newname" ]; then
               mv "$lib" "$newname"
               patchelf --set-soname "$newname" "$newname" || true
             fi
          fi
      done

      # Fix dependencies
      for lib in *.so; do
         [ -f "$lib" ] || continue
         needed=$(patchelf --print-needed "$lib" 2>/dev/null) || continue
         for n in $needed; do
           if [[ "$n" =~ \.so\.[0-9]+ ]]; then
             newn=$(echo "$n" | sed -E 's/\.so\.[0-9.]*$/.so/')
             if [ -f "$newn" ]; then
                patchelf --replace-needed "$n" "$newn" "$lib" || true
             fi
           fi
         done
      done
      
      # Return to project-root (from jniLibs/arm64-v8a)
      cd ../..

      # Create Gradle build files (using gradlegen)
      cp ${android_gradlegen_internal.buildGradle} build.gradle.kts
      cp ${android_gradlegen_internal.settingsGradle} settings.gradle.kts
      chmod u+w build.gradle.kts settings.gradle.kts

      # Create gradle.properties with AndroidX support
      cat > gradle.properties <<'EOF'
      android.useAndroidX=true
      android.enableJetifier=true
      org.gradle.jvmargs=-Xmx2048m
      kotlin.code.style=official
      EOF

      # Build APK
      gradle assembleDebug --offline --no-daemon --no-build-cache --no-watch-fs || {
        echo "Gradle build reported failure. Checking if APK was generated..."
      }
      
      # Use find to locate the generated APK anywhere in the project root
      FOUND_APK=$(find . -name "*.apk" | head -n 1)
      if [ -z "$FOUND_APK" ]; then
         echo "Error: APK was not generated."
         exit 1
      else
         echo "APK generated successfully at $FOUND_APK, ignoring Gradle shutdown error."
         mkdir -p app/build/outputs/apk/debug/
         cp "$FOUND_APK" app/build/outputs/apk/debug/app-debug.apk
      fi

      runHook postBuild
    '';

    installPhase = ''
            runHook preInstall

            # installPhase cwd = project-root (where buildPhase ended)
            mkdir -p $out/bin
            mkdir -p $out/lib
            
            # Copy APK
            APK_PATH=""
            if [ -f "project-root/build/outputs/apk/debug/Wawona-debug.apk" ]; then
              APK_PATH="project-root/build/outputs/apk/debug/Wawona-debug.apk"
            else
              echo "APK not found in expected locations, searching..."
              APK_PATH=$(find . -name "*.apk" -type f | head -1)
              if [ -z "$APK_PATH" ]; then
                echo "Error: No APK found!"
                exit 1
              fi
              echo "Found APK at: $APK_PATH"
            fi
            
            cp "$APK_PATH" $out/bin/Wawona.apk
            echo "Copied APK to $out/bin/Wawona.apk"
            
            # Copy runtime shared libraries
            if [ -d android-dependencies/lib ]; then
              find android-dependencies/lib -name "*.so*" -exec cp -L {} $out/lib/ \;
            fi
            
            # Copy the runner script (created by writeShellScript, already executable)
            cp ${runnerScript} $out/bin/wawona-android-run
            chmod +x $out/bin/wawona-android-run

            # Output project dir for gradlegen (Android Studio openable)
            # cwd is project-root, so copy current dir contents into $project
            mkdir -p $project
            cp -r . "$project/"
            
            runHook postInstall
    '';
  }
