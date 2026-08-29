{ pkgs
, nixSdkPath
, nixSdkRoot
, androidndkRoot
, systemImageId
, provisionScript ? ""
}:

# Detached Android APK runner / emulator launcher used by wawona-android.
# Extracted from android.nix to keep that file under the maintainability line budget.
pkgs.writeShellScript "wawona-android-run" ''
    set +e

    NIX_SDK_PATH="${nixSdkPath}"
    NDK_ROOT="${androidndkRoot}"
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
      SYSTEM_IMAGE="${systemImageId}"
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
    #   render at the wrong geometry. Use a Pixel-like panel instead.
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

      echo "[Wawona] App PID: $PID (paused. No code has run yet)"

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
''
