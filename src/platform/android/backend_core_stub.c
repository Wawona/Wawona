#include <stddef.h>
#include <stdint.h>

typedef struct CRenderNode CRenderNode;

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

typedef struct {
  uint64_t event_type;
  uint64_t window_id;
  uint32_t surface_id;
  char *title;
  uint32_t width, height;
  uint64_t parent_id;
  int32_t x, y;
  uint8_t decoration_mode;
  uint8_t fullscreen_shell;
  uint16_t padding;
  uint8_t size_kind;
  uint8_t size_cause;
  uint32_t configure_serial;
  uint64_t transaction_id;
} CWindowEvent;

typedef struct {
  uint64_t capture_id;
  void *ptr;
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  size_t size;
} CScreencopyRequest;

void *WWNCoreNew(void) { return NULL; }
int WWNCoreStart(void *core, const char *socket_name) {
  (void)core;
  (void)socket_name;
  return 0;
}
int WWNCoreStop(void *core) {
  (void)core;
  return 0;
}
int WWNCoreIsRunning(const void *core) {
  (void)core;
  return 0;
}
int WWNCoreProcessEvents(void *core) {
  (void)core;
  return 0;
}
void WWNCoreSetOutputSize(void *core, uint32_t width, uint32_t height, float scale) {
  (void)core;
  (void)width;
  (void)height;
  (void)scale;
}
void WWNCoreSetSafeAreaInsets(void *core, int32_t top, int32_t right, int32_t bottom, int32_t left) {
  (void)core;
  (void)top;
  (void)right;
  (void)bottom;
  (void)left;
}
void WWNCoreSetForceSSD(void *core, int enabled) {
  (void)core;
  (void)enabled;
}
void WWNCoreFree(void *core) { (void)core; }
CRenderScene *WWNCoreGetRenderScene(void *core) {
  (void)core;
  return NULL;
}
void WWNRenderSceneFree(CRenderScene *scene) { (void)scene; }
CBufferData *WWNCorePopPendingBuffer(void *core) {
  (void)core;
  return NULL;
}
void WWNBufferDataFree(CBufferData *data) { (void)data; }
void WWNCoreNotifyFramePresented(void *core, uint32_t surface_id, uint64_t buffer_id, uint32_t timestamp) {
  (void)core;
  (void)surface_id;
  (void)buffer_id;
  (void)timestamp;
}
void WWNCoreFlushClients(void *core) { (void)core; }
CWindowEvent *WWNCorePopWindowEvent(void *core) {
  (void)core;
  return NULL;
}
void WWNWindowEventFree(CWindowEvent *event) { (void)event; }
CScreencopyRequest WWNCoreGetPendingScreencopy(void *core) {
  (void)core;
  CScreencopyRequest req = {0};
  return req;
}
void WWNCoreScreencopyDone(void *core, uint64_t capture_id) {
  (void)core;
  (void)capture_id;
}
void WWNCoreScreencopyFailed(void *core, uint64_t capture_id) {
  (void)core;
  (void)capture_id;
}
CScreencopyRequest WWNCoreGetPendingImageCopyCapture(void *core) {
  (void)core;
  CScreencopyRequest req = {0};
  return req;
}
void WWNCoreImageCopyCaptureDone(void *core, uint64_t capture_id) {
  (void)core;
  (void)capture_id;
}
void WWNCoreImageCopyCaptureFailed(void *core, uint64_t capture_id) {
  (void)core;
  (void)capture_id;
}
void WWNCoreInjectTouchDown(void *core, int32_t id, double x, double y, uint32_t timestamp_ms) {
  (void)core;
  (void)id;
  (void)x;
  (void)y;
  (void)timestamp_ms;
}
void WWNCoreInjectTouchUp(void *core, int32_t id, uint32_t timestamp_ms) {
  (void)core;
  (void)id;
  (void)timestamp_ms;
}
void WWNCoreInjectTouchMotion(void *core, int32_t id, double x, double y, uint32_t timestamp_ms) {
  (void)core;
  (void)id;
  (void)x;
  (void)y;
  (void)timestamp_ms;
}
void WWNCoreInjectTouchCancel(void *core) { (void)core; }
void WWNCoreInject_touch_frame(void *core) { (void)core; }
void WWNCoreInjectKey(void *core, uint32_t keycode, uint32_t state, uint32_t timestamp_ms) {
  (void)core;
  (void)keycode;
  (void)state;
  (void)timestamp_ms;
}
void WWNCoreInjectModifiers(void *core, uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group) {
  (void)core;
  (void)depressed;
  (void)latched;
  (void)locked;
  (void)group;
}
void WWNCoreInjectPointerMotion(void *core, uint64_t window_id, double x, double y, uint32_t timestamp_ms) {
  (void)core;
  (void)window_id;
  (void)x;
  (void)y;
  (void)timestamp_ms;
}
void WWNCoreInjectPointerButton(void *core, uint64_t window_id, uint32_t button_code, uint32_t state, uint32_t timestamp_ms) {
  (void)core;
  (void)window_id;
  (void)button_code;
  (void)state;
  (void)timestamp_ms;
}
void WWNCoreInjectPointerEnter(void *core, uint64_t window_id, double x, double y, uint32_t timestamp_ms) {
  (void)core;
  (void)window_id;
  (void)x;
  (void)y;
  (void)timestamp_ms;
}
void WWNCoreInjectPointerLeave(void *core, uint64_t window_id, uint32_t timestamp_ms) {
  (void)core;
  (void)window_id;
  (void)timestamp_ms;
}
void WWNCoreInjectPointerAxis(void *core, uint64_t window_id, uint32_t axis, double value, uint32_t timestamp_ms) {
  (void)core;
  (void)window_id;
  (void)axis;
  (void)value;
  (void)timestamp_ms;
}
void WWNCoreInjectKeyboardEnter(void *core, uint64_t window_id, const uint32_t *keys, size_t count, uint32_t timestamp_ms) {
  (void)core;
  (void)window_id;
  (void)keys;
  (void)count;
  (void)timestamp_ms;
}
void WWNCoreInjectKeyboardLeave(void *core, uint64_t window_id) {
  (void)core;
  (void)window_id;
}
void WWNCoreTextInputCommit(void *core, const char *text) {
  (void)core;
  (void)text;
}
void WWNCoreTextInputPreedit(void *core, const char *text, int32_t cursor_begin, int32_t cursor_end) {
  (void)core;
  (void)text;
  (void)cursor_begin;
  (void)cursor_end;
}
void WWNCoreTextInputDeleteSurrounding(void *core, uint32_t before, uint32_t after) {
  (void)core;
  (void)before;
  (void)after;
}
void WWNCoreTextInputGetCursorRect(void *core, int32_t *out_x, int32_t *out_y, int32_t *out_width, int32_t *out_height) {
  (void)core;
  if (out_x) *out_x = 0;
  if (out_y) *out_y = 0;
  if (out_width) *out_width = 0;
  if (out_height) *out_height = 0;
}
