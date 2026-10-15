/*
 * Optional in-process entry points that wawona-dispatch (libwwn-pty.a)
 * references but the product keep-set does not link.
 *
 * Darwin's linker does not treat __attribute__((weak)) declarations as
 * allow-missing the way ELF does when the referencing .o is -force_load'd.
 * Provide empty definitions so platforms without those archives still link.
 *
 * Keep-set symbols must NOT be stubbed here, or the real archive member never
 * gets pulled (a definition satisfies the -Wl,-u root):
 *   fastfetch_main            libfastfetch.a (-force_load)
 *   ssh_main / ssh_keygen_main / scp_main   libwwn-ssh-cli.a (-force_load)
 *   wawona_coreutils_main     libwawona.a (uutils feature, -u root)
 *   waypipe_main              libwaypipe.a (lazy -l, -u root)
 *   wawona_wasm_* / wpm_main  libwawona_wasm.a / libwawona_relay.a
 *
 * Everything below is optional-software: weston, its toytoolkit demos, foot,
 * niri, fuzzel, and phoon now install from repo.wawona.io as debs or wasm
 * instead of being force-loaded into the app, so nothing on the link line
 * defines these. See docs/agent-rules/wawona-optional-software.md.
 *
 * watchOS uses src/platform/watchos/WWNWatchStubs.c instead of this file.
 */
#include <stddef.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && (TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_VISION)

/* wwn-neovim is not currently merged into the Wawona registry, but
 * libwwn-pty may still reference wawona_nvim_main. */
int wawona_nvim_main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;
  return 127;
}

/* 127 is "command not found": dispatch reports the client as unavailable
 * rather than pretending it ran. */
#define WWN_UNBUNDLED_CLIENT(name)                                             \
  int name(int argc, char *argv[]) {                                           \
    (void)argc;                                                                \
    (void)argv;                                                                \
    return 127;                                                                \
  }

WWN_UNBUNDLED_CLIENT(phoon_main)
WWN_UNBUNDLED_CLIENT(foot_main)
WWN_UNBUNDLED_CLIENT(fuzzel_main)
WWN_UNBUNDLED_CLIENT(weston_compositor_main)
WWN_UNBUNDLED_CLIENT(weston_terminal_main)
WWN_UNBUNDLED_CLIENT(weston_simple_shm_main)
WWN_UNBUNDLED_CLIENT(simple_egl_main)
WWN_UNBUNDLED_CLIENT(clickdot_main)
WWN_UNBUNDLED_CLIENT(cliptest_main)
WWN_UNBUNDLED_CLIENT(constraints_main)
WWN_UNBUNDLED_CLIENT(dnd_main)
WWN_UNBUNDLED_CLIENT(editor_main)
WWN_UNBUNDLED_CLIENT(eventdemo_main)
WWN_UNBUNDLED_CLIENT(flower_main)
WWN_UNBUNDLED_CLIENT(image_main)
WWN_UNBUNDLED_CLIENT(resizor_main)
WWN_UNBUNDLED_CLIENT(scaler_main)
WWN_UNBUNDLED_CLIENT(smoke_main)
WWN_UNBUNDLED_CLIENT(stacking_main)
WWN_UNBUNDLED_CLIENT(transformed_main)

/* GPU cube clients. Swift (IlandNestedGpuClients / IlandDrmBindings) still
 * declares these with @_silgen_name, so they are strong references from the
 * app's own objects, not weak dispatch references. kmscube and gbm-es2-demo
 * are optional-software, and the store Apple-mobile keep-set presents through
 * Metal with no ANGLE, so there is nothing to run here. */
WWN_UNBUNDLED_CLIENT(kmscube_main)
WWN_UNBUNDLED_CLIENT(gbm_es2_demo_main)

#undef WWN_UNBUNDLED_CLIENT

/* niri takes no argv over its C ABI. */
int niri_main(void) {
  return 127;
}

/* Nested-compositor re-entrancy probes that dispatch reads before starting
 * weston or niri. Report "not running, not used" so dispatch takes its own
 * fail-closed path. */
int wwn_weston_compositor_is_running(void) {
  return 0;
}

int wwn_niri_main_is_running(void) {
  return 0;
}

int wwn_niri_main_already_used(void) {
  return 0;
}

/*
 * Temporary dogfood stubs: tip GuestConsoleView calls wwn_term_* that the
 * pinned ios-backend-sim (26.10.13) libwawona.a does not export yet. Real
 * Terminal sources live under src/term (flake input). Rebuild
 * wawona-ios-backend-sim against tip Terminal, then delete this block.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct wwn_term wwn_term;

wwn_term *wwn_term_new(uint32_t cols, uint32_t rows) {
  (void)cols;
  (void)rows;
  return NULL;
}

void wwn_term_free(wwn_term *term) { (void)term; }

void wwn_term_resize(wwn_term *term, uint32_t cols, uint32_t rows) {
  (void)term;
  (void)cols;
  (void)rows;
}

void wwn_term_feed(wwn_term *term, const uint8_t *bytes, size_t len) {
  (void)term;
  (void)bytes;
  (void)len;
}

size_t wwn_term_take_reply(wwn_term *term, uint8_t *buf, size_t cap) {
  (void)term;
  (void)buf;
  (void)cap;
  return 0;
}

void wwn_term_set_cell_px(wwn_term *term, uint32_t width, uint32_t height) {
  (void)term;
  (void)width;
  (void)height;
}

void wwn_term_pointer(wwn_term *term, uint8_t button, uint32_t col, uint32_t row,
                      int32_t pressed, int32_t motion) {
  (void)term;
  (void)button;
  (void)col;
  (void)row;
  (void)pressed;
  (void)motion;
}

char *wwn_term_lines_json(const wwn_term *term) {
  (void)term;
  char *s = (char *)malloc(3);
  if (s) {
    memcpy(s, "[]", 3);
  }
  return s;
}

char *wwn_term_images_json(const wwn_term *term) {
  (void)term;
  char *s = (char *)malloc(3);
  if (s) {
    memcpy(s, "[]", 3);
  }
  return s;
}

char *wwn_term_encode_paste(wwn_term *term, const uint8_t *bytes, size_t len) {
  (void)term;
  if (!bytes || len == 0) {
    char *empty = (char *)malloc(1);
    if (empty) {
      empty[0] = '\0';
    }
    return empty;
  }
  char *s = (char *)malloc(len + 1);
  if (s) {
    memcpy(s, bytes, len);
    s[len] = '\0';
  }
  return s;
}

void wwn_term_string_free(char *ptr) { free(ptr); }

#endif /* iOS / iPadOS / tvOS / visionOS */
