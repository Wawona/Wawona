/*
 * wawona_client_stubs.c
 *
 * Android launcher bridge for bundled native Wayland clients that are still
 * shipped as separate shared objects. Weston toytoolkit clients (weston_main,
 * weston_terminal_main, flower_main, …) are static-linked from libweston-13.a
 * into libwawona.so — not dlopen'd here.
 */

#include <android/log.h>
#include <dlfcn.h>

#define TAG "WawonaClients"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

typedef int (*client_main_fn)(int argc, const char **argv);

static int run_client_main(const char *lib_name, const char *symbol_name,
                           int argc, const char **argv) {
  void *handle = dlopen(lib_name, RTLD_NOW | RTLD_LOCAL);
  if (!handle) {
    LOGE("Failed to dlopen(%s): %s", lib_name, dlerror());
    return 1;
  }

  dlerror();
  client_main_fn fn = (client_main_fn)dlsym(handle, symbol_name);
  const char *sym_err = dlerror();
  if (sym_err != NULL || fn == NULL) {
    LOGE("Failed to resolve %s from %s: %s", symbol_name, lib_name,
         sym_err ? sym_err : "unknown");
    dlclose(handle);
    return 1;
  }

  LOGI("Launching %s from %s", symbol_name, lib_name);
  int rc = fn(argc, argv);
  LOGI("%s exited with code %d", symbol_name, rc);
  dlclose(handle);
  return rc;
}

int foot_main(int argc, const char **argv) {
  return run_client_main("libfoot.so", "foot_main", argc, argv);
}
