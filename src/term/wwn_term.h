/* Guest console screen. The VT screen lives in github.com/Wawona/Terminal.
   This header is the in-process C link. Hosts draw the cells.
   iOS uses the SwiftUI text scroll in Terminal/apple/Terminal.
   The face is the bundled DejaVuSansM Nerd Font Mono, not a system font. */
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

/* One-shot pack of a whole buffer. Little-endian u32s:
   line_count, then for each line: cell_count, then cp, fg, bg, attrs.
   Free with wwn_term_snapshot_free. */
uint8_t *wwn_term_snapshot(const uint8_t *bytes, size_t len, uint32_t cols,
                           uint32_t rows, size_t *out_len);
/* Same pack as wwn_term_snapshot, for a live screen. */
uint8_t *wwn_term_export(const wwn_term *term, size_t *out_len);
void wwn_term_snapshot_free(uint8_t *ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif
