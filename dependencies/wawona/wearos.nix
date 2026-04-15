{
  pkgs,
  wawonaVersion,
  wawonaSrc ? ../..,
  androidSDK ? null,
  wearAndroidPackage ? "wawona-wearos-android",
  ...
}:

pkgs.writeShellApplication {
  name = "wawona-wearos-run";
  runtimeInputs = [
    pkgs.git
    pkgs.gnugrep
    pkgs.ripgrep
    pkgs.coreutils
    pkgs.android-tools
    pkgs.jdk17
    pkgs.util-linux
    pkgs.nix
  ];
  text = ''
    set -euo pipefail

    NIX_SDK_ROOT="${if androidSDK != null && androidSDK ? sdkRoot then androidSDK.sdkRoot else ""}"
    WEAR_AVD_NAME="WawonaWearEmulator"
    WEAR_SYSTEM_IMAGE=""
    WEAR_EMULATOR_SERIAL=""

    usage() {
      cat <<'EOF'
Usage: wawona-wearos-run [--no-device-smoke]

Builds Wawona WearOS APK via Nix and validates native WearOS wiring.
If a connected WearOS device/emulator is detected through adb, performs install/launch smoke test.
EOF
    }

    prepend_sdk_tools() {
      local sdk_root="$1"
      if [ ! -d "$sdk_root" ]; then
        return 0
      fi

      for bin_dir in \
        "$sdk_root/platform-tools" \
        "$sdk_root/emulator" \
        "$sdk_root/tools/bin" \
        "$sdk_root/cmdline-tools/latest/bin" \
        "$sdk_root"/cmdline-tools/*/bin
      do
        if [ -d "$bin_dir" ]; then
          export PATH="$bin_dir:$PATH"
        fi
      done
    }

    run_sdkmanager() {
      # With pipefail enabled, `yes | sdkmanager ...` can surface SIGPIPE from `yes`
      # as exit 141 even when sdkmanager succeeds. Run this pipeline with pipefail off.
      (
        set +o pipefail
        yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "$@"
      )
    }

    set_android_paths() {
      # Prefer a writable user SDK root for sdkmanager installs and licenses.
      local desired_sdk_root
      desired_sdk_root="''${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
      mkdir -p "$desired_sdk_root"

      if [ ! -w "$desired_sdk_root" ]; then
        if [ -n "$NIX_SDK_ROOT" ]; then
          echo "[wearos] WARNING: '$desired_sdk_root' is not writable, falling back to Nix SDK root."
          desired_sdk_root="$NIX_SDK_ROOT"
        else
          echo "[wearos] ERROR: Android SDK root '$desired_sdk_root' is not writable and no Nix SDK root is available." >&2
          exit 1
        fi
      fi

      export ANDROID_SDK_ROOT="$desired_sdk_root"
      export ANDROID_HOME="$desired_sdk_root"
      export JAVA_HOME="${pkgs.jdk17.home}"
      if [ -n "$NIX_SDK_ROOT" ]; then
        prepend_sdk_tools "$NIX_SDK_ROOT"
      fi
      prepend_sdk_tools "$ANDROID_SDK_ROOT"
    }

    ensure_wear_sdk() {
      echo "[wearos] Ensuring Android SDK licenses and Wear packages..." >&2
      set_android_paths

      if ! command -v sdkmanager >/dev/null 2>&1; then
        echo "[wearos] ERROR: sdkmanager not found. Install Android cmdline-tools or provide androidSDK in flake wiring." >&2
        exit 1
      fi
      if ! command -v avdmanager >/dev/null 2>&1; then
        echo "[wearos] ERROR: avdmanager not found. Install Android cmdline-tools." >&2
        exit 1
      fi
      if ! command -v emulator >/dev/null 2>&1; then
        echo "[wearos] ERROR: emulator not found. Install Android emulator package." >&2
        exit 1
      fi

      echo "[wearos] Accepting Android SDK licenses..." >&2
      # sdkmanager sometimes exits non-zero in non-interactive contexts even after writing accepted licenses.
      run_sdkmanager --licenses >/dev/null || true

      echo "[wearos] Installing Android SDK + Wear emulator packages..." >&2
      if ! run_sdkmanager \
        "platform-tools" \
        "emulator" \
        "platforms;android-35" \
        "cmdline-tools;latest" >/dev/null; then
        echo "[wearos] ERROR: Failed installing base Android SDK packages via sdkmanager." >&2
        return 1
      fi

      local candidate_images
      candidate_images=(
        "system-images;android-35;android-wear;arm64-v8a"
        "system-images;android-34;android-wear;arm64-v8a"
        "system-images;android-33;android-wear;arm64-v8a"
        "system-images;android-30;android-wear;arm64-v8a"
      )

      for candidate in "''${candidate_images[@]}"; do
        local api
        api="$(echo "$candidate" | cut -d';' -f2)"
        local sysdir="$ANDROID_SDK_ROOT/system-images/$api/android-wear/arm64-v8a"
        if [ -d "$sysdir" ]; then
          WEAR_SYSTEM_IMAGE="$candidate"
          break
        fi
        if run_sdkmanager "$candidate" >/dev/null 2>&1; then
          WEAR_SYSTEM_IMAGE="$candidate"
          break
        fi
      done

      if [ -z "$WEAR_SYSTEM_IMAGE" ]; then
        echo "[wearos] ERROR: Could not install any WearOS system image." >&2
        return 1
      fi
      echo "[wearos] Using Wear system image: $WEAR_SYSTEM_IMAGE" >&2
    }

    ensure_wear_avd() {
      echo "[wearos] Ensuring WearOS AVD exists..." >&2
      export ANDROID_USER_HOME="$HOME/.android"
      export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
      mkdir -p "$ANDROID_AVD_HOME"

      if ! emulator -list-avds 2>/dev/null | rg -q "^$WEAR_AVD_NAME$"; then
        echo "[wearos] Creating WearOS AVD '$WEAR_AVD_NAME'..." >&2
        if printf 'no\n' | avdmanager create avd -n "$WEAR_AVD_NAME" -k "$WEAR_SYSTEM_IMAGE" --device "wearos_square" --force >/dev/null 2>&1; then
          :
        elif printf 'no\n' | avdmanager create avd -n "$WEAR_AVD_NAME" -k "$WEAR_SYSTEM_IMAGE" --force >/dev/null 2>&1; then
          :
        else
          echo "[wearos] ERROR: Failed to create WearOS AVD '$WEAR_AVD_NAME'." >&2
          return 1
        fi
      fi
    }

    # Return first emulator serial that is fully booted *and* reports Wear/watch traits.
    # Reusing "any emulator" breaks smoke tests when a phone/tablet AVD is already running.
    wait_for_wear_emulator_boot() {
      local timeout=420
      local elapsed=0
           while [ "$elapsed" -lt "$timeout" ]; do
        local line serial state boot
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          serial="$(printf '%s' "$line" | awk '{ print $1 }')"
          state="$(printf '%s' "$line" | awk '{ print $2 }')"
          case "$serial" in
 emulator-*) ;;
            *) continue ;;
          esac
          [ "$state" = "device" ] || continue
          boot="$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
          [ "$boot" = "1" ] || continue
          if is_wear_target "$serial"; then
            echo "$serial"
            return 0
          fi
        done < <(adb devices 2>/dev/null | tail -n +2)
        sleep 3
        elapsed=$((elapsed + 3))
      done
      return 1
    }

    is_wear_target() {
      local serial="$1"
      local characteristics
      local features
      local model
      local product

      characteristics="$(adb -s "$serial" shell getprop ro.build.characteristics 2>/dev/null | tr -d '\r' || true)"
      if echo "$characteristics" | rg -qi "(watch|wear)"; then
        return 0
      fi

      features="$(adb -s "$serial" shell pm list features 2>/dev/null | tr -d '\r' || true)"
      if echo "$features" | rg -qi "android\\.hardware\\.type\\.watch"; then
        return 0
      fi

      model="$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
      product="$(adb -s "$serial" shell getprop ro.product.name 2>/dev/null | tr -d '\r' || true)"
      if echo "$model $product" | rg -qi "(wear|watch)"; then
        return 0
      fi

      return 1
    }

    find_booted_wear_serial() {
      local line serial state boot
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        serial="$(printf '%s' "$line" | awk '{ print $1 }')"
        state="$(printf '%s' "$line" | awk '{ print $2 }')"
        case "$serial" in
          emulator-*) ;;
          *) continue ;;
        esac
        [ "$state" = "device" ] || continue
        boot="$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
        [ "$boot" = "1" ] || continue
        if is_wear_target "$serial"; then
          echo "$serial"
          return 0
        fi
      done < <(adb devices 2>/dev/null | tail -n +2)
      return 1
    }

    ensure_wear_emulator_running() {
      echo "[wearos] Provisioning emulator runtime..." >&2
      ensure_wear_sdk || return 1
      ensure_wear_avd || return 1

      adb start-server >/dev/null 2>&1 || true
      local existing
      existing="$(find_booted_wear_serial || true)"
      if [ -n "$existing" ]; then
        WEAR_EMULATOR_SERIAL="$existing"
        echo "[wearos] Reusing booted Wear emulator: $existing" >&2
        return 0
      fi

      echo "[wearos] Starting WearOS emulator '$WEAR_AVD_NAME' (logs: /tmp/wawona-wearos-emulator.log)..." >&2
      echo "[wearos] If another non-Wear emulator is running, close it or wait — this script only attaches to Wear/watch targets." >&2
      (setsid nohup emulator -avd "$WEAR_AVD_NAME" -no-snapshot -no-boot-anim -gpu auto < /dev/null > /tmp/wawona-wearos-emulator.log 2>&1 &)

      local serial
      serial="$(wait_for_wear_emulator_boot || true)"
      if [ -z "$serial" ]; then
        echo "[wearos] ERROR: No WearOS emulator finished booting in time (7 min timeout)." >&2
        echo "[wearos] Check /tmp/wawona-wearos-emulator.log for details." >&2
        echo "[wearos] Tip: adb devices — expect emulator-* with Wear system image; phone AVDs are ignored." >&2
        return 1
      fi
      WEAR_EMULATOR_SERIAL="$serial"
    }

    do_device_smoke=1
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --no-device-smoke) do_device_smoke=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
      esac
    done

    if git rev-parse --show-toplevel >/dev/null 2>&1; then
      repo_root="$(git rev-parse --show-toplevel)"
    else
      repo_root="${wawonaSrc}"
    fi
    cd "$repo_root"

    echo "[wearos] Building Wawona WearOS package via Nix (.#${wearAndroidPackage})..." >&2
    nix build ".#${wearAndroidPackage}" --print-build-logs
    apk_path="$repo_root/result/bin/Wawona.apk"
    if [ ! -f "$apk_path" ]; then
      echo "[wearos] ERROR: APK not found at $apk_path" >&2
      exit 1
    fi

    main_entry_file="$repo_root/android/app/src/main/java/com/aspauldingcode/wawona/MainActivity.kt"
    if [ ! -f "$main_entry_file" ]; then
      echo "[wearos] ERROR: Missing Android entrypoint source: $main_entry_file" >&2
      exit 1
    fi
    if ! rg -q "class MainActivity" "$main_entry_file"; then
      echo "[wearos] ERROR: MainActivity entrypoint wiring is missing." >&2
      exit 1
    fi

    echo "[wearos] Wear source + APK build checks passed."

    if [ "$do_device_smoke" -eq 0 ]; then
      echo "[wearos] Device smoke test skipped (--no-device-smoke)."
      exit 0
    fi

    adb start-server >/dev/null 2>&1 || true
    serial="$(adb devices | awk '/\tdevice$/ { print $1; exit }')"
    if [ -z "$serial" ]; then
      echo "[wearos] No connected device/emulator found. Provisioning WearOS SDK/emulator..."
      if ! ensure_wear_emulator_running; then
        echo "[wearos] ERROR: WearOS emulator provisioning failed." >&2
        exit 1
      fi
      serial="$WEAR_EMULATOR_SERIAL"
    fi

    if ! is_wear_target "$serial"; then
      characteristics="$(adb -s "$serial" shell getprop ro.build.characteristics 2>/dev/null | tr -d '\r' || true)"
      echo "[wearos] Connected target '$serial' is not WearOS (characteristics=$characteristics)."
      echo "[wearos] Attempting to provision/reuse WearOS emulator instead..."
      if ! ensure_wear_emulator_running; then
        echo "[wearos] Build-only checks passed."
        exit 0
      fi
      serial="$WEAR_EMULATOR_SERIAL"
      if ! is_wear_target "$serial"; then
        echo "[wearos] WARN: Target '$serial' still does not report WearOS traits. Continuing with build-only checks."
        echo "[wearos] Build-only checks passed."
        exit 0
      fi
    fi

    echo "[wearos] Running WearOS device smoke on $serial..."
    if ! adb -s "$serial" install -r "$apk_path"; then
      echo "[wearos] Upgrade install failed (signature mismatch or stale install). Retrying clean install..."
      adb -s "$serial" uninstall com.aspauldingcode.wawona >/dev/null 2>&1 || true
      adb -s "$serial" install "$apk_path"
    fi

    # Use -W and retries to avoid false negatives on cold emulator startups.
    start_ok=0
    start_output=""
    for _ in $(seq 1 3); do
      set +e
      start_output="$(adb -s "$serial" shell am start -W -n com.aspauldingcode.wawona/.MainActivity 2>&1)"
      start_rc=$?
      set -e
      if [ "$start_rc" -eq 0 ]; then
        start_ok=1
        break
      fi
      echo "[wearos] WARN: Activity launch attempt failed; retrying..."
      sleep 1
    done
    if [ "$start_ok" -ne 1 ]; then
      echo "[wearos] ERROR: Failed to launch main activity on WearOS target." >&2
      echo "$start_output" >&2
      exit 1
    fi

    app_ready=0
    for launch_round in $(seq 1 3); do
      if [ "$launch_round" -gt 1 ]; then
        echo "[wearos] WARN: App exited after launch, retrying launch ($launch_round/3)..."
        set +e
        start_output="$(adb -s "$serial" shell am start -W -n com.aspauldingcode.wawona/.MainActivity 2>&1)"
        start_rc=$?
        set -e
        if [ "$start_rc" -ne 0 ]; then
          echo "[wearos] WARN: Relaunch command failed."
          echo "$start_output"
          continue
        fi
      fi

      for _ in $(seq 1 15); do
        if adb -s "$serial" shell pidof com.aspauldingcode.wawona >/dev/null 2>&1; then
          app_ready=1
          break
        fi
        sleep 1
      done

      if [ "$app_ready" -eq 1 ]; then
        break
      fi
    done

    if [ "$app_ready" -ne 1 ]; then
      echo "[wearos] ERROR: App did not remain running on WearOS target." >&2
      adb -s "$serial" logcat -d -v brief | rg -i "(wawona|AndroidRuntime|FATAL EXCEPTION|am_crash|am_proc_died|ActivityTaskManager)" | tail -n 120 >&2 || true
      exit 1
    fi
    echo "[wearos] WearOS smoke test passed."
  '';
  meta = with pkgs.lib; {
    description = "Automated WearOS build and smoke test runner";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
