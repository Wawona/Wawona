#ifndef WWN_WATCH_KEYMAP_H
#define WWN_WATCH_KEYMAP_H

/*
 * Watch mini compositor (C) still needs an XKB v1 fd. The string comes from
 * HostKeymapBridge (Rust). Do not grow a second layout blob here.
 */

#ifdef __cplusplus
extern "C" {
#endif

char *WWNHostKeymapXkbV1Copy(void);
void WWNHostKeymapXkbV1Free(char *s);

#ifdef __cplusplus
}
#endif

#endif
