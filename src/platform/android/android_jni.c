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
#ifdef WAWONA_ILAND_GL
#include "iland_presenter_android.h"
#include "iosurface_compat.h"
#endif
#include <android/choreographer.h>
#include <android/log.h>
#include <android/looper.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <dlfcn.h>
#include <jni.h>
#include <sys/types.h>
#include <bits/signal_types.h>
#include <signal.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <dirent.h>
#include <errno.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <time.h>

#ifdef WAWONA_ILAND_GL
typedef int (*WWNAHardwareBufferLockFn)(AHardwareBuffer *, uint64_t, int32_t,
                                        const ARect *, void **);
typedef int (*WWNAHardwareBufferUnlockFn)(AHardwareBuffer *, int32_t *);
typedef void (*WWNAHardwareBufferReleaseFn)(AHardwareBuffer *);
static WWNAHardwareBufferLockFn g_ahb_lock = NULL;
static WWNAHardwareBufferUnlockFn g_ahb_unlock = NULL;
static WWNAHardwareBufferReleaseFn g_ahb_release = NULL;
static pthread_once_t g_ahb_symbols_once = PTHREAD_ONCE_INIT;

static void wwn_load_ahb_symbols(void) {
  g_ahb_lock =
      (WWNAHardwareBufferLockFn)dlsym(RTLD_DEFAULT, "AHardwareBuffer_lock");
  g_ahb_unlock =
      (WWNAHardwareBufferUnlockFn)dlsym(RTLD_DEFAULT, "AHardwareBuffer_unlock");
  g_ahb_release = (WWNAHardwareBufferReleaseFn)dlsym(
      RTLD_DEFAULT, "AHardwareBuffer_release");
}
#endif

#define WWN_MAX_NATIVE_CLIENT_PIDS 32

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
static void resolve_ssh_binary_paths(void);
static void wwn_android_prepare_shell_environment(const char *files_dir);

static void jni_throw_illegal_state(JNIEnv *env, const char *msg) {
  if (!env || !msg)
    return;
  jclass cls = (*env)->FindClass(env, "java/lang/IllegalStateException");
  if (cls)
    (*env)->ThrowNew(env, cls, msg);
}

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

/* Window events - drain and apply title / fill-primary WM */
enum {
  CWindowEventTypeCreated = 0,
  CWindowEventTypeDestroyed = 1,
  CWindowEventTypeTitleChanged = 2,
  CWindowEventTypeSizeChanged = 3,
  CWindowEventTypeMinimizeRequested = 9,
  CWindowEventTypeMaximizeRequested = 10,
  CWindowEventTypeUnmaximizeRequested = 11,
  CWindowEventTypeFullscreenRequested = 14,
  CWindowEventTypeUnfullscreenRequested = 15,
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
  uint8_t host_locked;
  uint8_t edges;       /* xdg_toplevel resize_edge. Must match c_api.rs layout */
  uint8_t size_kind;   /* 0=Frame, 1=Content, 2=Buffer */
  uint8_t size_cause;  /* 0=Unknown, 1=HostConfigure, 2=ClientCommit, 3=OutputModeChange */
  uint32_t configure_serial;
  uint64_t transaction_id;
} CWindowEvent;
extern CWindowEvent *WWNCorePopWindowEvent(void *core);
extern void WWNWindowEventFree(CWindowEvent *event);
extern void WWNCoreInjectWindowResize(void *core, uint64_t window_id,
                                      uint32_t width, uint32_t height);
extern void WWNCoreBeginInteractiveResize(void *core, uint64_t window_id);
extern void WWNCoreEndInteractiveResize(void *core, uint64_t window_id,
                                        uint32_t width, uint32_t height);
extern void WWNCoreApplyHostWindowMaximized(void *core, uint64_t window_id,
                                            bool maximized, uint32_t width,
                                            uint32_t height);
extern void WWNCoreApplyHostWindowFullscreen(void *core, uint64_t window_id,
                                             bool fullscreen, uint32_t width,
                                             uint32_t height);
extern bool WWNCoreRequestWindowClose(void *core, uint64_t window_id);
extern void WWNCoreSetWindowActivated(void *core, uint64_t window_id,
                                      bool active);

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
extern void WWNCoreSetClipboardText(void *core, const char *text);
extern char *WWNCorePollClipboardText(void *core);
extern void WWNStringFree(char *s);
extern uint64_t WWNCoreWindowIdAtPoint(void *core, double x, double y);
extern void WWNCoreInjectKeyboardEnter(void *core, uint64_t window_id,
                                       const uint32_t *keys, size_t count,
                                       uint32_t timestamp_ms);
extern void WWNCoreInjectKeyboardLeave(void *core, uint64_t window_id);

extern void WWNCoreTextInputCommit(void *core, const char *text);
extern void WWNCoreTextInputPreedit(void *core, const char *text,
                                    int32_t cursor_begin, int32_t cursor_end);
extern void WWNCoreTextInputDeleteSurrounding(void *core, uint32_t before,
                                              uint32_t after);
extern int WWNCoreTextInputIsEnabled(void *core);
extern int WWNCoreTextEntryWanted(void *core);
extern void WWNCoreTextInputGetContentType(void *core, uint32_t *out_hint,
                                           uint32_t *out_purpose);
extern void WWNCoreTextInputGetCursorRect(void *core, int32_t *out_x,
                                          int32_t *out_y, int32_t *out_width,
                                          int32_t *out_height);

extern int waypipe_main(int argc, const char **argv) __attribute__((weak));
extern int weston_simple_shm_main(int argc, const char **argv)
    __attribute__((weak));
extern int weston_main(int argc, const char **argv) __attribute__((weak));
#ifdef WAWONA_WESTON_COMPOSITOR
extern int weston_compositor_main(int argc, char **argv);
#else
extern int weston_compositor_main(int argc, char **argv) __attribute__((weak));
#endif
extern volatile sig_atomic_t wwn_weston_compositor_shutdown_requested;
extern int weston_terminal_main(int argc, const char **argv)
    __attribute__((weak));
extern int flower_main(int argc, const char **argv) __attribute__((weak));
extern int clickdot_main(int argc, const char **argv) __attribute__((weak));
extern int smoke_main(int argc, const char **argv) __attribute__((weak));
extern int eventdemo_main(int argc, const char **argv) __attribute__((weak));
extern int resizor_main(int argc, const char **argv) __attribute__((weak));
extern int cliptest_main(int argc, const char **argv) __attribute__((weak));
extern int transformed_main(int argc, const char **argv) __attribute__((weak));
extern int stacking_main(int argc, const char **argv) __attribute__((weak));
extern int dnd_main(int argc, const char **argv) __attribute__((weak));
extern int image_main(int argc, const char **argv) __attribute__((weak));
extern int scaler_main(int argc, const char **argv) __attribute__((weak));
extern int editor_main(int argc, const char **argv) __attribute__((weak));
extern int constraints_main(int argc, const char **argv) __attribute__((weak));
extern int simple_egl_main(int argc, const char **argv) __attribute__((weak));
extern int kmscube_main(int argc, char **argv) __attribute__((weak));
extern int opengl_cube_main(int argc, char **argv) __attribute__((weak));
extern int vkcube_main(int argc, char **argv) __attribute__((weak));
extern int wwn_weston_is_compat_shim(void) __attribute__((weak));
extern int wwn_weston_terminal_is_compat_shim(void) __attribute__((weak));
extern int wwn_foot_is_compat_shim(void) __attribute__((weak));
extern int g_simple_shm_running __attribute__((weak));

// JNI Function Prototypes
JNIEXPORT void JNICALL Java_com_aspauldingcode_wawona_WawonaNative_nativeInit(
    JNIEnv *env, jobject thiz, jstring cacheDir);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsCompositorReady(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetSurface(JNIEnv *env,
                                                             jobject thiz,
                                                             jobject surface);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDestroySurface(JNIEnv *env,
                                                                 jobject thiz,
                                                                 jobject surface);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetXkbDefaults(
    JNIEnv *env, jobject thiz, jstring layout, jstring variant);
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
    jstring openglDriver, jstring compositorBackend);
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
Java_com_aspauldingcode_wawona_WawonaNative_nativeTextInputIsEnabled(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTextEntryWanted(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetTextInputContentType(
    JNIEnv *env, jobject thiz, jintArray outHintPurpose);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWaypipe(
    JNIEnv *env, jobject thiz, jboolean sshEnabled, jstring sshHost,
    jstring sshUser, jstring sshPassword, jstring sshKeyPath, jint sshAuthMethod,
    jstring remoteCommand, jstring compress, jint threads, jstring video,
    jboolean debug, jboolean oneshot, jboolean noGpu, jboolean loginShell,
    jstring titlePrefix, jstring secCtx);
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
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunBundledClient(
    JNIEnv *env, jobject thiz, jstring clientId);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopBundledClient(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsBundledClientRunning(
    JNIEnv *env, jobject thiz);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetRunningBundledClientId(
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
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRequestActiveWindowClose(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeConsumeMinimizeRequested(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetWindowActivated(
    JNIEnv *env, jobject thiz, jlong windowId, jboolean active);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetFocusedWindowTitle(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetClipboardText(
    JNIEnv *env, jobject thiz, jstring text);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePollClipboardText(
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
/* GlobalRef to the Java Surface that owns g_window. Used so a stale
 * SessionActivity surfaceDestroyed cannot tear down a newer host task. */
static jobject g_surface_jobj = NULL;
VkDevice g_device = VK_NULL_HANDLE;
VkQueue g_queue = VK_NULL_HANDLE;
VkSwapchainKHR g_swapchain = VK_NULL_HANDLE;
uint32_t g_queue_family = 0;
ANativeWindow *g_window = NULL;
uint32_t g_output_width = 0;
uint32_t g_output_height = 0;

/* Interactive resize settle: keep xdg_toplevel.state.resizing set across
 * mid-drag host size ticks; clear on the first idle frame after the last
 * inject (xdg-shell / niri pattern). */
static uint64_t g_interactive_resize_window = 0;
static uint32_t g_interactive_resize_w = 0;
static uint32_t g_interactive_resize_h = 0;
static int g_interactive_resize_active = 0;
static int g_interactive_resize_idle_frames = 0;

// Threading
static int g_running = 0;
static pthread_t g_render_thread = 0;

static void android_stop_render_thread_locked(void);
static void android_teardown_swapchain_locked(void);
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

/* Last pointer-targeted window id. This updates from hit-testing so pointer
 * events stay scoped to popups/toplevels under the cursor. */
static uint64_t g_pointer_window_id = 0;
static double g_pointer_last_x = 0.0;
static double g_pointer_last_y = 0.0;

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

static uint64_t resolve_pointer_window_id(double logical_x, double logical_y) {
  if (!g_core)
    return g_pointer_window_id;
  uint64_t hit_window_id = WWNCoreWindowIdAtPoint(g_core, logical_x, logical_y);
  if (hit_window_id != 0) {
    g_pointer_window_id = hit_window_id;
  }
  return g_pointer_window_id;
}

/* Pending client minimize. Kotlin polls and returns to Machines UI. */
static volatile int g_minimize_requested = 0;
static volatile uint64_t g_minimize_requested_window_id = 0;

/* Android freeform host-scene claims (#120).
 *
 * A task is reserved before its client launches; the next created Wayland
 * toplevel atomically claims that task.  This avoids the Termux-style race
 * where two adjacent SessionActivities both attach to the same first window.
 * The rendering backend remains responsible for presenting the claimed scene.
 */
#define ANDROID_HOST_SCENE_MAX_WINDOWS 64
typedef struct {
  uint64_t window_id;
  uint64_t host_id;
  uint8_t in_use;
} AndroidHostSceneClaim;
typedef struct {
  uint64_t host_id;
  uint64_t order;
  uint8_t in_use;
} AndroidHostSceneReservation;
static AndroidHostSceneClaim g_host_scene_claims[ANDROID_HOST_SCENE_MAX_WINDOWS];
static AndroidHostSceneReservation
    g_host_scene_reservations[ANDROID_HOST_SCENE_MAX_WINDOWS];
static pthread_mutex_t g_host_scene_claim_lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t g_host_scene_reservation_order = 0;

static void android_host_scene_claim_created_window(uint64_t window_id) {
  if (window_id == 0)
    return;
  pthread_mutex_lock(&g_host_scene_claim_lock);
  int reservation_index = -1;
  uint64_t oldest_order = UINT64_MAX;
  for (int i = 0; i < ANDROID_HOST_SCENE_MAX_WINDOWS; i++) {
    if (g_host_scene_reservations[i].in_use &&
        g_host_scene_reservations[i].order < oldest_order) {
      reservation_index = i;
      oldest_order = g_host_scene_reservations[i].order;
    }
  }
  if (reservation_index >= 0) {
    uint64_t host_id = g_host_scene_reservations[reservation_index].host_id;
    for (int i = 0; i < ANDROID_HOST_SCENE_MAX_WINDOWS; i++) {
      if (!g_host_scene_claims[i].in_use) {
        g_host_scene_claims[i].window_id = window_id;
        g_host_scene_claims[i].host_id = host_id;
        g_host_scene_claims[i].in_use = 1;
        LOGI("Host scene claim: host=%llu window=%llu",
             (unsigned long long)host_id,
             (unsigned long long)window_id);
        break;
      }
    }
    memset(&g_host_scene_reservations[reservation_index], 0,
           sizeof(g_host_scene_reservations[reservation_index]));
  }
  pthread_mutex_unlock(&g_host_scene_claim_lock);
}

static void android_host_scene_forget_window(uint64_t window_id) {
  pthread_mutex_lock(&g_host_scene_claim_lock);
  for (int i = 0; i < ANDROID_HOST_SCENE_MAX_WINDOWS; i++) {
    if (g_host_scene_claims[i].in_use &&
        g_host_scene_claims[i].window_id == window_id) {
      memset(&g_host_scene_claims[i], 0, sizeof(g_host_scene_claims[i]));
      break;
    }
  }
  pthread_mutex_unlock(&g_host_scene_claim_lock);
}

static uint64_t android_host_scene_window_for_host(uint64_t host_id) {
  uint64_t window_id = 0;
  pthread_mutex_lock(&g_host_scene_claim_lock);
  for (int i = 0; i < ANDROID_HOST_SCENE_MAX_WINDOWS; i++) {
    if (g_host_scene_claims[i].in_use &&
        g_host_scene_claims[i].host_id == host_id) {
      window_id = g_host_scene_claims[i].window_id;
      break;
    }
  }
  pthread_mutex_unlock(&g_host_scene_claim_lock);
  return window_id;
}

/* Fill-primary host (single surface): max/fullscreen → logical output size.
 * Also syncs xdg maximized/fullscreen so clients see negotiated WM state. */
static void android_inject_fill_primary(uint64_t window_id, int maximized,
                                        int fullscreen) {
  if (!g_core || window_id == 0 || g_output_width == 0 || g_output_height == 0)
    return;
  int sf = compute_auto_scale_factor();
  if (sf < 1)
    sf = 1;
  uint32_t lw = g_output_width / (uint32_t)sf;
  uint32_t lh = g_output_height / (uint32_t)sf;
  if (lw == 0)
    lw = 1;
  if (lh == 0)
    lh = 1;
  LOGI("WM fill-primary: window=%llu logical=%ux%u max=%d fs=%d",
       (unsigned long long)window_id, lw, lh, maximized, fullscreen);
  /* Max/fullscreen uses Maximized/Fullscreen states, not Resizing. */
  if (g_interactive_resize_active && g_interactive_resize_window == window_id) {
    WWNCoreEndInteractiveResize(g_core, window_id, lw, lh);
    g_interactive_resize_active = 0;
    g_interactive_resize_window = 0;
  }
  WWNCoreInjectWindowResize(g_core, window_id, lw, lh);
  if (fullscreen) {
    WWNCoreApplyHostWindowFullscreen(g_core, window_id, true, lw, lh);
  } else if (maximized) {
    WWNCoreApplyHostWindowMaximized(g_core, window_id, true, lw, lh);
  } else {
    WWNCoreApplyHostWindowFullscreen(g_core, window_id, false, lw, lh);
    WWNCoreApplyHostWindowMaximized(g_core, window_id, false, lw, lh);
  }
}

/*
 * Safe area insets arrive from Kotlin (WindowInsetsCompat) in raw physical
 * display pixels, but the compositor's scene graph (window positions, sizes,
 * content_rect crop math) operates entirely in the *logical* output space -
 * physical pixels divided by the auto-scale factor (see WWNCoreSetOutputSize
 * above). Pushing the raw physical inset straight into
 * WWNCoreSetSafeAreaInsets applies it as if it were already a logical-space
 * offset, over-cropping/offsetting windows by ~scale-factor times too much
 * (e.g. a 142px physical status bar inset at scale=3 ate 142 logical units
 * out of an ~808-unit-tall output instead of the correct ~47). Always scale
 * by the same factor used for the output size so insets and window geometry
 * agree on units.
 */
static void push_safe_area_to_core(void) {
  if (!g_core)
    return;
  int sf = compute_auto_scale_factor();
  int32_t top = g_safeAreaTop / sf;
  int32_t right = g_safeAreaRight / sf;
  int32_t bottom = g_safeAreaBottom / sf;
  int32_t left = g_safeAreaLeft / sf;
  WWNCoreSetSafeAreaInsets(g_core, top, right, bottom, left);
  LOGI("Safe area insets: physical(T=%d,R=%d,B=%d,L=%d) scale=%d -> "
       "logical(T=%d,R=%d,B=%d,L=%d)",
       g_safeAreaTop, g_safeAreaRight, g_safeAreaBottom, g_safeAreaLeft, sf,
       top, right, bottom, left);
}

/* OWL host↔client size: track which windows may receive host fill configures.
 * Fixed demos (weston-flower/smoke 200×200, simple-shm preferred) must not be
 * streamed to logical output size on every density/output tick. */
#define ANDROID_OWL_MAX_WINDOWS 64
typedef struct {
  uint64_t window_id;
  uint8_t host_locked;
  uint8_t follow_host;
  uint8_t in_use;
} AndroidOwlWindow;
static AndroidOwlWindow g_owl_windows[ANDROID_OWL_MAX_WINDOWS];

static AndroidOwlWindow *android_owl_find(uint64_t window_id, int create) {
  AndroidOwlWindow *free_slot = NULL;
  for (int i = 0; i < ANDROID_OWL_MAX_WINDOWS; i++) {
    if (g_owl_windows[i].in_use && g_owl_windows[i].window_id == window_id)
      return &g_owl_windows[i];
    if (!g_owl_windows[i].in_use && free_slot == NULL)
      free_slot = &g_owl_windows[i];
  }
  if (!create || free_slot == NULL)
    return NULL;
  memset(free_slot, 0, sizeof(*free_slot));
  free_slot->window_id = window_id;
  free_slot->in_use = 1;
  return free_slot;
}

static void android_owl_forget(uint64_t window_id) {
  AndroidOwlWindow *w = android_owl_find(window_id, 0);
  if (w)
    memset(w, 0, sizeof(*w));
}

static int android_window_should_follow_host(uint64_t window_id) {
  if (window_id == 0)
    return 0;
  AndroidOwlWindow *w = android_owl_find(window_id, 0);
  if (!w)
    return 0; /* unknown: do not force fill (OWL default after 0×0 seed) */
  return w->host_locked || w->follow_host;
}

static void android_owl_on_created(const CWindowEvent *evt) {
  if (!evt || evt->window_id == 0)
    return;
  AndroidOwlWindow *w = android_owl_find(evt->window_id, 1);
  if (!w)
    return;
  w->host_locked = evt->host_locked || evt->fullscreen_shell;
  /* Ordinary toplevels wait for ClientCommit; host_locked fills immediately. */
  w->follow_host = w->host_locked ? 1 : 0;
  LOGI("OWL create window=%llu host_locked=%u follow_host=%u",
       (unsigned long long)evt->window_id, w->host_locked, w->follow_host);
}

static void android_owl_on_size_changed(const CWindowEvent *evt) {
  if (!evt || evt->window_id == 0 || evt->width == 0 || evt->height == 0)
    return;
  /* Only ClientCommit drives follow_host (macOS/iOS SizeAuthority parity). */
  if (evt->size_cause != 2)
    return;
  AndroidOwlWindow *w = android_owl_find(evt->window_id, 1);
  if (!w)
    return;
  if (w->host_locked) {
    w->follow_host = 1;
    return;
  }
  int sf = compute_auto_scale_factor();
  if (sf < 1)
    sf = 1;
  uint32_t lw =
      g_output_width > 0 ? g_output_width / (uint32_t)sf : 0;
  uint32_t lh =
      g_output_height > 0 ? g_output_height / (uint32_t)sf : 0;
  int fills = (lw > 0 && lh > 0 && evt->width * 10 >= lw * 9 &&
               evt->height * 10 >= lh * 9);
  w->follow_host = fills ? 1 : 0;
  LOGI("OWL ClientCommit window=%llu %ux%u follow_host=%u (output %ux%u)",
       (unsigned long long)evt->window_id, evt->width, evt->height,
       w->follow_host, lw, lh);
}

static void android_begin_stream_resize(uint64_t window_id, uint32_t lw,
                                        uint32_t lh) {
  if (!g_core || window_id == 0 || lw == 0 || lh == 0)
    return;
  if (!android_window_should_follow_host(window_id))
    return;
  if (!g_interactive_resize_active || g_interactive_resize_window != window_id) {
    WWNCoreBeginInteractiveResize(g_core, window_id);
    g_interactive_resize_active = 1;
  }
  g_interactive_resize_window = window_id;
  g_interactive_resize_w = lw;
  g_interactive_resize_h = lh;
  g_interactive_resize_idle_frames = 0;
  WWNCoreInjectWindowResize(g_core, window_id, lw, lh);
}

static void android_maybe_settle_interactive_resize(void) {
  if (!g_core || !g_interactive_resize_active || g_interactive_resize_window == 0)
    return;
  /* Settle after one idle vsync with no further host size ticks. */
  if (g_interactive_resize_idle_frames < 1) {
    g_interactive_resize_idle_frames++;
    return;
  }
  LOGI("WM settle interactive resize window=%llu %ux%u",
       (unsigned long long)g_interactive_resize_window, g_interactive_resize_w,
       g_interactive_resize_h);
  WWNCoreEndInteractiveResize(g_core, g_interactive_resize_window,
                              g_interactive_resize_w, g_interactive_resize_h);
  g_interactive_resize_active = 0;
  g_interactive_resize_window = 0;
  g_interactive_resize_idle_frames = 0;
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
  /* Scale factor may have just changed (density/setting update). Re-push
   * safe area insets so they stay in sync with the new logical output. */
  push_safe_area_to_core();
  /* Stream host size only for windows that follow host (host_locked / fillers).
   * Fixed weston demos stay on Client authority after refuse/preferred commit. */
  if (g_pointer_window_id != 0 &&
      android_window_should_follow_host(g_pointer_window_id)) {
    android_begin_stream_resize(g_pointer_window_id, lw, lh);
  }
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

static int wwn_android_native_lib_dir(char *out, size_t out_len);

static void *g_vulkan_driver_handle = NULL;
static PFN_vkGetInstanceProcAddr wwn_vkGetInstanceProcAddr = NULL;
static PFN_vkGetDeviceProcAddr wwn_vkGetDeviceProcAddr = NULL;
#define WWN_VK_GLOBAL(name) static PFN_##name wwn_##name = NULL
WWN_VK_GLOBAL(vkCreateInstance);
WWN_VK_GLOBAL(vkEnumeratePhysicalDevices);
WWN_VK_GLOBAL(vkGetPhysicalDeviceProperties);
WWN_VK_GLOBAL(vkGetPhysicalDeviceQueueFamilyProperties);
WWN_VK_GLOBAL(vkGetPhysicalDeviceSurfaceSupportKHR);
WWN_VK_GLOBAL(vkEnumerateDeviceExtensionProperties);
WWN_VK_GLOBAL(vkCreateDevice);
WWN_VK_GLOBAL(vkGetPhysicalDeviceSurfaceCapabilitiesKHR);
WWN_VK_GLOBAL(vkCreateAndroidSurfaceKHR);
WWN_VK_GLOBAL(vkDestroySurfaceKHR);
WWN_VK_GLOBAL(vkDestroyInstance);
WWN_VK_GLOBAL(vkGetDeviceQueue);
WWN_VK_GLOBAL(vkCreateSwapchainKHR);
WWN_VK_GLOBAL(vkGetSwapchainImagesKHR);
WWN_VK_GLOBAL(vkCreateImageView);
WWN_VK_GLOBAL(vkDestroyImageView);
WWN_VK_GLOBAL(vkCreateRenderPass);
WWN_VK_GLOBAL(vkDestroyRenderPass);
WWN_VK_GLOBAL(vkCreateFramebuffer);
WWN_VK_GLOBAL(vkDestroyFramebuffer);
WWN_VK_GLOBAL(vkWaitForFences);
WWN_VK_GLOBAL(vkAcquireNextImageKHR);
WWN_VK_GLOBAL(vkResetFences);
WWN_VK_GLOBAL(vkBeginCommandBuffer);
WWN_VK_GLOBAL(vkCmdBeginRenderPass);
WWN_VK_GLOBAL(vkCmdSetViewport);
WWN_VK_GLOBAL(vkCmdSetScissor);
WWN_VK_GLOBAL(vkCmdEndRenderPass);
WWN_VK_GLOBAL(vkEndCommandBuffer);
WWN_VK_GLOBAL(vkQueueSubmit);
WWN_VK_GLOBAL(vkQueuePresentKHR);
WWN_VK_GLOBAL(vkCreateCommandPool);
WWN_VK_GLOBAL(vkAllocateCommandBuffers);
WWN_VK_GLOBAL(vkDestroyCommandPool);
WWN_VK_GLOBAL(vkCreateSemaphore);
WWN_VK_GLOBAL(vkDestroySemaphore);
WWN_VK_GLOBAL(vkCreateFence);
WWN_VK_GLOBAL(vkDestroyFence);
WWN_VK_GLOBAL(vkDeviceWaitIdle);
WWN_VK_GLOBAL(vkFreeCommandBuffers);
WWN_VK_GLOBAL(vkDestroyDevice);
WWN_VK_GLOBAL(vkDestroySwapchainKHR);
#undef WWN_VK_GLOBAL

#define vkCreateInstance wwn_vkCreateInstance
#define vkEnumeratePhysicalDevices wwn_vkEnumeratePhysicalDevices
#define vkGetPhysicalDeviceProperties wwn_vkGetPhysicalDeviceProperties
#define vkGetPhysicalDeviceQueueFamilyProperties wwn_vkGetPhysicalDeviceQueueFamilyProperties
#define vkGetPhysicalDeviceSurfaceSupportKHR wwn_vkGetPhysicalDeviceSurfaceSupportKHR
#define vkEnumerateDeviceExtensionProperties wwn_vkEnumerateDeviceExtensionProperties
#define vkCreateDevice wwn_vkCreateDevice
#define vkGetPhysicalDeviceSurfaceCapabilitiesKHR wwn_vkGetPhysicalDeviceSurfaceCapabilitiesKHR
#define vkCreateAndroidSurfaceKHR wwn_vkCreateAndroidSurfaceKHR
#define vkDestroySurfaceKHR wwn_vkDestroySurfaceKHR
#define vkDestroyInstance wwn_vkDestroyInstance
#define vkGetDeviceQueue wwn_vkGetDeviceQueue
#define vkCreateSwapchainKHR wwn_vkCreateSwapchainKHR
#define vkGetSwapchainImagesKHR wwn_vkGetSwapchainImagesKHR
#define vkCreateImageView wwn_vkCreateImageView
#define vkDestroyImageView wwn_vkDestroyImageView
#define vkCreateRenderPass wwn_vkCreateRenderPass
#define vkDestroyRenderPass wwn_vkDestroyRenderPass
#define vkCreateFramebuffer wwn_vkCreateFramebuffer
#define vkDestroyFramebuffer wwn_vkDestroyFramebuffer
#define vkWaitForFences wwn_vkWaitForFences
#define vkAcquireNextImageKHR wwn_vkAcquireNextImageKHR
#define vkResetFences wwn_vkResetFences
#define vkBeginCommandBuffer wwn_vkBeginCommandBuffer
#define vkCmdBeginRenderPass wwn_vkCmdBeginRenderPass
#define vkCmdSetViewport wwn_vkCmdSetViewport
#define vkCmdSetScissor wwn_vkCmdSetScissor
#define vkCmdEndRenderPass wwn_vkCmdEndRenderPass
#define vkEndCommandBuffer wwn_vkEndCommandBuffer
#define vkQueueSubmit wwn_vkQueueSubmit
#define vkQueuePresentKHR wwn_vkQueuePresentKHR
#define vkCreateCommandPool wwn_vkCreateCommandPool
#define vkAllocateCommandBuffers wwn_vkAllocateCommandBuffers
#define vkDestroyCommandPool wwn_vkDestroyCommandPool
#define vkCreateSemaphore wwn_vkCreateSemaphore
#define vkDestroySemaphore wwn_vkDestroySemaphore
#define vkCreateFence wwn_vkCreateFence
#define vkDestroyFence wwn_vkDestroyFence
#define vkDeviceWaitIdle wwn_vkDeviceWaitIdle
#define vkFreeCommandBuffers wwn_vkFreeCommandBuffers
#define vkDestroyDevice wwn_vkDestroyDevice
#define vkDestroySwapchainKHR wwn_vkDestroySwapchainKHR

static int wwn_load_host_vulkan(void) {
  const char *path = "libvulkan.so";

  if (g_vulkan_driver_handle) {
    dlclose(g_vulkan_driver_handle);
    g_vulkan_driver_handle = NULL;
  }
  g_vulkan_driver_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!g_vulkan_driver_handle) {
    LOGE("Could not load Vulkan driver %s: %s", path, dlerror());
    return -1;
  }
  wwn_vkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(
      g_vulkan_driver_handle, "vkGetInstanceProcAddr");
  if (!wwn_vkGetInstanceProcAddr) {
    LOGE("%s has no vkGetInstanceProcAddr", path);
    dlclose(g_vulkan_driver_handle);
    g_vulkan_driver_handle = NULL;
    return -1;
  }
  wwn_vkCreateInstance = (PFN_vkCreateInstance)wwn_vkGetInstanceProcAddr(
      VK_NULL_HANDLE, "vkCreateInstance");
  if (!wwn_vkCreateInstance) {
    LOGE("%s has no vkCreateInstance", path);
    return -1;
  }
  LOGI("Loaded Vulkan driver library: %s", path);
  return 0;
}

static int wwn_load_vulkan_instance_dispatch(VkInstance instance) {
#define WWN_LOAD_INSTANCE(name)                                                \
  do {                                                                         \
    wwn_##name = (PFN_##name)wwn_vkGetInstanceProcAddr(instance, #name);       \
    if (!wwn_##name) {                                                          \
      LOGE("Vulkan instance entrypoint missing: %s", #name);                    \
      return -1;                                                                \
    }                                                                           \
  } while (0)
  WWN_LOAD_INSTANCE(vkEnumeratePhysicalDevices);
  WWN_LOAD_INSTANCE(vkGetPhysicalDeviceProperties);
  WWN_LOAD_INSTANCE(vkGetPhysicalDeviceQueueFamilyProperties);
  WWN_LOAD_INSTANCE(vkGetPhysicalDeviceSurfaceSupportKHR);
  WWN_LOAD_INSTANCE(vkEnumerateDeviceExtensionProperties);
  WWN_LOAD_INSTANCE(vkCreateDevice);
  WWN_LOAD_INSTANCE(vkGetPhysicalDeviceSurfaceCapabilitiesKHR);
  WWN_LOAD_INSTANCE(vkCreateAndroidSurfaceKHR);
  WWN_LOAD_INSTANCE(vkDestroySurfaceKHR);
  WWN_LOAD_INSTANCE(vkDestroyInstance);
#undef WWN_LOAD_INSTANCE
  wwn_vkGetDeviceProcAddr = (PFN_vkGetDeviceProcAddr)
      wwn_vkGetInstanceProcAddr(instance, "vkGetDeviceProcAddr");
  return wwn_vkGetDeviceProcAddr ? 0 : -1;
}

static int wwn_load_vulkan_device_dispatch(VkDevice device) {
#define WWN_LOAD_DEVICE(name)                                                  \
  do {                                                                         \
    wwn_##name = (PFN_##name)wwn_vkGetDeviceProcAddr(device, #name);           \
    if (!wwn_##name) {                                                          \
      LOGE("Vulkan device entrypoint missing: %s", #name);                      \
      return -1;                                                                \
    }                                                                           \
  } while (0)
  WWN_LOAD_DEVICE(vkGetDeviceQueue);
  WWN_LOAD_DEVICE(vkCreateSwapchainKHR);
  WWN_LOAD_DEVICE(vkGetSwapchainImagesKHR);
  WWN_LOAD_DEVICE(vkCreateImageView);
  WWN_LOAD_DEVICE(vkDestroyImageView);
  WWN_LOAD_DEVICE(vkCreateRenderPass);
  WWN_LOAD_DEVICE(vkDestroyRenderPass);
  WWN_LOAD_DEVICE(vkCreateFramebuffer);
  WWN_LOAD_DEVICE(vkDestroyFramebuffer);
  WWN_LOAD_DEVICE(vkWaitForFences);
  WWN_LOAD_DEVICE(vkAcquireNextImageKHR);
  WWN_LOAD_DEVICE(vkResetFences);
  WWN_LOAD_DEVICE(vkBeginCommandBuffer);
  WWN_LOAD_DEVICE(vkCmdBeginRenderPass);
  WWN_LOAD_DEVICE(vkCmdSetViewport);
  WWN_LOAD_DEVICE(vkCmdSetScissor);
  WWN_LOAD_DEVICE(vkCmdEndRenderPass);
  WWN_LOAD_DEVICE(vkEndCommandBuffer);
  WWN_LOAD_DEVICE(vkQueueSubmit);
  WWN_LOAD_DEVICE(vkQueuePresentKHR);
  WWN_LOAD_DEVICE(vkCreateCommandPool);
  WWN_LOAD_DEVICE(vkAllocateCommandBuffers);
  WWN_LOAD_DEVICE(vkDestroyCommandPool);
  WWN_LOAD_DEVICE(vkCreateSemaphore);
  WWN_LOAD_DEVICE(vkDestroySemaphore);
  WWN_LOAD_DEVICE(vkCreateFence);
  WWN_LOAD_DEVICE(vkDestroyFence);
  WWN_LOAD_DEVICE(vkDeviceWaitIdle);
  WWN_LOAD_DEVICE(vkFreeCommandBuffers);
  WWN_LOAD_DEVICE(vkDestroyDevice);
  WWN_LOAD_DEVICE(vkDestroySwapchainKHR);
#undef WWN_LOAD_DEVICE
  return 0;
}

static int apply_graphics_driver_selection(void) {
  WWNGraphicsDriverSelection selection =
      WWNSettings_ResolveGraphicsDriverSelection();
  const char *vulkanDriver = selection.vulkanDriver;
  setenv("WWN_VULKAN_DRIVER", vulkanDriver, 1);
  unsetenv("WWN_DISABLE_VULKAN");
  if (strcmp(vulkanDriver, "none") == 0) {
    unsetenv("VK_DRIVER_FILES");
    unsetenv("VK_ICD_FILENAMES");
    unsetenv("WWN_SWIFTSHADER_LIBRARY");
    setenv("WWN_DISABLE_VULKAN", "1", 1);
  } else if (strcmp(vulkanDriver, "swiftshader") == 0) {
    /*
     * Host ANativeWindow WSI stays on libvulkan.so (loaded below). Bundled
     * SwiftShader is the portable offscreen ICD for iland/vkcube clients:
     * expose it both as WWN_SWIFTSHADER_LIBRARY (direct ICD dlopen, macOS-
     * style) and as a staged ICD manifest for any loader that respects
     * VK_ICD_FILENAMES. The jniLibs directory is often read-only, so the
     * JSON lives under WAWONA_FILES_DIR with an absolute library_path.
     */
    char native_lib_dir[512];
    char swiftshader_path[640];
    char icd_path[720];
    if (wwn_android_native_lib_dir(native_lib_dir, sizeof(native_lib_dir)) != 0)
      return -1;
    snprintf(swiftshader_path, sizeof(swiftshader_path),
             "%s/libvk_swiftshader.so", native_lib_dir);
    setenv("WWN_SWIFTSHADER_LIBRARY", swiftshader_path, 1);

    const char *files_dir = getenv("WAWONA_FILES_DIR");
    if (files_dir && files_dir[0]) {
      char vulkan_dir[640];
      char icd_dir[640];
      snprintf(vulkan_dir, sizeof(vulkan_dir), "%s/vulkan", files_dir);
      snprintf(icd_dir, sizeof(icd_dir), "%s/vulkan/icd.d", files_dir);
      mkdir(vulkan_dir, 0755);
      mkdir(icd_dir, 0755);
      snprintf(icd_path, sizeof(icd_path),
               "%s/vulkan/icd.d/vk_swiftshader_icd.json", files_dir);
      FILE *icd = fopen(icd_path, "w");
      if (icd) {
        fprintf(icd,
                "{\n"
                "  \"file_format_version\": \"1.0.0\",\n"
                "  \"ICD\": {\n"
                "    \"library_path\": \"%s\",\n"
                "    \"api_version\": \"1.3.0\"\n"
                "  }\n"
                "}\n",
                swiftshader_path);
        fclose(icd);
        setenv("VK_ICD_FILENAMES", icd_path, 1);
        setenv("VK_DRIVER_FILES", icd_path, 1);
      } else {
        LOGE("Could not stage SwiftShader ICD at %s", icd_path);
        unsetenv("VK_DRIVER_FILES");
        unsetenv("VK_ICD_FILENAMES");
      }
    } else {
      unsetenv("VK_DRIVER_FILES");
      unsetenv("VK_ICD_FILENAMES");
    }
  } else {
    unsetenv("VK_DRIVER_FILES");
    unsetenv("VK_ICD_FILENAMES");
    unsetenv("WWN_SWIFTSHADER_LIBRARY");
  }

  const char *openGLDriver = selection.openGLDriver;
  setenv("WWN_OPENGL_DRIVER", openGLDriver, 1);
  if (strcmp(openGLDriver, "none") == 0) {
    setenv("WWN_DISABLE_EGL", "1", 1);
    unsetenv("ANGLE_DEFAULT_PLATFORM");
  } else {
    /* Android iland GL clients always use bundled ANGLE (see egl.c load_angle).
     * Keep the Vulkan backend selected whenever EGL is enabled. */
    setenv("ANGLE_DEFAULT_PLATFORM", "vulkan", 1);
    unsetenv("WWN_DISABLE_EGL");
  }
  LOGI("Graphics drivers applied: Vulkan=%s OpenGL=%s", vulkanDriver,
       openGLDriver);
  if (strcmp(vulkanDriver, "none") == 0)
    return -1;
  /*
   * Android ANativeWindow WSI is owned by the system Vulkan loader. Bundled
   * SwiftShader is a portable, offscreen client ICD for iland KMS/GBM; it
   * cannot provide vkCreateAndroidSurfaceKHR for this host surface.
   */
  return wwn_load_host_vulkan();
}

/**
 * Create Vulkan instance with Android surface extensions
 */
static VkResult create_instance(void) {
  if (apply_graphics_driver_selection() != 0 ||
      getenv("WWN_DISABLE_VULKAN")) {
    LOGI("Vulkan disabled by graphics driver policy");
    return VK_ERROR_INITIALIZATION_FAILED;
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
    return res;
  }
  if (wwn_load_vulkan_instance_dispatch(g_instance) != 0) {
    LOGE("Failed to load Vulkan instance dispatch");
    return VK_ERROR_INITIALIZATION_FAILED;
  }
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
  if (wwn_load_vulkan_device_dispatch(g_device) != 0) {
    LOGE("Failed to load Vulkan device dispatch");
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
    android_maybe_settle_interactive_resize();
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
      switch (evt->event_type) {
      case CWindowEventTypeCreated:
        android_owl_on_created(evt);
        android_host_scene_claim_created_window(evt->window_id);
        break;
      case CWindowEventTypeDestroyed:
        android_owl_forget(evt->window_id);
        android_host_scene_forget_window(evt->window_id);
        break;
      case CWindowEventTypeSizeChanged:
        android_owl_on_size_changed(evt);
        break;
      case CWindowEventTypeMinimizeRequested:
        LOGI("WM MinimizeRequested window=%llu",
             (unsigned long long)evt->window_id);
        g_minimize_requested_window_id = evt->window_id;
        g_minimize_requested = 1;
        break;
      case CWindowEventTypeMaximizeRequested: {
        AndroidOwlWindow *owl = android_owl_find(evt->window_id, 1);
        if (owl)
          owl->follow_host = 1;
        android_inject_fill_primary(evt->window_id, /*maximized=*/1,
                                    /*fullscreen=*/0);
        break;
      }
      case CWindowEventTypeFullscreenRequested: {
        AndroidOwlWindow *owl = android_owl_find(evt->window_id, 1);
        if (owl)
          owl->follow_host = 1;
        android_inject_fill_primary(evt->window_id, /*maximized=*/0,
                                    /*fullscreen=*/1);
        break;
      }
      case CWindowEventTypeUnmaximizeRequested:
      case CWindowEventTypeUnfullscreenRequested: {
        /* Restore OWL follow from last ClientCommit rather than keep fill. */
        AndroidOwlWindow *owl = android_owl_find(evt->window_id, 0);
        if (owl && !owl->host_locked)
          owl->follow_host = 0;
        android_inject_fill_primary(evt->window_id, /*maximized=*/0,
                                    /*fullscreen=*/0);
        break;
      }
      default:
        break;
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
      LOGI("pending buffer: id=%llu %ux%u stride=%u format=%u pixels=%s "
           "iosurface_id=%u size=%zu",
           (unsigned long long)buf->buffer_id, buf->width, buf->height,
           buf->stride, buf->format, buf->pixels ? "set" : "NULL",
           buf->iosurface_id, buf->size);
      if (buf->pixels && buf->width > 0 && buf->height > 0) {
        renderer_android_cache_buffer(ctx->cmdBuf, buf->surface_id,
                                      buf->buffer_id, buf->width, buf->height,
                                      buf->stride, buf->format, buf->pixels,
                                      buf->size);
      } else if (buf->iosurface_id != 0 && buf->width > 0 && buf->height > 0) {
        /* Wayland dmabuf / #86: high-bit modifier packs an AHB-backed
         * ILandIOSurface id. Lock CPU-mapped pixels and upload like SHM. */
        IOSurfaceRef surf = ILandIOSurfaceLookup(buf->iosurface_id);
        if (surf) {
          ILandIOSurfaceLock(surf);
          void *base = ILandIOSurfaceGetBaseAddress(surf);
          uint32_t stride = (uint32_t)ILandIOSurfaceGetBytesPerRow(surf);
          size_t nbytes = (size_t)stride * buf->height;
          if (base && stride > 0) {
            renderer_android_cache_buffer(
                ctx->cmdBuf, buf->surface_id, buf->buffer_id, buf->width,
                buf->height, stride, buf->format, (const uint8_t *)base,
                nbytes);
          } else {
            LOGI("AHB lookup id=%u: no mapped base (stride=%u)",
                 buf->iosurface_id, stride);
          }
          ILandIOSurfaceUnlock(surf);
          ILandIOSurfaceRelease(surf);
        } else {
          LOGI("AHB lookup failed for iosurface_id=%u", buf->iosurface_id);
        }
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

  /* iland GL overlay (kmscube / nested Weston DRM) composites above empty
   * compositor when active. Tests userland KMS + GLES via ANGLE. */
#ifdef WAWONA_ILAND_GL
  uint32_t iland_presented_fb_id = 0;
  if (wwn_iland_presenter_android_is_active()) {
    AHardwareBuffer *iland_buffer = NULL;
    uint32_t iland_w = 0, iland_h = 0, iland_stride = 0, iland_fb_id = 0;
    int iland_is_new = 0;
    if (wwn_iland_presenter_android_take_hardware_buffer(
            &iland_buffer, &iland_w, &iland_h, &iland_stride, &iland_fb_id,
            &iland_is_new)) {
      int sf = compute_auto_scale_factor();
      uint32_t logical_w = ctx->extent.width / (uint32_t)sf;
      uint32_t logical_h = ctx->extent.height / (uint32_t)sf;
      if (logical_w == 0)
        logical_w = 1;
      if (logical_h == 0)
        logical_h = 1;
      if (iland_is_new && iland_buffer) {
        iland_presented_fb_id = iland_fb_id;
        void *iland_pixels = NULL;
        pthread_once(&g_ahb_symbols_once, wwn_load_ahb_symbols);
        if (g_ahb_lock && g_ahb_unlock &&
            g_ahb_lock(iland_buffer, AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN, -1,
                       NULL, &iland_pixels) == 0 &&
            iland_pixels) {
          renderer_android_draw_iland_overlay(
              ctx->cmdBuf, iland_pixels, iland_w, iland_h, iland_stride,
              logical_w, logical_h);
          g_ahb_unlock(iland_buffer, NULL);
        } else {
          static int s_lock_fail_logged = 0;
          if (!s_lock_fail_logged) {
            LOGE("iland overlay: AHardwareBuffer_lock failed (zero-copy GPU "
                 "import still open)");
            s_lock_fail_logged = 1;
          }
          /* Still redraw last good texture if we have one. */
          renderer_android_draw_iland_overlay(ctx->cmdBuf, NULL, iland_w,
                                               iland_h, iland_stride, logical_w,
                                               logical_h);
        }
        if (g_ahb_release)
          g_ahb_release(iland_buffer);
      } else {
        /* Sticky: redraw cached Vulkan texture between page flips. */
        renderer_android_draw_iland_overlay(ctx->cmdBuf, NULL, iland_w, iland_h,
                                             iland_stride, logical_w,
                                             logical_h);
      }
    }
  }
#endif

  if (g_core) {
    scene = WWNCoreGetRenderScene(g_core);
    if (scene) {
      if (ctx->frame_count % 60 == 0)
        LOGI("frame scene: count=%zu has_cursor=%d cursor_buffer_id=%llu",
             scene->count, scene->has_cursor,
             (unsigned long long)scene->cursor_buffer_id);
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
      if (WWNSettings_GetRenderMacOSPointer() && scene->has_cursor &&
          scene->cursor_buffer_id > 0) {
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
#ifdef WAWONA_ILAND_GL
  if ((res == VK_SUCCESS || res == VK_SUBOPTIMAL_KHR) &&
      iland_presented_fb_id != 0) {
    wwn_iland_presenter_android_frame_presented(iland_presented_fb_id);
  }
#endif
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
  // p22 runtime perf: raise this thread to Android's urgent-display priority so
  // vsync-aligned compositing isn't preempted by background work. On bionic,
  // setpriority(PRIO_PROCESS, 0, nice) sets the *calling thread's* nice value.
  // -8 == ANDROID_PRIORITY_URGENT_DISPLAY (matches SurfaceFlinger/render tier).
  errno = 0;
  if (setpriority(PRIO_PROCESS, 0, -8) != 0 && errno != 0) {
    // Non-fatal: bg-limited processes may lack CAP_SYS_NICE for negative nice.
    LOGE("render_thread: could not raise to urgent-display priority (errno=%d)",
         errno);
  }
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
  LOGI("  Host Cursor Rendering: %s",
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
  /* Do NOT destroy the graphics pipeline here. A second SetSurface can start
   * another render thread while this one is still exiting; destroying the
   * shared pipeline then races the new thread's draw_quads (Adreno SIGSEGV).
   * Pipeline teardown belongs to the waiter after pthread_join. */
  vkFreeCommandBuffers(g_device, cmdPool, 1, &cmdBuf);
  vkDestroyCommandPool(g_device, cmdPool, NULL);
  free(images);

  LOGI("Render thread stopped, rendered %d frames", frame_ctx.frame_count);
  return NULL;
}

// ============================================================================
// JNI Interface
// ============================================================================

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePrepareShellEnvironment(
    JNIEnv *env, jobject thiz, jstring filesDir) {
  (void)thiz;
  const char *files_utf = NULL;
  if (filesDir)
    files_utf = (*env)->GetStringUTFChars(env, filesDir, NULL);
  if (files_utf) {
    setenv("WAWONA_FILES_DIR", files_utf, 1);
    resolve_ssh_binary_paths();
    wwn_android_prepare_shell_environment(files_utf);
    (*env)->ReleaseStringUTFChars(env, filesDir, files_utf);
  }
}

/**
 * Initialize the compositor - create Vulkan instance
 * Called from Android Activity.onCreate()
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetXkbDefaults(
    JNIEnv *env, jobject thiz, jstring layout, jstring variant) {
  (void)thiz;
  /* Must run before seat keyboard init (wawona_xkb_config OnceLock). */
  if (layout) {
    const char *utf = (*env)->GetStringUTFChars(env, layout, NULL);
    if (utf && utf[0] != '\0') {
      setenv("XKB_DEFAULT_LAYOUT", utf, 1);
      LOGI("XKB_DEFAULT_LAYOUT=%s", utf);
    }
    if (utf)
      (*env)->ReleaseStringUTFChars(env, layout, utf);
  }
  if (variant) {
    const char *utf = (*env)->GetStringUTFChars(env, variant, NULL);
    if (utf) {
      setenv("XKB_DEFAULT_VARIANT", utf, 1);
      LOGI("XKB_DEFAULT_VARIANT=%s", utf);
      (*env)->ReleaseStringUTFChars(env, variant, utf);
    }
  } else {
    setenv("XKB_DEFAULT_VARIANT", "", 1);
  }
}

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
    /* sun_path guard: libwayland/waypipe bind AF_UNIX sockets at
     * XDG_RUNTIME_DIR + "/<name>" and sockaddr_un.sun_path caps at
     * sizeof(sun_path) (108 on Android). The longest suffix we append is
     * waypipe's "/waypipe-client-<rand>.sock" (~28 bytes), so reserve a
     * budget and fall back to the short /data/local/tmp path (dev/emulator)
     * if the app-private cache dir would overflow. Better a diagnostic than
     * a silent bind() EINVAL. */
    {
      const size_t sun_path_max = sizeof(((struct sockaddr_un *)0)->sun_path);
      const size_t suffix_budget = 32; /* "/waypipe-client-<rand>.sock" + NUL */
      if (strlen(runtime_dir) + suffix_budget > sun_path_max) {
        LOGE("XDG_RUNTIME_DIR too long for AF_UNIX sun_path (%zu + %zu > %zu): "
             "%s. Falling back to /data/local/tmp",
             strlen(runtime_dir), suffix_budget, sun_path_max, runtime_dir);
        snprintf(runtime_dir, sizeof(runtime_dir),
                 "/data/local/tmp/wawona-runtime");
      }
    }
    mkdir(runtime_dir, 0700);
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
    setenv("TMPDIR", cache_dir, 1);
    LOGI("XDG_RUNTIME_DIR=%s", runtime_dir);
    if (cache_dir_utf)
      (*env)->ReleaseStringUTFChars(env, cacheDir, cache_dir_utf);

    g_core = WWNCoreNew();
    if (!g_core) {
      LOGE("WWNCoreNew() returned NULL");
      pthread_mutex_unlock(&g_lock);
      jni_throw_illegal_state(
          env,
          "Compositor core unavailable (rebuild with nix run .#gradlegen or "
          "nix build .#wawona-android)");
      return;
    }
    LOGI("WWNCoreNew() succeeded: %p", g_core);
    if (!WWNCoreStart(g_core, "wayland-0")) {
      LOGE("WWNCoreStart() failed");
      WWNCoreFree(g_core);
      g_core = NULL;
      pthread_mutex_unlock(&g_lock);
      jni_throw_illegal_state(
          env,
          "Compositor failed to start Wayland socket (check logcat tag Wawona)");
      return;
    }
    LOGI("Compositor started on wayland-0");
    setenv("WAYLAND_DISPLAY", "wayland-0", 1);
  }

  VkResult r = create_instance();
  if (r != VK_SUCCESS) {
    LOGE("Vulkan instance creation failed (res=%d); rendering may be unavailable",
         (int)r);
  } else {
    uint32_t count = 0;
    VkResult res = vkEnumeratePhysicalDevices(g_instance, &count, NULL);
    LOGI("vkEnumeratePhysicalDevices count=%u, res=%d", count, res);
  }
  pthread_mutex_unlock(&g_lock);
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsCompositorReady(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  return (g_core && WWNCoreIsRunning(g_core)) ? JNI_TRUE : JNI_FALSE;
}

/**
 * Set the Android Surface and initialize rendering
 * Called when the SurfaceView is created/updated
 */
/* Stop the vsync render thread. Caller must hold g_lock. Joins before
 * returning so Vulkan/pipeline teardown cannot race a live frame callback. */
static void android_stop_render_thread_locked(void) {
  g_running = 0;
  if (!g_render_thread)
    return;
  pthread_t t = g_render_thread;
  g_render_thread = 0;
  /* Render thread never takes g_lock; join while holding is safe. */
  pthread_join(t, NULL);
}

/* Tear down swapchain-side resources after the render thread has stopped.
 * Leaves VkInstance / VkDevice intact. Caller holds g_lock. */
static void android_teardown_swapchain_locked(void) {
  if (g_device != VK_NULL_HANDLE)
    vkDeviceWaitIdle(g_device);

  if (g_framebuffers) {
    for (uint32_t i = 0; i < g_swapchainImageCount; i++)
      vkDestroyFramebuffer(g_device, g_framebuffers[i], NULL);
    free(g_framebuffers);
    g_framebuffers = NULL;
  }
  if (g_renderPass != VK_NULL_HANDLE) {
    vkDestroyRenderPass(g_device, g_renderPass, NULL);
    g_renderPass = VK_NULL_HANDLE;
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
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetSurface(JNIEnv *env,
                                                             jobject thiz,
                                                             jobject surface) {
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  LOGI("nativeSetSurface called");

  /* Surface recreate (split-screen / SessionActivity) used to start a second
   * render thread without joining the first. Both shared one pipeline and
   * the exiting thread destroyed it under the new thread (SIGSEGV in
   * draw_quads). Always stop + tear down presentation before rebuilding. */
  if (g_render_thread || g_running || g_swapchain || g_surface) {
    LOGI("nativeSetSurface: stopping prior render/swapchain");
    android_stop_render_thread_locked();
    android_teardown_swapchain_locked();
    if (g_surface && g_instance) {
      vkDestroySurfaceKHR(g_instance, g_surface, NULL);
      g_surface = VK_NULL_HANDLE;
    }
  }

  if (g_window) {
    LOGI("Releasing existing ANativeWindow");
    ANativeWindow_release(g_window);
    g_window = NULL;
  }
  if (g_surface_jobj) {
    (*env)->DeleteGlobalRef(env, g_surface_jobj);
    g_surface_jobj = NULL;
  }

  ANativeWindow *win = ANativeWindow_fromSurface(env, surface);
  if (!win) {
    LOGE("ANativeWindow_fromSurface returned NULL");
    pthread_mutex_unlock(&g_lock);
    return;
  }
  g_window = win;
  g_surface_jobj = (*env)->NewGlobalRef(env, surface);
  LOGI("Received ANativeWindow %p", (void *)win);

  // Skip safe area update for now - thiz is WawonaNative object, not Activity
  // Safe area will be updated when settings are applied via nativeApplySettings
  LOGI("Skipping safe area update (will be set via settings)");
  g_safeAreaLeft = 0;
  g_safeAreaTop = 0;
  g_safeAreaRight = 0;
  g_safeAreaBottom = 0;

#define WWN_CLEAR_ANDROID_WINDOW()                                             \
  do {                                                                         \
    if (g_window) {                                                            \
      ANativeWindow_release(g_window);                                         \
      g_window = NULL;                                                         \
    }                                                                          \
    if (g_surface_jobj) {                                                      \
      (*env)->DeleteGlobalRef(env, g_surface_jobj);                            \
      g_surface_jobj = NULL;                                                   \
    }                                                                          \
  } while (0)

  if (g_instance == VK_NULL_HANDLE) {
    LOGI("Creating Vulkan instance...");
    if (create_instance() != VK_SUCCESS) {
      LOGE("Failed to create Vulkan instance");
      WWN_CLEAR_ANDROID_WINDOW();
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
    WWN_CLEAR_ANDROID_WINDOW();
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Android VkSurfaceKHR created: %p", (void *)g_surface);

  LOGI("Picking Vulkan device...");
  VkPhysicalDevice pd = pick_device();
  if (pd == VK_NULL_HANDLE) {
    LOGE("No Vulkan devices found");
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    g_surface = VK_NULL_HANDLE;
    WWN_CLEAR_ANDROID_WINDOW();
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Vulkan device picked");

  LOGI("Creating Vulkan device...");
  if (g_device == VK_NULL_HANDLE) {
    if (create_device(pd) != 0) {
      LOGE("Failed to create device");
      vkDestroySurfaceKHR(g_instance, g_surface, NULL);
      g_surface = VK_NULL_HANDLE;
      WWN_CLEAR_ANDROID_WINDOW();
      pthread_mutex_unlock(&g_lock);
      return;
    }
    LOGI("Vulkan device created");
  } else {
    LOGI("Reusing existing Vulkan device");
  }

  LOGI("Creating swapchain...");
  if (create_swapchain(pd) != 0) {
    LOGE("Failed to create swapchain");
    android_teardown_swapchain_locked();
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    g_surface = VK_NULL_HANDLE;
    WWN_CLEAR_ANDROID_WINDOW();
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
    renderer_android_destroy_all();
    vkDestroyDevice(g_device, NULL);
    g_device = VK_NULL_HANDLE;
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    g_surface = VK_NULL_HANDLE;
    WWN_CLEAR_ANDROID_WINDOW();
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
                                                                 jobject thiz,
                                                                 jobject surface) {
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  /* SessionActivity teardown races: an old host task's surfaceDestroyed can
   * land after a new SessionActivity already called nativeSetSurface. Only
   * tear down when the dying Surface is still the active Java Surface
   * (issue #141. Blank/unresponsive window after first run). */
  if (surface && g_surface_jobj &&
      !(*env)->IsSameObject(env, surface, g_surface_jobj)) {
    LOGI("Destroying surface: ignoring stale Surface (active host still live)");
    pthread_mutex_unlock(&g_lock);
    return;
  }

  LOGI("Destroying surface");
  android_stop_render_thread_locked();
  android_teardown_swapchain_locked();

  if (g_surface && g_instance) {
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    g_surface = VK_NULL_HANDLE;
  }

  /* Full purge (including cached SHM textures) since the VkDevice they
   * belong to is about to be destroyed below - unlike nativeResizeSurface's
   * swapchain-only resize, which preserves the device and must NOT lose the
   * buffer cache (see renderer_android_destroy_pipeline()). */
  renderer_android_destroy_all();

  if (g_device) {
    vkDestroyDevice(g_device, NULL);
    g_device = VK_NULL_HANDLE;
  }

  if (g_instance) {
    vkDestroyInstance(g_instance, NULL);
    g_instance = VK_NULL_HANDLE;
  }
  if (g_vulkan_driver_handle) {
    dlclose(g_vulkan_driver_handle);
    g_vulkan_driver_handle = NULL;
  }

  if (g_window) {
    ANativeWindow_release(g_window);
    g_window = NULL;
  }
  if (g_surface_jobj) {
    (*env)->DeleteGlobalRef(env, g_surface_jobj);
    g_surface_jobj = NULL;
  }

  LOGI("Surface destroyed (compositor core preserved)");
  pthread_mutex_unlock(&g_lock);
}

/*
 * Called from libweston-13.a while in-process Wayland clients block in
 * wl_display_roundtrip / display_run (same symbol name as iOS).
 */
void wwn_ios_pump_host_compositor(void) {
  if (g_core)
    (void)WWNCoreProcessEvents(g_core);
}

/**
 * Resize surface. Recreate swapchain only, keep Vulkan instance/device/surface.
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

  android_stop_render_thread_locked();
  android_teardown_swapchain_locked();

  ANativeWindow_setBuffersGeometry(g_window, (int32_t)width, (int32_t)height, 0);

  if (create_swapchain_with_extent(g_physicalDevice, (uint32_t)width,
                                  (uint32_t)height) != 0) {
    LOGE("Resize swapchain failed");
    pthread_mutex_unlock(&g_lock);
    return;
  }

  g_output_width = (uint32_t)width;
  g_output_height = (uint32_t)height;
#ifdef WAWONA_ILAND_GL
  wwn_iland_presenter_android_set_surface_size(g_output_width, g_output_height);
#endif
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
 * Lightweight output-size sync. Updates the compositor output dimensions
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
 * Final shutdown. Tears down the compositor core.
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

  /* Android respects safe area by inset-padding the compositor view in Compose
   * (same model as iOS safeAreaLayoutGuide). The wl_output size already matches
   * the inset container. Do not also shrink via Rust safe_area_insets. */
  g_safeAreaLeft = 0;
  g_safeAreaTop = 0;
  g_safeAreaRight = 0;
  g_safeAreaBottom = 0;
  LOGI("JNI Update Safe Area: raw(T=%d,R=%d,B=%d,L=%d) respect=%s -> core insets zeroed",
       top, right, bottom, left,
       WWNSettings_GetRespectSafeArea() ? "on" : "off");
  push_safe_area_to_core();
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
    jstring openglDriver, jstring compositorBackend) {
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
  char compositorBackendBuf[32] = {0};
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
  if (compositorBackend) {
    const char *s = (*env)->GetStringUTFChars(env, compositorBackend, NULL);
    if (s) {
      strncpy(compositorBackendBuf, s, sizeof(compositorBackendBuf) - 1);
      (*env)->ReleaseStringUTFChars(env, compositorBackend, s);
    }
  }
  LOGI("  Vulkan Driver: %s", vulkanDriverBuf[0] ? vulkanDriverBuf : "system");
  LOGI("  OpenGL Driver: %s", openglDriverBuf[0] ? openglDriverBuf : "system");
  LOGI("  Display Backend: %s",
       compositorBackendBuf[0] ? compositorBackendBuf : "auto");

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
  strncpy(config.compositorBackend,
          compositorBackendBuf[0] ? compositorBackendBuf : "auto",
          sizeof(config.compositorBackend) - 1);
  config.compositorBackend[sizeof(config.compositorBackend) - 1] = '\0';
  WWNSettings_UpdateConfig(&config);

  /* Push OpenGL/Vulkan driver env *before* any bundled GL client starts.
   * create_instance() also calls this, but kmscube/opengl-cube launch from
   * MainActivity before SessionActivity brings up the host Vulkan surface. */
  (void)apply_graphics_driver_selection();

  // Safe area is applied in Compose when enabled (iOS safeAreaLayoutGuide parity).
  g_safeAreaLeft = 0;
  g_safeAreaTop = 0;
  g_safeAreaRight = 0;
  g_safeAreaBottom = 0;

  LOGI("Safe area updated based on settings: %s (Compose inset when enabled)",
       respectSafeArea ? "enabled" : "disabled");

  /* Push to Rust backend */
  if (g_core) {
    WWNCoreSetForceSSD(g_core, forceServerSideDecorations ? 1 : 0);
  }
  push_safe_area_to_core();

  // Reapply output scale (auto-scale toggle may have changed); this also
  // re-pushes safe area insets scaled to the (possibly new) logical output.
  apply_output_scale();

  LOGI("Wawona settings applied successfully with safe area support");
  pthread_mutex_unlock(&g_lock);
}

/**
 * Apply environment overrides from JSON:
 * `{ "set": { "TERM": "xterm" }, "unset": ["RUST_LOG"] }` (#157 / #160).
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeApplyEnvironmentOverrides(
    JNIEnv *env, jobject thiz, jstring json) {
  (void)thiz;
  if (!json) {
    return;
  }
  const char *utf = (*env)->GetStringUTFChars(env, json, NULL);
  if (!utf) {
    return;
  }
  LOGI("Applying environment overrides (%zu bytes)", strlen(utf));

  /* Minimal parse: walk "set" object and "unset" array without a full JSON lib.
   * Payload is generated by EnvironmentOverrides.jniPayload. Trusted shape. */
  const char *set_key = strstr(utf, "\"set\"");
  const char *unset_key = strstr(utf, "\"unset\"");
  if (set_key) {
    const char *brace = strchr(set_key, '{');
    const char *end = brace ? strchr(brace, '}') : NULL;
    if (brace && end && end > brace) {
      const char *p = brace + 1;
      while (p < end) {
        while (p < end && (*p == ' ' || *p == ',' || *p == '\n' || *p == '\r'))
          p++;
        if (p >= end || *p != '"')
          break;
        p++;
        const char *name_start = p;
        while (p < end && *p != '"')
          p++;
        if (p >= end)
          break;
        size_t name_len = (size_t)(p - name_start);
        p++; /* closing quote */
        while (p < end && (*p == ' ' || *p == ':'))
          p++;
        if (p >= end || *p != '"')
          break;
        p++;
        const char *val_start = p;
        while (p < end && *p != '"') {
          if (*p == '\\' && p + 1 < end)
            p += 2;
          else
            p++;
        }
        size_t val_len = (size_t)(p - val_start);
        if (name_len > 0 && name_len < 256 && val_len < 4096) {
          char name[256];
          char value[4096];
          memcpy(name, name_start, name_len);
          name[name_len] = '\0';
          memcpy(value, val_start, val_len);
          value[val_len] = '\0';
          if (strncmp(name, "DYLD_", 5) != 0 && strncmp(name, "LD_", 3) != 0) {
            setenv(name, value, 1);
            LOGI("  setenv %s", name);
          }
        }
        if (p < end)
          p++;
      }
    }
  }
  if (unset_key) {
    const char *bracket = strchr(unset_key, '[');
    const char *end = bracket ? strchr(bracket, ']') : NULL;
    if (bracket && end && end > bracket) {
      const char *p = bracket + 1;
      while (p < end) {
        while (p < end && (*p == ' ' || *p == ','))
          p++;
        if (p >= end || *p != '"')
          break;
        p++;
        const char *name_start = p;
        while (p < end && *p != '"')
          p++;
        size_t name_len = (size_t)(p - name_start);
        if (name_len > 0 && name_len < 256) {
          char name[256];
          memcpy(name, name_start, name_len);
          name[name_len] = '\0';
          unsetenv(name);
          LOGI("  unsetenv %s", name);
        }
        if (p < end)
          p++;
      }
    }
  }

  (*env)->ReleaseStringUTFChars(env, json, utf);
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
// Text Input (IME / Emoji). Forward composed text to Wayland text-input-v3
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

  /* Prefer text-input-v3 when the client has committed Enable. */
  if (WWNCoreTextInputIsEnabled(g_core)) {
    WWNCoreTextInputCommit(g_core, utf8);
    (*env)->ReleaseStringUTFChars(env, text, utf8);
    return;
  }

  /* Terminal synthesis / no TI: key inject for mappable ASCII; TI commit
   * only as a last resort for unmappable (emoji/CJK). */
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
    WWNCoreTextInputCommit(g_core, utf8);
    (*env)->ReleaseStringUTFChars(env, text, utf8);
    return;
  }

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

/* Push text copied on the native side (Android ClipboardManager) into the
 * compositor so Wayland clients (e.g. weston-terminal) can paste it. */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetClipboardText(
    JNIEnv *env, jobject thiz, jstring text) {
  (void)thiz;
  if (!g_core || !text)
    return;
  const char *utf8 = (*env)->GetStringUTFChars(env, text, NULL);
  if (!utf8)
    return;
  WWNCoreSetClipboardText(g_core, utf8);
  (*env)->ReleaseStringUTFChars(env, text, utf8);
}

/* Pop the most recent text a Wayland client copied to the clipboard,
 * clearing it. Returns null if nothing new has been copied since the last
 * poll. The Kotlin side pushes the result into ClipboardManager. */
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePollClipboardText(
    JNIEnv *env, jobject thiz) {
  (void)thiz;
  if (!g_core)
    return NULL;
  char *text = WWNCorePollClipboardText(g_core);
  if (!text)
    return NULL;
  jstring result = (*env)->NewStringUTF(env, text);
  WWNStringFree(text);
  return result;
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

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTextInputIsEnabled(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return JNI_FALSE;
  return WWNCoreTextInputIsEnabled(g_core) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTextEntryWanted(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return JNI_FALSE;
  return WWNCoreTextEntryWanted(g_core) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetTextInputContentType(
    JNIEnv *env, jobject thiz, jintArray outHintPurpose) {
  (void)thiz;
  if (!outHintPurpose)
    return;
  jsize len = (*env)->GetArrayLength(env, outHintPurpose);
  if (len < 2)
    return;
  uint32_t hint = 0, purpose = 0;
  if (g_core)
    WWNCoreTextInputGetContentType(g_core, &hint, &purpose);
  jint buf[2] = {(jint)hint, (jint)purpose};
  (*env)->SetIntArrayRegion(env, outHintPurpose, 0, 2, buf);
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
   * WWNCoreInjectModifiers here. Mixing update_mask with update_key
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
    uint64_t target_window_id =
        resolve_pointer_window_id(g_pointer_last_x, g_pointer_last_y);
    /* axis: 0 = vertical, 1 = horizontal */
    WWNCoreInjectPointerAxis(g_core, target_window_id, (uint32_t)axis,
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
    double logical_x = x / sf;
    double logical_y = y / sf;
    g_pointer_last_x = logical_x;
    g_pointer_last_y = logical_y;
    uint64_t target_window_id = resolve_pointer_window_id(logical_x, logical_y);
    WWNCoreInjectPointerMotion(g_core, target_window_id, logical_x, logical_y,
                               (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerButton(
    JNIEnv *env, jobject thiz, jint buttonCode, jint state, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    uint64_t target_window_id =
        resolve_pointer_window_id(g_pointer_last_x, g_pointer_last_y);
    /* buttonCode: 0x110 = BTN_LEFT, 0x111 = BTN_RIGHT */
    WWNCoreInjectPointerButton(g_core, target_window_id,
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
    double logical_x = x / sf;
    double logical_y = y / sf;
    g_pointer_last_x = logical_x;
    g_pointer_last_y = logical_y;
    uint64_t target_window_id = resolve_pointer_window_id(logical_x, logical_y);
    WWNCoreInjectPointerEnter(g_core, target_window_id, logical_x, logical_y,
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
    WWNCoreSetWindowActivated(g_core, g_pointer_window_id, true);
  } else {
    WWNCoreInjectKeyboardLeave(g_core, g_pointer_window_id);
    WWNCoreSetWindowActivated(g_core, g_pointer_window_id, false);
  }
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRequestActiveWindowClose(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  if (!g_core || g_pointer_window_id == 0)
    return JNI_FALSE;
  return WWNCoreRequestWindowClose(g_core, g_pointer_window_id) ? JNI_TRUE
                                                                : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeConsumeMinimizeRequested(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  if (!g_minimize_requested)
    return JNI_FALSE;
  g_minimize_requested = 0;
  g_minimize_requested_window_id = 0;
  return JNI_TRUE;
}

JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeConsumeMinimizedWindow(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  uint64_t window_id = g_minimize_requested_window_id;
  g_minimize_requested_window_id = 0;
  g_minimize_requested = 0;
  return (jlong)window_id;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeReserveNextHostWindow(
    JNIEnv *env, jobject thiz, jlong host_id) {
  (void)env;
  (void)thiz;
  if (host_id == 0)
    return;
  pthread_mutex_lock(&g_host_scene_claim_lock);
  int free_index = -1;
  for (int i = 0; i < ANDROID_HOST_SCENE_MAX_WINDOWS; i++) {
    if (g_host_scene_reservations[i].in_use &&
        g_host_scene_reservations[i].host_id == (uint64_t)host_id) {
      pthread_mutex_unlock(&g_host_scene_claim_lock);
      return;
    }
    if (!g_host_scene_reservations[i].in_use && free_index < 0)
      free_index = i;
  }
  if (free_index >= 0) {
    g_host_scene_reservation_order++;
    if (g_host_scene_reservation_order == 0)
      g_host_scene_reservation_order = 1;
    g_host_scene_reservations[free_index].host_id = (uint64_t)host_id;
    g_host_scene_reservations[free_index].order =
        g_host_scene_reservation_order;
    g_host_scene_reservations[free_index].in_use = 1;
  } else {
    LOGE("Host scene reservation table full; host=%llu",
         (unsigned long long)host_id);
  }
  pthread_mutex_unlock(&g_host_scene_claim_lock);
}

JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetWindowForHost(
    JNIEnv *env, jobject thiz, jlong host_id) {
  (void)env;
  (void)thiz;
  if (host_id == 0)
    return 0;
  return (jlong)android_host_scene_window_for_host((uint64_t)host_id);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeResizeHostWindow(
    JNIEnv *env, jobject thiz, jlong host_id, jint width, jint height) {
  (void)env;
  (void)thiz;
  if (!g_core || host_id == 0 || width <= 0 || height <= 0)
    return;
  uint64_t window_id = android_host_scene_window_for_host((uint64_t)host_id);
  if (window_id == 0)
    return;
  int sf = compute_auto_scale_factor();
  uint32_t logical_width = (uint32_t)width / (uint32_t)(sf > 0 ? sf : 1);
  uint32_t logical_height = (uint32_t)height / (uint32_t)(sf > 0 ? sf : 1);
  WWNCoreInjectWindowResize(g_core, window_id, logical_width ? logical_width : 1,
                            logical_height ? logical_height : 1);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetHostWindowFocused(
    JNIEnv *env, jobject thiz, jlong host_id, jboolean focused) {
  (void)env;
  (void)thiz;
  if (!g_core || host_id == 0)
    return;
  uint64_t window_id = android_host_scene_window_for_host((uint64_t)host_id);
  if (window_id != 0)
    WWNCoreSetWindowActivated(g_core, window_id, focused == JNI_TRUE);
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeCloseHostWindow(
    JNIEnv *env, jobject thiz, jlong host_id) {
  (void)env;
  (void)thiz;
  if (!g_core || host_id == 0)
    return JNI_FALSE;
  uint64_t window_id = android_host_scene_window_for_host((uint64_t)host_id);
  return window_id != 0 && WWNCoreRequestWindowClose(g_core, window_id)
             ? JNI_TRUE
             : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeReleaseHostWindow(
    JNIEnv *env, jobject thiz, jlong host_id) {
  (void)env;
  (void)thiz;
  if (host_id == 0)
    return;
  pthread_mutex_lock(&g_host_scene_claim_lock);
  for (int i = 0; i < ANDROID_HOST_SCENE_MAX_WINDOWS; i++) {
    if (g_host_scene_reservations[i].in_use &&
        g_host_scene_reservations[i].host_id == (uint64_t)host_id) {
      memset(&g_host_scene_reservations[i], 0,
             sizeof(g_host_scene_reservations[i]));
      break;
    }
  }
  for (int i = 0; i < ANDROID_HOST_SCENE_MAX_WINDOWS; i++) {
    if (g_host_scene_claims[i].in_use &&
        g_host_scene_claims[i].host_id == (uint64_t)host_id) {
      memset(&g_host_scene_claims[i], 0, sizeof(g_host_scene_claims[i]));
      break;
    }
  }
  pthread_mutex_unlock(&g_host_scene_claim_lock);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetWindowActivated(
    JNIEnv *env, jobject thiz, jlong windowId, jboolean active) {
  (void)env;
  (void)thiz;
  if (!g_core || windowId == 0)
    return;
  WWNCoreSetWindowActivated(g_core, (uint64_t)windowId, active == JNI_TRUE);
}

// ============================================================================
// Waypipe Integration
// ============================================================================

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <signal.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static char g_ssh_bin_path[512] = {0};
static char g_sshpass_bin_path[512] = {0};
static char g_zsh_bin_path[512] = {0};

static int wwn_android_native_lib_dir(char *out, size_t out_len) {
  Dl_info info;
  if (!out || out_len == 0)
    return -1;
  out[0] = '\0';
  if (!dladdr((void *)wwn_android_native_lib_dir, &info) || !info.dli_fname)
    return -1;
  strncpy(out, info.dli_fname, out_len - 1);
  out[out_len - 1] = '\0';
  char *lastSlash = strrchr(out, '/');
  if (!lastSlash)
    return -1;
  *lastSlash = '\0';
  return 0;
}

/* PATH entries under usr/bin must resolve to something exec()-able. Android
 * Q+ (API 29+) denies execve() of files living in app-private storage
 * (files/cache. SELinux execute_no_trans / W^X), which is exactly where
 * wawona-rootfs/usr/bin lives, so a byte-for-byte copy there (the old
 * behavior, still used for e.g. weston asset trees) silently produces a
 * dead, "Permission denied" binary for fastfetch/waypipe/ssh/nvim/zsh.
 * The native lib dir (native_lib_dir, extracted from the APK's jniLibs with
 * extractNativeLibs=true) is always exec()-able by design, and exec()
 * permission checks follow the *resolved* target of a symlink. So a
 * symlink here keeps the friendly PATH name while actually executing out of
 * the native lib dir, same as SHELL/g_ssh_bin_path already do directly. */
static void wwn_android_install_shell_tool(const char *native_lib_dir,
                                           const char *usr_bin,
                                           const char *jni_lib_name,
                                           const char *bin_name) {
  char src[512];
  char dst[512];
  struct stat st;

  if (!native_lib_dir || !native_lib_dir[0] || !usr_bin || !bin_name ||
      !jni_lib_name)
    return;

  snprintf(src, sizeof(src), "%s/%s", native_lib_dir, jni_lib_name);
  snprintf(dst, sizeof(dst), "%s/%s", usr_bin, bin_name);
  if (stat(src, &st) != 0)
    return;

  char existing_target[512];
  ssize_t existing_len = readlink(dst, existing_target, sizeof(existing_target) - 1);
  if (existing_len > 0) {
    existing_target[existing_len] = '\0';
    if (strcmp(existing_target, src) == 0)
      return; /* already linked correctly */
    unlink(dst);
  } else if (lstat(dst, &st) == 0) {
    /* Stale non-exec'able regular-file copy from an older Wawona build
     * (or a broken symlink). Replace it with a working symlink. */
    unlink(dst);
  }

  if (symlink(src, dst) == 0)
    LOGI("Shell env: linked %s -> %s", dst, src);
  else
    LOGE("Shell env: failed to symlink %s -> %s (%s)", dst, src, strerror(errno));
}

static int wwn_android_should_write_generated_file(const char *path) {
  FILE *fp = fopen(path, "r");
  if (!fp)
    return 1;

  char buf[512];
  size_t n = fread(buf, 1, sizeof(buf) - 1, fp);
  fclose(fp);
  buf[n] = '\0';
  return strstr(buf, "Wawona Android generated") != NULL;
}

static void wwn_android_write_generated_file(const char *path,
                                             const char *contents) {
  if (!path || !contents || !wwn_android_should_write_generated_file(path))
    return;

  FILE *fp = fopen(path, "w");
  if (!fp) {
    LOGE("Shell env: failed to write %s (%s)", path, strerror(errno));
    return;
  }
  fputs(contents, fp);
  fclose(fp);
}

static void wwn_android_write_zsh_defaults(const char *home,
                                           const char *rootfs) {
  if (!home || !home[0] || !rootfs || !rootfs[0])
    return;

  char zshenv[512], zshrc[512], zlogin[512];
  snprintf(zshenv, sizeof(zshenv), "%s/.zshenv", home);
  snprintf(zshrc, sizeof(zshrc), "%s/.zshrc", home);
  snprintf(zlogin, sizeof(zlogin), "%s/.zlogin", home);

  wwn_android_write_generated_file(
      zshenv,
      "# Wawona Android generated .zshenv - safe to edit; Wawona will only\n"
      "# replace this file while this marker remains present.\n"
      ": ${WAWONA_BUNDLE_ROOTFS:=${WAWONA_ROOTFS:-${HOME:h}}}\n"
      "typeset -gU fpath\n"
      "fpath=(\n"
      "  $WAWONA_BUNDLE_ROOTFS/usr/share/zsh/Functions\n"
      "  $WAWONA_BUNDLE_ROOTFS/usr/share/zsh/Functions/**(/N)\n"
      ")\n"
      "if [[ -n \"${WAWONA_ENABLE_COMPINIT:-}\" ]]; then\n"
      "  fpath=(\n"
      "    $WAWONA_BUNDLE_ROOTFS/usr/share/zsh/Completion\n"
      "    $WAWONA_BUNDLE_ROOTFS/usr/share/zsh/Completion/**(/N)\n"
      "    $fpath\n"
      "  )\n"
      "fi\n");

  wwn_android_write_generated_file(
      zshrc,
      "# Wawona Android generated .zshrc - safe to edit; Wawona will only\n"
      "# replace this file while this marker remains present.\n"
      "cd \"$HOME\" 2>/dev/null\n"
      "export HISTFILE=\"$HOME/.zsh_history\"\n"
      "export HISTSIZE=2000\n"
      "export SAVEHIST=2000\n"
      "setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE\n"
      "setopt INTERACTIVE_COMMENTS NO_BEEP NO_NOMATCH\n"
      "unsetopt MONITOR 2>/dev/null\n"
      "PROMPT_EOL_MARK=\"\"\n"
      "PROMPT='%F{cyan}%~%f %# '\n"
      "chpwd_functions=()\n"
      "precmd_functions=( ${precmd_functions:#__vte*} ${precmd_functions:#_vte*} )\n"
      "for __wwn_vte_fn in __vte_osc7 _vte_precmd __vte_precmd; do\n"
      "  (( ${+functions[$__wwn_vte_fn]} )) && unfunction $__wwn_vte_fn 2>/dev/null\n"
      "done\n"
      "unset __wwn_vte_fn\n"
      "precmd() { print -Pn \"\\e]0;%~\\a\" }\n"
      "clear() { print -rn -- $'\\033[2J\\033[H' }\n"
      "command_not_found_handler() {\n"
      "  local cmd=\"$1\"\n"
      "  print -u2 -- \"zsh: command not found: $cmd\"\n"
      "  return 127\n"
      "}\n"
      "if [[ -z \"${WAWONA_ZSH_BANNER_SHOWN:-}\" ]]; then\n"
      "  export WAWONA_ZSH_BANNER_SHOWN=1\n"
      "  print -P \"%F{green}Wawona%f zsh ${ZSH_VERSION} - bundled Android userland.\"\n"
      "  print -P \"%F{blue}Bundled:%f uutils coreutils, fastfetch, neovim, waypipe, ssh/ssh-keygen, niri, fuzzel.\"\n"
      "  print -P \"%F{yellow}Note:%f weston demos launch from Machines (not PATH) until multi-client tabs land.\"\n"
      "  print -P \"%F{yellow}Note:%f ssh is OpenSSH portable (wwn-ssh). Try ssh -V / ssh-keygen -t ed25519.\"\n"
      "fi\n");

  wwn_android_write_generated_file(
      zlogin,
      "# Wawona Android generated .zlogin - safe to edit; Wawona will only\n"
      "# replace this file while this marker remains present.\n"
      "if [[ -z \"${WAWONA_ZSH_BANNER_SHOWN:-}\" ]]; then\n"
      "  export WAWONA_ZSH_BANNER_SHOWN=1\n"
      "  print -P \"%F{green}Wawona%f zsh ${ZSH_VERSION} - bundled Android userland.\"\n"
      "  print -P \"%F{blue}Bundled:%f uutils coreutils, fastfetch, neovim, waypipe, ssh/ssh-keygen, niri, fuzzel.\"\n"
      "  print -P \"%F{yellow}Note:%f weston demos launch from Machines (not PATH) until multi-client tabs land.\"\n"
      "  print -P \"%F{yellow}Note:%f ssh is OpenSSH portable (wwn-ssh). Try ssh -V / ssh-keygen -t ed25519.\"\n"
      "fi\n");

  LOGI("Shell env: zsh defaults ensured in %s (rootfs: %s)", home, rootfs);
}

static void wwn_android_prepare_shell_environment(const char *files_dir) {
  if (!files_dir || !files_dir[0])
    return;

  char rootfs[512];
  snprintf(rootfs, sizeof(rootfs), "%s/wawona-rootfs", files_dir);
  char usr_bin[512];
  snprintf(usr_bin, sizeof(usr_bin), "%s/usr/bin", rootfs);
  mkdir(rootfs, 0755);
  mkdir(usr_bin, 0755);

  if (!g_zsh_bin_path[0])
    resolve_ssh_binary_paths(); /* native lib dir probe lives there today */

  if (g_zsh_bin_path[0]) {
    /* Symlink (not copy. See wwn_android_install_shell_tool) into the
     * rootfs for PATH discoverability ("zsh" typed at the prompt), but
     * SHELL must point at the APK-extracted native lib directly: on API
     * 29+ exec() of files in app-private storage is denied by SELinux
     * (execute_no_trans). */
    char zsh_dest[512];
    snprintf(zsh_dest, sizeof(zsh_dest), "%s/zsh", usr_bin);
    char existing_target[512];
    ssize_t existing_len =
        readlink(zsh_dest, existing_target, sizeof(existing_target) - 1);
    if (existing_len > 0) {
      existing_target[existing_len] = '\0';
      if (strcmp(existing_target, g_zsh_bin_path) != 0) {
        unlink(zsh_dest);
        symlink(g_zsh_bin_path, zsh_dest);
      }
    } else {
      struct stat st;
      if (lstat(zsh_dest, &st) == 0)
        unlink(zsh_dest); /* stale copy from an older build */
      symlink(g_zsh_bin_path, zsh_dest);
    }
    setenv("SHELL", g_zsh_bin_path, 1);
    setenv("WAWONA_SHELL", g_zsh_bin_path, 1);
  }

  char home[512];
  snprintf(home, sizeof(home), "%s/home", rootfs);
  mkdir(home, 0755);

  setenv("WAWONA_BUNDLE_ROOTFS", rootfs, 1);
  setenv("WAWONA_ROOTFS", rootfs, 1);
  setenv("HOME", home, 1);
  setenv("ZDOTDIR", home, 1);
  setenv("USER", "wawona", 1);
  setenv("LOGNAME", "wawona", 1);
  setenv("TERM", "xterm-256color", 1);
  setenv("PROMPT", "%F{cyan}%~%f %# ", 1);
  setenv("PS1", "%F{cyan}%~%f %# ", 1);
  wwn_android_write_zsh_defaults(home, rootfs);

  char share_zsh[512];
  snprintf(share_zsh, sizeof(share_zsh), "%s/usr/share/zsh", rootfs);
  setenv("fpath", share_zsh, 1);

  char xkb_root[512];
  snprintf(xkb_root, sizeof(xkb_root), "%s/usr/share/X11/xkb", rootfs);
  struct stat xkb_st;
  if (stat(xkb_root, &xkb_st) == 0 && S_ISDIR(xkb_st.st_mode)) {
    setenv("WAWONA_XKB_CONFIG_ROOT", xkb_root, 1);
    LOGI("Shell env: XKB_CONFIG_ROOT=%s", xkb_root);
  }

  char weston_data[512];
  snprintf(weston_data, sizeof(weston_data), "%s/usr/share/weston", rootfs);
  struct stat weston_st;
  if (stat(weston_data, &weston_st) == 0 && S_ISDIR(weston_st.st_mode)) {
    setenv("WESTON_DATA_DIR", weston_data, 1);
    LOGI("Shell env: WESTON_DATA_DIR=%s", weston_data);
  } else {
    LOGE("Shell env: missing Weston data at %s (toytoolkit CSD clients may fail)",
         weston_data);
  }

  /* Fontconfig: no system-wide /etc/fonts on Android, so without an explicit
   * config cairo/fontconfig finds zero fonts and toytoolkit clients
   * (weston-terminal, …) render blank text. Mirror the Apple-platform fix
   * (WWNConfigureBundledFontsIfNeeded): generate a fonts.conf pointing at the
   * bundled DejaVu tree plus Android system fonts. */
  if (getenv("FONTCONFIG_FILE") == NULL) {
    char fc_dir[512];
    snprintf(fc_dir, sizeof(fc_dir), "%s/fontconfig", files_dir);
    mkdir(fc_dir, 0755);
    char fc_cache[512];
    snprintf(fc_cache, sizeof(fc_cache), "%s/cache", fc_dir);
    mkdir(fc_cache, 0755);

    char font_dir[512];
    snprintf(font_dir, sizeof(font_dir), "%s/usr/share/fonts", rootfs);

    char fc_conf[512];
    snprintf(fc_conf, sizeof(fc_conf), "%s/fonts.conf", fc_dir);
    FILE *fp = fopen(fc_conf, "w");
    if (fp) {
      fprintf(fp,
              "<?xml version=\"1.0\"?>\n"
              "<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">\n"
              "<fontconfig>\n"
              "  <dir>%s</dir>\n"
              "  <dir>/system/fonts</dir>\n"
              "  <cachedir>%s</cachedir>\n"
              "  <alias>\n"
              "    <family>monospace</family>\n"
              "    <prefer><family>DejaVu Sans Mono</family></prefer>\n"
              "  </alias>\n"
              "  <alias>\n"
              "    <family>sans-serif</family>\n"
              "    <prefer><family>DejaVu Sans</family></prefer>\n"
              "  </alias>\n"
              "</fontconfig>\n",
              font_dir, fc_cache);
      fclose(fp);
      setenv("FONTCONFIG_FILE", fc_conf, 1);
      setenv("FONTCONFIG_PATH", fc_dir, 1);
      LOGI("Shell env: FONTCONFIG_FILE=%s (fonts: %s)", fc_conf, font_dir);

      char mono_font[512];
      snprintf(mono_font, sizeof(mono_font),
               "%s/truetype/DejaVuSansMono.ttf", font_dir);
      struct stat mono_st;
      if (stat(mono_font, &mono_st) == 0)
        setenv("WAWONA_MONO_FONT", mono_font, 1);
      {
        int font_px = (int)(12.0f * g_display_density + 0.5f);
        if (font_px < 12)
          font_px = 12;
        if (font_px > 36)
          font_px = 36;
        char font_size_buf[16];
        snprintf(font_size_buf, sizeof(font_size_buf), "%d", font_px);
        setenv("WAWONA_TERMINAL_FONT_SIZE", font_size_buf, 1);
        LOGI("Shell env: WAWONA_TERMINAL_FONT_SIZE=%s (density=%.2f)",
             font_size_buf, g_display_density);
      }
    } else {
      LOGE("Shell env: failed to write %s (text rendering will be blank)",
           fc_conf);
    }
  }

  char path_buf[768];
  snprintf(path_buf, sizeof(path_buf), "%s:%s", usr_bin, "/system/bin");
  setenv("PATH", path_buf, 1);

  {
    char native_lib_dir[512];
    if (wwn_android_native_lib_dir(native_lib_dir, sizeof(native_lib_dir)) == 0) {
      /* PIE shell tools (waypipe→libzstd.so, etc.) resolve DT_NEEDED from
       * nativeLibraryDir. Without this, exec of usr/bin/waypipe fails with
       * "library \"libzstd.so\" not found" (issue #80). */
      setenv("LD_LIBRARY_PATH", native_lib_dir, 1);
      LOGI("Shell env: LD_LIBRARY_PATH=%s", native_lib_dir);

      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libfastfetch_bin.so",
                                     "fastfetch");
      /* uutils multicall (safe subset): ls/mkdir/whoami/…. Must precede
       * /system/bin on PATH so we do not silently use toybox (issue: whoami). */
      {
        static const char *const cu_utils[] = {
            "coreutils", "ls",       "cat",      "cp",      "mv",     "rm",
            "mkdir",     "rmdir",    "ln",       "touch",   "echo",   "pwd",
            "head",      "tail",     "wc",       "sort",    "cut",    "tr",
            "seq",       "basename", "dirname",  "stat",    "du",     "df",
            "date",      "env",      "printenv", "uname",   "whoami", "yes",
            "tee",       "nl",       "tac",      "fold",    "expand", "unexpand",
            "truncate",
        };
        size_t ci;
        for (ci = 0; ci < sizeof(cu_utils) / sizeof(cu_utils[0]); ci++) {
          wwn_android_install_shell_tool(native_lib_dir, usr_bin,
                                         "libcoreutils_bin.so", cu_utils[ci]);
        }
      }
      /* phoon (wwn-phoon-rs): clean-room Rust moon-phase utility. */
      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libphoon_bin.so",
                                     "phoon");
      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libnvim_bin.so", "nvim");
      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libwaypipe_bin.so",
                                     "waypipe");
      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libwaypipe_bin.so",
                                     "waypipe-rs");
      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libssh_bin.so", "ssh");
      /* wwn-ssh: OpenSSH portable ssh-keygen + scp (not Dropbear). */
      wwn_android_install_shell_tool(native_lib_dir, usr_bin,
                                     "libssh_keygen_bin.so", "ssh-keygen");
      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libscp_bin.so",
                                     "scp");
      wwn_android_install_shell_tool(native_lib_dir, usr_bin,
                                     "libsshpass_bin.so", "sshpass");
      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libniri_bin.so",
                                     "niri");
      /* fuzzel (wwn-niri): niri Mod+D launcher. Same jniLibs PIE pattern. */
      wwn_android_install_shell_tool(native_lib_dir, usr_bin,
                                     "libfuzzel_bin.so", "fuzzel");
      /* foot (wwn-foot): Wayland terminal. Fork/exec libfoot_bin.so. */
      wwn_android_install_shell_tool(native_lib_dir, usr_bin, "libfoot_bin.so",
                                     "foot");
      /* Nested-niri fuzzel catalog Exec=weston-* → multicall PIE that dlopens
       * the real client and inherits niri's WAYLAND_DISPLAY (issue #78). */
      {
        static const char *const wl_execs[] = {
            "weston-simple-shm", "weston-flower",   "weston-clickdot",
            "weston-smoke",      "weston-eventdemo", "weston-resizor",
            "weston-cliptest",   "weston-transformed", "weston-stacking",
            "weston-dnd",        "weston-image",    "weston-scaler",
            "weston-editor",     "weston-constraints",
        };
        size_t wi;
        for (wi = 0; wi < sizeof(wl_execs) / sizeof(wl_execs[0]); wi++) {
          wwn_android_install_shell_tool(native_lib_dir, usr_bin,
                                         "libwawona_wl_bin.so", wl_execs[wi]);
        }
      }
    }
  }

  /* Neovim runtime from APK assets → rootfs (issue #81). */
  {
    char vimruntime[768];
    snprintf(vimruntime, sizeof(vimruntime), "%s/usr/share/nvim/runtime", rootfs);
    if (access(vimruntime, R_OK) == 0) {
      setenv("VIMRUNTIME", vimruntime, 1);
      LOGI("Shell env: VIMRUNTIME=%s", vimruntime);
    } else {
      LOGI("Shell env: VIMRUNTIME missing at %s (nvim may FORTIFY-abort)",
           vimruntime);
    }
  }

  /* Freedesktop catalog for fuzzel (issue #78). share/applications + hicolor
   * live under the synthetic rootfs usr/share (extracted from APK assets). */
  {
    char share_buf[768];
    snprintf(share_buf, sizeof(share_buf), "%s/usr/share", rootfs);
    const char *existing = getenv("XDG_DATA_DIRS");
    if (existing && existing[0]) {
      char combined[1536];
      snprintf(combined, sizeof(combined), "%s:%s", share_buf, existing);
      setenv("XDG_DATA_DIRS", combined, 1);
    } else {
      setenv("XDG_DATA_DIRS", share_buf, 1);
    }
    char data_home[768];
    snprintf(data_home, sizeof(data_home), "%s/home/.local/share", rootfs);
    setenv("XDG_DATA_HOME", data_home, 1);
    char cache_home[768];
    snprintf(cache_home, sizeof(cache_home), "%s/home/.cache", rootfs);
    /* fuzzel, GTK, foot, etc. read XDG_CONFIG_HOME / XDG_CACHE_HOME; without
     * them set+created, config/cache writes fall back to $HOME/.config etc.
     * which may not exist yet. Materialize both so bundled clients have a
     * writable sandbox FS (issue #78 sandbox/rootfs). */
    char config_home[768];
    snprintf(config_home, sizeof(config_home), "%s/home/.config", rootfs);
    char state_home[768];
    snprintf(state_home, sizeof(state_home), "%s/home/.local/state", rootfs);
    setenv("XDG_CACHE_HOME", cache_home, 1);
    setenv("XDG_CONFIG_HOME", config_home, 1);
    setenv("XDG_STATE_HOME", state_home, 1);
    char home_dir[768];
    char local_dir[768];
    snprintf(home_dir, sizeof(home_dir), "%s/home", rootfs);
    snprintf(local_dir, sizeof(local_dir), "%s/home/.local", rootfs);
    mkdir(home_dir, 0755);
    mkdir(local_dir, 0755);
    mkdir(data_home, 0755);
    mkdir(cache_home, 0755);
    mkdir(config_home, 0755);
    mkdir(state_home, 0755);
    LOGI("Shell env: XDG_DATA_DIRS=%s XDG_CONFIG_HOME=%s (fuzzel catalog)",
         share_buf, config_home);
  }

  LOGI("Shell env: ROOTFS=%s SHELL=%s", rootfs, getenv("SHELL") ?: "(unset)");
}

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
     * dirs (cache, files) due to W^X. Exec fails with "Permission denied".
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

    char zshPath[512];
    snprintf(zshPath, sizeof(zshPath), "%s/libzsh_bin.so", nativeLibDir);
    if (stat(zshPath, &st) == 0) {
      strncpy(g_zsh_bin_path, zshPath, sizeof(g_zsh_bin_path) - 1);
      LOGI("[SHELL] Using zsh from native lib: %s", g_zsh_bin_path);
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
  char ssh_key_path[512];
  int ssh_auth_method; /* 0 = password, 1 = publickey */
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

  /* Preserve the AHardwareBuffer-backed zero-copy path unless the machine
   * explicitly disables GPU transport or selects no Vulkan implementation. */
  const char *waypipe_vulkan_driver = WWNSettings_GetVulkanDriver();
  if (g_waypipe_config.no_gpu ||
      (waypipe_vulkan_driver &&
       strcmp(waypipe_vulkan_driver, "none") == 0)) {
    argv[argc++] = "--no-gpu";
  }

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
    // OpenSSH portable supports streamlocal-forward@openssh.com natively.

    if (!g_ssh_bin_path[0]) {
      LOGE("SSH binary (libssh_bin.so) not found. Cannot start waypipe SSH");
      return NULL;
    }

    static char quoted_rcmd[520];
    const char *raw_rcmd = g_waypipe_config.remote_command[0]
                               ? g_waypipe_config.remote_command
                               : "weston-simple-shm";
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
    argv[argc++] = "-o";
    argv[argc++] = "StrictHostKeyChecking=accept-new";
    argv[argc++] = "-o";
    argv[argc++] = "UserKnownHostsFile=/dev/null";
    argv[argc++] = "-T";
    argv[argc++] = "-p";
    argv[argc++] = port_str;
    argv[argc++] = "-l";
    argv[argc++] = g_waypipe_config.ssh_user;
    if (g_waypipe_config.ssh_auth_method == 1 &&
        g_waypipe_config.ssh_key_path[0]) {
      argv[argc++] = "-i";
      argv[argc++] = g_waypipe_config.ssh_key_path;
      argv[argc++] = "-o";
      argv[argc++] = "PreferredAuthentications=publickey";
    } else {
      argv[argc++] = "-o";
      argv[argc++] =
          "PreferredAuthentications=password,keyboard-interactive";
    }
    argv[argc++] = g_waypipe_config.ssh_host;
    argv[argc++] = "--";
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
    jstring sshUser, jstring sshPassword, jstring sshKeyPath, jint sshAuthMethod,
    jstring remoteCommand, jstring compress, jint threads, jstring video,
    jboolean debug, jboolean oneshot, jboolean noGpu, jboolean loginShell,
    jstring titlePrefix, jstring secCtx) {
  (void)thiz;

  if (g_waypipe_running) {
    LOGE("Waypipe is already running");
    return JNI_FALSE;
  }

  memset(&g_waypipe_config, 0, sizeof(g_waypipe_config));
  g_waypipe_config.ssh_enabled = sshEnabled;
  g_waypipe_config.ssh_auth_method = (int)sshAuthMethod;
  g_waypipe_config.threads = threads;
  g_waypipe_config.debug = debug;
  g_waypipe_config.oneshot = oneshot;
  g_waypipe_config.no_gpu = noGpu;
  g_waypipe_config.login_shell = loginShell;

  const char *str;

  str = sshKeyPath ? (*env)->GetStringUTFChars(env, sshKeyPath, NULL) : NULL;
  if (str) {
    strncpy(g_waypipe_config.ssh_key_path, str,
            sizeof(g_waypipe_config.ssh_key_path) - 1);
    (*env)->ReleaseStringUTFChars(env, sshKeyPath, str);
  }

  str = (*env)->GetStringUTFChars(env, sshHost, NULL);
  if (str) {
    /* Support "host:port" syntax. Parse port if present */
    const char *colon = strrchr(str, ':');
    long parsed_port = 0;
    if (colon && colon != str) {
      char *end = NULL;
      parsed_port = strtol(colon + 1, &end, 10);
      if (end && *end == '\0' && parsed_port > 0 && parsed_port < 65536) {
        /* Valid port. Copy only the host part */
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

static _Atomic int g_weston_shm_count = 0;

static void *weston_simple_shm_thread_func(void *arg) {
  (void)arg;
  LOGI("Starting weston-simple-shm background thread");
  if (!weston_simple_shm_main) {
    LOGE("weston-simple-shm symbol is unavailable in this build");
    atomic_fetch_sub(&g_weston_shm_count, 1);
    return NULL;
  }

  // No --width/--height: size is negotiated via xdg_toplevel with Wawona.
  char *argv[] = {"weston-simple-shm", NULL};
  int argc = 1;

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

  atomic_fetch_sub(&g_weston_shm_count, 1);
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonSimpleSHM(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;

  atomic_fetch_add(&g_weston_shm_count, 1);
  pthread_t thread = 0;
  int result = pthread_create(&thread, NULL, weston_simple_shm_thread_func, NULL);
  if (result != 0) {
    LOGE("Failed to create weston-simple-shm thread: %d", result);
    atomic_fetch_sub(&g_weston_shm_count, 1);
    return JNI_FALSE;
  }
  pthread_detach(thread);

  LOGI("weston-simple-shm launched successfully (instances=%d)",
       atomic_load(&g_weston_shm_count));
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWestonSimpleSHM(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;

  if (atomic_load(&g_weston_shm_count) <= 0) {
    LOGI("weston-simple-shm is not running");
    return;
  }

  LOGI("Stopping weston-simple-shm (all instances)...");
  if (&g_simple_shm_running) {
    g_simple_shm_running = 0;
  }
  atomic_store(&g_weston_shm_count, 0);
  LOGI("weston-simple-shm stop requested");
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonSimpleSHMRunning(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  return atomic_load(&g_weston_shm_count) > 0 ? JNI_TRUE : JNI_FALSE;
}

// ============================================================================
// Weston client
// ============================================================================

static int g_weston_running = 0;
static pthread_t g_weston_thread = 0;

static void *weston_thread_func(void *arg) {
  (void)arg;
  LOGI("Starting nested weston_compositor_main background thread");
  if (!weston_compositor_main) {
    LOGE("weston_compositor_main symbol is unavailable in this build");
    g_weston_running = 0;
    return NULL;
  }
  char saved_cwd[512] = "";
  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  if (xdg_dir) {
    getcwd(saved_cwd, sizeof(saved_cwd));
    chdir(xdg_dir);
  }
  wwn_weston_compositor_shutdown_requested = 0;
  /* Deterministic nested socket name so the Swinging Bridge app bridge can attach
   * reliably (WAYLAND_DISPLAY=wayland-0 is Wawona's root Smithay socket; the
   * nested compositor exposes "wawona-nested"). Keep in sync with
   * AnowawSession.NESTED_SOCKET (legacy Kotlin name) (Kotlin) and kWWNSwingingBridgeNestedSocket (macOS). */
  const char *backend = WWNSettings_ResolveCompositorBackend();
  const int use_drm = (backend && strcmp(backend, "drm") == 0);
#ifdef WAWONA_ILAND_GL
  if (use_drm)
    wwn_iland_presenter_android_init();
#endif
  /* DRM/KMS → wwn-iland userspace display stack; Wayland → nested client of
   * the Wawona compositor. Matches macOS Display Backend / --backend. */
  char *argv_drm[] = {"weston", "--backend=drm", "--renderer=gl",
                      "--socket=wawona-nested", "--shell=desktop-shell.so",
                      NULL};
  char *argv_wl[] = {"weston", "--backend=wayland", "--renderer=gl",
                     "--socket=wawona-nested", "--shell=desktop-shell.so",
                     NULL};
  LOGI("weston backend=%s", use_drm ? "drm (wwn-iland)" : "wayland (nested)");
  /* Panel launchers (weston-terminal icon) connect via this named socket. */
  setenv("WAWONA_NESTED_WAYLAND_DISPLAY", "wawona-nested", 1);
  weston_compositor_main(5, use_drm ? argv_drm : argv_wl);
  if (saved_cwd[0])
    chdir(saved_cwd);
  g_weston_running = 0;
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWeston(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  if (!weston_compositor_main) {
    LOGE("Refusing to launch weston: compositor symbol unavailable in this build");
    return JNI_FALSE;
  }
  if (wwn_weston_is_compat_shim && wwn_weston_is_compat_shim() != 0) {
    LOGE("Refusing to launch weston: compatibility shim build detected");
    return JNI_FALSE;
  }
  if (g_weston_running)
    return JNI_FALSE;
  wwn_android_prepare_shell_environment(getenv("WAWONA_FILES_DIR"));
  g_weston_running = 1;
  if (pthread_create(&g_weston_thread, NULL, weston_thread_func, NULL) != 0) {
    g_weston_running = 0;
    return JNI_FALSE;
  }
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWeston(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  if (!g_weston_running)
    return;
  wwn_weston_compositor_shutdown_requested = 1;
  if (g_weston_thread) {
    pthread_join(g_weston_thread, NULL);
    g_weston_thread = 0;
  }
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

static _Atomic int g_weston_terminal_count = 0;

static void *weston_terminal_thread_func(void *arg) {
  (void)arg;
  LOGI("Starting weston-terminal background thread");
  if (!weston_terminal_main) {
    LOGE("weston-terminal symbol is unavailable in this build");
    atomic_fetch_sub(&g_weston_terminal_count, 1);
    return NULL;
  }
  char saved_cwd[512] = "";
  const char *home_dir = getenv("HOME");
  if (home_dir && home_dir[0]) {
    getcwd(saved_cwd, sizeof(saved_cwd));
    if (chdir(home_dir) == 0)
      LOGI("weston-terminal cwd=%s", home_dir);
    else
      LOGE("weston-terminal chdir to HOME %s failed: %s", home_dir,
           strerror(errno));
  }
  // No --maximized / size argv: window size is negotiated via xdg_toplevel
  // with Wawona (initial 0×0 configure → client preferred → host adopts /
  // host resize configures). Do not force client-side size workarounds.
  char *argv[] = {"weston-terminal", NULL};
  weston_terminal_main(1, argv);
  if (saved_cwd[0]) chdir(saved_cwd);
  atomic_fetch_sub(&g_weston_terminal_count, 1);
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonTerminal(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  if (!weston_terminal_main) {
    LOGE("Refusing to launch weston-terminal: symbol unavailable in this build");
    return JNI_FALSE;
  }
  if (wwn_weston_terminal_is_compat_shim &&
      wwn_weston_terminal_is_compat_shim() != 0) {
    LOGE("Refusing to launch weston-terminal: compatibility shim build detected");
    return JNI_FALSE;
  }
  wwn_android_prepare_shell_environment(getenv("WAWONA_FILES_DIR"));
  atomic_fetch_add(&g_weston_terminal_count, 1);
  pthread_t thread = 0;
  if (pthread_create(&thread, NULL, weston_terminal_thread_func, NULL) != 0) {
    atomic_fetch_sub(&g_weston_terminal_count, 1);
    return JNI_FALSE;
  }
  pthread_detach(thread);
  LOGI("weston-terminal launched (instances=%d)",
       atomic_load(&g_weston_terminal_count));
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWestonTerminal(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  atomic_store(&g_weston_terminal_count, 0);
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonTerminalRunning(
    JNIEnv *env, jobject thiz) {
  (void)env; (void)thiz;
  return atomic_load(&g_weston_terminal_count) > 0 ? JNI_TRUE : JNI_FALSE;
}

// ============================================================================
// Generic bundled toytoolkit client launcher (weston-flower, weston-smoke, …)
// ============================================================================

typedef int (*wwn_client_main_fn)(int argc, const char **argv);

typedef struct {
  const char *id;
  wwn_client_main_fn fn;
} WwnClientEntry;

static int kmscube_stub_main(int argc, const char **argv) {
  (void)argc;
  (void)argv;
#ifdef WAWONA_ILAND_GL
  /* Prefer the live host surface size before the client modesets once. */
  if (g_output_width > 0 && g_output_height > 0)
    wwn_iland_presenter_android_set_surface_size(g_output_width,
                                                 g_output_height);
  if (!wwn_iland_presenter_android_launch_kmscube()) {
    LOGE("kmscube unavailable on Android (iland + ANGLE GL client not linked "
         "in this build)");
    return 1;
  }
  while (wwn_iland_presenter_android_is_active()) {
    usleep(100000);
  }
  return 0;
#else
  LOGE("kmscube unavailable on Android (rebuild with iland + ANGLE via gradlegen)");
  return 1;
#endif
}

static int gbm_es2_demo_stub_main(int argc, const char **argv) {
  (void)argc;
  (void)argv;
#ifdef WAWONA_ILAND_GL
  if (g_output_width > 0 && g_output_height > 0)
    wwn_iland_presenter_android_set_surface_size(g_output_width,
                                                 g_output_height);
  if (!wwn_iland_presenter_android_launch_gbm_es2_demo()) {
    LOGE("gbm-es2-demo unavailable on Android (iland + ANGLE GL client not "
         "linked in this build)");
    return 1;
  }
  while (wwn_iland_presenter_android_is_active()) {
    usleep(100000);
  }
  return 0;
#else
  LOGE("gbm-es2-demo unavailable on Android (rebuild with iland + ANGLE)");
  return 1;
#endif
}

static int opengl_cube_stub_main(int argc, const char **argv) {
#ifdef WAWONA_ILAND_GL
  /* Wayland-EGL client. Posts AHB dmabuf buffers to the compositor. Do not
   * start the KMS presenter (that path is kmscube-only). */
  if (!opengl_cube_main) {
    LOGE("opengl-cube unavailable (libopengl_cube.a not linked)");
    return 1;
  }
  (void)argc;
  (void)argv;
  char *mutable_argv[] = {(char *)"opengl-cube", NULL};
  return opengl_cube_main(1, mutable_argv);
#else
  (void)argc;
  (void)argv;
  LOGE("opengl-cube unavailable on Android (rebuild with iland + ANGLE via gradlegen)");
  return 1;
#endif
}

static int vkcube_stub_main(int argc, const char **argv) {
  if (!vkcube_main) {
    LOGE("vkcube unavailable (libvkcube.a not linked)");
    return 1;
  }
  char *mutable_argv[] = {(char *)"vkcube", NULL};
  return vkcube_main(1, mutable_argv);
}

static int simple_egl_stub_main(int argc, const char **argv) {
  if (!simple_egl_main) {
    LOGE("weston-simple-egl unavailable in this build (simple_egl_main not "
         "linked)");
    return 1;
  }
  return simple_egl_main(argc, argv);
}

static const WwnClientEntry kBundledClients[] = {
    {"weston-simple-shm", weston_simple_shm_main},
    {"weston-terminal", weston_terminal_main},
    /* foot is fork/exec'd as libfoot_bin.so (see wwn_launch_foot), not
     * launched via the in-process foot_main dlopen stub. */
    {"weston-flower", flower_main},
    {"weston-clickdot", clickdot_main},
    {"weston-smoke", smoke_main},
    {"weston-eventdemo", eventdemo_main},
    {"weston-resizor", resizor_main},
    {"weston-cliptest", cliptest_main},
    {"weston-transformed", transformed_main},
    {"weston-stacking", stacking_main},
    {"weston-dnd", dnd_main},
    {"weston-image", image_main},
    {"weston-scaler", scaler_main},
    {"weston-editor", editor_main},
    {"weston-constraints", constraints_main},
    {"weston-simple-egl", simple_egl_stub_main},
    {"kmscube", kmscube_stub_main},
    {"gbm-es2-demo", gbm_es2_demo_stub_main},
    {"opengl-cube", opengl_cube_stub_main},
    {"vkcube", vkcube_stub_main},
};

static wwn_client_main_fn wwn_client_main_for_id(const char *client_id) {
  if (!client_id)
    return NULL;
  for (size_t i = 0; i < sizeof(kBundledClients) / sizeof(kBundledClients[0]);
       i++) {
    if (strcmp(client_id, kBundledClients[i].id) == 0)
      return kBundledClients[i].fn;
  }
  return NULL;
}

static jboolean wwn_foot_binary_available(void) {
  char native_lib_dir[512];
  char foot_path[560];
  if (wwn_android_native_lib_dir(native_lib_dir, sizeof(native_lib_dir)) != 0)
    return JNI_FALSE;
  snprintf(foot_path, sizeof(foot_path), "%s/libfoot_bin.so", native_lib_dir);
  return access(foot_path, X_OK) == 0 ? JNI_TRUE : JNI_FALSE;
}

/* Refuse only when the companion libfoot.so explicitly reports shim=1.
 * Missing symbol / dlopen failure does not block a real libfoot_bin.so. */
static int wwn_foot_compat_shim_value(void) {
  if (wwn_foot_is_compat_shim)
    return wwn_foot_is_compat_shim();
  void *handle = dlopen("libfoot.so", RTLD_NOW | RTLD_LOCAL);
  if (!handle)
    return 0;
  dlerror();
  int (*fn)(void) = (int (*)(void))dlsym(handle, "wwn_foot_is_compat_shim");
  int value = (fn != NULL) ? fn() : 0;
  dlclose(handle);
  return value;
}

static jboolean wwn_bundled_client_available(const char *client_id) {
  if (!client_id || client_id[0] == '\0')
    return JNI_FALSE;
  if (strcmp(client_id, "foot") == 0) {
    if (wwn_foot_binary_available() && wwn_foot_compat_shim_value() == 0)
      return JNI_TRUE;
    /* Shim-only builds fall back to weston-terminal on launch. */
    if (weston_terminal_main)
      return JNI_TRUE;
    LOGE("foot unavailable (no libfoot_bin.so and no weston-terminal fallback)");
    return JNI_FALSE;
  }
  if (strcmp(client_id, "kmscube") == 0) {
    if (!kmscube_main) {
      LOGE("kmscube unavailable on Android (iland + ANGLE GL client not linked "
           "in this build)");
      return JNI_FALSE;
    }
    return JNI_TRUE;
  }
  if (strcmp(client_id, "gbm-es2-demo") == 0) {
    extern int gbm_es2_demo_main(int argc, char **argv) __attribute__((weak));
    if (!gbm_es2_demo_main) {
      LOGE("gbm-es2-demo unavailable on Android (not linked in this build)");
      return JNI_FALSE;
    }
    return JNI_TRUE;
  }
  if (strcmp(client_id, "weston-simple-egl") == 0) {
    if (!simple_egl_main) {
      LOGE("weston-simple-egl unavailable in this build (simple_egl_main not "
           "linked)");
      return JNI_FALSE;
    }
    return JNI_TRUE;
  }
  if (strcmp(client_id, "weston-smoke") == 0) {
    if (!smoke_main) {
      LOGE("weston-smoke unavailable in this build (smoke_main not linked)");
      return JNI_FALSE;
    }
    return JNI_TRUE;
  }
  if (strcmp(client_id, "weston") == 0) {
    // Nested weston runs through its dedicated launcher, but the UI lists it
    // in the same bundled-client picker. Report real availability here.
    if (!weston_compositor_main) {
      LOGE("weston unavailable in this build (weston_compositor_main not "
           "linked)");
      return JNI_FALSE;
    }
    if (wwn_weston_is_compat_shim && wwn_weston_is_compat_shim() != 0) {
      LOGE("weston unavailable: compatibility shim build detected");
      return JNI_FALSE;
    }
    return JNI_TRUE;
  }
  return wwn_client_main_for_id(client_id) ? JNI_TRUE : JNI_FALSE;
}

static _Atomic int g_bundled_client_count = 0;
static char g_bundled_client_id[64] = "";
static pthread_mutex_t g_bundled_client_mu = PTHREAD_MUTEX_INITIALIZER;

typedef struct {
  char id[64];
} bundled_client_thread_arg_t;

static void *bundled_client_thread_func(void *arg) {
  bundled_client_thread_arg_t *params = (bundled_client_thread_arg_t *)arg;
  char client_id[64] = "";
  if (params) {
    snprintf(client_id, sizeof(client_id), "%s", params->id);
    free(params);
  }

  wwn_client_main_fn fn = wwn_client_main_for_id(client_id);
  if (!fn) {
    LOGE("No bundled client entry for '%s'", client_id);
    atomic_fetch_sub(&g_bundled_client_count, 1);
    return NULL;
  }

  if (strcmp(client_id, "weston") == 0) {
    LOGE("Use nativeRunWeston() for nested compositor (not bundled client table)");
    atomic_fetch_sub(&g_bundled_client_count, 1);
    return NULL;
  }
  if (strcmp(client_id, "weston-terminal") == 0 &&
      wwn_weston_terminal_is_compat_shim &&
      wwn_weston_terminal_is_compat_shim() != 0) {
    LOGE("Refusing to launch weston-terminal: compatibility shim build detected");
    atomic_fetch_sub(&g_bundled_client_count, 1);
    return NULL;
  }

  LOGI("Starting bundled client '%s'", client_id);
  char saved_cwd[512] = "";
  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  if (xdg_dir) {
    getcwd(saved_cwd, sizeof(saved_cwd));
    chdir(xdg_dir);
  }

  const char *argv[] = {client_id, NULL};
  int result = fn(1, argv);
  LOGI("Bundled client '%s' returned %d", client_id, result);

  if (saved_cwd[0])
    chdir(saved_cwd);
  if (atomic_fetch_sub(&g_bundled_client_count, 1) <= 1) {
    pthread_mutex_lock(&g_bundled_client_mu);
    g_bundled_client_id[0] = '\0';
    pthread_mutex_unlock(&g_bundled_client_mu);
  }
  return NULL;
}

/* niri (wwn-niri): nested scrollable-tiling compositor. Unlike the in-process
 * client table, niri ships as a PIE executable (libniri_bin.so, waypipe
 * pattern) and is fork/exec'd from the exec-allowed nativeLibraryDir as a
 * Wayland client of the Wawona compositor (NIRI_BACKEND=nested). It then
 * serves its own scrollable-tiling clients on a child socket inside
 * XDG_RUNTIME_DIR. */
static pid_t g_niri_pids[WWN_MAX_NATIVE_CLIENT_PIDS];
static int g_niri_pid_count = 0;
static pthread_mutex_t g_niri_mu = PTHREAD_MUTEX_INITIALIZER;

static void wwn_niri_reap(void) {
  pthread_mutex_lock(&g_niri_mu);
  int dst = 0;
  for (int i = 0; i < g_niri_pid_count; i++) {
    pid_t pid = g_niri_pids[i];
    if (pid <= 0)
      continue;
    if (waitpid(pid, NULL, WNOHANG) == 0)
      g_niri_pids[dst++] = pid;
  }
  g_niri_pid_count = dst;
  pthread_mutex_unlock(&g_niri_mu);
}

static int wwn_niri_running(void) {
  wwn_niri_reap();
  pthread_mutex_lock(&g_niri_mu);
  int n = g_niri_pid_count;
  pthread_mutex_unlock(&g_niri_mu);
  return n > 0;
}

static jboolean wwn_launch_niri_nested(void) {
  wwn_niri_reap();

  char native_lib_dir[512];
  char niri_path[560];
  if (wwn_android_native_lib_dir(native_lib_dir, sizeof(native_lib_dir)) != 0) {
    LOGE("niri: could not resolve native lib dir");
    return JNI_FALSE;
  }
  snprintf(niri_path, sizeof(niri_path), "%s/libniri_bin.so", native_lib_dir);
  if (access(niri_path, X_OK) != 0) {
    LOGE("niri binary not found or not executable at %s: %s", niri_path,
         strerror(errno));
    return JNI_FALSE;
  }

  const char *backend = WWNSettings_ResolveCompositorBackend();
  const int use_drm = (backend && strcmp(backend, "drm") == 0);
#ifdef WAWONA_ILAND_GL
  /* Presenter lives in the Wawona process (parent); niri DRM page-flips into
   * iland and the host composites the AHB overlay. Init before fork. */
  if (use_drm)
    wwn_iland_presenter_android_init();
#endif

  pid_t pid = fork();
  if (pid == 0) {
    /* WAYLAND_DISPLAY and XDG_RUNTIME_DIR are inherited from the app
     * process. Honour Display Backend: drm → niri tty/DRM path over
     * wwn-iland; otherwise nested Wayland client of Wawona. */
    setenv("NIRI_BACKEND", use_drm ? "tty" : "nested", 1);
    /* The exec'd binary leaves the app's linker namespace, so its NEEDED
     * libs (libwayland-*, libxkbcommon bundled in jniLibs) must be found
     * via LD_LIBRARY_PATH. */
    setenv("LD_LIBRARY_PATH", native_lib_dir, 1);
    const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_dir)
      chdir(xdg_dir);
    /* argv[0] must be a realpath()-able path: Berberis (arm64-on-x86 emu)
     * rejects bare "niri" with "Unable to get realpath of niri". */
    const char *argv_niri[] = {niri_path, NULL};
    execv(niri_path, (char *const *)argv_niri);
    _exit(127);
  }
  if (pid < 0) {
    LOGE("niri: fork failed: %s", strerror(errno));
    return JNI_FALSE;
  }
  pthread_mutex_lock(&g_niri_mu);
  if (g_niri_pid_count < WWN_MAX_NATIVE_CLIENT_PIDS) {
    g_niri_pids[g_niri_pid_count++] = pid;
  } else {
    LOGE("niri: pid table full. Orphaning PID %d", (int)pid);
  }
  int instances = g_niri_pid_count;
  pthread_mutex_unlock(&g_niri_mu);
  LOGI("Launched niri (nested compositor) PID %d from %s (instances=%d)",
       (int)pid, niri_path, instances);
  return JNI_TRUE;
}

static void wwn_stop_niri(void) {
  pthread_mutex_lock(&g_niri_mu);
  for (int i = 0; i < g_niri_pid_count; i++) {
    pid_t pid = g_niri_pids[i];
    if (pid > 0) {
      kill(pid, SIGTERM);
      waitpid(pid, NULL, WNOHANG);
    }
  }
  g_niri_pid_count = 0;
  pthread_mutex_unlock(&g_niri_mu);
}

/* Launch a nested-niri catalog client (libwawona_wl_bin.so multicall) against
 * niri's child Wayland socket. Must be fork/exec'd from the app process so
 * Berberis (arm64-on-x86) can translate it. Adb shell exec fails to link. */
static jboolean wwn_launch_nested_wl_client(const char *exec_name) {
  char native_lib_dir[512];
  char wl_bin[560];
  char nested[128];
  const char *xdg;
  DIR *dir;
  struct dirent *ent;

  if (!exec_name || !exec_name[0])
    return JNI_FALSE;
  if (wwn_android_native_lib_dir(native_lib_dir, sizeof(native_lib_dir)) != 0) {
    LOGE("nested wl client: no native lib dir");
    return JNI_FALSE;
  }
  snprintf(wl_bin, sizeof(wl_bin), "%s/libwawona_wl_bin.so", native_lib_dir);
  if (access(wl_bin, X_OK) != 0) {
    LOGE("nested wl client: missing %s", wl_bin);
    return JNI_FALSE;
  }
  xdg = getenv("XDG_RUNTIME_DIR");
  if (!xdg || !xdg[0]) {
    LOGE("nested wl client: XDG_RUNTIME_DIR unset");
    return JNI_FALSE;
  }
  nested[0] = '\0';
  dir = opendir(xdg);
  if (!dir) {
    LOGE("nested wl client: opendir(%s) failed: %s", xdg, strerror(errno));
    return JNI_FALSE;
  }
  while ((ent = readdir(dir)) != NULL) {
    const char *n = ent->d_name;
    if (strncmp(n, "wayland-", 8) != 0)
      continue;
    if (strstr(n, ".lock"))
      continue;
    if (strcmp(n, "wayland-0") == 0)
      continue;
    snprintf(nested, sizeof(nested), "%s", n);
    break;
  }
  closedir(dir);
  if (!nested[0]) {
    LOGE("nested wl client: no nested wayland-* socket in %s", xdg);
    return JNI_FALSE;
  }

  pid_t pid = fork();
  if (pid == 0) {
    setenv("LD_LIBRARY_PATH", native_lib_dir, 1);
    setenv("WAYLAND_DISPLAY", nested, 1);
    setenv("WAWONA_WL_EXEC", exec_name, 1);
    chdir(xdg);
    const char *argv_wl[] = {wl_bin, exec_name, NULL};
    execv(wl_bin, (char *const *)argv_wl);
    _exit(127);
  }
  if (pid < 0) {
    LOGE("nested wl client: fork failed: %s", strerror(errno));
    return JNI_FALSE;
  }
  LOGI("Launched nested wl client '%s' PID %d on %s via %s", exec_name,
       (int)pid, nested, wl_bin);
  return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunNestedWlClient(
    JNIEnv *env, jobject thiz, jstring execName) {
  (void)thiz;
  if (!execName)
    return JNI_FALSE;
  const char *utf = (*env)->GetStringUTFChars(env, execName, NULL);
  if (!utf)
    return JNI_FALSE;
  jboolean ok = wwn_launch_nested_wl_client(utf);
  (*env)->ReleaseStringUTFChars(env, execName, utf);
  return ok;
}

/* foot (wwn-foot): Wayland terminal as PIE libfoot_bin.so. Fork/exec like niri
 * so the terminal runs out-of-process with its own main(). */
static pid_t g_foot_pids[WWN_MAX_NATIVE_CLIENT_PIDS];
static int g_foot_pid_count = 0;
static pthread_mutex_t g_foot_mu = PTHREAD_MUTEX_INITIALIZER;

static void wwn_foot_reap(void) {
  pthread_mutex_lock(&g_foot_mu);
  int dst = 0;
  for (int i = 0; i < g_foot_pid_count; i++) {
    pid_t pid = g_foot_pids[i];
    if (pid <= 0)
      continue;
    if (waitpid(pid, NULL, WNOHANG) == 0)
      g_foot_pids[dst++] = pid;
  }
  g_foot_pid_count = dst;
  pthread_mutex_unlock(&g_foot_mu);
}

static int wwn_foot_running(void) {
  wwn_foot_reap();
  pthread_mutex_lock(&g_foot_mu);
  int n = g_foot_pid_count;
  pthread_mutex_unlock(&g_foot_mu);
  return n > 0;
}

static jboolean wwn_launch_foot(void) {
  wwn_foot_reap();
  if (wwn_foot_compat_shim_value() != 0) {
    /* Old APKs shipped a weston-simple-shm stub as "foot". That paints a
     * black/empty surface. Prefer the real in-process terminal instead. */
    LOGI("foot compat shim detected. Falling back to weston-terminal");
    return Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonTerminal(
        NULL, NULL);
  }

  char native_lib_dir[512];
  char foot_path[560];
  if (wwn_android_native_lib_dir(native_lib_dir, sizeof(native_lib_dir)) != 0) {
    LOGE("foot: could not resolve native lib dir");
    return JNI_FALSE;
  }
  snprintf(foot_path, sizeof(foot_path), "%s/libfoot_bin.so", native_lib_dir);
  if (access(foot_path, X_OK) != 0) {
    LOGE("foot binary not found or not executable at %s: %s", foot_path,
         strerror(errno));
    return JNI_FALSE;
  }

  const char *files_dir = getenv("WAWONA_FILES_DIR");
  if (files_dir && files_dir[0])
    wwn_android_prepare_shell_environment(files_dir);
  setenv("TERM", "xterm-256color", 1);

  /* Explicit foot.ini with DejaVu path. Same pattern as macOS launchFoot.
   * Relying on fontconfig "monospace" alone still yields a blank window when
   * fcft fails to resolve a face. */
  char ini_path[560];
  const char *xdg_runtime = getenv("XDG_RUNTIME_DIR");
  if (xdg_runtime && xdg_runtime[0])
    snprintf(ini_path, sizeof(ini_path), "%s/wawona-foot.ini", xdg_runtime);
  else if (files_dir && files_dir[0])
    snprintf(ini_path, sizeof(ini_path), "%s/wawona-foot.ini", files_dir);
  else
    snprintf(ini_path, sizeof(ini_path), "/data/local/tmp/wawona-foot.ini");

  const char *mono = getenv("WAWONA_MONO_FONT");
  const char *font_size = getenv("WAWONA_TERMINAL_FONT_SIZE");
  int size_px = 14;
  if (font_size && font_size[0]) {
    int parsed = atoi(font_size);
    if (parsed >= 10 && parsed <= 48)
      size_px = parsed;
  }
  {
    FILE *fp = fopen(ini_path, "w");
    if (fp) {
      if (mono && mono[0] && access(mono, R_OK) == 0)
        fprintf(fp, "[main]\nterm=xterm-256color\nfont=%s:size=%d\ndpi-aware=yes\n\n", mono,
                size_px);
      else
        fprintf(fp, "[main]\nterm=xterm-256color\nfont=monospace:size=%d\ndpi-aware=yes\n\n",
                size_px);
      fputs("[tweak]\nfont-monospace-warn=no\n", fp);
      fclose(fp);
    } else {
      LOGE("foot: failed to write %s: %s", ini_path, strerror(errno));
      ini_path[0] = '\0';
    }
  }

  pid_t pid = fork();
  if (pid == 0) {
    setenv("LD_LIBRARY_PATH", native_lib_dir, 1);
    setenv("TERM", "xterm-256color", 1);
    setenv("COLORTERM", "truecolor", 1);
    if (xdg_runtime && xdg_runtime[0])
      chdir(xdg_runtime);
    const char *shell = getenv("SHELL");
    /* argv[0] must be realpath()-able for Berberis (arm64-on-x86 emu). */
    if (ini_path[0] && shell && shell[0]) {
      const char *argv_foot[] = {foot_path, "-t", "xterm-256color", "-o",
                                 "tweak.font-monospace-warn=no", "-c",
                                 ini_path, shell, NULL};
      execv(foot_path, (char *const *)argv_foot);
    } else if (ini_path[0]) {
      const char *argv_foot[] = {foot_path, "-t", "xterm-256color", "-o",
                                 "tweak.font-monospace-warn=no", "-c",
                                 ini_path, NULL};
      execv(foot_path, (char *const *)argv_foot);
    } else if (shell && shell[0]) {
      const char *argv_foot[] = {foot_path, "-t", "xterm-256color", shell,
                                 NULL};
      execv(foot_path, (char *const *)argv_foot);
    } else {
      const char *argv_foot[] = {foot_path, NULL};
      execv(foot_path, (char *const *)argv_foot);
    }
    _exit(127);
  }
  if (pid < 0) {
    LOGE("foot: fork failed: %s", strerror(errno));
    return JNI_FALSE;
  }
  pthread_mutex_lock(&g_foot_mu);
  if (g_foot_pid_count < WWN_MAX_NATIVE_CLIENT_PIDS) {
    g_foot_pids[g_foot_pid_count++] = pid;
  } else {
    LOGE("foot: pid table full. Orphaning PID %d", (int)pid);
  }
  int instances = g_foot_pid_count;
  pthread_mutex_unlock(&g_foot_mu);
  LOGI("Launched foot PID %d from %s (ini=%s instances=%d)", (int)pid, foot_path,
       ini_path[0] ? ini_path : "(none)", instances);
  return JNI_TRUE;
}

static void wwn_stop_foot(void) {
  pthread_mutex_lock(&g_foot_mu);
  for (int i = 0; i < g_foot_pid_count; i++) {
    pid_t pid = g_foot_pids[i];
    if (pid > 0) {
      kill(pid, SIGTERM);
      waitpid(pid, NULL, WNOHANG);
    }
  }
  g_foot_pid_count = 0;
  pthread_mutex_unlock(&g_foot_mu);
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunBundledClient(
    JNIEnv *env, jobject thiz, jstring clientId) {
  (void)thiz;
  if (!clientId)
    return JNI_FALSE;

  const char *id_utf = (*env)->GetStringUTFChars(env, clientId, NULL);
  if (!id_utf)
    return JNI_FALSE;

  // Nested weston is not in the client-main table (it has its own thread and
  // shutdown flag). Route it to its dedicated launcher instead of failing.
  if (strcmp(id_utf, "weston") == 0) {
    (*env)->ReleaseStringUTFChars(env, clientId, id_utf);
    return Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWeston(env,
                                                                       thiz);
  }

  /* niri (wwn-niri) is exec'd out-of-process (waypipe pattern), not routed
   * through the in-process client-main table. */
  if (strcmp(id_utf, "niri") == 0) {
    (*env)->ReleaseStringUTFChars(env, clientId, id_utf);
    return wwn_launch_niri_nested();
  }

  /* foot (wwn-foot): same out-of-process PIE pattern as niri. */
  if (strcmp(id_utf, "foot") == 0) {
    (*env)->ReleaseStringUTFChars(env, clientId, id_utf);
    return wwn_launch_foot();
  }

  if (!wwn_bundled_client_available(id_utf)) {
    LOGE("Bundled client unavailable: %s", id_utf);
    (*env)->ReleaseStringUTFChars(env, clientId, id_utf);
    return JNI_FALSE;
  }

  bundled_client_thread_arg_t *params = calloc(1, sizeof(*params));
  if (!params) {
    (*env)->ReleaseStringUTFChars(env, clientId, id_utf);
    return JNI_FALSE;
  }
  snprintf(params->id, sizeof(params->id), "%s", id_utf);
  (*env)->ReleaseStringUTFChars(env, clientId, id_utf);

  pthread_mutex_lock(&g_bundled_client_mu);
  snprintf(g_bundled_client_id, sizeof(g_bundled_client_id), "%s", params->id);
  pthread_mutex_unlock(&g_bundled_client_mu);
  atomic_fetch_add(&g_bundled_client_count, 1);

  pthread_t thread = 0;
  if (pthread_create(&thread, NULL, bundled_client_thread_func, params) != 0) {
    free(params);
    atomic_fetch_sub(&g_bundled_client_count, 1);
    return JNI_FALSE;
  }
  pthread_detach(thread);
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopBundledClient(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  atomic_store(&g_bundled_client_count, 0);
  pthread_mutex_lock(&g_bundled_client_mu);
  if (strcmp(g_bundled_client_id, "weston-simple-shm") == 0 &&
      &g_simple_shm_running) {
    g_simple_shm_running = 0;
  }
  g_bundled_client_id[0] = '\0';
  pthread_mutex_unlock(&g_bundled_client_mu);
  wwn_stop_niri();
  wwn_stop_foot();
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsBundledClientRunning(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  if (wwn_foot_running())
    return JNI_TRUE;
  if (wwn_niri_running())
    return JNI_TRUE;
  return atomic_load(&g_bundled_client_count) > 0 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetRunningBundledClientId(
    JNIEnv *env, jobject thiz) {
  (void)thiz;
  if (wwn_foot_running())
    return (*env)->NewStringUTF(env, "foot");
  if (wwn_niri_running())
    return (*env)->NewStringUTF(env, "niri");
  pthread_mutex_lock(&g_bundled_client_mu);
  int running = atomic_load(&g_bundled_client_count) > 0 &&
                g_bundled_client_id[0] != '\0';
  char id_copy[64] = "";
  if (running)
    snprintf(id_copy, sizeof(id_copy), "%s", g_bundled_client_id);
  pthread_mutex_unlock(&g_bundled_client_mu);
  if (!running)
    return NULL;
  return (*env)->NewStringUTF(env, id_copy);
}

// ============================================================================
// Foot client
// ============================================================================

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunFoot(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  return wwn_launch_foot();
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopFoot(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  wwn_stop_foot();
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsFootRunning(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  return wwn_foot_running() ? JNI_TRUE : JNI_FALSE;
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
// Test SSH: OpenSSH portable connection + auth test via fork/exec
// ---------------------------------------------------------------------------
#include <poll.h>

JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestSSH(
    JNIEnv *, jobject, jstring, jstring, jstring, jint, jstring, jint);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestSSH(
    JNIEnv *env, jobject thiz, jstring host, jstring user, jstring password,
    jint port, jstring keyPath, jint authMethod) {
  (void)thiz;
  const char *host_str = (*env)->GetStringUTFChars(env, host, NULL);
  const char *user_str = (*env)->GetStringUTFChars(env, user, NULL);
  const char *pass_str = (*env)->GetStringUTFChars(env, password, NULL);
  const char *key_str =
      keyPath ? (*env)->GetStringUTFChars(env, keyPath, NULL) : NULL;
  char result[2048];
  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", port);

  LOGI("Testing SSH connection to %s@%s:%d (OpenSSH auth=%d)", user_str,
       host_str, port, (int)authMethod);

  resolve_ssh_binary_paths();

  /* Ensure XDG_RUNTIME_DIR (and thus HOME for OpenSSH known_hosts) before fork */
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

    if (pass_str && pass_str[0] != '\0' && authMethod == 0) {
      setenv("SSHPASS", pass_str, 1);
    }
    /* OpenSSH needs HOME for known_hosts; use XDG_RUNTIME_DIR (writable). */
    {
      const char *xdg = getenv("XDG_RUNTIME_DIR");
      if (xdg)
        setenv("HOME", xdg, 1);
    }

    char target[512];
    if (user_str[0])
      snprintf(target, sizeof(target), "%s@%s", user_str, host_str);
    else
      snprintf(target, sizeof(target), "%s", host_str);

    /* argv[0] must be realpath()-able for Berberis (arm64-on-x86 emu). */
    char *argv_ssh[24];
    int a = 0;
    argv_ssh[a++] = g_ssh_bin_path;
    argv_ssh[a++] = "-o";
    argv_ssh[a++] = "StrictHostKeyChecking=accept-new";
    argv_ssh[a++] = "-o";
    argv_ssh[a++] = "UserKnownHostsFile=/dev/null";
    argv_ssh[a++] = "-T";
    argv_ssh[a++] = "-p";
    argv_ssh[a++] = port_str;
    if (authMethod == 1 && key_str && key_str[0]) {
      argv_ssh[a++] = "-i";
      argv_ssh[a++] = (char *)key_str;
      argv_ssh[a++] = "-o";
      argv_ssh[a++] = "PreferredAuthentications=publickey";
    } else {
      argv_ssh[a++] = "-o";
      argv_ssh[a++] =
          "PreferredAuthentications=password,keyboard-interactive";
    }
    argv_ssh[a++] = target;
    argv_ssh[a++] = "uname -a";
    argv_ssh[a] = NULL;
    LOGI("[SSH Test] exec OpenSSH -T -p %s %s", port_str, target);
    execv(g_ssh_bin_path, argv_ssh);

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
             "OK: SSH connected and authenticated (OpenSSH)\nRemote: "
             "%s\nLatency: %ldms",
             uname_buf, latency_ms);
  } else {
    const char *out = uname_buf[0] ? uname_buf : err_buf;
    snprintf(result, sizeof(result),
             "FAIL: SSH failed (exit %d)\nHost: %s\nOutput: %s\nLatency: %ldms",
             WIFEXITED(status) ? WEXITSTATUS(status) : -1,
             host_str, out[0] ? out : "(no output)", latency_ms);
    if (out[0] &&
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
  if (keyPath && key_str)
    (*env)->ReleaseStringUTFChars(env, keyPath, key_str);
  return (*env)->NewStringUTF(env, result);
}

static volatile int g_mobile_vm_running = 0;

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeLaunchMobileVm(
    JNIEnv *env, jclass clazz, jstring guest_dir, jint memory_mb) {
  (void)clazz;
  (void)memory_mb;
  const char *dir = (*env)->GetStringUTFChars(env, guest_dir, NULL);
  if (!dir)
    return JNI_FALSE;
  struct stat st;
  char rootfs[512];
  snprintf(rootfs, sizeof(rootfs), "%s/rootfs.img", dir);
  int ok = (stat(rootfs, &st) == 0 && S_ISREG(st.st_mode));
  if (ok) {
    g_mobile_vm_running = 1;
    LOGI("mobile VM lane: guest at %s (embed QEMU engine to boot)", dir);
  } else {
    LOGE("mobile VM: missing %s", rootfs);
  }
  (*env)->ReleaseStringUTFChars(env, guest_dir, dir);
  return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopMobileVm(JNIEnv *env,
                                                               jclass clazz) {
  (void)env;
  (void)clazz;
  g_mobile_vm_running = 0;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsMobileVmRunning(
    JNIEnv *env, jclass clazz) {
  (void)env;
  (void)clazz;
  return g_mobile_vm_running ? JNI_TRUE : JNI_FALSE;
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
