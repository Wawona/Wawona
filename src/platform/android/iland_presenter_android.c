#ifdef __ANDROID__

#include "iland_presenter_android.h"

#include "rendering/renderer_android.h"

#include <android/log.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "iosurface_compat.h"
#include "iland_present.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "WawonaIland", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "WawonaIland", __VA_ARGS__)

#ifdef WAWONA_ILAND_GL
extern int kmscube_main(int argc, char **argv);
#else
extern int kmscube_main(int argc, char **argv) __attribute__((weak));
#endif

static pthread_mutex_t g_frame_lock = PTHREAD_MUTEX_INITIALIZER;
static uint8_t *g_frame_pixels = NULL;
static size_t g_frame_size = 0;
static uint32_t g_frame_width = 0;
static uint32_t g_frame_height = 0;
static uint32_t g_frame_stride = 0;
static int g_frame_dirty = 0;
static int g_presenter_active = 0;
static uint32_t g_surface_width = 1280;
static uint32_t g_surface_height = 720;

static pthread_t g_kmscube_thread = 0;
static int g_kmscube_running = 0;

static void wwn_iland_present_trampoline(uint32_t crtc_id, uint32_t fb_id,
                                         IOSurfaceRef surface, uint32_t flags,
                                         void *user) {
  (void)crtc_id;
  (void)fb_id;
  (void)flags;
  (void)user;
  if (!surface)
    return;

  IOSurfaceLock(surface);
  uint32_t w = IOSurfaceGetWidth(surface);
  uint32_t h = IOSurfaceGetHeight(surface);
  size_t stride = IOSurfaceGetBytesPerRow(surface);
  size_t need = (size_t)stride * h;
  uint8_t *src = (uint8_t *)IOSurfaceGetBaseAddress(surface);
  if (!src || w == 0 || h == 0) {
    IOSurfaceUnlock(surface);
    return;
  }

  pthread_mutex_lock(&g_frame_lock);
  if (g_frame_size < need) {
    uint8_t *p = realloc(g_frame_pixels, need);
    if (!p) {
      pthread_mutex_unlock(&g_frame_lock);
      IOSurfaceUnlock(surface);
      return;
    }
    g_frame_pixels = p;
    g_frame_size = need;
  }
  memcpy(g_frame_pixels, src, need);
  g_frame_width = w;
  g_frame_height = h;
  g_frame_stride = (uint32_t)stride;
  g_frame_dirty = 1;
  pthread_mutex_unlock(&g_frame_lock);
  IOSurfaceUnlock(surface);
}

void wwn_iland_presenter_android_init(void) {
  iland_drm_set_preferred_mode(g_surface_width, g_surface_height, 60);
  iland_drm_set_present_callback(wwn_iland_present_trampoline, NULL);
  g_presenter_active = 1;
  LOGI("iland present callback registered (%ux%u)", g_surface_width,
       g_surface_height);
}

void wwn_iland_presenter_android_shutdown(void) {
  g_kmscube_running = 0;
  if (g_kmscube_thread) {
    pthread_join(g_kmscube_thread, NULL);
    g_kmscube_thread = 0;
  }
  iland_drm_set_present_callback(NULL, NULL);
  pthread_mutex_lock(&g_frame_lock);
  free(g_frame_pixels);
  g_frame_pixels = NULL;
  g_frame_size = 0;
  g_frame_width = g_frame_height = g_frame_stride = 0;
  g_frame_dirty = 0;
  pthread_mutex_unlock(&g_frame_lock);
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
    iland_drm_set_preferred_mode(width, height, 60);
}

static void *wwn_kmscube_thread(void *arg) {
  (void)arg;
  char *argv[] = {(char *)"kmscube", NULL};
  if (!kmscube_main) {
    LOGE("kmscube_main unavailable");
    g_kmscube_running = 0;
    return NULL;
  }
  LOGI("kmscube_main starting (iland userland KMS)");
  kmscube_main(1, argv);
  g_kmscube_running = 0;
  return NULL;
}

int wwn_iland_presenter_android_launch_kmscube(void) {
  if (!kmscube_main) {
    LOGE("Refusing kmscube: symbol unavailable (rebuild with iland + ANGLE)");
    return 0;
  }
  if (g_kmscube_running)
    return 1;
  if (!g_presenter_active)
    wwn_iland_presenter_android_init();
  g_kmscube_running = 1;
  if (pthread_create(&g_kmscube_thread, NULL, wwn_kmscube_thread, NULL) != 0) {
    g_kmscube_running = 0;
    return 0;
  }
  return 1;
}

int wwn_iland_presenter_android_is_active(void) { return g_presenter_active; }

int wwn_iland_presenter_android_take_frame(uint8_t **out_pixels,
                                           uint32_t *out_w, uint32_t *out_h,
                                           uint32_t *out_stride) {
  if (!out_pixels || !out_w || !out_h || !out_stride)
    return 0;
  pthread_mutex_lock(&g_frame_lock);
  if (!g_frame_dirty || !g_frame_pixels || g_frame_width == 0 ||
      g_frame_height == 0) {
    pthread_mutex_unlock(&g_frame_lock);
    return 0;
  }
  *out_pixels = g_frame_pixels;
  *out_w = g_frame_width;
  *out_h = g_frame_height;
  *out_stride = g_frame_stride;
  g_frame_dirty = 0;
  pthread_mutex_unlock(&g_frame_lock);
  return 1;
}

#endif
