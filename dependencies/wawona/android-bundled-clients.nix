# Bundled Wayland clients (weston-simple-shm, foot, nested-niri fuzzel Exec
# launcher) for the Android APK.
#
# Extracted from android.nix to keep that file under its maintainability budget.
# `preBuildFragment` compiles weston-simple-shm in-tree and bundles foot as
# libfoot_bin.so (fork/exec PIE) plus companion libfoot.so; also builds
# libwawona_wl_bin.so so fuzzel Exec=weston-* resolves on PATH. `verifyApkFragment`
# asserts they are packaged in the built APK.
{
  androidCC,
  libwaylandAndroid,
  westonAndroid,
  footAndroid,
}:
let
  # Embedded so the filtered android workspace src does not need to carry the
  # file (Phase 25 builds against a trimmed tree).
  wlClientBinSrc = builtins.toFile "wawona_wl_client_bin.c" ''
    #include <android/log.h>
    #include <dlfcn.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>

    #define TAG "WawonaWlBin"
    #define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
    #define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

    typedef int (*client_main_fn)(int argc, char **argv);

    struct client_map {
      const char *exec_name;
      const char *lib_name;
      const char *symbol_name;
    };

    static const struct client_map k_clients[] = {
        {"weston-simple-shm", "libweston_simple_shm.so", "weston_simple_shm_main"},
        {"weston-flower", "libwawona.so", "flower_main"},
        {"weston-clickdot", "libwawona.so", "clickdot_main"},
        {"weston-smoke", "libwawona.so", "smoke_main"},
        {"weston-eventdemo", "libwawona.so", "eventdemo_main"},
        {"weston-resizor", "libwawona.so", "resizor_main"},
        {"weston-cliptest", "libwawona.so", "cliptest_main"},
        {"weston-transformed", "libwawona.so", "transformed_main"},
        {"weston-stacking", "libwawona.so", "stacking_main"},
        {"weston-dnd", "libwawona.so", "dnd_main"},
        {"weston-image", "libwawona.so", "image_main"},
        {"weston-scaler", "libwawona.so", "scaler_main"},
        {"weston-editor", "libwawona.so", "editor_main"},
        {"weston-constraints", "libwawona.so", "constraints_main"},
    };

    static const struct client_map *lookup_client(const char *name) {
      size_t i;
      if (!name || !name[0])
        return NULL;
      for (i = 0; i < sizeof(k_clients) / sizeof(k_clients[0]); i++) {
        if (strcmp(name, k_clients[i].exec_name) == 0)
          return &k_clients[i];
      }
      return NULL;
    }

    static const char *basename_of(const char *path) {
      const char *slash = strrchr(path, '/');
      return slash ? slash + 1 : path;
    }

    int main(int argc, char **argv) {
      const char *argv0 = (argc > 0 && argv[0]) ? argv[0] : "wawona-wl-client";
      const char *name = basename_of(argv0);
      const struct client_map *entry = lookup_client(name);
      void *handle;
      client_main_fn fn;
      const char *err;
      int rc;
      const char *wd = getenv("WAYLAND_DISPLAY");
      const char *xdg = getenv("XDG_RUNTIME_DIR");

      if (!entry) {
        LOGE("unknown client argv0=%s (not in nested-niri catalog launcher map)",
             name);
        return 127;
      }

      LOGI("launch %s via %s:%s WAYLAND_DISPLAY=%s XDG_RUNTIME_DIR=%s", name,
           entry->lib_name, entry->symbol_name, wd ? wd : "(null)",
           xdg ? xdg : "(null)");

      handle = dlopen(entry->lib_name, RTLD_NOW | RTLD_LOCAL);
      if (!handle) {
        LOGE("dlopen(%s) failed: %s", entry->lib_name, dlerror());
        return 127;
      }

      dlerror();
      fn = (client_main_fn)dlsym(handle, entry->symbol_name);
      err = dlerror();
      if (err || !fn) {
        LOGE("dlsym(%s) failed: %s", entry->symbol_name, err ? err : "null");
        dlclose(handle);
        return 127;
      }

      rc = fn(argc, argv);
      LOGI("%s exited %d", name, rc);
      dlclose(handle);
      return rc;
    }
  '';
in
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
    rm -f "$JNI_LIB_DIR/libfoot_bin.so"
    cp -L "$FOOT_BIN" "$JNI_LIB_DIR/libfoot_bin.so"
    chmod u+w "$JNI_LIB_DIR/libfoot_bin.so"
    chmod +x "$JNI_LIB_DIR/libfoot_bin.so"
    echo "Bundled libfoot_bin.so for out-of-process foot launch"

    FOOT_LIB="${footAndroid}/lib/arm64-v8a/libfoot.so"
    if [ ! -f "$FOOT_LIB" ]; then
      echo "ERROR: Missing required Android foot library at $FOOT_LIB"
      exit 1
    fi
    rm -f "$JNI_LIB_DIR/libfoot.so"
    cp -L "$FOOT_LIB" "$JNI_LIB_DIR/libfoot.so"
    chmod u+w "$JNI_LIB_DIR/libfoot.so"
    chmod +x "$JNI_LIB_DIR/libfoot.so"
    echo "Bundled libfoot.so companion (wwn_foot_is_compat_shim)"

    # Multicall PIE for fuzzel Exec=weston-* (nested niri).
    "$SHM_CC" -O2 -fPIC -D_GNU_SOURCE \
      -o "$JNI_LIB_DIR/libwawona_wl_bin.so" ${wlClientBinSrc} \
      -ldl -llog -landroid
    chmod +x "$JNI_LIB_DIR/libwawona_wl_bin.so"
    echo "Built libwawona_wl_bin.so for nested-niri fuzzel Exec launch"

    for lib in libweston_simple_shm.so libfoot.so libfoot_bin.so libwawona_wl_bin.so; do
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
      # non-zero. A false "missing" even though the lib is present. Use a
      # pipe-free glob match against the captured list instead.
      APK_ENTRIES="$(unzip -Z1 "$APK_VERIFY_PATH")"
      # Shell DT_NEEDED libs (waypipe → libzstd.so) + bundled clients (issue #80).
      for lib in libweston_simple_shm.so libfoot.so libfoot_bin.so libwawona_wl_bin.so libzstd.so libwaypipe_bin.so; do
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
