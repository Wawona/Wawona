/*
 * modeb-ttyd: Mode B userspace multi-VT console (Classic own-display).
 *
 * Linux-like VTs on framebufferd via DRM dumb buffers (no kernel tty):
 *   Ctrl+Alt+F1..F6  (inputd) -> text VT 1..6 (PTY + /bin/zsh)
 *   Ctrl+Alt+F7      (inputd) -> graphics VT (spawn kmscube)
 *   Ctrl+Alt+Backspace        -> restore Aqua (inputd stamp; helper)
 *
 * Built for DYLD_INSERT_LIBRARIES=libwayland-mac.dylib (Mode B).
 */
#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <bootstrap.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

#include <mach-o/dyld.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include "input_ipc.h"

#include "modeb_tty_font.h"

#define VT_TEXT_COUNT 6
#define VT_GRAPHICS 7
#define COLS_MAX 240
#define ROWS_MAX 80
#define CELL_W MODEB_TTY_GLYPH_W
#define CELL_H MODEB_TTY_GLYPH_H
#define VT_FILE "/tmp/libwayland-support/modeb-vt"
#define STATUS_HINT "VT%d/%d  C-A-Fn=switch  C-A-Backspace=Aqua"

extern char **environ;

typedef struct {
  int master;
  int slave;
  pid_t shell_pid;
  char *cells; /* rows * cols chars */
  int cols;
  int rows;
  int cx, cy;
  int dirty;
} vt_t;

static volatile sig_atomic_t g_run = 1;
static int g_active_vt = 1; /* 1..7 */
static vt_t g_vt[VT_TEXT_COUNT];
static pid_t g_gfx_pid = -1;
static char g_kmscube[1024];

static int g_drm_fd = -1;
static uint32_t g_crtc_id;
static uint32_t g_conn_id;
static drmModeModeInfo g_mode;
static uint32_t g_fb_id;
static uint32_t g_bo_handle;
static uint32_t g_pitch;
static uint32_t *g_fb; /* BGRA pixels */
static int g_fb_w, g_fb_h;

static mach_port_t g_input_recv = MACH_PORT_NULL;
static int g_shift;
static int g_caps;

static void on_signal(int sig) {
  (void)sig;
  g_run = 0;
}

static void clear_cells(vt_t *v) {
  memset(v->cells, ' ', (size_t)v->cols * (size_t)v->rows);
  v->cx = 0;
  v->cy = 0;
  v->dirty = 1;
}

static int spawn_shell(vt_t *v) {
  int m = -1, s = -1;
  if (openpty(&m, &s, NULL, NULL, NULL) < 0) {
    perror("openpty");
    return -1;
  }
  struct winsize ws = {
      .ws_row = (unsigned short)v->rows,
      .ws_col = (unsigned short)v->cols,
      .ws_xpixel = (unsigned short)(v->cols * CELL_W),
      .ws_ypixel = (unsigned short)(v->rows * CELL_H),
  };
  ioctl(s, TIOCSWINSZ, &ws);

  pid_t pid = fork();
  if (pid < 0) {
    perror("fork");
    close(m);
    close(s);
    return -1;
  }
  if (pid == 0) {
    close(m);
    setsid();
    ioctl(s, TIOCSCTTY, 0);
    dup2(s, 0);
    dup2(s, 1);
    dup2(s, 2);
    if (s > 2)
      close(s);
    setenv("TERM", "linux", 1);
    setenv("WWN_MODEB_TTY", "1", 1);
    execl("/bin/zsh", "zsh", "-l", (char *)NULL);
    execl("/bin/bash", "bash", "-l", (char *)NULL);
    _exit(127);
  }
  close(s);
  fcntl(m, F_SETFL, O_NONBLOCK);
  v->master = m;
  v->slave = -1;
  v->shell_pid = pid;
  return 0;
}

static void vt_putc(vt_t *v, char c) {
  if (c == '\r') {
    v->cx = 0;
    v->dirty = 1;
    return;
  }
  if (c == '\n') {
    v->cx = 0;
    v->cy++;
    if (v->cy >= v->rows) {
      memmove(v->cells, v->cells + v->cols,
              (size_t)(v->rows - 1) * (size_t)v->cols);
      memset(v->cells + (v->rows - 1) * v->cols, ' ', (size_t)v->cols);
      v->cy = v->rows - 1;
    }
    v->dirty = 1;
    return;
  }
  if (c == '\b') {
    if (v->cx > 0)
      v->cx--;
    v->dirty = 1;
    return;
  }
  if (c == '\t') {
    int n = 8 - (v->cx % 8);
    while (n--)
      vt_putc(v, ' ');
    return;
  }
  if (c < 32 || c > 126)
    c = '?';
  v->cells[v->cy * v->cols + v->cx] = c;
  v->cx++;
  if (v->cx >= v->cols) {
    v->cx = 0;
    vt_putc(v, '\n');
  }
  v->dirty = 1;
}

static void vt_write_bytes(vt_t *v, const char *buf, size_t n) {
  for (size_t i = 0; i < n; i++)
    vt_putc(v, buf[i]);
}

static void draw_glyph(int px, int py, char ch, uint32_t fg, uint32_t bg) {
  if (ch < 32 || ch > 126)
    ch = '?';
  const uint8_t *g = modeb_tty_font[ch - 32];
  for (int y = 0; y < CELL_H; y++) {
    uint8_t row = g[y];
    for (int x = 0; x < CELL_W; x++) {
      int X = px + x;
      int Y = py + y;
      if (X < 0 || Y < 0 || X >= g_fb_w || Y >= g_fb_h)
        continue;
      g_fb[Y * (g_pitch / 4) + X] = (row & (0x80 >> x)) ? fg : bg;
    }
  }
}

static void render_active_text(void) {
  if (g_active_vt < 1 || g_active_vt > VT_TEXT_COUNT)
    return;
  vt_t *v = &g_vt[g_active_vt - 1];
  const uint32_t bg = 0xFF101010;
  const uint32_t fg = 0xFFE0E0E0;
  const uint32_t st = 0xFF80C0FF;
  for (int i = 0; i < g_fb_w * g_fb_h; i++)
    g_fb[i] = bg;

  for (int y = 0; y < v->rows; y++) {
    for (int x = 0; x < v->cols; x++) {
      char c = v->cells[y * v->cols + x];
      draw_glyph(x * CELL_W, y * CELL_H, c, fg, bg);
    }
  }
  /* cursor */
  draw_glyph(v->cx * CELL_W, v->cy * CELL_H, 0xDB, st, bg);

  char status[128];
  snprintf(status, sizeof(status), STATUS_HINT, g_active_vt, VT_TEXT_COUNT);
  int sy = g_fb_h - CELL_H - 2;
  for (int i = 0; status[i] && i < v->cols; i++)
    draw_glyph(i * CELL_W, sy, status[i], st, bg);

  v->dirty = 0;
  drmModePageFlip(g_drm_fd, g_crtc_id, g_fb_id, 0, NULL);
}

static int setup_drm(void) {
  g_drm_fd = drmOpen("card0", NULL);
  if (g_drm_fd < 0)
    g_drm_fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
  if (g_drm_fd < 0) {
    perror("drmOpen");
    return -1;
  }
  drmModeResPtr res = drmModeGetResources(g_drm_fd);
  if (!res || res->count_connectors < 1) {
    fprintf(stderr, "[modeb-ttyd] no DRM connectors\n");
    return -1;
  }
  drmModeConnectorPtr conn = NULL;
  for (int i = 0; i < res->count_connectors; i++) {
    conn = drmModeGetConnector(g_drm_fd, res->connectors[i]);
    if (conn && conn->connection == 1 /* connected */ && conn->count_modes > 0)
      break;
    if (conn) {
      drmModeFreeConnector(conn);
      conn = NULL;
    }
  }
  if (!conn) {
    conn = drmModeGetConnector(g_drm_fd, res->connectors[0]);
  }
  if (!conn || conn->count_modes < 1) {
    fprintf(stderr, "[modeb-ttyd] no modes\n");
    return -1;
  }
  g_mode = conn->modes[0];
  g_conn_id = conn->connector_id;
  g_fb_w = (int)g_mode.hdisplay;
  g_fb_h = (int)g_mode.vdisplay;

  uint32_t handle = 0, pitch = 0;
  uint64_t size = 0;
  if (drmModeCreateDumbBuffer(g_drm_fd, (uint32_t)g_fb_w, (uint32_t)g_fb_h, 32,
                              0, &handle, &pitch, &size) != 0) {
    perror("CreateDumbBuffer");
    return -1;
  }
  g_bo_handle = handle;
  g_pitch = pitch;
  uint64_t map_off = 0;
  if (drmModeMapDumbBuffer(g_drm_fd, handle, &map_off) != 0) {
    perror("MapDumbBuffer");
    return -1;
  }
  g_fb = (uint32_t *)(uintptr_t)map_off;
  if (!g_fb) {
    fprintf(stderr, "[modeb-ttyd] null dumb map\n");
    return -1;
  }
  if (drmModeAddFB(g_drm_fd, (uint32_t)g_fb_w, (uint32_t)g_fb_h, 24, 32, pitch,
                   handle, &g_fb_id) != 0) {
    perror("AddFB");
    return -1;
  }

  uint32_t crtc = 0;
  if (conn->encoder_id) {
    drmModeEncoderPtr enc = drmModeGetEncoder(g_drm_fd, conn->encoder_id);
    if (enc) {
      crtc = enc->crtc_id;
      drmModeFreeEncoder(enc);
    }
  }
  if (!crtc && res->count_crtcs > 0)
    crtc = res->crtcs[0];
  g_crtc_id = crtc;
  uint32_t connectors[1] = {g_conn_id};
  if (drmModeSetCrtc(g_drm_fd, g_crtc_id, g_fb_id, 0, 0, connectors, 1,
                     &g_mode) != 0) {
    perror("SetCrtc");
    return -1;
  }
  drmModeFreeConnector(conn);
  drmModeFreeResources(res);
  fprintf(stderr, "[modeb-ttyd] DRM %dx%d crtc=%u fb=%u\n", g_fb_w, g_fb_h,
          g_crtc_id, g_fb_id);
  return 0;
}

static int input_subscribe(void) {
  mach_port_t service = MACH_PORT_NULL;
  mach_port_t bp = MACH_PORT_NULL;
  task_get_bootstrap_port(mach_task_self(), &bp);
  kern_return_t kr =
      bootstrap_look_up(bp, (char *)INPUT_IPC_SERVICE_NAME, &service);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "[modeb-ttyd] inputd look_up: %s\n", mach_error_string(kr));
    return -1;
  }
  kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE,
                          &g_input_recv);
  if (kr != KERN_SUCCESS)
    return -1;
  mach_port_t send = MACH_PORT_NULL;
  mach_port_insert_right(mach_task_self(), g_input_recv, g_input_recv,
                         MACH_MSG_TYPE_MAKE_SEND);
  send = g_input_recv;

  input_ipc_subscribe_t sub = {0};
  sub.header.msgh_bits =
      MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
  sub.header.msgh_remote_port = service;
  sub.header.msgh_local_port = MACH_PORT_NULL;
  sub.header.msgh_id = INPUT_IPC_SUBSCRIBE_ID;
  sub.header.msgh_size = sizeof(sub);
  sub.body.msgh_descriptor_count = 1;
  sub.client_port.name = send;
  sub.client_port.disposition = MACH_MSG_TYPE_COPY_SEND;
  sub.client_port.type = MACH_MSG_PORT_DESCRIPTOR;
  kr = mach_msg(&sub.header, MACH_SEND_MSG, sizeof(sub), 0, MACH_PORT_NULL,
                MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "[modeb-ttyd] subscribe: %s\n", mach_error_string(kr));
    return -1;
  }
  fprintf(stderr, "[modeb-ttyd] subscribed to inputd\n");
  return 0;
}

/* Minimal US keymap (evdev KEY_* -> ASCII). */
static char key_to_ascii(int key, int shift) {
  if (key == 28)
    return '\n';
  if (key == 14)
    return '\b';
  if (key == 15)
    return '\t';
  if (key == 57)
    return ' ';
  static const char *digits = "1234567890";
  static const char *digits_s = "!@#$%^&*()";
  if (key >= 2 && key <= 11)
    return shift ? digits_s[key - 2] : digits[key - 2];
  static const char *row1 = "qwertyuiop";
  static const char *row1s = "QWERTYUIOP";
  if (key >= 16 && key <= 25)
    return shift ? row1s[key - 16] : row1[key - 16];
  static const char *row2 = "asdfghjkl";
  static const char *row2s = "ASDFGHJKL";
  if (key >= 30 && key <= 38)
    return shift ? row2s[key - 30] : row2[key - 30];
  static const char *row3 = "zxcvbnm";
  static const char *row3s = "ZXCVBNM";
  if (key >= 44 && key <= 50)
    return shift ? row3s[key - 44] : row3[key - 44];
  if (key == 12)
    return shift ? '_' : '-';
  if (key == 13)
    return shift ? '+' : '=';
  if (key == 26)
    return shift ? '{' : '[';
  if (key == 27)
    return shift ? '}' : ']';
  if (key == 39)
    return shift ? ':' : ';';
  if (key == 40)
    return shift ? '"' : '\'';
  if (key == 41)
    return shift ? '~' : '`';
  if (key == 43)
    return shift ? '|' : '\\';
  if (key == 51)
    return shift ? '<' : ',';
  if (key == 52)
    return shift ? '>' : '.';
  if (key == 53)
    return shift ? '?' : '/';
  return 0;
}

static void handle_key(int key, int pressed) {
  if (key == 42 || key == 54) { /* shifts */
    g_shift = pressed ? 1 : 0;
    return;
  }
  if (key == 58 && pressed) {
    g_caps = !g_caps;
    return;
  }
  if (!pressed)
    return;
  if (g_active_vt < 1 || g_active_vt > VT_TEXT_COUNT)
    return;
  vt_t *v = &g_vt[g_active_vt - 1];
  if (v->master < 0)
    return;
  int shift = g_shift ^ g_caps;
  char c = key_to_ascii(key, shift);
  if (c)
    (void)write(v->master, &c, 1);
}

static void stop_graphics(void) {
  if (g_gfx_pid > 0) {
    kill(g_gfx_pid, SIGTERM);
    int st = 0;
    waitpid(g_gfx_pid, &st, WNOHANG);
    g_gfx_pid = -1;
  }
}

static void start_graphics(void) {
  if (g_gfx_pid > 0)
    return;
  const char *exe = g_kmscube[0] ? g_kmscube : NULL;
  if (!exe) {
    fprintf(stderr, "[modeb-ttyd] no kmscube path (WWN_MODEB_KMSCUBE)\n");
    return;
  }
  pid_t pid = fork();
  if (pid == 0) {
    execl(exe, "kmscube", (char *)NULL);
    _exit(127);
  }
  if (pid > 0) {
    g_gfx_pid = pid;
    fprintf(stderr, "[modeb-ttyd] graphics VT7 kmscube pid=%d\n", (int)pid);
  }
}

static void switch_vt(int vt) {
  if (vt < 1 || vt > VT_GRAPHICS)
    return;
  if (vt == g_active_vt)
    return;
  fprintf(stderr, "[modeb-ttyd] switch VT %d -> %d\n", g_active_vt, vt);
  if (vt == VT_GRAPHICS) {
    g_active_vt = vt;
    start_graphics();
    return;
  }
  if (g_active_vt == VT_GRAPHICS)
    stop_graphics();
  g_active_vt = vt;
  g_vt[vt - 1].dirty = 1;
  render_active_text();
}

static void poll_vt_file(void) {
  static int last = -1;
  FILE *f = fopen(VT_FILE, "r");
  if (!f)
    return;
  int vt = 0;
  if (fscanf(f, "%d", &vt) == 1 && vt != last) {
    last = vt;
    switch_vt(vt);
  }
  fclose(f);
}

static void *input_thread(void *arg) {
  (void)arg;
  while (g_run) {
    input_ipc_event_t msg;
    memset(&msg, 0, sizeof(msg));
    kern_return_t kr =
        mach_msg(&msg.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof(msg),
                 g_input_recv, 100, MACH_PORT_NULL);
    if (kr == MACH_RCV_TIMED_OUT)
      continue;
    if (kr != KERN_SUCCESS)
      continue;
    if (msg.event_type == INPUT_IPC_EVENT_KEYBOARD_KEY)
      handle_key(msg.key, msg.key_state == 1);
  }
  return NULL;
}

static void find_kmscube(void) {
  const char *env = getenv("WWN_MODEB_KMSCUBE");
  if (env && env[0]) {
    snprintf(g_kmscube, sizeof(g_kmscube), "%s", env);
    return;
  }
  /* Prefer sibling of this binary under Resources/bin */
  char self[1024];
  uint32_t sz = sizeof(self);
  if (_NSGetExecutablePath(self, &sz) == 0) {
    char *slash = strrchr(self, '/');
    if (slash) {
      *slash = 0;
      snprintf(g_kmscube, sizeof(g_kmscube), "%s/kmscube", self);
      if (access(g_kmscube, X_OK) == 0)
        return;
    }
  }
  g_kmscube[0] = 0;
}

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  signal(SIGTERM, on_signal);
  signal(SIGINT, on_signal);
  signal(SIGHUP, on_signal);
  signal(SIGCHLD, SIG_IGN);
  mkdir("/tmp/libwayland-support", 0755);
  find_kmscube();

  if (setup_drm() != 0)
    return 1;

  int cols = g_fb_w / CELL_W;
  int rows = (g_fb_h / CELL_H) - 1; /* leave status row */
  if (cols > COLS_MAX)
    cols = COLS_MAX;
  if (rows > ROWS_MAX)
    rows = ROWS_MAX;
  if (cols < 40)
    cols = 40;
  if (rows < 10)
    rows = 10;

  for (int i = 0; i < VT_TEXT_COUNT; i++) {
    g_vt[i].cols = cols;
    g_vt[i].rows = rows;
    g_vt[i].cells = calloc((size_t)cols * (size_t)rows, 1);
    g_vt[i].master = -1;
    clear_cells(&g_vt[i]);
    if (spawn_shell(&g_vt[i]) != 0) {
      fprintf(stderr, "[modeb-ttyd] shell VT%d failed\n", i + 1);
      return 1;
    }
  }

  (void)input_subscribe();
  pthread_t thr;
  if (g_input_recv != MACH_PORT_NULL)
    pthread_create(&thr, NULL, input_thread, NULL);

  /* Banner on VT1 */
  {
    const char *msg =
        "\r\nWawona Mode B TTY (userspace VTs)\r\n"
        "Ctrl+Alt+F1-F6 text | F7 kmscube | Ctrl+Alt+Backspace Aqua\r\n\r\n";
    vt_write_bytes(&g_vt[0], msg, strlen(msg));
  }

  g_active_vt = 1;
  render_active_text();
  fprintf(stderr, "[modeb-ttyd] ready on VT1 (%dx%d cells)\n", cols, rows);

  while (g_run) {
    poll_vt_file();

    struct pollfd pfd[VT_TEXT_COUNT];
    for (int i = 0; i < VT_TEXT_COUNT; i++) {
      pfd[i].fd = g_vt[i].master;
      pfd[i].events = POLLIN;
      pfd[i].revents = 0;
    }
    int pr = poll(pfd, VT_TEXT_COUNT, 50);
    if (pr > 0) {
      for (int i = 0; i < VT_TEXT_COUNT; i++) {
        if (!(pfd[i].revents & POLLIN))
          continue;
        char buf[4096];
        ssize_t n = read(g_vt[i].master, buf, sizeof(buf));
        if (n > 0)
          vt_write_bytes(&g_vt[i], buf, (size_t)n);
      }
    }

    if (g_active_vt >= 1 && g_active_vt <= VT_TEXT_COUNT &&
        g_vt[g_active_vt - 1].dirty)
      render_active_text();

    if (g_gfx_pid > 0) {
      int st = 0;
      pid_t r = waitpid(g_gfx_pid, &st, WNOHANG);
      if (r == g_gfx_pid) {
        g_gfx_pid = -1;
        if (g_active_vt == VT_GRAPHICS)
          switch_vt(1);
      }
    }
  }

  stop_graphics();
  for (int i = 0; i < VT_TEXT_COUNT; i++) {
    if (g_vt[i].shell_pid > 0)
      kill(g_vt[i].shell_pid, SIGHUP);
    if (g_vt[i].master >= 0)
      close(g_vt[i].master);
    free(g_vt[i].cells);
  }
  fprintf(stderr, "[modeb-ttyd] exit\n");
  return 0;
}
