/* Rust VT C ABI for Wawona Terminal hosts (libghostty-vt via VtEngine).
   Grid only. Chrome (windows, PTY, ToolbarKeys) stays in Wawona L4.
   Zig GhosttyLib keeps ghostty_surface_* for Metal. Do not collide. */
#ifndef WWN_TERM_H
#define WWN_TERM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int wwn_term_init(void);
void wwn_term_shutdown(void);

typedef struct WwnTermSurface WwnTermSurface;

typedef struct WwnTermCell {
  uint32_t cp;
  uint32_t fg;
  uint32_t bg;
  uint32_t attrs;
} WwnTermCell;

#define WWN_TERM_BOLD 1u
#define WWN_TERM_DIM 2u
#define WWN_TERM_ITALIC 4u
#define WWN_TERM_UNDERLINE 8u

WwnTermSurface *wwn_term_new(uint32_t cols, uint32_t rows);
void wwn_term_free(WwnTermSurface *s);
void wwn_term_resize(WwnTermSurface *s, uint32_t cols, uint32_t rows);
void wwn_term_feed(WwnTermSurface *s, const uint8_t *bytes, size_t len);
void wwn_term_key(
    WwnTermSurface *s, uint32_t keycode, uint32_t mods, uint32_t action, const uint8_t *text,
    size_t text_len);
/* Selection: mode 0=cell, 1=word, 2=row. Coords are viewport cells. */
void wwn_term_select_begin(WwnTermSurface *s, uint32_t col, uint32_t row, uint32_t mode);
void wwn_term_select_extend(WwnTermSurface *s, uint32_t col, uint32_t row);
void wwn_term_select_clear(WwnTermSurface *s);
void wwn_term_select_all(WwnTermSurface *s);
size_t wwn_term_take_reply(WwnTermSurface *s, uint8_t *buf, size_t cap);
uint32_t wwn_term_cols(const WwnTermSurface *s);
uint32_t wwn_term_line_count(const WwnTermSurface *s);
uint32_t wwn_term_viewport(
    const WwnTermSurface *s, uint32_t origin, WwnTermCell *out, uint32_t cap, uint32_t *cols,
    uint32_t *rows);
uint32_t wwn_term_origin(const WwnTermSurface *s);
void wwn_term_scroll_to(WwnTermSurface *s, uint32_t origin);
void wwn_term_scroll_delta(WwnTermSurface *s, int32_t delta);
void wwn_term_scroll_bottom(WwnTermSurface *s);
uint32_t wwn_term_scroll_total(const WwnTermSurface *s);
uint32_t wwn_term_selection_text(const WwnTermSurface *s, uint8_t *out, uint32_t cap);
uint32_t wwn_term_title(const WwnTermSurface *s, uint8_t *out, uint32_t cap);
void wwn_term_set_cell_px(WwnTermSurface *s, uint32_t width, uint32_t height);
void wwn_term_pointer(
    WwnTermSurface *s, uint8_t button, uint32_t col, uint32_t row, int pressed, int motion);
char *wwn_term_encode_paste(WwnTermSurface *s, const uint8_t *bytes, size_t len);
void wwn_term_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif
