# Bundled Wayland clients (weston-simple-shm, foot) for the Android APK.
#
# Extracted from android.nix to keep that file under its maintainability budget.
# `preBuildFragment` compiles weston-simple-shm in-tree and bundles foot as
# libfoot_bin.so (fork/exec PIE) plus companion libfoot.so; `verifyApkFragment`
# asserts both are packaged in the built APK. Both are spliced into the APK
# derivation (preBuild / buildPhase).
{
  androidCC,
  libwaylandAndroid,
  westonAndroid,
  footAndroid,
}:
{
  preBuildFragment = ''
    # weston-simple-shm as libweston_simple_shm.so (dlopen'd from libwawona.so).
    SHM_CC="${androidCC}"
    SHM_CFLAGS="-fPIC -O2 -D_GNU_SOURCE -DWWN_ANDROID_SHM_POLYFILL \
      -include deps/weston-simple-shm/wwn-android-signal-polyfill.h \
      -Ideps/weston-simple-shm -Ideps/weston-simple-shm/shared -Ideps/weston-simple-shm/include \
      -I${libwaylandAndroid}/include -I${westonAndroid}/include -I${westonAndroid}/include/weston-gen"
    SHM_OBJ_DIR="$TMPDIR/wawona-shm-objs"
    mkdir -p "$SHM_OBJ_DIR"
    SHM_OBJS=""
    for src in clients/simple-shm.c shared/os-compatibility.c xdg-shell-protocol.c fullscreen-shell-unstable-v1-protocol.c; do
      obj="$SHM_OBJ_DIR/$(basename "''${src%.c}.o")"
      "$SHM_CC" -c "deps/weston-simple-shm/$src" $SHM_CFLAGS -o "$obj"
      SHM_OBJS="$SHM_OBJS $obj"
    done
    "$SHM_CC" -shared -o "$JNI_LIB_DIR/libweston_simple_shm.so" $SHM_OBJS \
      -L${libwaylandAndroid}/lib -lwayland-client -lwayland-cursor \
      -lm -ldl
    chmod +x "$JNI_LIB_DIR/libweston_simple_shm.so"
    echo "Built libweston_simple_shm.so for in-process client launch"

    # foot: PIE as libfoot_bin.so (fork/exec, niri pattern) + companion
    # libfoot.so (shim probe / legacy dlopen stub).
    FOOT_BIN="${footAndroid}/lib/libfoot_bin.so"
    if [ ! -f "$FOOT_BIN" ] && [ -f "${footAndroid}/bin/foot" ]; then
      FOOT_BIN="${footAndroid}/bin/foot"
    fi
    if [ ! -f "$FOOT_BIN" ]; then
      echo "ERROR: Missing required Android foot binary at ${footAndroid}/lib/libfoot_bin.so"
      exit 1
    fi
    cp -L "$FOOT_BIN" "$JNI_LIB_DIR/libfoot_bin.so"
    chmod +x "$JNI_LIB_DIR/libfoot_bin.so"
    echo "Bundled libfoot_bin.so for out-of-process foot launch"

    FOOT_LIB="${footAndroid}/lib/arm64-v8a/libfoot.so"
    if [ ! -f "$FOOT_LIB" ]; then
      echo "ERROR: Missing required Android foot library at $FOOT_LIB"
      exit 1
    fi
    cp -L "$FOOT_LIB" "$JNI_LIB_DIR/libfoot.so"
    chmod +x "$JNI_LIB_DIR/libfoot.so"
    echo "Bundled libfoot.so companion (wwn_foot_is_compat_shim)"

    for lib in libweston_simple_shm.so libfoot.so libfoot_bin.so; do
      if [ ! -f "$JNI_LIB_DIR/$lib" ]; then
        echo "ERROR: Required bundled client library missing: $JNI_LIB_DIR/$lib"
        exit 1
      fi
    done
  '';

  verifyApkFragment = ''
    # Verify bundled client shared libraries are packaged in the APK.
    APK_VERIFY_PATH=""
    shopt -s nullglob globstar
    for candidate in \
      app/build/outputs/apk/**/*.apk \
      android/app/build/outputs/apk/**/*.apk \
      build/outputs/apk/**/*.apk
    do
      if [ -f "$candidate" ]; then
        APK_VERIFY_PATH="$candidate"
        break
      fi
    done
    shopt -u nullglob globstar
    if [ -n "$APK_VERIFY_PATH" ]; then
      # Capture the APK entry list once. Do NOT use `unzip -l | grep -q`: grep -q
      # closes the pipe on first match, unzip then dies with SIGPIPE (exit 141),
      # and with `set -o pipefail` (active in this build) the pipeline reports
      # non-zero — a false "missing" even though the lib is present. Use a
      # pipe-free glob match against the captured list instead.
      APK_ENTRIES="$(unzip -Z1 "$APK_VERIFY_PATH")"
      # Shell DT_NEEDED libs (waypipe → libzstd.so) + bundled clients (issue #80).
      for lib in libweston_simple_shm.so libfoot.so libfoot_bin.so libzstd.so libwaypipe_bin.so; do
        case "$APK_ENTRIES" in
          *"lib/arm64-v8a/$lib"*) ;;
          *)
            echo "ERROR: APK $APK_VERIFY_PATH missing lib/arm64-v8a/$lib"
            echo "=== APK lib/arm64-v8a entries ==="
            printf '%s\n' "$APK_ENTRIES" | grep "lib/arm64-v8a/" || true
            exit 1
            ;;
        esac
      done
      echo "Verified bundled client libraries in APK"
    fi
  '';
}
