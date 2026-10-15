/* Guest console screen. The VT screen lives in github.com/Wawona/Terminal.
   wwn_term_viewport is the GPU upload. lines_json remains until generated
   UniFFI Swift/Kotlin is on the compile. This crate does not link a GPU
   library. Hosts pick the face. */
#ifndef WWN_TERM_H
#define WWN_TERM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct wwn_term wwn_term;

typedef struct wwn_term_cell {
  uint32_t cp;
  uint32_t fg;
  uint32_t bg;
  uint32_t attrs;
} wwn_term_cell;

#define WWN_TERM_BOLD 1u
#define WWN_TERM_DIM 2u
#define WWN_TERM_ITALIC 4u
#define WWN_TERM_UNDERLINE 8u

wwn_term *wwn_term_new(uint32_t cols, uint32_t rows);
void wwn_term_free(wwn_term *term);
void wwn_term_resize(wwn_term *term, uint32_t cols, uint32_t rows);
void wwn_term_feed(wwn_term *term, const uint8_t *bytes, size_t len);
/* Bytes the host must write back to the PTY (cursor reports). */
size_t wwn_term_take_reply(wwn_term *term, uint8_t *buf, size_t cap);
uint32_t wwn_term_cols(const wwn_term *term);
uint32_t wwn_term_line_count(const wwn_term *term);
uint32_t wwn_term_line_cells(const wwn_term *term, uint32_t line,
                             wwn_term_cell *out, uint32_t cap);
void wwn_term_cursor(const wwn_term *term, uint32_t *line, uint32_t *col);

/* JSON array of UniFFI TerminalLine records. Free with wwn_term_string_free. */
char *wwn_term_lines_json(const wwn_term *term);
char *wwn_term_bytes_lines_json(const uint8_t *bytes, size_t len, uint32_t cols,
                                uint32_t rows);
void wwn_term_string_free(char *ptr);
/* Paste bytes for the PTY. Wraps with mode 2004 when that mode is on. */
char *wwn_term_encode_paste(const wwn_term *term, const uint8_t *bytes, size_t len);
/* button: 0 left, 1 middle, 2 right. Reports land in take_reply. */
void wwn_term_pointer(wwn_term *term, uint8_t button, uint32_t col, uint32_t row,
                      int pressed, int motion);

/* Visible grid, one GPU upload. origin is a scrollback row. */
uint32_t wwn_term_viewport(const wwn_term *term, uint32_t origin,
                           wwn_term_cell *out, uint32_t cap, uint32_t *cols,
                           uint32_t *rows);
uint32_t wwn_term_origin(const wwn_term *term);
/* OSC 0 / OSC 2 title. Writes a NUL and returns the length without it. */
uint32_t wwn_term_title(const wwn_term *term, uint8_t *out, uint32_t cap);

/* Kitty graphics. RGBA8 placements. Copy pixels out before the next feed. */
typedef struct wwn_term_image {
  uint32_t id;
  int32_t col;
  int32_t row;
  int32_t x_px;
  int32_t y_px;
  uint32_t px_w;
  uint32_t px_h;
  uint32_t cols;
  uint32_t rows;
  int32_t z;
  uint32_t rgba_len;
} wwn_term_image;

void wwn_term_set_cell_px(wwn_term *term, uint32_t width, uint32_t height);
uint32_t wwn_term_image_count(const wwn_term *term);
int wwn_term_image_meta(const wwn_term *term, uint32_t index, wwn_term_image *out);
uint32_t wwn_term_image_rgba(const wwn_term *term, uint32_t index, uint8_t *out,
                             uint32_t cap);
char *wwn_term_images_json(const wwn_term *term);
char *wwn_term_bytes_images_json(const uint8_t *bytes, size_t len, uint32_t cols,
                                 uint32_t rows, uint32_t cell_w, uint32_t cell_h);

#ifdef __cplusplus
}
#endif

#endif
