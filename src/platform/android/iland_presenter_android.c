#ifdef __ANDROID__

#include "iland_presenter_android.h"

#include "rendering/renderer_android.h"

#include <android/log.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "iosurface_compat.h"
#include "iland_present.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "WawonaIland", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "WawonaIland", __VA_ARGS__)

/* iland_drm_set_preferred_mode takes millihertz, not Hz. */
#define WWN_ILAND_REFRESH_MILLIHZ 60000u

#ifdef WAWONA_ILAND_GL
extern int kmscube_main(int argc, char **argv);
extern int gbm_es2_demo_main(int argc, char **argv);
#else
extern int kmscube_main(int argc, char **argv) __attribute__((weak));
extern int gbm_es2_demo_main(int argc, char **argv) __attribute__((weak));
#endif
extern void iland_drm_complete_page_flip(uint32_t crtc_id, uint32_t fb_id)
    __attribute__((weak));

static pthread_mutex_t g_frame_lock = PTHREAD_MUTEX_INITIALIZER;
static AHardwareBuffer *g_frame_buffer = NULL;
static uint32_t g_frame_width = 0;
static uint32_t g_frame_height = 0;
static uint32_t g_frame_stride = 0;
static uint32_t g_frame_fb_id = 0;
static int g_frame_dirty = 0;
static int g_presenter_active = 0;
static uint32_t g_surface_width = 1280;
static uint32_t g_surface_height = 720;

static pthread_t g_kms_client_thread = 0;
static int g_kms_client_running = 0;
static const char *g_kms_client_id = "kmscube";

typedef int (*wwn_kms_client_main_fn)(int argc, char **argv);

static wwn_kms_client_main_fn wwn_kms_client_entry(const char *client_id) {
  if (client_id && strcmp(client_id, "gbm-es2-demo") == 0)
    return gbm_es2_demo_main;
  return kmscube_main;
}

typedef void (*WWNAHardwareBufferRefFn)(AHardwareBuffer *);
static WWNAHardwareBufferRefFn g_ahb_acquire = NULL;
static WWNAHardwareBufferRefFn g_ahb_release = NULL;
static pthread_once_t g_ahb_symbols_once = PTHREAD_ONCE_INIT;

static void wwn_load_ahb_symbols(void) {
  g_ahb_acquire =
      (WWNAHardwareBufferRefFn)dlsym(RTLD_DEFAULT, "AHardwareBuffer_acquire");
  g_ahb_release =
      (WWNAHardwareBufferRefFn)dlsym(RTLD_DEFAULT, "AHardwareBuffer_release");
}

static int wwn_ahb_supported(void) {
  pthread_once(&g_ahb_symbols_once, wwn_load_ahb_symbols);
  return g_ahb_acquire && g_ahb_release;
}

static void wwn_iland_present_trampoline(uint32_t crtc_id, uint32_t fb_id,
                                         IOSurfaceRef surface, uint32_t flags,
                                         void *user) {
  (void)crtc_id;
  (void)flags;
  (void)user;
  if (!surface)
    return;

  uint32_t w = IOSurfaceGetWidth(surface);
  uint32_t h = IOSurfaceGetHeight(surface);
  size_t stride = IOSurfaceGetBytesPerRow(surface);
  AHardwareBuffer *buffer = ILandIOSurfaceGetHardwareBuffer(surface);
  if (!buffer || w == 0 || h == 0 || !wwn_ahb_supported()) {
    LOGE("iland present skipped: buffer=%p %ux%u ahb=%d", (void *)buffer, w, h,
         wwn_ahb_supported());
    return;
  }
  g_ahb_acquire(buffer);

  pthread_mutex_lock(&g_frame_lock);
  AHardwareBuffer *old_buffer = g_frame_buffer;
  g_frame_buffer = buffer;
  g_frame_width = w;
  g_frame_height = h;
  g_frame_stride = (uint32_t)stride;
  g_frame_fb_id = fb_id;
  g_frame_dirty = 1;
  pthread_mutex_unlock(&g_frame_lock);
  if (old_buffer)
    g_ahb_release(old_buffer);
}

void wwn_iland_presenter_android_init(void) {
  /* Init can run before the SurfaceView reports a size, in which case this
   * publishes the placeholder above; set_surface_size republishes (and the shim
   * re-enumerates modes) once the real size arrives. A 0x0 would instead leave
   * the shim on its 1920x1080 fallback, so refuse it. */
  if (g_surface_width > 0 && g_surface_height > 0) {
    iland_drm_set_preferred_mode(g_surface_width, g_surface_height,
                                 WWN_ILAND_REFRESH_MILLIHZ);
  }
  iland_drm_set_present_callback(wwn_iland_present_trampoline, NULL);
  g_presenter_active = 1;
  LOGI("iland present callback registered (%ux%u)", g_surface_width,
       g_surface_height);
}

void wwn_iland_presenter_android_shutdown(void) {
  g_kms_client_running = 0;
  if (g_kms_client_thread) {
    pthread_join(g_kms_client_thread, NULL);
    g_kms_client_thread = 0;
  }
  iland_drm_set_present_callback(NULL, NULL);
  pthread_mutex_lock(&g_frame_lock);
  AHardwareBuffer *old_buffer = g_frame_buffer;
  g_frame_buffer = NULL;
  g_frame_width = g_frame_height = g_frame_stride = g_frame_fb_id = 0;
  g_frame_dirty = 0;
  pthread_mutex_unlock(&g_frame_lock);
  if (old_buffer)
    g_ahb_release(old_buffer);
  g_presenter_active = 0;
}

void wwn_iland_presenter_android_set_surface_size(uint32_t width,
                                                  uint32_t height) {
  if (width < 1)
    width = 1;
  if (height < 1)
    height = 1;
  g_surface_width = width;
  g_surface_height = height;
  if (g_presenter_active)
    iland_drm_set_preferred_mode(width, height, WWN_ILAND_REFRESH_MILLIHZ);
}

static void *wwn_kms_client_thread(void *arg) {
  (void)arg;
  const char *client_id = g_kms_client_id ? g_kms_client_id : "kmscube";
  char *argv[] = {(char *)client_id, NULL};
  wwn_kms_client_main_fn entry = wwn_kms_client_entry(client_id);
  if (!entry) {
    LOGE("%s_main unavailable", client_id);
    g_kms_client_running = 0;
    return NULL;
  }
  LOGI("%s starting (iland userland KMS)", client_id);
  entry(1, argv);
  g_kms_client_running = 0;
  return NULL;
}

static int wwn_iland_presenter_android_launch_kms_client(const char *client_id) {
  wwn_kms_client_main_fn entry = wwn_kms_client_entry(client_id);
  if (!entry) {
    LOGE("Refusing %s: symbol unavailable (rebuild with iland + ANGLE)",
         client_id ? client_id : "(null)");
    return 0;
  }
  if (g_kms_client_running)
    return 1;
  if (!g_presenter_active)
    wwn_iland_presenter_android_init();
  g_kms_client_id = client_id ? client_id : "kmscube";
  g_kms_client_running = 1;
  if (pthread_create(&g_kms_client_thread, NULL, wwn_kms_client_thread, NULL) !=
      0) {
    g_kms_client_running = 0;
    return 0;
  }
  return 1;
}

int wwn_iland_presenter_android_launch_kmscube(void) {
  return wwn_iland_presenter_android_launch_kms_client("kmscube");
}

int wwn_iland_presenter_android_launch_gbm_es2_demo(void) {
  return wwn_iland_presenter_android_launch_kms_client("gbm-es2-demo");
}

int wwn_iland_presenter_android_is_active(void) { return g_presenter_active; }

int wwn_iland_presenter_android_take_hardware_buffer(
    AHardwareBuffer **out_buffer, uint32_t *out_w, uint32_t *out_h,
    uint32_t *out_stride, uint32_t *out_fb_id, int *out_is_new) {
  if (!out_buffer || !out_w || !out_h || !out_stride || !out_fb_id)
    return 0;
  pthread_mutex_lock(&g_frame_lock);
  if (!g_frame_buffer || g_frame_width == 0 || g_frame_height == 0) {
    pthread_mutex_unlock(&g_frame_lock);
    return 0;
  }
  if (!wwn_ahb_supported()) {
    pthread_mutex_unlock(&g_frame_lock);
    return 0;
  }
  /*
   * Sticky last frame: always report the latest buffer so the host keeps
   * painting between kmscube page flips (dirty-only used to flash clear color).
   * Only a dirty frame needs a fresh AHB acquire + GPU upload + flip ACK;
   * otherwise the caller redraws the cached Vulkan texture (do not re-lock -
   * the client may already be rendering into this BO after the prior ACK).
   */
  const int is_new = g_frame_dirty;
  *out_w = g_frame_width;
  *out_h = g_frame_height;
  *out_stride = g_frame_stride;
  *out_fb_id = g_frame_fb_id;
  if (out_is_new)
    *out_is_new = is_new;
  if (is_new) {
    g_ahb_acquire(g_frame_buffer);
    *out_buffer = g_frame_buffer;
    g_frame_dirty = 0;
  } else {
    *out_buffer = NULL;
  }
  pthread_mutex_unlock(&g_frame_lock);
  return 1;
}

void wwn_iland_presenter_android_frame_presented(uint32_t fb_id) {
  if (iland_drm_complete_page_flip)
    iland_drm_complete_page_flip(1, fb_id);
}

#endif
