/**
 * Android JNI Bridge for Wawona Wayland Compositor
 *
 * This file provides the Java Native Interface (JNI) bridge between the Android
 * application layer and the Wawona compositor. It handles Vulkan surface
 * creation, safe area detection, and iOS settings compatibility.
 *
 * Features:
 * - Vulkan rendering with hardware acceleration
 * - Android WindowInsets integration for safe area support
 * - iOS settings 1:1 mapping
 * - Thread-safe initialization and cleanup
 */

#include "../macos/WWNSettings.h"
#include "input_android.h"
#include "rendering/renderer_android.h"
#include <android/choreographer.h>
#include <android/log.h>
#include <android/looper.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <jni.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#include <stdarg.h>
#include <time.h>

static void wwn_log(int prio, const char *tag, const char *fmt, ...)
    __attribute__((format(printf, 3, 4)));
static void wwn_log(int prio, const char *tag, const char *fmt, ...) {
  char msg[1024];
  char timebuf[32];
  time_t now = time(NULL);
  struct tm *tm = localtime(&now);
  strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", tm);
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(msg, sizeof(msg), fmt, ap);
  va_end(ap);
  __android_log_print(prio, "Wawona", "%s [%s] %s", timebuf, tag, msg);
}

#define LOGI(...) wwn_log(ANDROID_LOG_INFO, "JNI", __VA_ARGS__)
#define LOGE(...) wwn_log(ANDROID_LOG_ERROR, "JNI", __VA_ARGS__)

static void choreographer_frame_cb(long frameTimeNanos, void *data);

static void schedule_next_frame(void *ctx) {
#if __ANDROID_API__ >= 24
  AChoreographer_postFrameCallback(AChoreographer_getInstance(),
                                   choreographer_frame_cb, ctx);
#else
  (void)ctx;
#endif
}

// ============================================================================
// Forward declarations for Rust backend FFI (from c_api.rs / libwawona.a)
// ============================================================================
extern void *WWNCoreNew(void);
extern int WWNCoreStart(void *core, const char *socket_name);
extern int WWNCoreStop(void *core);
extern int WWNCoreIsRunning(const void *core);
extern int WWNCoreProcessEvents(void *core);
extern void WWNCoreSetOutputSize(void *core, uint32_t width, uint32_t height,
                                 float scale);
extern void WWNCoreSetSafeAreaInsets(void *core, int32_t top, int32_t right,
                                     int32_t bottom, int32_t left);
extern void WWNCoreSetForceSSD(void *core, int enabled);
extern void WWNCoreFree(void *core);

typedef struct {
  CRenderNode *nodes;
  size_t count;
  size_t capacity;
  int has_cursor;
  float cursor_x, cursor_y;
  float cursor_hotspot_x, cursor_hotspot_y;
  uint64_t cursor_buffer_id;
  uint32_t cursor_width, cursor_height, cursor_stride, cursor_format;
  uint32_t cursor_iosurface_id;
} CRenderScene;

extern CRenderScene *WWNCoreGetRenderScene(void *core);
extern void WWNRenderSceneFree(CRenderScene *scene);

typedef struct {
  uint64_t window_id;
  uint32_t surface_id;
  uint64_t buffer_id;
  uint32_t width, height, stride, format;
  uint8_t *pixels;
  size_t size;
  size_t capacity;
  uint32_t iosurface_id;
} CBufferData;

extern CBufferData *WWNCorePopPendingBuffer(void *core);
extern void WWNBufferDataFree(CBufferData *data);
extern void WWNCoreNotifyFramePresented(void *core, uint32_t surface_id,
                                        uint64_t buffer_id, uint32_t timestamp);
extern void WWNCoreFlushClients(void *core);

/* Window events - drain and apply title to UI */
enum {
  CWindowEventTypeCreated = 0,
  CWindowEventTypeTitleChanged = 2,
};
typedef struct {
  uint64_t event_type;
  uint64_t window_id;
  uint32_t surface_id;
  char *title; /* FFI: *mut c_char */
  uint32_t width, height;
  uint64_t parent_id;
  int32_t x, y;
  uint8_t decoration_mode;
  uint8_t fullscreen_shell;
  uint16_t padding;
} CWindowEvent;
extern CWindowEvent *WWNCorePopWindowEvent(void *core);
extern void WWNWindowEventFree(CWindowEvent *event);

/* Screencopy (zwlr_screencopy_manager_v1) - platform writes ARGB8888 to ptr */
typedef struct {
  uint64_t capture_id;
  void *ptr;
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  size_t size;
} CScreencopyRequest;
extern CScreencopyRequest WWNCoreGetPendingScreencopy(void *core);
extern void WWNCoreScreencopyDone(void *core, uint64_t capture_id);
extern void WWNCoreScreencopyFailed(void *core, uint64_t capture_id);
extern CScreencopyRequest WWNCoreGetPendingImageCopyCapture(void *core);
extern void WWNCoreImageCopyCaptureDone(void *core, uint64_t capture_id);
extern void WWNCoreImageCopyCaptureFailed(void *core, uint64_t capture_id);

extern void WWNCoreInjectTouchDown(void *core, int32_t id, double x, double y,
                                   uint32_t timestamp_ms);
extern void WWNCoreInjectTouchUp(void *core, int32_t id, uint32_t timestamp_ms);
extern void WWNCoreInjectTouchMotion(void *core, int32_t id, double x, double y,
                                     uint32_t timestamp_ms);
extern void WWNCoreInjectTouchCancel(void *core);
extern void WWNCoreInject_touch_frame(void *core);
extern void WWNCoreInjectKey(void *core, uint32_t keycode, uint32_t state,
                             uint32_t timestamp_ms);
extern void WWNCoreInjectModifiers(void *core, uint32_t depressed,
                                   uint32_t latched, uint32_t locked,
                                   uint32_t group);
extern void WWNCoreInjectPointerMotion(void *core, uint64_t window_id, double x,
                                       double y, uint32_t timestamp_ms);
extern void WWNCoreInjectPointerButton(void *core, uint64_t window_id,
                                       uint32_t button_code, uint32_t state,
                                       uint32_t timestamp_ms);
extern void WWNCoreInjectPointerEnter(void *core, uint64_t window_id, double x,
                                      double y, uint32_t timestamp_ms);
extern void WWNCoreInjectPointerLeave(void *core, uint64_t window_id,
                                      uint32_t timestamp_ms);
extern void WWNCoreInjectPointerAxis(void *core, uint64_t window_id,
                                     uint32_t axis, double value,
                                     uint32_t timestamp_ms);
extern void WWNCoreInjectKeyboardEnter(void *core, uint64_t window_id,
                                       const uint32_t *keys, size_t count,
                                       uint32_t timestamp_ms);
extern void WWNCoreInjectKeyboardLeave(void *core, uint64_t window_id);

extern void WWNCoreTextInputCommit(void *core, const char *text);
extern void WWNCoreTextInputPreedit(void *core, const char *text,
                                    int32_t cursor_begin, int32_t cursor_end);
extern void WWNCoreTextInputDeleteSurrounding(void *core, uint32_t before,
                                              uint32_t after);
extern void WWNCoreTextInputGetCursorRect(void *core, int32_t *out_x,
                                          int32_t *out_y, int32_t *out_width,
                                          int32_t *out_height);

extern int waypipe_main(int argc, const char **argv) __attribute__((weak));
extern int weston_simple_shm_main(int argc, const char **argv)
    __attribute__((weak));
extern int weston_main(int argc, const char **argv);
extern int weston_terminal_main(int argc, const char **argv);
extern int foot_main(int argc, const char **argv);
extern int wwn_weston_is_compat_shim(void) __attribute__((weak));
extern int wwn_weston_terminal_is_compat_shim(void) __attribute__((weak));
extern int wwn_foot_is_compat_shim(void) __attribute__((weak));
extern int g_simple_shm_running __attribute__((weak));

// JNI Function Prototypes
JNIEXPORT void JNICALL Java_com_aspauldingcode_wawona_WawonaNative_nativeInit(
    JNIEnv *env, jobject thiz, jstring cacheDir);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetSurface(JNIEnv *env,
                                                             jobject thiz,
                                                             jobject surface);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDestroySurface(JNIEnv *env,
                                                                 jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeResizeSurface(JNIEnv *env,
                                                                jobject thiz,
                                                                jint width,
                                                                jint height);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSyncOutputSize(JNIEnv *env,
                                                                 jobject thiz,
                                                                 jint width,
                                                                 jint height);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeShutdown(JNIEnv *env,
                                                           jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetDisplayDensity(
    JNIEnv *env, jobject thiz, jfloat density);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeUpdateSafeArea(
    JNIEnv *env, jobject thiz, jint left, jint top, jint right, jint bottom);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeApplySettings(
    JNIEnv *env, jobject thiz, jboolean forceServerSideDecorations,
    jboolean autoRetinaScaling, jint renderingBackend, jboolean respectSafeArea,
    jboolean renderMacOSPointer, jboolean swapCmdAsCtrl,
    jboolean universalClipboard, jboolean colorSyncSupport,
    jboolean nestedCompositorsSupport, jboolean useMetal4ForNested,
    jboolean multipleClients, jboolean waypipeRSSupport,
    jboolean enableTCPListener, jint tcpPort, jstring vulkanDriver,
    jstring openglDriver);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetCore(JNIEnv *env,
                                                          jobject thiz,
                                                          jlong corePtr);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeCommitText(JNIEnv *env,
                                                             jobject thiz,
                                                             jstring text);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePreeditText(
    JNIEnv *env, jobject thiz, jstring text, jint cursorBegin, jint cursorEnd);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDeleteSurroundingText(
    JNIEnv *env, jobject thiz, jint beforeLength, jint afterLength);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetCursorRect(
    JNIEnv *env, jobject thiz, jintArray outRect);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWaypipe(
    JNIEnv *env, jobject thiz, jboolean sshEnabled, jstring sshHost,
    jstring sshUser, jstring sshPassword, jstring remoteCommand,
    jstring compress, jint threads, jstring video, jboolean debug,
    jboolean oneshot, jboolean noGpu, jboolean loginShell, jstring titlePrefix,
    jstring secCtx);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWaypipe(JNIEnv *env,
                                                              jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWaypipeRunning(
    JNIEnv *env, jobject thiz);

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonSimpleSHM(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWestonSimpleSHM(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonSimpleSHMRunning(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWeston(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWeston(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonRunning(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonTerminal(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWestonTerminal(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonTerminalRunning(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunFoot(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopFoot(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsFootRunning(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchDown(
    JNIEnv *env, jobject thiz, jint id, jfloat x, jfloat y, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchUp(JNIEnv *env,
                                                          jobject thiz, jint id,
                                                          jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchMotion(
    JNIEnv *env, jobject thiz, jint id, jfloat x, jfloat y, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchCancel(JNIEnv *env,
                                                              jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchFrame(JNIEnv *env,
                                                             jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeKeyEvent(
    JNIEnv *env, jobject thiz, jint keycode, jint state, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeInjectKey(
    JNIEnv *env, jobject thiz, jint linuxKeycode, jboolean pressed,
    jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeInjectModifiers(
    JNIEnv *env, jobject thiz, jint depressed, jint latched, jint locked,
    jint group);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerAxis(
    JNIEnv *env, jobject thiz, jint axis, jfloat value, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerMotion(
    JNIEnv *env, jobject thiz, jdouble x, jdouble y, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerButton(
    JNIEnv *env, jobject thiz, jint buttonCode, jint state, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerEnter(
    JNIEnv *env, jobject thiz, jdouble x, jdouble y, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerLeave(
    JNIEnv *env, jobject thiz, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeKeyboardFocus(
    JNIEnv *env, jobject thiz, jboolean hasFocus);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetFocusedWindowTitle(
    JNIEnv *env, jobject thiz);
JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetPendingScreencopy(
    JNIEnv *env, jobject thiz, jintArray outWidthHeight);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeScreencopyComplete(
    JNIEnv *env, jobject thiz, jlong captureId, jbyteArray pixels);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeScreencopyFailed(
    JNIEnv *env, jobject thiz, jlong captureId);
JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetPendingImageCopyCapture(
    JNIEnv *env, jobject thiz, jintArray outWidthHeight);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeImageCopyCaptureComplete(
    JNIEnv *env, jobject thiz, jlong captureId, jbyteArray pixels);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeImageCopyCaptureFailed(
    JNIEnv *env, jobject thiz, jlong captureId);

// ============================================================================
// Global State
// ============================================================================

// Vulkan resources
VkInstance g_instance = VK_NULL_HANDLE;
VkPhysicalDevice g_physicalDevice = VK_NULL_HANDLE;
VkSurfaceKHR g_surface = VK_NULL_HANDLE;
VkDevice g_device = VK_NULL_HANDLE;
VkQueue g_queue = VK_NULL_HANDLE;
VkSwapchainKHR g_swapchain = VK_NULL_HANDLE;
uint32_t g_queue_family = 0;
ANativeWindow *g_window = NULL;
uint32_t g_output_width = 0;
uint32_t g_output_height = 0;

// Threading
static int g_running = 0;
static pthread_t g_render_thread = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

// Window title from drained CWindowEvent (TitleChanged) - for ActionBar/status
// display
#define WINDOW_TITLE_MAX 256
static char g_window_title[WINDOW_TITLE_MAX];
static pthread_mutex_t g_title_lock = PTHREAD_MUTEX_INITIALIZER;

// Pending screencopy - ptr stored for nativeScreencopyComplete (must run on
// same thread as GetPending)
static void *g_screencopy_ptr = NULL;
static uint32_t g_screencopy_stride = 0;
static size_t g_screencopy_size = 0;

// Safe area support (for display cutouts, notches, etc.)
static int g_safeAreaLeft = 0;
static int g_safeAreaTop = 0;
static int g_safeAreaRight = 0;
static int g_safeAreaBottom = 0;

// Raw safe area values from Android (independent of setting)
static int g_rawSafeAreaLeft = 0;
static int g_rawSafeAreaTop = 0;
static int g_rawSafeAreaRight = 0;
static int g_rawSafeAreaBottom = 0;

// Display density from Android (set by nativeSetDisplayDensity)
static float g_display_density = 1.0f;

// Compositor core pointer (set when Rust core is initialised)
static void *g_core = NULL;

/* Modifier state for InjectModifiers (XKB modifier mask) */
#define XKB_MOD_SHIFT (1 << 0)
#define XKB_MOD_CAPS (1 << 1)
#define XKB_MOD_CTRL (1 << 2)
#define XKB_MOD_ALT (1 << 3)
#define XKB_MOD_NUM (1 << 4)
#define XKB_MOD_LOGO (1 << 6) /* Super/Meta = Mod4 */
static uint32_t g_modifiers_depressed = 0;

/* Single full-screen window id for pointer enter/leave/axis (Android has no
 * multi-window UI).  Starts at 0 so the render loop detects the first real
 * window and auto-sends keyboard enter. */
static uint64_t g_pointer_window_id = 0;

/* Active touch count - for pointer enter/leave (inject enter on 0->1, leave on
 * 1->0) */
static int g_active_touches = 0;

// iOS Settings 1:1 mapping (for compatibility with iOS version)
// Now managed by WawonaSettings.c via WWNSettings_UpdateConfig

// ============================================================================
// Auto-Scale Helpers
// ============================================================================

static int compute_auto_scale_factor(void) {
  if (!WWNSettings_GetAutoRetinaScalingEnabled())
    return 1;
  if (g_display_density <= 1.0f)
    return 1;
  int scale = (int)(g_display_density + 0.5f);
  if (scale < 1)
    scale = 1;
  if (scale > 4)
    scale = 4;
  return scale;
}

static void apply_output_scale(void) {
  if (!g_core || g_output_width == 0 || g_output_height == 0)
    return;
  int sf = compute_auto_scale_factor();
  uint32_t lw = g_output_width / (uint32_t)sf;
  uint32_t lh = g_output_height / (uint32_t)sf;
  if (lw == 0)
    lw = 1;
  if (lh == 0)
    lh = 1;
  WWNCoreSetOutputSize(g_core, lw, lh, (float)sf);
  LOGI("Auto-scale: physical=%ux%u density=%.2f scale=%d logical=%ux%u",
       g_output_width, g_output_height, g_display_density, sf, lw, lh);
}

// ============================================================================
// Safe Area Detection
// ============================================================================

/**
 * Update safe area insets from Android WindowInsets API
 * Handles display cutouts (notches, punch holes) and system gesture insets
 */
static void update_safe_area(JNIEnv *env, jobject activity) {
  LOGI("update_safe_area called");
  if (!activity) {
    LOGE("update_safe_area: activity is NULL");
    g_safeAreaLeft = 0;
    g_safeAreaTop = 0;
    g_safeAreaRight = 0;
    g_safeAreaBottom = 0;
    return;
  }
  if (!WWNSettings_GetRespectSafeArea()) {
    LOGI("Safe area respect disabled, setting to 0");
    g_safeAreaLeft = 0;
    g_safeAreaTop = 0;
    g_safeAreaRight = 0;
    g_safeAreaBottom = 0;
    return;
  }
  LOGI("Updating safe area from WindowInsets...");

  // Get WindowInsets
  jclass activityClass = (*env)->GetObjectClass(env, activity);
  jmethodID getWindowMethod = (*env)->GetMethodID(
      env, activityClass, "getWindow", "()Landroid/view/Window;");
  jobject window = (*env)->CallObjectMethod(env, activity, getWindowMethod);

  if (window) {
    jclass windowClass = (*env)->GetObjectClass(env, window);
    jmethodID getDecorViewMethod = (*env)->GetMethodID(
        env, windowClass, "getDecorView", "()Landroid/view/View;");
    jobject decorView =
        (*env)->CallObjectMethod(env, window, getDecorViewMethod);

    if (decorView) {
      // Get root window insets
      jclass viewClass = (*env)->GetObjectClass(env, decorView);
      jmethodID getRootWindowInsetsMethod =
          (*env)->GetMethodID(env, viewClass, "getRootWindowInsets",
                              "()Landroid/view/WindowInsets;");
      jobject windowInsets =
          (*env)->CallObjectMethod(env, decorView, getRootWindowInsetsMethod);

      if (windowInsets) {
        // Get display cutout for notch/punch hole
        jclass windowInsetsClass = (*env)->GetObjectClass(env, windowInsets);
        jmethodID getDisplayCutoutMethod =
            (*env)->GetMethodID(env, windowInsetsClass, "getDisplayCutout",
                                "()Landroid/view/DisplayCutout;");
        jobject displayCutout =
            (*env)->CallObjectMethod(env, windowInsets, getDisplayCutoutMethod);

        if (displayCutout) {
          jclass displayCutoutClass =
              (*env)->GetObjectClass(env, displayCutout);

          // Get safe insets
          jmethodID getSafeInsetLeftMethod = (*env)->GetMethodID(
              env, displayCutoutClass, "getSafeInsetLeft", "()I");
          jmethodID getSafeInsetTopMethod = (*env)->GetMethodID(
              env, displayCutoutClass, "getSafeInsetTop", "()I");
          jmethodID getSafeInsetRightMethod = (*env)->GetMethodID(
              env, displayCutoutClass, "getSafeInsetRight", "()I");
          jmethodID getSafeInsetBottomMethod = (*env)->GetMethodID(
              env, displayCutoutClass, "getSafeInsetBottom", "()I");

          g_safeAreaLeft =
              (*env)->CallIntMethod(env, displayCutout, getSafeInsetLeftMethod);
          g_safeAreaTop =
              (*env)->CallIntMethod(env, displayCutout, getSafeInsetTopMethod);
          g_safeAreaRight = (*env)->CallIntMethod(env, displayCutout,
                                                  getSafeInsetRightMethod);
          g_safeAreaBottom = (*env)->CallIntMethod(env, displayCutout,
                                                   getSafeInsetBottomMethod);

          LOGI("Safe area updated: left=%d, top=%d, right=%d, bottom=%d",
               g_safeAreaLeft, g_safeAreaTop, g_safeAreaRight,
               g_safeAreaBottom);

          (*env)->DeleteLocalRef(env, displayCutout);
        } else {
          // Fallback to system gesture insets for navigation bar
          jmethodID getSystemGestureInsetsMethod = (*env)->GetMethodID(
              env, windowInsetsClass, "getSystemGestureInsets",
              "()Landroid/graphics/Insets;");
          jobject systemGestureInsets = (*env)->CallObjectMethod(
              env, windowInsets, getSystemGestureInsetsMethod);

          if (systemGestureInsets) {
            jclass insetsClass =
                (*env)->GetObjectClass(env, systemGestureInsets);
            jfieldID leftField =
                (*env)->GetFieldID(env, insetsClass, "left", "I");
            jfieldID topField =
                (*env)->GetFieldID(env, insetsClass, "top", "I");
            jfieldID rightField =
                (*env)->GetFieldID(env, insetsClass, "right", "I");
            jfieldID bottomField =
                (*env)->GetFieldID(env, insetsClass, "bottom", "I");

            g_safeAreaLeft =
                (*env)->GetIntField(env, systemGestureInsets, leftField);
            g_safeAreaTop =
                (*env)->GetIntField(env, systemGestureInsets, topField);
            g_safeAreaRight =
                (*env)->GetIntField(env, systemGestureInsets, rightField);
            g_safeAreaBottom =
                (*env)->GetIntField(env, systemGestureInsets, bottomField);

            LOGI("System gesture insets: left=%d, top=%d, right=%d, bottom=%d",
                 g_safeAreaLeft, g_safeAreaTop, g_safeAreaRight,
                 g_safeAreaBottom);

            (*env)->DeleteLocalRef(env, systemGestureInsets);
          } else {
            // Default to no safe area
            g_safeAreaLeft = 0;
            g_safeAreaTop = 0;
            g_safeAreaRight = 0;
            g_safeAreaBottom = 0;
            LOGI("No safe area detected, using full screen");
          }
        }

        (*env)->DeleteLocalRef(env, windowInsets);
      }

      (*env)->DeleteLocalRef(env, decorView);
    }

    (*env)->DeleteLocalRef(env, window);
  }

  (*env)->DeleteLocalRef(env, activityClass);
}

// ============================================================================
// Vulkan Initialization
// ============================================================================

/**
 * Create Vulkan instance with Android surface extensions
 */
static VkResult create_instance(void) {
  const char *vulkanDriver = WWNSettings_GetVulkanDriver();

  // If Waypipe support is enabled, force SwiftShader for compatibility
  if (WWNSettings_GetWaypipeRSSupportEnabled()) {
    LOGI("Waypipe support enabled: Forcing SwiftShader ICD");
    setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json",
           1);
  } else if (strcmp(vulkanDriver, "none") == 0) {
    // Vulkan disabled - use SwiftShader as safe fallback so compositor can
    // still run
    LOGI("Vulkan driver 'none' selected: Using SwiftShader fallback");
    setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json",
           1);
  } else if (strcmp(vulkanDriver, "swiftshader") == 0) {
    LOGI("Vulkan driver 'swiftshader' selected");
    setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json",
           1);
  } else if (strcmp(vulkanDriver, "turnip") == 0) {
    LOGI("Vulkan driver 'turnip' (freedreno) selected");
    setenv("VK_ICD_FILENAMES", "/data/local/tmp/freedreno_icd.json", 1);
  } else {
    // "system" or unknown - use system default (unset or platform default)
    LOGI("Vulkan driver 'system' selected: Using platform default");
    unsetenv("VK_ICD_FILENAMES");
  }

  const char *exts[] = {VK_KHR_SURFACE_EXTENSION_NAME,
                        VK_KHR_ANDROID_SURFACE_EXTENSION_NAME};
  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO};
  app.pApplicationName = "Wawona";
  app.applicationVersion = VK_MAKE_VERSION(0, 0, 1);
  app.pEngineName = "Wawona";
  app.engineVersion = VK_MAKE_VERSION(0, 0, 1);
  app.apiVersion = VK_API_VERSION_1_0;

  VkInstanceCreateInfo ci = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
  ci.pApplicationInfo = &app;
  ci.enabledExtensionCount = (uint32_t)(sizeof(exts) / sizeof(exts[0]));
  ci.ppEnabledExtensionNames = exts;

  VkResult res = vkCreateInstance(&ci, NULL, &g_instance);
  if (res != VK_SUCCESS) {
    LOGE("vkCreateInstance failed: %d", res);
    // Try SwiftShader fallback
    setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json",
           1);
    res = vkCreateInstance(&ci, NULL, &g_instance);
  }
  if (res != VK_SUCCESS)
    LOGE("vkCreateInstance failed: %d", res);
  return res;
}

/**
 * Pick the first available Vulkan physical device
 */
static VkPhysicalDevice pick_device(void) {
  uint32_t count = 0;
  VkResult res = vkEnumeratePhysicalDevices(g_instance, &count, NULL);
  if (res != VK_SUCCESS || count == 0) {
    LOGE("vkEnumeratePhysicalDevices failed: %d, count=%u", res, count);
    return VK_NULL_HANDLE;
  }
  VkPhysicalDevice devs[4];
  if (count > 4)
    count = 4;
  res = vkEnumeratePhysicalDevices(g_instance, &count, devs);
  if (res != VK_SUCCESS) {
    LOGE("vkEnumeratePhysicalDevices failed: %d", res);
    return VK_NULL_HANDLE;
  }
  LOGI("Found %u Vulkan devices", count);

  // Print device names
  for (uint32_t i = 0; i < count; i++) {
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(devs[i], &props);
    LOGI("Device %u: %s (Type: %d, API: %u.%u.%u)", i, props.deviceName,
         props.deviceType, VK_VERSION_MAJOR(props.apiVersion),
         VK_VERSION_MINOR(props.apiVersion),
         VK_VERSION_PATCH(props.apiVersion));
  }

  g_physicalDevice = devs[0];
  return devs[0];
}

/**
 * Find a queue family that supports graphics and surface presentation
 */
static int pick_queue_family(VkPhysicalDevice pd) {
  uint32_t count = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, NULL);
  if (count == 0)
    return -1;

  VkQueueFamilyProperties props[8];
  if (count > 8)
    count = 8;
  vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, props);

  for (uint32_t i = 0; i < count; i++) {
    VkBool32 sup = VK_FALSE;
    vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, g_surface, &sup);
    if ((props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && sup) {
      LOGI("Found graphics queue family %u", i);
      return (int)i;
    }
  }
  LOGE("No graphics queue family found");
  return -1;
}

/**
 * Check if an extension is available in the list
 */
static int is_extension_available(const char *name,
                                  VkExtensionProperties *props,
                                  uint32_t count) {
  for (uint32_t i = 0; i < count; i++) {
    if (strcmp(name, props[i].extensionName) == 0) {
      return 1;
    }
  }
  return 0;
}

/**
 * Create Vulkan logical device with swapchain extension
 */
static int create_device(VkPhysicalDevice pd) {
  int q = pick_queue_family(pd);
  if (q < 0)
    return -1;
  g_queue_family = (uint32_t)q;

  float prio = 1.0f;
  VkDeviceQueueCreateInfo qci = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
  qci.queueFamilyIndex = g_queue_family;
  qci.queueCount = 1;
  qci.pQueuePriorities = &prio;

  // Check available extensions
  uint32_t extCount = 0;
  vkEnumerateDeviceExtensionProperties(pd, NULL, &extCount, NULL);
  VkExtensionProperties *availableExts =
      malloc(sizeof(VkExtensionProperties) * extCount);
  if (availableExts) {
    vkEnumerateDeviceExtensionProperties(pd, NULL, &extCount, availableExts);
  }

  // List of desired extensions
  const char *desired_exts[] = {
      VK_KHR_SWAPCHAIN_EXTENSION_NAME, VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME,
      VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME,
      "VK_EXT_external_memory_dma_buf", // Explicit string if header missing
      "VK_ANDROID_external_memory_android_hardware_buffer"};
  uint32_t desiredCount = sizeof(desired_exts) / sizeof(desired_exts[0]);

  // Filter enabled extensions
  const char *enabled_exts[16];
  uint32_t enabledCount = 0;

  for (uint32_t i = 0; i < desiredCount; i++) {
    if (availableExts &&
        is_extension_available(desired_exts[i], availableExts, extCount)) {
      enabled_exts[enabledCount++] = desired_exts[i];
      LOGI("Enabling extension: %s", desired_exts[i]);
    } else {
      LOGI("Extension not available (skipping): %s", desired_exts[i]);
    }
  }

  if (availableExts)
    free(availableExts);

  VkDeviceCreateInfo dci = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
  dci.queueCreateInfoCount = 1;
  dci.pQueueCreateInfos = &qci;
  dci.enabledExtensionCount = enabledCount;
  dci.ppEnabledExtensionNames = enabled_exts;

  if (vkCreateDevice(pd, &dci, NULL, &g_device) != VK_SUCCESS) {
    LOGE("vkCreateDevice failed");
    return -1;
  }
  vkGetDeviceQueue(g_device, g_queue_family, 0, &g_queue);
  LOGI("Device created successfully");
  return 0;
}

/**
 * Create swapchain for surface presentation
 */
static int create_swapchain(VkPhysicalDevice pd) {
  VkSurfaceCapabilitiesKHR caps;
  VkResult res =
      vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, g_surface, &caps);
  if (res != VK_SUCCESS) {
    LOGE("vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed: %d", res);
    return -1;
  }

  VkExtent2D ext = caps.currentExtent;
  if (ext.width == 0 || ext.height == 0)
    ext = (VkExtent2D){640, 480};
  LOGI("Swapchain extent: %ux%u", ext.width, ext.height);

  VkSwapchainCreateInfoKHR sci = {
      .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
  sci.surface = g_surface;
  sci.minImageCount = caps.minImageCount > 2 ? caps.minImageCount : 2;
  sci.imageFormat = VK_FORMAT_R8G8B8A8_UNORM;
  sci.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  sci.imageExtent = ext;
  sci.imageArrayLayers = 1;
  sci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
  sci.preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  sci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  sci.presentMode = VK_PRESENT_MODE_FIFO_KHR;
  sci.clipped = VK_TRUE;

  if (vkCreateSwapchainKHR(g_device, &sci, NULL, &g_swapchain) != VK_SUCCESS) {
    LOGE("vkCreateSwapchainKHR failed");
    return -1;
  }
  LOGI("Swapchain created successfully");
  return 0;
}

/**
 * Create swapchain with explicit extent (for resize without full teardown)
 */
static int create_swapchain_with_extent(VkPhysicalDevice pd, uint32_t width,
                                        uint32_t height) {
  VkSurfaceCapabilitiesKHR caps;
  VkResult res =
      vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, g_surface, &caps);
  if (res != VK_SUCCESS) {
    LOGE("vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed: %d", res);
    return -1;
  }

  VkExtent2D ext = {.width = width, .height = height};
  if (ext.width < caps.minImageExtent.width)
    ext.width = caps.minImageExtent.width;
  if (ext.height < caps.minImageExtent.height)
    ext.height = caps.minImageExtent.height;
  if (caps.maxImageExtent.width > 0 && ext.width > caps.maxImageExtent.width)
    ext.width = caps.maxImageExtent.width;
  if (caps.maxImageExtent.height > 0 && ext.height > caps.maxImageExtent.height)
    ext.height = caps.maxImageExtent.height;

  LOGI("Swapchain extent (resize): %ux%u", ext.width, ext.height);

  VkSwapchainCreateInfoKHR sci = {
      .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
  sci.surface = g_surface;
  sci.minImageCount = caps.minImageCount > 2 ? caps.minImageCount : 2;
  sci.imageFormat = VK_FORMAT_R8G8B8A8_UNORM;
  sci.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  sci.imageExtent = ext;
  sci.imageArrayLayers = 1;
  sci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
  sci.preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  sci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  sci.presentMode = VK_PRESENT_MODE_FIFO_KHR;
  sci.clipped = VK_TRUE;

  if (vkCreateSwapchainKHR(g_device, &sci, NULL, &g_swapchain) != VK_SUCCESS) {
    LOGE("vkCreateSwapchainKHR failed (resize)");
    return -1;
  }
  LOGI("Swapchain recreated successfully");
  return 0;
}

// ============================================================================
// Rendering
// ============================================================================

static VkImageView *g_imageViews = NULL;
static VkFramebuffer *g_framebuffers = NULL;
static VkRenderPass g_renderPass = VK_NULL_HANDLE;
static uint32_t g_swapchainImageCount = 0;

/**
 * Create Image Views
 */
static int create_image_views(uint32_t imageCount, VkImage *images) {
  if (g_imageViews)
    free(g_imageViews);
  g_imageViews = malloc(imageCount * sizeof(VkImageView));
  g_swapchainImageCount = imageCount;
  for (uint32_t i = 0; i < imageCount; i++) {
    VkImageViewCreateInfo ivci = {.sType =
                                      VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    ivci.image = images[i];
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format = VK_FORMAT_R8G8B8A8_UNORM; // Must match swapchain format
    ivci.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
    ivci.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
    ivci.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
    ivci.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
    ivci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    ivci.subresourceRange.baseMipLevel = 0;
    ivci.subresourceRange.levelCount = 1;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount = 1;

    if (vkCreateImageView(g_device, &ivci, NULL, &g_imageViews[i]) !=
        VK_SUCCESS) {
      LOGE("Failed to create image view %u", i);
      return -1;
    }
  }
  return 0;
}

/**
 * Create Render Pass
 */
static int create_render_pass(void) {
  if (g_renderPass != VK_NULL_HANDLE)
    vkDestroyRenderPass(g_device, g_renderPass, NULL);

  VkAttachmentDescription colorAttachment = {0};
  colorAttachment.format = VK_FORMAT_R8G8B8A8_UNORM;
  colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
  colorAttachment.loadOp =
      VK_ATTACHMENT_LOAD_OP_CLEAR; /* Clear to CompositorBackground (0x0F1018) */
  colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
  colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
  colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

  VkAttachmentReference colorAttachmentRef = {0};
  colorAttachmentRef.attachment = 0;
  colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

  VkSubpassDescription subpass = {0};
  subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
  subpass.colorAttachmentCount = 1;
  subpass.pColorAttachments = &colorAttachmentRef;

  VkSubpassDependency dependency = {0};
  dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
  dependency.dstSubpass = 0;
  dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  dependency.srcAccessMask = 0;
  dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

  VkRenderPassCreateInfo renderPassInfo = {
      .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
  renderPassInfo.attachmentCount = 1;
  renderPassInfo.pAttachments = &colorAttachment;
  renderPassInfo.subpassCount = 1;
  renderPassInfo.pSubpasses = &subpass;
  renderPassInfo.dependencyCount = 1;
  renderPassInfo.pDependencies = &dependency;

  if (vkCreateRenderPass(g_device, &renderPassInfo, NULL, &g_renderPass) !=
      VK_SUCCESS) {
    LOGE("Failed to create render pass");
    return -1;
  }
  return 0;
}

/**
 * Create Framebuffers
 */
static int create_framebuffers(uint32_t imageCount, VkExtent2D extent) {
  if (g_framebuffers)
    free(g_framebuffers);
  g_framebuffers = malloc(imageCount * sizeof(VkFramebuffer));
  for (uint32_t i = 0; i < imageCount; i++) {
    VkImageView attachments[] = {g_imageViews[i]};

    VkFramebufferCreateInfo framebufferInfo = {
        .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
    framebufferInfo.renderPass = g_renderPass;
    framebufferInfo.attachmentCount = 1;
    framebufferInfo.pAttachments = attachments;
    framebufferInfo.width = extent.width;
    framebufferInfo.height = extent.height;
    framebufferInfo.layers = 1;

    if (vkCreateFramebuffer(g_device, &framebufferInfo, NULL,
                            &g_framebuffers[i]) != VK_SUCCESS) {
      LOGE("Failed to create framebuffer %u", i);
      return -1;
    }
  }
  return 0;
}

/** Context for Choreographer vsync-driven frame callback (Phase E) */
typedef struct {
  VkCommandBuffer cmdBuf;
  VkCommandPool cmdPool;
  VkExtent2D extent;
  int frame_count;
  VkSemaphore imageAvailable;
  VkSemaphore renderFinished;
  VkFence inFlightFence;
} RenderFrameCtx;

/** Frame callback invoked at display vsync by AChoreographer (NDK API:
 * frameTimeNanos first, then data) */
static void choreographer_frame_cb(long frameTimeNanos, void *data) {
  (void)frameTimeNanos;
  RenderFrameCtx *ctx = (RenderFrameCtx *)data;
  if (!ctx || !g_running)
    return;

  VkResult res;
  uint32_t imageIndex;

  if (g_core) {
    WWNCoreProcessEvents(g_core);
    /* Drain window events - update g_window_title for TitleChanged */
    CWindowEvent *evt;
    while ((evt = WWNCorePopWindowEvent(g_core)) != NULL) {
      if ((evt->event_type == CWindowEventTypeTitleChanged ||
           evt->event_type == CWindowEventTypeCreated) &&
          evt->title != NULL) {
        pthread_mutex_lock(&g_title_lock);
        strncpy(g_window_title, evt->title, WINDOW_TITLE_MAX - 1);
        g_window_title[WINDOW_TITLE_MAX - 1] = '\0';
        pthread_mutex_unlock(&g_title_lock);
      }
      WWNWindowEventFree(evt);
    }
  }

  vkWaitForFences(g_device, 1, &ctx->inFlightFence, VK_TRUE, UINT64_MAX);

  res = vkAcquireNextImageKHR(g_device, g_swapchain, UINT64_MAX,
                              ctx->imageAvailable, VK_NULL_HANDLE, &imageIndex);
  if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR) {
    if (res != VK_ERROR_OUT_OF_DATE_KHR)
      LOGE("vkAcquireNextImageKHR failed: %d", res);
    goto reschedule;
  }

  vkResetFences(g_device, 1, &ctx->inFlightFence);

  res = vkBeginCommandBuffer(
      ctx->cmdBuf, &(VkCommandBufferBeginInfo){
                       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                       .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT});
  if (res != VK_SUCCESS)
    goto reschedule;

  /* Process pending buffers BEFORE render pass - upload SHM to textures */
  if (g_core) {
    CBufferData *buf;
    while ((buf = WWNCorePopPendingBuffer(g_core)) != NULL) {
      if (buf->pixels && buf->width > 0 && buf->height > 0) {
        renderer_android_cache_buffer(ctx->cmdBuf, buf->buffer_id, buf->width,
                                      buf->height, buf->stride, buf->format,
                                      buf->pixels, buf->size);
      }
      WWNBufferDataFree(buf);
    }
  }

  /* Match CompositorBackground (0x0F1018) to reduce flashing when presenting
   * empty frames or during waypipe client connect. */
  VkClearValue clearValue = {{{15.f / 255.f, 16.f / 255.f, 24.f / 255.f, 1.0f}}};
  VkRenderPassBeginInfo rpbi = {.sType =
                                    VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                                .renderPass = g_renderPass,
                                .framebuffer = g_framebuffers[imageIndex],
                                .renderArea = {{0, 0}, ctx->extent},
                                .clearValueCount = 1,
                                .pClearValues = &clearValue};
  vkCmdBeginRenderPass(ctx->cmdBuf, &rpbi, VK_SUBPASS_CONTENTS_INLINE);

  /* Set viewport and scissor (required for dynamic state) */
  VkViewport viewport = {.x = 0,
                         .y = 0,
                         .width = (float)ctx->extent.width,
                         .height = (float)ctx->extent.height,
                         .minDepth = 0,
                         .maxDepth = 1};
  vkCmdSetViewport(ctx->cmdBuf, 0, 1, &viewport);
  VkRect2D scissor = {{0, 0}, ctx->extent};
  vkCmdSetScissor(ctx->cmdBuf, 0, 1, &scissor);

  /* Draw scene nodes as textured quads; keep scene alive for post-present
   * notifications so buffer releases happen after the frame is submitted. */
  CRenderScene *scene = NULL;
  if (g_core) {
    scene = WWNCoreGetRenderScene(g_core);
    if (scene) {
      if (scene->count > 0) {
        uint64_t new_wid = scene->nodes[0].window_id;
        if (new_wid != g_pointer_window_id) {
          WWNCoreInjectKeyboardLeave(g_core, g_pointer_window_id);
          g_pointer_window_id = new_wid;
          WWNCoreInjectKeyboardEnter(g_core, g_pointer_window_id, NULL, 0, 0);
          LOGI("Auto-focused keyboard on window %llu",
               (unsigned long long)g_pointer_window_id);
        }
        int sf = compute_auto_scale_factor();
        uint32_t logical_w = ctx->extent.width / (uint32_t)sf;
        uint32_t logical_h = ctx->extent.height / (uint32_t)sf;
        if (logical_w == 0) logical_w = 1;
        if (logical_h == 0) logical_h = 1;
        renderer_android_draw_quads(ctx->cmdBuf, scene->nodes, scene->count,
                                    logical_w, logical_h);
      }
      if (scene->has_cursor && scene->cursor_buffer_id > 0) {
        int sf = compute_auto_scale_factor();
        uint32_t logical_w = ctx->extent.width / (uint32_t)sf;
        uint32_t logical_h = ctx->extent.height / (uint32_t)sf;
        if (logical_w == 0) logical_w = 1;
        if (logical_h == 0) logical_h = 1;
        renderer_android_draw_cursor(
            ctx->cmdBuf, scene->cursor_buffer_id, scene->cursor_x,
            scene->cursor_y, scene->cursor_hotspot_x, scene->cursor_hotspot_y,
            logical_w, logical_h);
      }
    }
  }

  vkCmdEndRenderPass(ctx->cmdBuf);
  vkEndCommandBuffer(ctx->cmdBuf);

  VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  VkSubmitInfo submitInfo = {
      .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
      .waitSemaphoreCount = 1,
      .pWaitSemaphores = &ctx->imageAvailable,
      .pWaitDstStageMask = &waitStage,
      .commandBufferCount = 1,
      .pCommandBuffers = &ctx->cmdBuf,
      .signalSemaphoreCount = 1,
      .pSignalSemaphores = &ctx->renderFinished,
  };
  vkQueueSubmit(g_queue, 1, &submitInfo, ctx->inFlightFence);

  VkPresentInfoKHR presentInfo = {
      .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
      .waitSemaphoreCount = 1,
      .pWaitSemaphores = &ctx->renderFinished,
      .swapchainCount = 1,
      .pSwapchains = &g_swapchain,
      .pImageIndices = &imageIndex,
  };
  res = vkQueuePresentKHR(g_queue, &presentInfo);
  if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR &&
      res != VK_ERROR_OUT_OF_DATE_KHR) {
    LOGE("vkQueuePresentKHR failed: %d", res);
  }

  if (g_core && scene) {
    for (size_t i = 0; i < scene->count; i++) {
      CRenderNode *node = &scene->nodes[i];
      WWNCoreNotifyFramePresented(g_core, node->surface_id, node->buffer_id,
                                  (uint32_t)(ctx->frame_count * 16));
    }
    WWNRenderSceneFree(scene);
    WWNCoreFlushClients(g_core);
  }

  ctx->frame_count++;
  if (ctx->frame_count % 300 == 0)
    LOGI("Rendered frame %d (vsync)", ctx->frame_count);

reschedule:
  if (g_running) {
    schedule_next_frame(ctx);
  }
}

/**
 * Render thread - renders frames to the swapchain
 * Uses AChoreographer for vsync-aligned frame timing (Phase E)
 */
static void *render_thread(void *arg) {
  (void)arg;
  LOGI("Render thread started with settings:");
  LOGI("  Force Server-Side Decorations: %s",
       WWNSettings_GetForceServerSideDecorations() ? "enabled" : "disabled");
  LOGI("  Auto Retina Scaling: %s",
       WWNSettings_GetAutoRetinaScalingEnabled() ? "enabled" : "disabled");
  LOGI("  Rendering Backend: %d (0=Automatic, 1=Vulkan, 2=Surface)",
       WWNSettings_GetRenderingBackend());
  LOGI("  Respect Safe Area: %s",
       WWNSettings_GetRespectSafeArea() ? "enabled" : "disabled");
  LOGI("  Safe Area: left=%d, top=%d, right=%d, bottom=%d", g_safeAreaLeft,
       g_safeAreaTop, g_safeAreaRight, g_safeAreaBottom);
  LOGI("  Render macOS Pointer: %s",
       WWNSettings_GetRenderMacOSPointer() ? "enabled" : "disabled");
  LOGI("  Swap Cmd as Ctrl: %s",
       WWNSettings_GetSwapCmdAsCtrl() ? "enabled" : "disabled");
  LOGI("  Universal Clipboard: %s",
       WWNSettings_GetUniversalClipboardEnabled() ? "enabled" : "disabled");
  LOGI("  ColorSync Support: %s",
       WWNSettings_GetColorSyncSupportEnabled() ? "enabled" : "disabled");
  LOGI("  Nested Compositors Support: %s",
       WWNSettings_GetNestedCompositorsSupportEnabled() ? "enabled"
                                                        : "disabled");
  LOGI("  Use Metal 4 for Nested: %s",
       WWNSettings_GetUseMetal4ForNested() ? "enabled" : "disabled");
  LOGI("  Multiple Clients: %s",
       WWNSettings_GetMultipleClientsEnabled() ? "enabled" : "disabled");
  LOGI("  Waypipe RS Support: %s",
       WWNSettings_GetWaypipeRSSupportEnabled() ? "enabled" : "disabled");
  LOGI("  Enable TCP Listener: %s",
       WWNSettings_GetEnableTCPListener() ? "enabled" : "disabled");
  LOGI("  TCP Port: %d", WWNSettings_GetTCPListenerPort());

  // Get swapchain images
  uint32_t imageCount = 0;
  VkResult res =
      vkGetSwapchainImagesKHR(g_device, g_swapchain, &imageCount, NULL);
  if (res != VK_SUCCESS || imageCount == 0) {
    LOGE("Failed to get swapchain images: %d, count=%u", res, imageCount);
    return NULL;
  }

  VkImage *images = malloc(imageCount * sizeof(VkImage));
  res = vkGetSwapchainImagesKHR(g_device, g_swapchain, &imageCount, images);
  if (res != VK_SUCCESS) {
    LOGE("Failed to get swapchain images: %d", res);
    free(images);
    return NULL;
  }

  LOGI("Got %u swapchain images", imageCount);

  VkExtent2D extent;
  if (g_output_width > 0 && g_output_height > 0) {
    extent = (VkExtent2D){.width = g_output_width, .height = g_output_height};
  } else {
    VkSurfaceCapabilitiesKHR caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pick_device(), g_surface, &caps);
    extent = caps.currentExtent;
  }

  // Create Render Pass and Framebuffers
  if (create_image_views(imageCount, images) != 0)
    return NULL;
  if (create_render_pass() != 0)
    return NULL;
  if (create_framebuffers(imageCount, extent) != 0)
    return NULL;

  // Create textured quad pipeline for surface rendering
  if (renderer_android_create_pipeline(g_device, pick_device(), g_renderPass,
                                       g_queue_family, extent.width,
                                       extent.height) != 0) {
    LOGI("Warning: renderer pipeline creation failed, surfaces may not render");
  }

  // Create command pool
  VkCommandPool cmdPool;
  VkCommandPoolCreateInfo cpci = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
  cpci.queueFamilyIndex = g_queue_family;
  cpci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  res = vkCreateCommandPool(g_device, &cpci, NULL, &cmdPool);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create command pool: %d", res);
    free(images);
    return NULL;
  }

  // Create command buffer
  VkCommandBuffer cmdBuf;
  VkCommandBufferAllocateInfo cbai = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
  cbai.commandPool = cmdPool;
  cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  cbai.commandBufferCount = 1;
  res = vkAllocateCommandBuffers(g_device, &cbai, &cmdBuf);
  if (res != VK_SUCCESS) {
    LOGE("Failed to allocate command buffer: %d", res);
    vkDestroyCommandPool(g_device, cmdPool, NULL);
    free(images);
    return NULL;
  }

  // Set output size for the compositor core.
  // If nativeResizeSurface already updated g_output_width/height, only update
  // when the render-thread extent actually differs (avoids clobbering a
  // correct value with a stale caps.currentExtent).
  if (g_output_width != extent.width || g_output_height != extent.height ||
      g_output_width == 0) {
    g_output_width = extent.width;
    g_output_height = extent.height;
    apply_output_scale();
  }

  VkSemaphore imageAvailable = VK_NULL_HANDLE;
  VkSemaphore renderFinished = VK_NULL_HANDLE;
  VkFence inFlightFence = VK_NULL_HANDLE;
  VkSemaphoreCreateInfo semCI = {.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
  VkFenceCreateInfo fenceCI = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                               .flags = VK_FENCE_CREATE_SIGNALED_BIT};
  vkCreateSemaphore(g_device, &semCI, NULL, &imageAvailable);
  vkCreateSemaphore(g_device, &semCI, NULL, &renderFinished);
  vkCreateFence(g_device, &fenceCI, NULL, &inFlightFence);

  RenderFrameCtx frame_ctx = {.cmdBuf = cmdBuf,
                               .cmdPool = cmdPool,
                               .extent = extent,
                               .frame_count = 0,
                               .imageAvailable = imageAvailable,
                               .renderFinished = renderFinished,
                               .inFlightFence = inFlightFence};

  ALooper_prepare(0);
#if __ANDROID_API__ >= 24
  schedule_next_frame(&frame_ctx);

  while (g_running) {
    int ret = ALooper_pollOnce(-1, NULL, NULL, NULL);
    if (ret == ALOOPER_POLL_ERROR)
      break;
  }
#else
  while (g_running) {
    choreographer_frame_cb(0, &frame_ctx);
    usleep(16666);
  }
#endif

  vkDeviceWaitIdle(g_device);
  vkDestroySemaphore(g_device, imageAvailable, NULL);
  vkDestroySemaphore(g_device, renderFinished, NULL);
  vkDestroyFence(g_device, inFlightFence, NULL);
  renderer_android_destroy_pipeline();
  vkFreeCommandBuffers(g_device, cmdPool, 1, &cmdBuf);
  vkDestroyCommandPool(g_device, cmdPool, NULL);
  free(images);

  LOGI("Render thread stopped, rendered %d frames", frame_ctx.frame_count);
  return NULL;
}

// ============================================================================
// JNI Interface
// ============================================================================

/**
 * Initialize the compositor - create Vulkan instance
 * Called from Android Activity.onCreate()
 */
JNIEXPORT void JNICALL Java_com_aspauldingcode_wawona_WawonaNative_nativeInit(
    JNIEnv *env, jobject thiz, jstring cacheDir) {
  (void)thiz;
  pthread_mutex_lock(&g_lock);
  if (g_instance != VK_NULL_HANDLE) {
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Starting Wawona Compositor (Android) - Rust Core + Vulkan");

  // Initialize the Rust compositor core
  if (!g_core) {
    // Set up XDG_RUNTIME_DIR for the Wayland socket (use app cache dir from Java)
    const char *cache_dir = "/data/local/tmp";
    const char *cache_dir_utf = NULL;
    if (cacheDir) {
      cache_dir_utf = (*env)->GetStringUTFChars(env, cacheDir, NULL);
      if (cache_dir_utf)
        cache_dir = cache_dir_utf;
    }
    char runtime_dir[256];
    snprintf(runtime_dir, sizeof(runtime_dir), "%s/wawona-runtime", cache_dir);
    mkdir(runtime_dir, 0700);
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
    setenv("TMPDIR", cache_dir, 1);
    LOGI("XDG_RUNTIME_DIR=%s", runtime_dir);
    if (cache_dir_utf)
      (*env)->ReleaseStringUTFChars(env, cacheDir, cache_dir_utf);

    g_core = WWNCoreNew();
    if (g_core) {
      LOGI("WWNCoreNew() succeeded: %p", g_core);
      if (WWNCoreStart(g_core, "wayland-0")) {
        LOGI("Compositor started on wayland-0");
        setenv("WAYLAND_DISPLAY", "wayland-0", 1);
      } else {
        LOGE("WWNCoreStart() failed");
      }
    } else {
      LOGE("WWNCoreNew() returned NULL");
    }
  }

  VkResult r = create_instance();
  if (r != VK_SUCCESS) {
    pthread_mutex_unlock(&g_lock);
    return;
  }
  uint32_t count = 0;
  VkResult res = vkEnumeratePhysicalDevices(g_instance, &count, NULL);
  LOGI("vkEnumeratePhysicalDevices count=%u, res=%d", count, res);
  pthread_mutex_unlock(&g_lock);
}

/**
 * Set the Android Surface and initialize rendering
 * Called when the SurfaceView is created/updated
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetSurface(JNIEnv *env,
                                                             jobject thiz,
                                                             jobject surface) {
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  LOGI("nativeSetSurface called");

  if (g_window) {
    LOGI("Releasing existing ANativeWindow");
    ANativeWindow_release(g_window);
    g_window = NULL;
  }

  ANativeWindow *win = ANativeWindow_fromSurface(env, surface);
  if (!win) {
    LOGE("ANativeWindow_fromSurface returned NULL");
    pthread_mutex_unlock(&g_lock);
    return;
  }
  g_window = win;
  LOGI("Received ANativeWindow %p", (void *)win);

  // Skip safe area update for now - thiz is WawonaNative object, not Activity
  // Safe area will be updated when settings are applied via nativeApplySettings
  LOGI("Skipping safe area update (will be set via settings)");
  g_safeAreaLeft = 0;
  g_safeAreaTop = 0;
  g_safeAreaRight = 0;
  g_safeAreaBottom = 0;

  if (g_instance == VK_NULL_HANDLE) {
    LOGI("Creating Vulkan instance...");
    if (create_instance() != VK_SUCCESS) {
      LOGE("Failed to create Vulkan instance");
      ANativeWindow_release(win);
      g_window = NULL;
      pthread_mutex_unlock(&g_lock);
      return;
    }
    LOGI("Vulkan instance created");
  } else {
    LOGI("Vulkan instance already exists");
  }

  LOGI("Creating Android surface...");
  VkAndroidSurfaceCreateInfoKHR sci = {
      .sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR};
  sci.window = win;
  VkResult res = vkCreateAndroidSurfaceKHR(g_instance, &sci, NULL, &g_surface);
  if (res != VK_SUCCESS) {
    LOGE("vkCreateAndroidSurfaceKHR failed: %d", res);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Android VkSurfaceKHR created: %p", (void *)g_surface);

  LOGI("Picking Vulkan device...");
  VkPhysicalDevice pd = pick_device();
  if (pd == VK_NULL_HANDLE) {
    LOGE("No Vulkan devices found");
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Vulkan device picked");

  LOGI("Creating Vulkan device...");
  if (create_device(pd) != 0) {
    LOGE("Failed to create device");
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Vulkan device created");

  LOGI("Creating swapchain...");
  if (create_swapchain(pd) != 0) {
    LOGE("Failed to create swapchain");
    vkDestroyDevice(g_device, NULL);
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Swapchain created");

  // Start render thread with brief delay to ensure surface is ready
  LOGI("Starting render thread...");
  g_running = 1;
  usleep(50000); // 50ms delay (was 500ms; resize path uses nativeResizeSurface)
  int thread_result =
      pthread_create(&g_render_thread, NULL, render_thread, NULL);
  if (thread_result != 0) {
    LOGE("Failed to create render thread: %d", thread_result);
    g_running = 0;
    vkDestroySwapchainKHR(g_device, g_swapchain, NULL);
    vkDestroyDevice(g_device, NULL);
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Render thread created successfully");

  LOGI("Wawona Compositor initialized successfully");
  pthread_mutex_unlock(&g_lock);
}

/**
 * Destroy surface and clean up Vulkan resources
 * Called when the SurfaceView is destroyed
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDestroySurface(JNIEnv *env,
                                                                 jobject thiz) {
  (void)env;
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  LOGI("Destroying surface");
  g_running = 0;

  // Wait for render thread to finish
  if (g_render_thread) {
    pthread_join(g_render_thread, NULL);
    g_render_thread = 0;
  }

  // Clean up Vulkan resources
  if (g_device != VK_NULL_HANDLE) {
    vkDeviceWaitIdle(g_device);
  }

  // Clean up Framebuffers
  if (g_framebuffers) {
    for (uint32_t i = 0; i < g_swapchainImageCount; i++) {
      vkDestroyFramebuffer(g_device, g_framebuffers[i], NULL);
    }
    free(g_framebuffers);
    g_framebuffers = NULL;
  }

  // Clean up Render Pass
  if (g_renderPass != VK_NULL_HANDLE) {
    vkDestroyRenderPass(g_device, g_renderPass, NULL);
    g_renderPass = VK_NULL_HANDLE;
  }

  // Clean up Image Views
  if (g_imageViews) {
    for (uint32_t i = 0; i < g_swapchainImageCount; i++) {
      vkDestroyImageView(g_device, g_imageViews[i], NULL);
    }
    free(g_imageViews);
    g_imageViews = NULL;
  }

  if (g_swapchain && g_device) {
    vkDestroySwapchainKHR(g_device, g_swapchain, NULL);
    g_swapchain = VK_NULL_HANDLE;
  }

  if (g_surface && g_instance) {
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    g_surface = VK_NULL_HANDLE;
  }

  if (g_device) {
    vkDestroyDevice(g_device, NULL);
    g_device = VK_NULL_HANDLE;
  }

  if (g_instance) {
    vkDestroyInstance(g_instance, NULL);
    g_instance = VK_NULL_HANDLE;
  }

  if (g_window) {
    ANativeWindow_release(g_window);
    g_window = NULL;
  }

  LOGI("Surface destroyed (compositor core preserved)");
  pthread_mutex_unlock(&g_lock);
}

/**
 * Resize surface — recreate swapchain only, keep Vulkan instance/device/surface.
 * Much faster than destroy+set; avoids blank screen during keyboard show/hide.
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeResizeSurface(JNIEnv *env,
                                                                jobject thiz,
                                                                jint width,
                                                                jint height) {
  (void)env;
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  if (!g_surface || !g_device || !g_window || width <= 0 || height <= 0) {
    LOGI("nativeResizeSurface: skip (need full init or invalid size)");
    pthread_mutex_unlock(&g_lock);
    return;
  }

  LOGI("Resizing surface to %dx%d (swapchain-only)", (int)width, (int)height);

  g_running = 0;
  if (g_render_thread) {
    pthread_join(g_render_thread, NULL);
    g_render_thread = 0;
  }

  if (g_device != VK_NULL_HANDLE)
    vkDeviceWaitIdle(g_device);

  /* Destroy swapchain resources only */
  if (g_framebuffers) {
    for (uint32_t i = 0; i < g_swapchainImageCount; i++)
      vkDestroyFramebuffer(g_device, g_framebuffers[i], NULL);
    free(g_framebuffers);
    g_framebuffers = NULL;
  }
  if (g_imageViews) {
    for (uint32_t i = 0; i < g_swapchainImageCount; i++)
      vkDestroyImageView(g_device, g_imageViews[i], NULL);
    free(g_imageViews);
    g_imageViews = NULL;
  }
  if (g_swapchain && g_device) {
    vkDestroySwapchainKHR(g_device, g_swapchain, NULL);
    g_swapchain = VK_NULL_HANDLE;
  }

  renderer_android_destroy_pipeline();

  ANativeWindow_setBuffersGeometry(g_window, (int32_t)width, (int32_t)height, 0);

  if (create_swapchain_with_extent(g_physicalDevice, (uint32_t)width,
                                  (uint32_t)height) != 0) {
    LOGE("Resize swapchain failed");
    pthread_mutex_unlock(&g_lock);
    return;
  }

  g_output_width = (uint32_t)width;
  g_output_height = (uint32_t)height;
  apply_output_scale();

  g_running = 1;
  int thread_result =
      pthread_create(&g_render_thread, NULL, render_thread, NULL);
  if (thread_result != 0) {
    LOGE("Failed to create render thread after resize: %d", thread_result);
    g_running = 0;
    pthread_mutex_unlock(&g_lock);
    return;
  }

  LOGI("Surface resized successfully (no full teardown)");
  pthread_mutex_unlock(&g_lock);
}

/**
 * Lightweight output-size sync — updates the compositor output dimensions
 * and reconfigures connected clients WITHOUT tearing down the render pipeline.
 * Use this when the view size may have drifted (e.g. after a new waypipe
 * client connects) but the Vulkan swapchain is still valid.
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSyncOutputSize(JNIEnv *env,
                                                                 jobject thiz,
                                                                 jint width,
                                                                 jint height) {
  (void)env;
  (void)thiz;
  if (width <= 0 || height <= 0 || !g_core)
    return;

  uint32_t w = (uint32_t)width;
  uint32_t h = (uint32_t)height;

  if (w == g_output_width && h == g_output_height)
    return;

  LOGI("nativeSyncOutputSize: %ux%u → %ux%u", g_output_width, g_output_height,
       w, h);
  g_output_width = w;
  g_output_height = h;
  apply_output_scale();
}

/**
 * Set the Android display density so auto-scale can compute the right factor.
 * Called from Java before surface setup; density is DisplayMetrics.density
 * (e.g. 2.0 for xhdpi, 2.75 for xxhdpi-420dpi, 3.0 for xxhdpi).
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetDisplayDensity(
    JNIEnv *env, jobject thiz, jfloat density) {
  (void)env;
  (void)thiz;
  g_display_density = density;
  LOGI("Display density set to %.3f", (double)density);
  apply_output_scale();
}

/**
 * Final shutdown — tears down the compositor core.
 * Called from Activity.onDestroy(), NOT from surface lifecycle callbacks.
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeShutdown(JNIEnv *env,
                                                           jobject thiz) {
  (void)env;
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  if (g_core) {
    LOGI("Shutting down compositor core...");
    WWNCoreStop(g_core);
    WWNCoreFree(g_core);
    g_core = NULL;
  }

  LOGI("Compositor shutdown complete");
  pthread_mutex_unlock(&g_lock);
}

/**
 * Update safe area insets from Android WindowInsets API
 * Called directly from Kotlin to avoid complex JNI reflection
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeUpdateSafeArea(
    JNIEnv *env, jobject thiz, jint left, jint top, jint right, jint bottom) {
  (void)env;
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  g_rawSafeAreaLeft = left;
  g_rawSafeAreaTop = top;
  g_rawSafeAreaRight = right;
  g_rawSafeAreaBottom = bottom;

  if (WWNSettings_GetRespectSafeArea()) {
    g_safeAreaLeft = left;
    g_safeAreaTop = top;
    g_safeAreaRight = right;
    g_safeAreaBottom = bottom;
    LOGI("JNI Update Safe Area: Applied (L=%d, T=%d, R=%d, B=%d)", left, top,
         right, bottom);
  } else {
    g_safeAreaLeft = 0;
    g_safeAreaTop = 0;
    g_safeAreaRight = 0;
    g_safeAreaBottom = 0;
    LOGI("JNI Update Safe Area: Cached (L=%d, T=%d, R=%d, B=%d), but disabled",
         left, top, right, bottom);
  }
  /* Push to Rust backend for layer-shell exclusive zones etc. */
  if (g_core) {
    WWNCoreSetSafeAreaInsets(g_core, g_safeAreaTop, g_safeAreaRight,
                             g_safeAreaBottom, g_safeAreaLeft);
  }
  pthread_mutex_unlock(&g_lock);
}

/**
 * Apply iOS-compatible settings
 * Provides 1:1 mapping of iOS settings for cross-platform compatibility
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeApplySettings(
    JNIEnv *env, jobject thiz, jboolean forceServerSideDecorations,
    jboolean autoRetinaScaling, jint renderingBackend, jboolean respectSafeArea,
    jboolean renderMacOSPointer, jboolean swapCmdAsCtrl,
    jboolean universalClipboard, jboolean colorSyncSupport,
    jboolean nestedCompositorsSupport, jboolean useMetal4ForNested,
    jboolean multipleClients, jboolean waypipeRSSupport,
    jboolean enableTCPListener, jint tcpPort, jstring vulkanDriver,
    jstring openglDriver) {
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  LOGI("Applying Wawona settings:");
  LOGI("  Force Server-Side Decorations: %s",
       forceServerSideDecorations ? "enabled" : "disabled");
  LOGI("  Auto Retina Scaling: %s", autoRetinaScaling ? "enabled" : "disabled");
  LOGI("  Rendering Backend: %d (0=Automatic, 1=Vulkan, 2=Surface)",
       renderingBackend);
  LOGI("  Respect Safe Area: %s", respectSafeArea ? "enabled" : "disabled");
  LOGI("  Render Software Pointer: %s",
       renderMacOSPointer ? "enabled" : "disabled");
  LOGI("  Swap Cmd as Ctrl: %s", swapCmdAsCtrl ? "enabled" : "disabled");
  LOGI("  Universal Clipboard: %s",
       universalClipboard ? "enabled" : "disabled");
  LOGI("  ColorSync Support: %s", colorSyncSupport ? "enabled" : "disabled");
  LOGI("  Nested Compositors Support: %s",
       nestedCompositorsSupport ? "enabled" : "disabled");
  LOGI("  Use Metal 4 for Nested: %s",
       useMetal4ForNested ? "enabled" : "disabled");
  LOGI("  Multiple Clients: %s", multipleClients ? "enabled" : "disabled");
  LOGI("  Waypipe RS Support: %s", waypipeRSSupport ? "enabled" : "disabled");
  LOGI("  Enable TCP Listener: %s", enableTCPListener ? "enabled" : "disabled");
  LOGI("  TCP Port: %d", tcpPort);

  char vulkanDriverBuf[32] = {0};
  char openglDriverBuf[32] = {0};
  if (vulkanDriver) {
    const char *s = (*env)->GetStringUTFChars(env, vulkanDriver, NULL);
    if (s) {
      strncpy(vulkanDriverBuf, s, sizeof(vulkanDriverBuf) - 1);
      (*env)->ReleaseStringUTFChars(env, vulkanDriver, s);
    }
  }
  if (openglDriver) {
    const char *s = (*env)->GetStringUTFChars(env, openglDriver, NULL);
    if (s) {
      strncpy(openglDriverBuf, s, sizeof(openglDriverBuf) - 1);
      (*env)->ReleaseStringUTFChars(env, openglDriver, s);
    }
  }
  LOGI("  Vulkan Driver: %s", vulkanDriverBuf[0] ? vulkanDriverBuf : "system");
  LOGI("  OpenGL Driver: %s", openglDriverBuf[0] ? openglDriverBuf : "system");

  // Apply settings
  WWNSettingsConfig config = {
      .forceServerSideDecorations = forceServerSideDecorations,
      .autoRetinaScaling = autoRetinaScaling,
      .renderingBackend = renderingBackend,
      .respectSafeArea = respectSafeArea,
      .renderMacOSPointer = renderMacOSPointer,
      .swapCmdAsCtrl = swapCmdAsCtrl,
      .universalClipboard = universalClipboard,
      .colorSyncSupport = colorSyncSupport,
      .nestedCompositorsSupport = nestedCompositorsSupport,
      .useMetal4ForNested = useMetal4ForNested,
      .multipleClients = multipleClients,
      .waypipeRSSupport = waypipeRSSupport,
      .enableTCPListener = enableTCPListener,
      .tcpPort = tcpPort,
      .vulkanDrivers = false,
      .eglDrivers = false};
  strncpy(config.vulkanDriver, vulkanDriverBuf[0] ? vulkanDriverBuf : "system",
          sizeof(config.vulkanDriver) - 1);
  config.vulkanDriver[sizeof(config.vulkanDriver) - 1] = '\0';
  strncpy(config.openglDriver, openglDriverBuf[0] ? openglDriverBuf : "system",
          sizeof(config.openglDriver) - 1);
  config.openglDriver[sizeof(config.openglDriver) - 1] = '\0';
  WWNSettings_UpdateConfig(&config);

  /* Push to Rust backend */
  if (g_core) {
    WWNCoreSetForceSSD(g_core, forceServerSideDecorations ? 1 : 0);
    WWNCoreSetSafeAreaInsets(g_core, g_safeAreaTop, g_safeAreaRight,
                             g_safeAreaBottom, g_safeAreaLeft);
  }

  // Update safe area based on new setting
  if (respectSafeArea) {
    g_safeAreaLeft = g_rawSafeAreaLeft;
    g_safeAreaTop = g_rawSafeAreaTop;
    g_safeAreaRight = g_rawSafeAreaRight;
    g_safeAreaBottom = g_rawSafeAreaBottom;
  } else {
    g_safeAreaLeft = 0;
    g_safeAreaTop = 0;
    g_safeAreaRight = 0;
    g_safeAreaBottom = 0;
  }

  LOGI("Safe area updated based on settings: %s (L=%d, T=%d, R=%d, B=%d)",
       respectSafeArea ? "enabled" : "disabled", g_safeAreaLeft, g_safeAreaTop,
       g_safeAreaRight, g_safeAreaBottom);

  // Reapply output scale (auto-scale toggle may have changed)
  apply_output_scale();

  LOGI("Wawona settings applied successfully with safe area support");
  pthread_mutex_unlock(&g_lock);
}

// ============================================================================
// JNI Initialization
// ============================================================================

static int pfd[2];
static pthread_t thr;
static const char *tag = "Wawona-Stdout";

static void *thread_func(void *arg) {
  ssize_t rdsz;
  char buf[128];
  while ((rdsz = read(pfd[0], buf, sizeof buf - 1)) > 0) {
    if (buf[rdsz - 1] == '\n')
      --rdsz;
    buf[rdsz] = 0; /* add null-terminator */
    __android_log_write(ANDROID_LOG_DEBUG, tag, buf);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Text Input (IME / Emoji) — forward composed text to Wayland text-input-v3
// ---------------------------------------------------------------------------

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetCore(JNIEnv *env,
                                                          jobject thiz,
                                                          jlong corePtr) {
  (void)env;
  (void)thiz;
  pthread_mutex_lock(&g_lock);
  g_core = (void *)(intptr_t)corePtr;
  LOGI("Compositor core pointer set: %p", g_core);
  pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeCommitText(JNIEnv *env,
                                                             jobject thiz,
                                                             jstring text) {
  (void)thiz;
  const char *utf8 = (*env)->GetStringUTFChars(env, text, NULL);
  if (!utf8)
    return;
  LOGI("Text input commit: %s", utf8);
  if (!g_core) {
    (*env)->ReleaseStringUTFChars(env, text, utf8);
    return;
  }

  /* Check whether every character has a Linux keycode mapping (mirrors the
   * iOS allMappable check in insertText:). */
  int all_mappable = 1;
  for (const char *p = utf8; *p; p++) {
    if ((unsigned char)*p > 127) {
      all_mappable = 0;
      break;
    }
    int ns;
    if (char_to_linux_keycode(*p, &ns) == 0) {
      all_mappable = 0;
      break;
    }
  }

  if (!all_mappable) {
    /* Non-ASCII or unmappable — use text-input-v3 (emoji, CJK, etc.) */
    WWNCoreTextInputCommit(g_core, utf8);
    (*env)->ReleaseStringUTFChars(env, text, utf8);
    return;
  }

  /* All characters are mappable — synthesize wl_keyboard.key events for
   * maximum compatibility (same pattern as iOS charToLinuxKeycode path).
   * This ensures remote clients via waypipe that only speak wl_keyboard
   * still receive the input.
   *
   * Modifier state is driven entirely by the Shift key press/release —
   * the Rust core's XKB state machine (update_key) updates the
   * depressed/latched/locked mask automatically. */
  uint32_t ts = 0;
  for (const char *p = utf8; *p; p++) {
    int needs_shift = 0;
    uint32_t kc = char_to_linux_keycode(*p, &needs_shift);
    if (kc == 0)
      continue;
    if (needs_shift)
      WWNCoreInjectKey(g_core, WWN_KEY_LEFTSHIFT, 1, ts);
    WWNCoreInjectKey(g_core, kc, 1, ts);
    WWNCoreInjectKey(g_core, kc, 0, ts);
    if (needs_shift)
      WWNCoreInjectKey(g_core, WWN_KEY_LEFTSHIFT, 0, ts);
  }
  (*env)->ReleaseStringUTFChars(env, text, utf8);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePreeditText(
    JNIEnv *env, jobject thiz, jstring text, jint cursorBegin, jint cursorEnd) {
  (void)thiz;
  const char *utf8 = (*env)->GetStringUTFChars(env, text, NULL);
  if (!utf8)
    return;
  LOGI("Text input preedit: %s [%d..%d]", utf8, cursorBegin, cursorEnd);
  if (g_core)
    WWNCoreTextInputPreedit(g_core, utf8, cursorBegin, cursorEnd);
  (*env)->ReleaseStringUTFChars(env, text, utf8);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDeleteSurroundingText(
    JNIEnv *env, jobject thiz, jint beforeLength, jint afterLength) {
  (void)env;
  (void)thiz;
  LOGI("Text input delete surrounding: before=%d after=%d", beforeLength,
       afterLength);
  if (g_core)
    WWNCoreTextInputDeleteSurrounding(g_core, (uint32_t)beforeLength,
                                      (uint32_t)afterLength);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetCursorRect(
    JNIEnv *env, jobject thiz, jintArray outRect) {
  (void)thiz;
  if (!outRect)
    return;
  jsize len = (*env)->GetArrayLength(env, outRect);
  if (len < 4)
    return;
  int32_t x = 0, y = 0, w = 0, h = 0;
  if (g_core)
    WWNCoreTextInputGetCursorRect(g_core, &x, &y, &w, &h);
  int sf = compute_auto_scale_factor();
  jint buf[4] = {x * sf, y * sf, w * sf, h * sf};
  (*env)->SetIntArrayRegion(env, outRect, 0, 4, buf);
}

// ============================================================================
// Touch / Key Input Forwarding
// ============================================================================

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchDown(
    JNIEnv *env, jobject thiz, jint id, jfloat x, jfloat y, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    int sf = compute_auto_scale_factor();
    g_active_touches++;
    WWNCoreInjectTouchDown(g_core, id, (double)x / sf, (double)y / sf,
                           (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchUp(JNIEnv *env,
                                                          jobject thiz, jint id,
                                                          jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectTouchUp(g_core, id, (uint32_t)timestampMs);
    g_active_touches--;
    if (g_active_touches < 0) {
      g_active_touches = 0;
    }
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchMotion(
    JNIEnv *env, jobject thiz, jint id, jfloat x, jfloat y, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    int sf = compute_auto_scale_factor();
    WWNCoreInjectTouchMotion(g_core, id, (double)x / sf, (double)y / sf,
                             (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchCancel(JNIEnv *env,
                                                              jobject thiz) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectTouchCancel(g_core);
    g_active_touches = 0;
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchFrame(JNIEnv *env,
                                                             jobject thiz) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInject_touch_frame(g_core);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeKeyEvent(
    JNIEnv *env, jobject thiz, jint keycode, jint state, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;

  uint32_t linux_keycode = android_keycode_to_linux((uint32_t)keycode);

  /* Let the Rust core's XKB state machine (update_key) handle modifier
   * tracking automatically.  We intentionally do NOT call
   * WWNCoreInjectModifiers here — mixing update_mask with update_key
   * corrupts XKB's internal key-tracking state and prevents modifier
   * releases from clearing correctly. */
  WWNCoreInjectKey(g_core, linux_keycode, (uint32_t)state,
                   (uint32_t)timestampMs);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeInjectKey(
    JNIEnv *env, jobject thiz, jint linuxKeycode, jboolean pressed,
    jint timestampMs) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;
  WWNCoreInjectKey(g_core, (uint32_t)linuxKeycode, pressed ? 1u : 0u,
                  (uint32_t)timestampMs);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeInjectModifiers(
    JNIEnv *env, jobject thiz, jint depressed, jint latched, jint locked,
    jint group) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;
  g_modifiers_depressed = (uint32_t)depressed;
  WWNCoreInjectModifiers(g_core, (uint32_t)depressed, (uint32_t)latched,
                        (uint32_t)locked, (uint32_t)group);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerAxis(
    JNIEnv *env, jobject thiz, jint axis, jfloat value, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core && value != 0.0f) {
    /* axis: 0 = vertical, 1 = horizontal */
    WWNCoreInjectPointerAxis(g_core, g_pointer_window_id, (uint32_t)axis,
                             (double)value, (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerMotion(
    JNIEnv *env, jobject thiz, jdouble x, jdouble y, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    int sf = compute_auto_scale_factor();
    WWNCoreInjectPointerMotion(g_core, g_pointer_window_id, x / sf, y / sf,
                               (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerButton(
    JNIEnv *env, jobject thiz, jint buttonCode, jint state, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    /* buttonCode: 0x110 = BTN_LEFT, 0x111 = BTN_RIGHT */
    WWNCoreInjectPointerButton(g_core, g_pointer_window_id,
                               (uint32_t)buttonCode, (uint32_t)state,
                               (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerEnter(
    JNIEnv *env, jobject thiz, jdouble x, jdouble y, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    int sf = compute_auto_scale_factor();
    WWNCoreInjectPointerEnter(g_core, g_pointer_window_id, x / sf, y / sf,
                              (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerLeave(
    JNIEnv *env, jobject thiz, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectPointerLeave(g_core, g_pointer_window_id,
                              (uint32_t)timestampMs);
  }
}

JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetFocusedWindowTitle(
    JNIEnv *env, jobject thiz) {
  (void)thiz;
  pthread_mutex_lock(&g_title_lock);
  jstring result =
      (*env)->NewStringUTF(env, g_window_title[0] ? g_window_title : "");
  pthread_mutex_unlock(&g_title_lock);
  return result;
}

JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetPendingScreencopy(
    JNIEnv *env, jobject thiz, jintArray outWidthHeight) {
  (void)thiz;
  jlong capture_id = 0;
  if (!g_core)
    return 0;
  CScreencopyRequest req = WWNCoreGetPendingScreencopy(g_core);
  if (req.capture_id == 0 || req.ptr == NULL)
    return 0;
  g_screencopy_ptr = req.ptr;
  g_screencopy_stride = req.stride;
  g_screencopy_size = req.size;
  capture_id = (jlong)req.capture_id;
  if (outWidthHeight && (*env)->GetArrayLength(env, outWidthHeight) >= 3) {
    jint whs[3] = {(jint)req.width, (jint)req.height, (jint)req.stride};
    (*env)->SetIntArrayRegion(env, outWidthHeight, 0, 3, whs);
  } else if (outWidthHeight &&
             (*env)->GetArrayLength(env, outWidthHeight) >= 2) {
    jint wh[2] = {(jint)req.width, (jint)req.height};
    (*env)->SetIntArrayRegion(env, outWidthHeight, 0, 2, wh);
  }
  return capture_id;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeScreencopyComplete(
    JNIEnv *env, jobject thiz, jlong captureId, jbyteArray pixels) {
  (void)thiz;
  if (!g_core || g_screencopy_ptr == NULL || !pixels)
    return;
  jsize len = (*env)->GetArrayLength(env, pixels);
  if ((size_t)len > g_screencopy_size)
    len = (jsize)g_screencopy_size;
  jbyte *src = (*env)->GetByteArrayElements(env, pixels, NULL);
  if (src) {
    memcpy(g_screencopy_ptr, src, (size_t)len);
    (*env)->ReleaseByteArrayElements(env, pixels, src, JNI_ABORT);
  }
  WWNCoreScreencopyDone(g_core, (uint64_t)captureId);
  g_screencopy_ptr = NULL;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeScreencopyFailed(
    JNIEnv *env, jobject thiz, jlong captureId) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;
  WWNCoreScreencopyFailed(g_core, (uint64_t)captureId);
  g_screencopy_ptr = NULL;
}

JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetPendingImageCopyCapture(
    JNIEnv *env, jobject thiz, jintArray outWidthHeight) {
  (void)thiz;
  jlong capture_id = 0;
  if (!g_core)
    return 0;
  CScreencopyRequest req = WWNCoreGetPendingImageCopyCapture(g_core);
  if (req.capture_id == 0 || req.ptr == NULL)
    return 0;
  g_screencopy_ptr = req.ptr;
  g_screencopy_stride = req.stride;
  g_screencopy_size = req.size;
  capture_id = (jlong)req.capture_id;
  if (outWidthHeight && (*env)->GetArrayLength(env, outWidthHeight) >= 3) {
    jint whs[3] = {(jint)req.width, (jint)req.height, (jint)req.stride};
    (*env)->SetIntArrayRegion(env, outWidthHeight, 0, 3, whs);
  } else if (outWidthHeight &&
             (*env)->GetArrayLength(env, outWidthHeight) >= 2) {
    jint wh[2] = {(jint)req.width, (jint)req.height};
    (*env)->SetIntArrayRegion(env, outWidthHeight, 0, 2, wh);
  }
  return capture_id;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeImageCopyCaptureComplete(
    JNIEnv *env, jobject thiz, jlong captureId, jbyteArray pixels) {
  (void)thiz;
  if (!g_core || g_screencopy_ptr == NULL || !pixels)
    return;
  jsize len = (*env)->GetArrayLength(env, pixels);
  if ((size_t)len > g_screencopy_size)
    len = (jsize)g_screencopy_size;
  jbyte *src = (*env)->GetByteArrayElements(env, pixels, NULL);
  if (src) {
    memcpy(g_screencopy_ptr, src, (size_t)len);
    (*env)->ReleaseByteArrayElements(env, pixels, src, JNI_ABORT);
  }
  WWNCoreImageCopyCaptureDone(g_core, (uint64_t)captureId);
  g_screencopy_ptr = NULL;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeImageCopyCaptureFailed(
    JNIEnv *env, jobject thiz, jlong captureId) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;
  WWNCoreImageCopyCaptureFailed(g_core, (uint64_t)captureId);
  g_screencopy_ptr = NULL;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeKeyboardFocus(
    JNIEnv *env, jobject thiz, jboolean hasFocus) {
  (void)env;
  (void)thiz;
  if (!g_core || g_pointer_window_id == 0)
    return;
  if (hasFocus) {
    WWNCoreInjectKeyboardEnter(g_core, g_pointer_window_id, NULL, 0, 0);
  } else {
    WWNCoreInjectKeyboardLeave(g_core, g_pointer_window_id);
  }
}

// ============================================================================
// Waypipe Integration
// ============================================================================

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static char g_ssh_bin_path[512] = {0};
static char g_sshpass_bin_path[512] = {0};

static void resolve_ssh_binary_paths(void) {
  if (g_ssh_bin_path[0])
    return;

  Dl_info info;
  if (dladdr((void *)resolve_ssh_binary_paths, &info) && info.dli_fname) {
    char nativeLibDir[512];
    strncpy(nativeLibDir, info.dli_fname, sizeof(nativeLibDir) - 1);
    char *lastSlash = strrchr(nativeLibDir, '/');
    if (lastSlash)
      *lastSlash = '\0';

    LOGI("[SSH] Native lib dir: %s", nativeLibDir);

    char sshPath[512], sshpassPath[512];
    snprintf(sshPath, sizeof(sshPath), "%s/libssh_bin.so", nativeLibDir);
    snprintf(sshpassPath, sizeof(sshpassPath), "%s/libsshpass_bin.so",
             nativeLibDir);

    /*
     * On Android Q+ (API 29+), apps cannot execute binaries from app-private
     * dirs (cache, files) due to W^X — exec fails with "Permission denied".
     * Use the native lib dir directly (/data/app/.../lib/arm64/): system-
     * extracted from APK, executable by design (extractNativeLibs=true).
     */
    struct stat st;
    if (stat(sshPath, &st) == 0) {
      strncpy(g_ssh_bin_path, sshPath, sizeof(g_ssh_bin_path) - 1);
      LOGI("[SSH] Using ssh from native lib: %s", g_ssh_bin_path);
    } else {
      LOGE("[SSH] libssh_bin.so not found at %s: %s", sshPath, strerror(errno));
    }
    if (stat(sshpassPath, &st) == 0) {
      strncpy(g_sshpass_bin_path, sshpassPath, sizeof(g_sshpass_bin_path) - 1);
      LOGI("[SSH] Using sshpass from native lib: %s", g_sshpass_bin_path);
    } else {
      LOGE("[SSH] libsshpass_bin.so not found at %s: %s", sshpassPath,
           strerror(errno));
    }
  } else {
    LOGE("[SSH] dladdr failed - cannot locate native lib directory");
  }
}

static volatile int g_waypipe_running = 0;
static pthread_t g_waypipe_thread = 0;
static volatile int g_waypipe_stop_requested = 0;

typedef struct {
  int ssh_enabled;
  char ssh_host[256];
  char ssh_user[128];
  char ssh_password[256];
  char remote_command[512];
  char compress[64];
  int threads;
  char video[64];
  int debug;
  int ssh_port;
  int oneshot;
  int no_gpu;
  int login_shell;
  char title_prefix[128];
  char sec_ctx[128];
} WaypipeConfig;

static WaypipeConfig g_waypipe_config;


static void *waypipe_thread_func(void *arg) {
  (void)arg;
  resolve_ssh_binary_paths();
  LOGI("Waypipe thread started");
  LOGI("  SSH: %s", g_waypipe_config.ssh_enabled ? "enabled" : "disabled");
  if (g_waypipe_config.ssh_enabled) {
    LOGI("  Host: %s", g_waypipe_config.ssh_host);
    LOGI("  User: %s", g_waypipe_config.ssh_user);
    LOGI("  Remote Command: %s", g_waypipe_config.remote_command);
  }
  LOGI("  Compression: %s", g_waypipe_config.compress);
  LOGI("  Threads: %d", g_waypipe_config.threads);
  LOGI("  Debug: %s", g_waypipe_config.debug ? "yes" : "no");
  LOGI("  Oneshot: %s", g_waypipe_config.oneshot ? "yes" : "no");
  LOGI("  No GPU: %s", g_waypipe_config.no_gpu ? "yes" : "no");

  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  LOGI("XDG_RUNTIME_DIR=%s  WAYLAND_DISPLAY=%s", xdg_dir ? xdg_dir : "(null)",
       getenv("WAYLAND_DISPLAY") ? getenv("WAYLAND_DISPLAY") : "(null)");

  // Build waypipe argv
  const char *argv[64];
  int argc = 0;
  argv[argc++] = "waypipe";

  if (g_waypipe_config.compress[0]) {
    argv[argc++] = "--compress";
    argv[argc++] = g_waypipe_config.compress;
  }

  char threads_str[16];
  if (g_waypipe_config.threads > 0) {
    argv[argc++] = "--threads";
    snprintf(threads_str, sizeof(threads_str), "%d", g_waypipe_config.threads);
    argv[argc++] = threads_str;
  }

  if (g_waypipe_config.oneshot || g_waypipe_config.ssh_enabled) {
    argv[argc++] = "--oneshot";
  }

  /* Android lacks accessible DRM render nodes; always disable the GPU/DMABUF
   * path so waypipe negotiates CPU-side shm copies instead of trying to import
   * DMA-BUF handles that will fail on the Android side. */
  argv[argc++] = "--no-gpu";

  if (g_waypipe_config.login_shell) {
    argv[argc++] = "--login-shell";
  }

  if (g_waypipe_config.debug) {
    argv[argc++] = "--debug";
  }

  if (g_waypipe_config.title_prefix[0]) {
    argv[argc++] = "--title-prefix";
    argv[argc++] = g_waypipe_config.title_prefix;
  }

  if (g_waypipe_config.sec_ctx[0]) {
    argv[argc++] = "--secctx";
    argv[argc++] = g_waypipe_config.sec_ctx;
  }

  int result;

  if (g_waypipe_config.ssh_enabled && g_waypipe_config.ssh_host[0]) {
    // ── SSH mode ──
    // Uses waypipe's native "ssh" subcommand. Waypipe creates a local Unix
    // socket, spawns the SSH client with -R /remote.sock:/local.sock, and
    // the remote waypipe server connects back through the SSH tunnel.
    // Dropbear (dbclient) is patched to support -R with Unix socket paths
    // via streamlocal-forward@openssh.com.

    if (!g_ssh_bin_path[0]) {
      LOGE("SSH binary (libssh_bin.so) not found — cannot start waypipe SSH");
      return NULL;
    }

    static char quoted_rcmd[520];
    const char *raw_rcmd = g_waypipe_config.remote_command[0]
                               ? g_waypipe_config.remote_command
                               : "weston-terminal";
    snprintf(quoted_rcmd, sizeof(quoted_rcmd), "\"%s\"", raw_rcmd);
    const char *rcmd = quoted_rcmd;

    static char port_str[16];
    int ssh_port = g_waypipe_config.ssh_port > 0 ? g_waypipe_config.ssh_port : 22;
    snprintf(port_str, sizeof(port_str), "%d", ssh_port);

    if (g_waypipe_config.ssh_password[0]) {
      setenv("SSHPASS", g_waypipe_config.ssh_password, 1);
    }

    {
      const char *xdg = getenv("XDG_RUNTIME_DIR");
      if (xdg)
        setenv("HOME", xdg, 1);
    }

    /* --socket sets the LOCAL (client) socket prefix; waypipe appends
     * "-client-RAND.sock".  Using a relative path works because we chdir to
     * XDG_RUNTIME_DIR before calling waypipe_main, so the socket lands there. */
    static char wp_socket_prefix[] = "./waypipe";
    argv[argc++] = "--socket";
    argv[argc++] = wp_socket_prefix;

    /* --remote-socket sets the SERVER socket prefix used on the remote Linux
     * host.  It must be an absolute path so OpenSSH sshd can create the
     * streamlocal socket.  This also appears in the remote "waypipe --socket"
     * command, so it must be a path that is valid on the remote machine. */
    static char wp_remote_socket_prefix[] = "/tmp/waypipe";
    argv[argc++] = "--remote-socket";
    argv[argc++] = wp_remote_socket_prefix;

    argv[argc++] = "--ssh-bin";
    argv[argc++] = g_ssh_bin_path;
    argv[argc++] = "ssh";
    argv[argc++] = "-y";
    argv[argc++] = "-T";
    argv[argc++] = "-p";
    argv[argc++] = port_str;
    argv[argc++] = "-l";
    argv[argc++] = g_waypipe_config.ssh_user;
    argv[argc++] = g_waypipe_config.ssh_host;
    /* Dropbear does not support "--" (OpenSSH option separator); omit it */
    argv[argc++] = rcmd;
    argv[argc] = NULL;

    {
      const char *wl_disp = getenv("WAYLAND_DISPLAY");
      if (xdg_dir && wl_disp) {
        char comp_sock[512];
        snprintf(comp_sock, sizeof(comp_sock), "%s/%s", xdg_dir, wl_disp);
        struct stat st;
        if (stat(comp_sock, &st) == 0) {
          LOGI("Compositor socket OK: %s (mode=%o)", comp_sock, st.st_mode);
        } else {
          LOGE("Compositor socket MISSING: %s: %s", comp_sock, strerror(errno));
        }
      }
    }

    LOGI("Calling waypipe_main (ssh mode) with %d args:", argc);
    for (int i = 0; i < argc; i++) {
      LOGI("  argv[%d] = %s", i, argv[i]);
    }

    char saved_cwd[512] = "";
    if (xdg_dir) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      if (chdir(xdg_dir) == 0) {
        LOGI("chdir to %s for waypipe", xdg_dir);
      } else {
        LOGE("chdir to %s failed: %s", xdg_dir, strerror(errno));
      }
    }

    setenv("RUST_BACKTRACE", "full", 1);
    if (xdg_dir) {
      setenv("TMPDIR", xdg_dir, 1);
    }

    char stderr_log[512];
    snprintf(stderr_log, sizeof(stderr_log), "%s/waypipe-stderr.log",
             xdg_dir ? xdg_dir : "/data/local/tmp");
    int log_fd = open(stderr_log, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int saved_stderr = -1;
    if (log_fd >= 0) {
      saved_stderr = dup(STDERR_FILENO);
      dup2(log_fd, STDERR_FILENO);
      close(log_fd);
      setvbuf(stderr, NULL, _IONBF, 0); /* unbuffered so log viewer can refresh live */
    }

    if (!waypipe_main) {
      LOGE("waypipe_main is unavailable in this build");
      result = -1;
    } else {
      result = waypipe_main(argc, argv);
    }

    if (saved_stderr >= 0) {
      dup2(saved_stderr, STDERR_FILENO);
      close(saved_stderr);
    }
    LOGI("waypipe_main (ssh) returned %d", result);

    {
      int rfd = open(stderr_log, O_RDONLY);
      if (rfd >= 0) {
        char errbuf[4096];
        ssize_t n = read(rfd, errbuf, sizeof(errbuf) - 1);
        if (n > 0) {
          errbuf[n] = '\0';
          LOGI("waypipe stderr:\n%s", errbuf);
        } else {
          LOGI("waypipe produced no stderr output");
        }
        close(rfd);
      }
    }

    if (saved_cwd[0])
      chdir(saved_cwd);

  } else {
    // Non-SSH mode: run waypipe as a client with a local socket.
    // waypipe requires a subcommand (client/server) to function.
    if (xdg_dir) {
      setenv("TMPDIR", xdg_dir, 1);
    }
    static char wp_socket_path_local[512];
    snprintf(wp_socket_path_local, sizeof(wp_socket_path_local),
             "%s/waypipe-local.sock", xdg_dir ? xdg_dir : "/data/local/tmp");
    unlink(wp_socket_path_local);

    argv[argc++] = "--socket";
    argv[argc++] = wp_socket_path_local;
    argv[argc++] = "client";

    char saved_cwd2[512] = "";
    if (xdg_dir) {
      getcwd(saved_cwd2, sizeof(saved_cwd2));
      chdir(xdg_dir);
    }
    argv[argc] = NULL;
    LOGI("Calling waypipe_main with %d args:", argc);
    for (int i = 0; i < argc; i++) {
      LOGI("  argv[%d] = %s", i, argv[i]);
    }
    if (!waypipe_main) {
      LOGE("waypipe_main is unavailable in this build");
      result = -1;
    } else {
      result = waypipe_main(argc, argv);
    }
    LOGI("waypipe_main returned %d", result);
    if (saved_cwd2[0])
      chdir(saved_cwd2);
    unlink(wp_socket_path_local);
  }

  g_waypipe_running = 0;
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWaypipe(
    JNIEnv *env, jobject thiz, jboolean sshEnabled, jstring sshHost,
    jstring sshUser, jstring sshPassword, jstring remoteCommand,
    jstring compress, jint threads, jstring video, jboolean debug,
    jboolean oneshot, jboolean noGpu, jboolean loginShell, jstring titlePrefix,
    jstring secCtx) {
  (void)thiz;

  if (g_waypipe_running) {
    LOGE("Waypipe is already running");
    return JNI_FALSE;
  }

  memset(&g_waypipe_config, 0, sizeof(g_waypipe_config));
  g_waypipe_config.ssh_enabled = sshEnabled;
  g_waypipe_config.threads = threads;
  g_waypipe_config.debug = debug;
  g_waypipe_config.oneshot = oneshot;
  g_waypipe_config.no_gpu = noGpu;
  g_waypipe_config.login_shell = loginShell;

  const char *str;

  str = (*env)->GetStringUTFChars(env, sshHost, NULL);
  if (str) {
    /* Support "host:port" syntax — parse port if present */
    const char *colon = strrchr(str, ':');
    long parsed_port = 0;
    if (colon && colon != str) {
      char *end = NULL;
      parsed_port = strtol(colon + 1, &end, 10);
      if (end && *end == '\0' && parsed_port > 0 && parsed_port < 65536) {
        /* Valid port — copy only the host part */
        size_t hostlen = (size_t)(colon - str);
        if (hostlen >= sizeof(g_waypipe_config.ssh_host))
          hostlen = sizeof(g_waypipe_config.ssh_host) - 1;
        memcpy(g_waypipe_config.ssh_host, str, hostlen);
        g_waypipe_config.ssh_host[hostlen] = '\0';
        g_waypipe_config.ssh_port = (int)parsed_port;
      } else {
        strncpy(g_waypipe_config.ssh_host, str,
                sizeof(g_waypipe_config.ssh_host) - 1);
        g_waypipe_config.ssh_port = 22;
      }
    } else {
      strncpy(g_waypipe_config.ssh_host, str,
              sizeof(g_waypipe_config.ssh_host) - 1);
      g_waypipe_config.ssh_port = 22;
    }
    (*env)->ReleaseStringUTFChars(env, sshHost, str);
  }

  str = (*env)->GetStringUTFChars(env, sshUser, NULL);
  if (str) {
    strncpy(g_waypipe_config.ssh_user, str,
            sizeof(g_waypipe_config.ssh_user) - 1);
    (*env)->ReleaseStringUTFChars(env, sshUser, str);
  }

  str = (*env)->GetStringUTFChars(env, sshPassword, NULL);
  if (str) {
    strncpy(g_waypipe_config.ssh_password, str,
            sizeof(g_waypipe_config.ssh_password) - 1);
    (*env)->ReleaseStringUTFChars(env, sshPassword, str);
  }

  str = (*env)->GetStringUTFChars(env, remoteCommand, NULL);
  if (str) {
    strncpy(g_waypipe_config.remote_command, str,
            sizeof(g_waypipe_config.remote_command) - 1);
    (*env)->ReleaseStringUTFChars(env, remoteCommand, str);
  }

  str = (*env)->GetStringUTFChars(env, compress, NULL);
  if (str) {
    strncpy(g_waypipe_config.compress, str,
            sizeof(g_waypipe_config.compress) - 1);
    (*env)->ReleaseStringUTFChars(env, compress, str);
  }

  str = (*env)->GetStringUTFChars(env, video, NULL);
  if (str) {
    strncpy(g_waypipe_config.video, str, sizeof(g_waypipe_config.video) - 1);
    (*env)->ReleaseStringUTFChars(env, video, str);
  }

  str = (*env)->GetStringUTFChars(env, titlePrefix, NULL);
  if (str) {
    strncpy(g_waypipe_config.title_prefix, str,
            sizeof(g_waypipe_config.title_prefix) - 1);
    (*env)->ReleaseStringUTFChars(env, titlePrefix, str);
  }

  str = (*env)->GetStringUTFChars(env, secCtx, NULL);
  if (str) {
    strncpy(g_waypipe_config.sec_ctx, str,
            sizeof(g_waypipe_config.sec_ctx) - 1);
    (*env)->ReleaseStringUTFChars(env, secCtx, str);
  }

  g_waypipe_stop_requested = 0;
  g_waypipe_running = 1;

  int result =
      pthread_create(&g_waypipe_thread, NULL, waypipe_thread_func, NULL);
  if (result != 0) {
    LOGE("Failed to create waypipe thread: %d", result);
    g_waypipe_running = 0;
    return JNI_FALSE;
  }

  LOGI("Waypipe launched successfully");
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWaypipe(JNIEnv *env,
                                                              jobject thiz) {
  (void)env;
  (void)thiz;

  if (!g_waypipe_running) {
    LOGI("Waypipe is not running");
    return;
  }

  LOGI("Stopping waypipe...");
  g_waypipe_stop_requested = 1;

  if (g_waypipe_thread) {
    pthread_join(g_waypipe_thread, NULL);
    g_waypipe_thread = 0;
  }

  g_waypipe_running = 0;
  LOGI("Waypipe stopped");
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWaypipeRunning(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  return g_waypipe_running ? JNI_TRUE : JNI_FALSE;
}

// ============================================================================
// Weston Simple SHM execution
// ============================================================================

static int g_weston_shm_running = 0;
static pthread_t g_weston_shm_thread = 0;

static void *weston_simple_shm_thread_func(void *arg) {
  (void)arg;
  LOGI("Starting weston-simple-shm background thread (%ux%u)", g_output_width,
       g_output_height);
  if (!weston_simple_shm_main) {
    LOGE("weston-simple-shm symbol is unavailable in this build");
    g_weston_shm_running = 0;
    return NULL;
  }

  char w_str[16];
  char h_str[16];
  snprintf(w_str, sizeof(w_str), "%u",
           g_output_width > 0 ? g_output_width : 250);
  snprintf(h_str, sizeof(h_str), "%u",
           g_output_height > 0 ? g_output_height : 250);

  const char *argv[] = {"weston-simple-shm", "--width", w_str,
                        "--height",          h_str,     NULL};
  int argc = 5;

  char saved_cwd[512] = "";
  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  if (xdg_dir) {
    getcwd(saved_cwd, sizeof(saved_cwd));
    chdir(xdg_dir);
  }

  int result = weston_simple_shm_main(argc, argv);
  LOGI("weston-simple-shm returned %d", result);

  if (saved_cwd[0])
    chdir(saved_cwd);

  g_weston_shm_running = 0;
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonSimpleSHM(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;

  if (g_weston_shm_running) {
    LOGE("weston-simple-shm is already running");
    return JNI_FALSE;
  }

  g_weston_shm_running = 1;

  int result = pthread_create(&g_weston_shm_thread, NULL,
                              weston_simple_shm_thread_func, NULL);
  if (result != 0) {
    LOGE("Failed to create weston-simple-shm thread: %d", result);
    g_weston_shm_running = 0;
    return JNI_FALSE;
  }

  LOGI("weston-simple-shm launched successfully");
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWestonSimpleSHM(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;

  if (!g_weston_shm_running) {
    LOGI("weston-simple-shm is not running");
    return;
  }

  LOGI("Stopping weston-simple-shm...");
  if (&g_simple_shm_running) {
    g_simple_shm_running = 0;
  }

  if (g_weston_shm_thread) {
    pthread_join(g_weston_shm_thread, NULL);
    g_weston_shm_thread = 0;
  }

  g_weston_shm_running = 0;
  LOGI("weston-simple-shm stopped cleanly");
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonSimpleSHMRunning(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  return g_weston_shm_running ? JNI_TRUE : JNI_FALSE;
}

// ============================================================================
// Weston client
// ============================================================================

static int g_weston_running = 0;
static pthread_t g_weston_thread = 0;

static void *weston_thread_func(void *arg) {
  (void)arg;
  LOGI("Starting weston background thread");
  char saved_cwd[512] = "";
  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  if (xdg_dir) { getcwd(saved_cwd, sizeof(saved_cwd)); chdir(xdg_dir); }
  const char *argv[] = {"weston", NULL};
  weston_main(1, argv);
  if (saved_cwd[0]) chdir(saved_cwd);
  g_weston_running = 0;
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWeston(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  if (wwn_weston_is_compat_shim && wwn_weston_is_compat_shim() != 0) {
    LOGE("Refusing to launch weston: compatibility shim build detected");
    return JNI_FALSE;
  }
  if (g_weston_running) return JNI_FALSE;
  g_weston_running = 1;
  if (pthread_create(&g_weston_thread, NULL, weston_thread_func, NULL) != 0) {
    g_weston_running = 0; return JNI_FALSE;
  }
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWeston(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  g_weston_running = 0;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonRunning(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  return g_weston_running ? JNI_TRUE : JNI_FALSE;
}

// ============================================================================
// Weston-terminal client
// ============================================================================

static int g_weston_terminal_running = 0;
static pthread_t g_weston_terminal_thread = 0;

static void *weston_terminal_thread_func(void *arg) {
  (void)arg;
  LOGI("Starting weston-terminal background thread");
  char saved_cwd[512] = "";
  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  if (xdg_dir) { getcwd(saved_cwd, sizeof(saved_cwd)); chdir(xdg_dir); }
  const char *argv[] = {"weston-terminal", NULL};
  weston_terminal_main(1, argv);
  if (saved_cwd[0]) chdir(saved_cwd);
  g_weston_terminal_running = 0;
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonTerminal(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  if (wwn_weston_terminal_is_compat_shim &&
      wwn_weston_terminal_is_compat_shim() != 0) {
    LOGE("Refusing to launch weston-terminal: compatibility shim build detected");
    return JNI_FALSE;
  }
  if (g_weston_terminal_running) return JNI_FALSE;
  g_weston_terminal_running = 1;
  if (pthread_create(&g_weston_terminal_thread, NULL, weston_terminal_thread_func, NULL) != 0) {
    g_weston_terminal_running = 0; return JNI_FALSE;
  }
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWestonTerminal(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  g_weston_terminal_running = 0;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonTerminalRunning(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  return g_weston_terminal_running ? JNI_TRUE : JNI_FALSE;
}

// ============================================================================
// Foot client
// ============================================================================

static int g_foot_running = 0;
static pthread_t g_foot_thread = 0;

static void *foot_thread_func(void *arg) {
  (void)arg;
  LOGI("Starting foot background thread");
  char saved_cwd[512] = "";
  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  if (xdg_dir) { getcwd(saved_cwd, sizeof(saved_cwd)); chdir(xdg_dir); }
  const char *argv[] = {"foot", NULL};
  foot_main(1, argv);
  if (saved_cwd[0]) chdir(saved_cwd);
  g_foot_running = 0;
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunFoot(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  if (wwn_foot_is_compat_shim && wwn_foot_is_compat_shim() != 0) {
    LOGE("Refusing to launch foot: compatibility shim build detected");
    return JNI_FALSE;
  }
  if (g_foot_running) return JNI_FALSE;
  g_foot_running = 1;
  if (pthread_create(&g_foot_thread, NULL, foot_thread_func, NULL) != 0) {
    g_foot_running = 0; return JNI_FALSE;
  }
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopFoot(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  g_foot_running = 0;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsFootRunning(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  return g_foot_running ? JNI_TRUE : JNI_FALSE;
}

// ---------------------------------------------------------------------------
// Test Ping: TCP connect to host:port, measure latency
// ---------------------------------------------------------------------------
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/time.h>

JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestPing(JNIEnv *, jobject,
                                                           jstring, jint, jint);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestPing(
    JNIEnv *env, jobject thiz, jstring host, jint port, jint timeoutMs) {
  (void)thiz;
  const char *host_str = (*env)->GetStringUTFChars(env, host, NULL);
  char result[1024];
  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", port);

  LOGI("Testing TCP connectivity to %s:%d (timeout %dms)", host_str, port,
       timeoutMs);

  struct addrinfo hints = {0}, *res = NULL;
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;

  int rc = getaddrinfo(host_str, port_str, &hints, &res);
  if (rc != 0) {
    snprintf(result, sizeof(result), "FAIL: DNS resolution failed for '%s': %s",
             host_str, gai_strerror(rc));
    LOGE("Ping test failed: %s", result);
    (*env)->ReleaseStringUTFChars(env, host, host_str);
    return (*env)->NewStringUTF(env, result);
  }

  int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
  if (sock < 0) {
    snprintf(result, sizeof(result), "FAIL: Could not create socket: %s",
             strerror(errno));
    freeaddrinfo(res);
    (*env)->ReleaseStringUTFChars(env, host, host_str);
    return (*env)->NewStringUTF(env, result);
  }

  struct timeval tv;
  tv.tv_sec = timeoutMs / 1000;
  tv.tv_usec = (timeoutMs % 1000) * 1000;
  setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

  struct timeval t_start, t_end;
  gettimeofday(&t_start, NULL);
  rc = connect(sock, res->ai_addr, res->ai_addrlen);
  gettimeofday(&t_end, NULL);

  long latency_ms = (t_end.tv_sec - t_start.tv_sec) * 1000 +
                    (t_end.tv_usec - t_start.tv_usec) / 1000;

  if (rc != 0) {
    snprintf(result, sizeof(result), "FAIL: TCP connect to %s:%d failed: %s",
             host_str, port, strerror(errno));
    LOGE("Ping test: %s", result);
    close(sock);
    freeaddrinfo(res);
    (*env)->ReleaseStringUTFChars(env, host, host_str);
    return (*env)->NewStringUTF(env, result);
  }

  char banner[256] = {0};
  ssize_t n = recv(sock, banner, sizeof(banner) - 1, 0);
  if (n > 0) {
    banner[n] = '\0';
    char *nl = strchr(banner, '\n');
    if (nl)
      *nl = '\0';
    char *cr = strchr(banner, '\r');
    if (cr)
      *cr = '\0';
  }

  close(sock);
  freeaddrinfo(res);

  if (n > 0 && banner[0]) {
    snprintf(result, sizeof(result), "OK: %s:%d reachable (%ldms)\nServer: %s",
             host_str, port, latency_ms, banner);
  } else {
    snprintf(result, sizeof(result), "OK: %s:%d reachable (%ldms)", host_str,
             port, latency_ms);
  }
  LOGI("Ping test: %s", result);
  (*env)->ReleaseStringUTFChars(env, host, host_str);
  return (*env)->NewStringUTF(env, result);
}

// ---------------------------------------------------------------------------
// Test SSH: Dropbear-based connection + auth test via fork/exec
// ---------------------------------------------------------------------------
#include <poll.h>

JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestSSH(JNIEnv *, jobject,
                                                          jstring, jstring,
                                                          jstring, jint);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestSSH(
    JNIEnv *env, jobject thiz, jstring host, jstring user, jstring password,
    jint port) {
  (void)thiz;
  const char *host_str = (*env)->GetStringUTFChars(env, host, NULL);
  const char *user_str = (*env)->GetStringUTFChars(env, user, NULL);
  const char *pass_str = (*env)->GetStringUTFChars(env, password, NULL);
  char result[2048];
  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", port);

  LOGI("Testing SSH connection to %s@%s:%d (Dropbear)", user_str, host_str,
       port);

  resolve_ssh_binary_paths();

  /* Ensure XDG_RUNTIME_DIR (and thus HOME for Dropbear) is set before fork */
  if (!getenv("XDG_RUNTIME_DIR")) {
    const char *cache_dir = getenv("TMPDIR");
    if (!cache_dir)
      cache_dir = "/data/local/tmp";
    char runtime_dir[256];
    snprintf(runtime_dir, sizeof(runtime_dir), "%s/wawona-runtime", cache_dir);
    mkdir(runtime_dir, 0700);
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
  }

  if (!g_ssh_bin_path[0]) {
    snprintf(result, sizeof(result),
             "FAIL: SSH binary not found in native lib directory");
    goto cleanup_strings;
  }

  struct timeval t_start, t_end;
  gettimeofday(&t_start, NULL);

  int out_pipe[2], err_pipe[2];
  if (pipe(out_pipe) < 0 || pipe(err_pipe) < 0) {
    snprintf(result, sizeof(result), "FAIL: pipe() failed: %s",
             strerror(errno));
    goto cleanup_strings;
  }

  pid_t pid = fork();
  if (pid < 0) {
    snprintf(result, sizeof(result), "FAIL: fork() failed: %s",
             strerror(errno));
    close(out_pipe[0]);
    close(out_pipe[1]);
    close(err_pipe[0]);
    close(err_pipe[1]);
    goto cleanup_strings;
  }

  if (pid == 0) {
    close(out_pipe[0]);
    close(err_pipe[0]);
    dup2(out_pipe[1], STDOUT_FILENO);
    dup2(err_pipe[1], STDERR_FILENO);
    close(out_pipe[1]);
    close(err_pipe[1]);

    if (pass_str[0] != '\0') {
      setenv("SSHPASS", pass_str, 1);
    }
    /* Dropbear needs HOME for ~/.ssh/known_hosts; use XDG_RUNTIME_DIR (writable) */
    {
      const char *xdg = getenv("XDG_RUNTIME_DIR");
      if (xdg)
        setenv("HOME", xdg, 1);
    }

    /* Build target: user@host or just host if user empty. Pass "uname -a" as
     * single arg to avoid Dropbear misparsing "-a". Android Dropbear has
     * SSHPASS env support (patched getpass), so no sshpass - avoids argv bugs. */
    char target[512];
    if (user_str[0])
      snprintf(target, sizeof(target), "%s@%s", user_str, host_str);
    else
      snprintf(target, sizeof(target), "%s", host_str);

    const char *argv_ssh[] = {
        "ssh", "-y", "-T", "-p", port_str, target, "uname -a", NULL
    };
    LOGI("[SSH Test] exec: ssh -y -T -p %s %s uname -a", port_str, target);
    execv(g_ssh_bin_path, (char *const *)argv_ssh);

    fprintf(stderr, "exec failed: %s (path=%s)\n", strerror(errno),
            g_ssh_bin_path);
    _exit(127);
  }

  close(out_pipe[1]);
  close(err_pipe[1]);

  /* Read stdout only for Remote: line (uname output). Stderr may contain
   * "ssh:" warnings (e.g. host key) which we discard to match iOS/macOS. */
  char uname_buf[512] = {0};
  int total = 0;
  struct pollfd pf = {out_pipe[0], POLLIN, 0};
  while (total < (int)sizeof(uname_buf) - 1) {
    int pr = poll(&pf, 1, 15000);
    if (pr <= 0)
      break;
    ssize_t n =
        read(out_pipe[0], uname_buf + total, sizeof(uname_buf) - 1 - total);
    if (n <= 0)
      break;
    total += (int)n;
  }
  close(out_pipe[0]);
  uname_buf[total] = '\0';

  /* Drain stderr; use for failure output when stdout is empty */
  char err_buf[512] = {0};
  {
    int err_total = 0;
    struct pollfd pe = {err_pipe[0], POLLIN, 0};
    while (err_total < (int)sizeof(err_buf) - 1) {
      if (poll(&pe, 1, 100) <= 0)
        break;
      ssize_t n = read(err_pipe[0], err_buf + err_total,
                      sizeof(err_buf) - 1 - err_total);
      if (n <= 0)
        break;
      err_total += (int)n;
    }
    err_buf[err_total] = '\0';
  }
  close(err_pipe[0]);

  int status;
  waitpid(pid, &status, 0);

  gettimeofday(&t_end, NULL);
  long latency_ms = (t_end.tv_sec - t_start.tv_sec) * 1000 +
                    (t_end.tv_usec - t_start.tv_usec) / 1000;

  if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
    char *nl = strchr(uname_buf, '\n');
    if (nl)
      *nl = '\0';
    snprintf(result, sizeof(result),
             "OK: SSH connected and authenticated (Dropbear)\nRemote: "
             "%s\nLatency: %ldms",
             uname_buf, latency_ms);
  } else {
    const char *out = uname_buf[0] ? uname_buf : err_buf;
    snprintf(result, sizeof(result),
             "FAIL: SSH failed (exit %d)\nHost: %s\nOutput: %s\nLatency: %ldms",
             WIFEXITED(status) ? WEXITSTATUS(status) : -1,
             host_str, out[0] ? out : "(no output)", latency_ms);
    /* If hostname doesn't resolve, suggest using IP (skip if error shows "ssh"
     * - that indicates a Dropbear argv bug, not a config alias issue) */
    if (out[0] && !strstr(out, "resolving 'ssh'") &&
        (strstr(out, "No address associated with hostname") ||
         strstr(out, "Could not resolve hostname"))) {
      size_t len = strlen(result);
      if (len < sizeof(result) - 120)
        snprintf(result + len, sizeof(result) - len,
                 "\n\nTip: Use the IP address in Settings → SSH → SSH Host. Android does not read ~/.ssh/config.");
    }
  }

cleanup_strings:
  LOGI("SSH test result: %s", result);
  (*env)->ReleaseStringUTFChars(env, host, host_str);
  (*env)->ReleaseStringUTFChars(env, user, user_str);
  (*env)->ReleaseStringUTFChars(env, password, pass_str);
  return (*env)->NewStringUTF(env, result);
}

// ---------------------------------------------------------------------------

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
  // Redirect stdout/stderr to logcat
  setvbuf(stdout, 0, _IOLBF, 0);
  setvbuf(stderr, 0, _IONBF, 0);
  pipe(pfd);
  dup2(pfd[1], 1);
  dup2(pfd[1], 2);
  if (pthread_create(&thr, 0, thread_func, 0) == -1)
    return -1;
  pthread_detach(thr);

  return JNI_VERSION_1_6;
}
