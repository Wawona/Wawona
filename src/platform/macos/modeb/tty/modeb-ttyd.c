/*
 * modeb-ttyd: Mode B multi-VT console (Classic own-display).
 *
 * Linux-TTY-shaped: PTY + modeb-getty (Doorman login) per VT, libvterm for
 * ECMA-48/SGR (colors, bold, reverse) like the Linux framebuffer console.
 * Not a full xterm (no mouse / OSC chrome). Present via DRM dumb ->
 * framebufferd.
 *
 *   Ctrl+Option+F1..F6  -> text VT 1..6
 *   Ctrl+Option+F7      -> kmscube
 *   Ctrl+Option+Backspace -> restore Aqua
 *
 * Auth: modeb-getty uses Doorman (github.com/Wawona/doorman) the way Linux
 * uses getty+login / PAM. Typing goes to the PTY; after login the user
 * shell owns the session.
 */
#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <mach/message.h>
#include <bootstrap.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>
#include <mach-o/dyld.h>

#include <vterm.h>
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
#define STATUS_HINT "VT%d/%d  C-Opt-Fn  C-Opt-BS=Aqua"

extern char **environ;

typedef struct {
  int master;
  pid_t shell_pid;
  VTerm *vt;
  VTermScreen *screen;
  int cols;
  int rows;
  int dirty;
} vt_t;

static volatile sig_atomic_t g_run = 1;
static int g_active_vt = 1;
static vt_t g_vt[VT_TEXT_COUNT];
static pid_t g_gfx_pid = -1;
static char g_kmscube[1024];
static char g_getty[1024];

static int g_drm_fd = -1;
static uint32_t g_crtc_id;
static uint32_t g_conn_id;
static drmModeModeInfo g_mode;
static uint32_t g_fb_id;
static uint32_t g_bo_handle;
static uint32_t g_pitch;
static uint32_t *g_fb;
static int g_fb_w, g_fb_h;

static mach_port_t g_input_recv = MACH_PORT_NULL;
static int g_shift, g_caps, g_ctrl, g_alt;
static int g_cursor_on = 1;

/* mach_msg receive always appends a trailer. sizeof(event) alone returns
 * MACH_RCV_TOO_LARGE, so keys never reach the PTY. */
#ifndef MODEB_IPC_TRAILER
#define MODEB_IPC_TRAILER 256
#endif

static void on_signal(int sig) {
  (void)sig;
  g_run = 0;
}

static void switch_vt(int vt);
static void render_active_text(void);

static int screen_damage(VTermRect rect, void *user) {
  (void)rect;
  ((vt_t *)user)->dirty = 1;
  return 1;
}

static int screen_moverect(VTermRect dest, VTermRect src, void *user) {
  (void)dest;
  (void)src;
  ((vt_t *)user)->dirty = 1;
  return 1;
}

static int screen_movecursor(VTermPos pos, VTermPos oldpos, int visible,
                             void *user) {
  (void)pos;
  (void)oldpos;
  (void)visible;
  ((vt_t *)user)->dirty = 1;
  return 1;
}

static int screen_settermprop(VTermProp prop, VTermValue *val, void *user) {
  (void)prop;
  (void)val;
  (void)user;
  return 1;
}

static int screen_bell(void *user) {
  (void)user;
  return 1;
}

static int screen_resize(int rows, int cols, void *user) {
  (void)rows;
  (void)cols;
  (void)user;
  return 0; /* refuse resize from host */
}

static int screen_sb_pushline(int cols, const VTermScreenCell *cells,
                              void *user) {
  (void)cols;
  (void)cells;
  (void)user;
  return 1;
}

static int screen_sb_popline(int cols, VTermScreenCell *cells, void *user) {
  (void)cols;
  (void)cells;
  (void)user;
  return 0;
}

static int screen_sb_clear(void *user) {
  (void)user;
  return 1;
}

static const VTermScreenCallbacks g_screen_cbs = {
    .damage = screen_damage,
    .moverect = screen_moverect,
    .movecursor = screen_movecursor,
    .settermprop = screen_settermprop,
    .bell = screen_bell,
    .resize = screen_resize,
    .sb_pushline = screen_sb_pushline,
    .sb_popline = screen_sb_popline,
    .sb_clear = screen_sb_clear,
};

static int spawn_getty(vt_t *v) {
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
    /* Linux console TERM; colors via SGR (16/256 via libvterm). */
    setenv("TERM", "linux", 1);
    setenv("COLORTERM", "truecolor", 1);
    setenv("WWN_MODEB_TTY", "1", 1);
    if (g_getty[0])
      execl(g_getty, "modeb-getty", (char *)NULL);
    /* Dev fallback: root shell without login (not the shipping path). */
    execl("/bin/zsh", "zsh", "-l", (char *)NULL);
    _exit(127);
  }
  close(s);
  fcntl(m, F_SETFL, O_NONBLOCK);
  v->master = m;
  v->shell_pid = pid;
  return 0;
}

static int vt_init(vt_t *v, int cols, int rows) {
  memset(v, 0, sizeof(*v));
  v->cols = cols;
  v->rows = rows;
  v->master = -1;
  v->vt = vterm_new(rows, cols);
  if (!v->vt)
    return -1;
  vterm_set_utf8(v->vt, 1);
  v->screen = vterm_obtain_screen(v->vt);
  vterm_screen_set_callbacks(v->screen, &g_screen_cbs, v);
  vterm_screen_set_damage_merge(v->screen, VTERM_DAMAGE_SCREEN);
  vterm_screen_enable_altscreen(v->screen, 1);
  {
    VTermColor fg, bg;
    vterm_color_rgb(&fg, 0xe0, 0xe0, 0xe0);
    vterm_color_rgb(&bg, 0x10, 0x10, 0x10);
    vterm_screen_set_default_colors(v->screen, &fg, &bg);
  }
  vterm_screen_reset(v->screen, 1);
  v->dirty = 1;
  return spawn_getty(v);
}

static void vt_feed_pty(vt_t *v, const char *buf, size_t n) {
  if (!v->vt || n == 0)
    return;
  vterm_input_write(v->vt, buf, n);
  vterm_screen_flush_damage(v->screen);
}

static uint32_t color_to_bgra(VTermScreen *screen, VTermColor col) {
  vterm_screen_convert_color_to_rgb(screen, &col);
  uint8_t r = col.rgb.red;
  uint8_t g = col.rgb.green;
  uint8_t b = col.rgb.blue;
  return 0xFF000000u | ((uint32_t)b << 16) | ((uint32_t)g << 8) | (uint32_t)r;
}

static void draw_glyph_colored(int px, int py, uint32_t cp, uint32_t fg,
                               uint32_t bg) {
  char ch = '?';
  if (cp >= 32 && cp <= 126)
    ch = (char)cp;
  else if (cp == 0)
    ch = ' ';
  const uint8_t *g = modeb_tty_font[(unsigned char)ch - 32];
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
  if (!v->screen)
    return;

  const uint32_t status_fg = 0xFF80C0FF;
  const uint32_t status_bg = 0xFF101010;

  for (int row = 0; row < v->rows; row++) {
    for (int col = 0; col < v->cols; col++) {
      VTermPos pos = {.row = row, .col = col};
      VTermScreenCell cell;
      memset(&cell, 0, sizeof(cell));
      vterm_screen_get_cell(v->screen, pos, &cell);
      VTermColor fg = cell.fg;
      VTermColor bg = cell.bg;
      if (cell.attrs.reverse) {
        VTermColor tmp = fg;
        fg = bg;
        bg = tmp;
      }
      uint32_t fgc = color_to_bgra(v->screen, fg);
      uint32_t bgc = color_to_bgra(v->screen, bg);
      if (cell.attrs.bold) {
        /* brighten FG slightly */
        uint8_t r = (uint8_t)(fgc & 0xff);
        uint8_t g = (uint8_t)((fgc >> 8) & 0xff);
        uint8_t b = (uint8_t)((fgc >> 16) & 0xff);
        r = r > 200 ? 255 : (uint8_t)(r + 55);
        g = g > 200 ? 255 : (uint8_t)(g + 55);
        b = b > 200 ? 255 : (uint8_t)(b + 55);
        fgc = 0xFF000000u | ((uint32_t)b << 16) | ((uint32_t)g << 8) | r;
      }
      uint32_t cp = cell.chars[0];
      draw_glyph_colored(col * CELL_W, row * CELL_H, cp, fgc, bgc);
    }
  }

  /* Linux-console block cursor at the vterm caret. */
  if (g_cursor_on && v->vt) {
    VTermState *st = vterm_obtain_state(v->vt);
    VTermPos cur = {.row = 0, .col = 0};
    if (st)
      vterm_state_get_cursorpos(st, &cur);
    if (cur.row >= 0 && cur.row < v->rows && cur.col >= 0 &&
        cur.col < v->cols) {
      int px = cur.col * CELL_W;
      int py = cur.row * CELL_H;
      uint32_t block = 0xFFE8E8E8u;
      for (int y = 0; y < CELL_H; y++) {
        int Y = py + y;
        if (Y < 0 || Y >= g_fb_h)
          continue;
        for (int x = 0; x < CELL_W; x++) {
          int X = px + x;
          if (X < 0 || X >= g_fb_w)
            continue;
          g_fb[Y * (g_pitch / 4) + X] = block;
        }
      }
    }
  }

  char status[128];
  snprintf(status, sizeof(status), STATUS_HINT, g_active_vt, VT_TEXT_COUNT);
  int sy = g_fb_h - CELL_H - 2;
  for (int i = 0; status[i] && i < v->cols; i++)
    draw_glyph_colored(i * CELL_W, sy, (unsigned char)status[i], status_fg,
                       status_bg);

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
    if (conn && conn->connection == DRM_MODE_CONNECTED &&
        conn->count_modes > 0)
      break;
    if (conn) {
      drmModeFreeConnector(conn);
      conn = NULL;
    }
  }
  if (!conn)
    conn = drmModeGetConnector(g_drm_fd, res->connectors[0]);
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

static int input_bootstrap_look_up(const char *name, mach_port_t *out) {
  mach_port_t bp = MACH_PORT_NULL;
  task_get_bootstrap_port(mach_task_self(), &bp);
  kern_return_t kr = bootstrap_look_up(bp, (char *)name, out);
  if (kr == KERN_SUCCESS)
    return 0;
  for (int depth = 0; depth < 8; depth++) {
    mach_port_t parent = MACH_PORT_NULL;
    kern_return_t pkr = bootstrap_parent(bp, &parent);
    if (pkr != KERN_SUCCESS || parent == MACH_PORT_NULL || parent == bp)
      break;
    if (bp != bootstrap_port)
      mach_port_deallocate(mach_task_self(), bp);
    bp = parent;
    kr = bootstrap_look_up(bp, (char *)name, out);
    if (kr == KERN_SUCCESS) {
      if (bp != bootstrap_port)
        mach_port_deallocate(mach_task_self(), bp);
      return 0;
    }
  }
  if (bp != bootstrap_port)
    mach_port_deallocate(mach_task_self(), bp);
  fprintf(stderr, "[modeb-ttyd] inputd look_up %s: %s\n", name,
          mach_error_string(kr));
  return -1;
}

static int input_subscribe(void) {
  mach_port_t service = MACH_PORT_NULL;
  if (input_bootstrap_look_up(INPUT_IPC_SERVICE_NAME, &service) != 0)
    return -1;
  kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE,
                                        &g_input_recv);
  if (kr != KERN_SUCCESS)
    return -1;

  input_ipc_subscribe_t sub = {0};
  sub.header.msgh_bits =
      MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
  sub.header.msgh_remote_port = service;
  sub.header.msgh_local_port = MACH_PORT_NULL;
  sub.header.msgh_id = INPUT_IPC_SUBSCRIBE_ID;
  sub.header.msgh_size = sizeof(sub);
  sub.body.msgh_descriptor_count = 1;
  sub.client_port.name = g_input_recv;
  sub.client_port.disposition = MACH_MSG_TYPE_MAKE_SEND;
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

static void clear_chord_modifiers(void) {
  /* After Ctrl+Option chords, key-up can be lost while WS is down. Sticky
   * Ctrl turns every letter into a control char (looks like "typing does
   * nothing"). Clear both sides of the chord when we consume it. */
  g_ctrl = 0;
  g_alt = 0;
}

static void modeb_request_restore_local(void) {
  int fd = open("/tmp/libwayland-support/modeb-restore-aqua",
                O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd >= 0) {
    const char *msg = "modeb-ttyd-chord\n";
    (void)write(fd, msg, strlen(msg));
    close(fd);
  }
  fprintf(stderr, "[modeb-ttyd] Ctrl+Option+Backspace -> restore Aqua\n");
  g_run = 0;
}

static void handle_key(int key, int pressed) {
  if (key == 29 || key == 97) {
    g_ctrl = pressed ? 1 : 0;
    return;
  }
  if (key == 56 || key == 100) {
    g_alt = pressed ? 1 : 0;
    return;
  }
  if (key == 42 || key == 54) {
    g_shift = pressed ? 1 : 0;
    return;
  }
  if (key == 58 && pressed) {
    g_caps = !g_caps;
    return;
  }
  if (!pressed)
    return;

  fprintf(stderr, "[modeb-ttyd] key=%d ctrl=%d alt=%d\n", key, g_ctrl, g_alt);

  if (g_ctrl && g_alt) {
    if (key == 14) {
      clear_chord_modifiers();
      modeb_request_restore_local();
      return;
    }
    if (key >= 59 && key <= 65) {
      int vt = key - 59 + 1;
      FILE *f = fopen(VT_FILE, "w");
      if (f) {
        fprintf(f, "%d\n", vt);
        fclose(f);
      }
      clear_chord_modifiers();
      switch_vt(vt);
      return;
    }
  }

  if (g_active_vt < 1 || g_active_vt > VT_TEXT_COUNT)
    return;
  vt_t *v = &g_vt[g_active_vt - 1];
  if (v->master < 0)
    return;

  if (g_ctrl && !g_alt) {
    char c = key_to_ascii(key, 0);
    if (c >= 'a' && c <= 'z') {
      char ctrl = (char)(c - 'a' + 1);
      (void)write(v->master, &ctrl, 1);
    }
    return;
  }

  int shift = g_shift ^ g_caps;
  char c = key_to_ascii(key, shift);
  if (key == 14)
    c = 0x7f;
  if (c) {
    ssize_t w = write(v->master, &c, 1);
    if (w != 1)
      fprintf(stderr, "[modeb-ttyd] PTY write key=%d c=%d failed\n", key,
              (int)(unsigned char)c);
  }
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
  if (!g_kmscube[0]) {
    fprintf(stderr, "[modeb-ttyd] no kmscube path\n");
    return;
  }
  pid_t pid = fork();
  if (pid == 0) {
    execl(g_kmscube, "kmscube", (char *)NULL);
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
    /* inputd consumes the chord; key-up may never arrive here. */
    g_ctrl = 0;
    g_alt = 0;
    switch_vt(vt);
  }
  fclose(f);
}

static void *input_thread(void *arg) {
  (void)arg;
  while (g_run) {
    struct {
      input_ipc_event_t ev;
      uint8_t trailer[MODEB_IPC_TRAILER];
    } buf;
    memset(&buf, 0, sizeof(buf));
    kern_return_t kr =
        mach_msg(&buf.ev.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0,
                 sizeof(buf), g_input_recv, 100, MACH_PORT_NULL);
    if (kr == MACH_RCV_TIMED_OUT)
      continue;
    if (kr != KERN_SUCCESS) {
      fprintf(stderr, "[modeb-ttyd] mach_msg recv: kr=0x%x %s\n",
              (unsigned)kr, mach_error_string(kr));
      continue;
    }
    if (buf.ev.event_type == INPUT_IPC_EVENT_KEYBOARD_KEY)
      handle_key(buf.ev.key, buf.ev.key_state == 1);
  }
  return NULL;
}

static void find_sidecar(char *out, size_t out_sz, const char *name,
                         const char *env_key) {
  out[0] = 0;
  const char *env = getenv(env_key);
  if (env && env[0] && access(env, X_OK) == 0) {
    snprintf(out, out_sz, "%s", env);
    return;
  }
  char self[1024];
  uint32_t sz = sizeof(self);
  if (_NSGetExecutablePath(self, &sz) == 0) {
    char *slash = strrchr(self, '/');
    if (slash) {
      *slash = 0;
      snprintf(out, out_sz, "%s/%s", self, name);
      if (access(out, X_OK) == 0)
        return;
    }
  }
  out[0] = 0;
}

static void find_kmscube(void) {
  find_sidecar(g_kmscube, sizeof(g_kmscube), "kmscube", "WWN_MODEB_KMSCUBE");
}

static void find_getty(void) {
  find_sidecar(g_getty, sizeof(g_getty), "modeb-getty", "WWN_MODEB_GETTY");
}

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  signal(SIGTERM, on_signal);
  signal(SIGINT, on_signal);
  signal(SIGHUP, on_signal);
  signal(SIGCHLD, SIG_DFL);
  mkdir("/tmp/libwayland-support", 0755);
  find_kmscube();
  find_getty();
  if (!g_getty[0])
    fprintf(stderr, "[modeb-ttyd] WARN: modeb-getty missing; fallback zsh -l\n");
  else
    fprintf(stderr, "[modeb-ttyd] getty=%s\n", g_getty);

  if (setup_drm() != 0)
    return 1;

  int cols = g_fb_w / CELL_W;
  int rows = (g_fb_h / CELL_H) - 1;
  if (cols > COLS_MAX)
    cols = COLS_MAX;
  if (rows > ROWS_MAX)
    rows = ROWS_MAX;
  if (cols < 40)
    cols = 40;
  if (rows < 10)
    rows = 10;

  for (int i = 0; i < VT_TEXT_COUNT; i++) {
    if (vt_init(&g_vt[i], cols, rows) != 0) {
      fprintf(stderr, "[modeb-ttyd] VT%d init failed\n", i + 1);
      return 1;
    }
  }

  if (input_subscribe() != 0) {
    fprintf(stderr, "[modeb-ttyd] FATAL: no inputd subscribe\n");
    return 1;
  }
  pthread_t thr;
  pthread_create(&thr, NULL, input_thread, NULL);

  {
    const char *banner =
        "\r\nWawona Mode B TTY (libvterm + Doorman login)\r\n"
        "Ctrl+Option+F1-F6 | F7 kmscube | Ctrl+Option+Backspace Aqua\r\n"
        "(MacBook: hold Fn for F-keys if needed)\r\n\r\n";
    vt_feed_pty(&g_vt[0], banner, strlen(banner));
  }

  g_active_vt = 1;
  render_active_text();
  fprintf(stderr, "[modeb-ttyd] ready on VT1 (%dx%d) libvterm\n", cols, rows);

  while (g_run) {
    poll_vt_file();

    {
      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC, &ts);
      int phase = (int)((ts.tv_sec * 1000 + ts.tv_nsec / 1000000) / 530);
      int on = (phase & 1) ? 1 : 0;
      if (on != g_cursor_on) {
        g_cursor_on = on;
        if (g_active_vt >= 1 && g_active_vt <= VT_TEXT_COUNT)
          g_vt[g_active_vt - 1].dirty = 1;
      }
    }

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
          vt_feed_pty(&g_vt[i], buf, (size_t)n);
      }
    }

    /* Respawn getty/login after shell logout (Linux getty restart). */
    for (int i = 0; i < VT_TEXT_COUNT; i++) {
      if (g_vt[i].shell_pid <= 0)
        continue;
      int st = 0;
      pid_t r = waitpid(g_vt[i].shell_pid, &st, WNOHANG);
      if (r == g_vt[i].shell_pid) {
        fprintf(stderr, "[modeb-ttyd] VT%d session ended; respawn getty\n",
                i + 1);
        if (g_vt[i].master >= 0) {
          close(g_vt[i].master);
          g_vt[i].master = -1;
        }
        g_vt[i].shell_pid = -1;
        if (g_vt[i].vt) {
          vterm_screen_reset(g_vt[i].screen, 1);
          g_vt[i].dirty = 1;
        }
        (void)spawn_getty(&g_vt[i]);
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
    if (g_vt[i].vt)
      vterm_free(g_vt[i].vt);
  }
  fprintf(stderr, "[modeb-ttyd] exit\n");
  return 0;
}
