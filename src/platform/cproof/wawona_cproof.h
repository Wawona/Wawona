#ifndef WAWONA_CPROOF_H
#define WAWONA_CPROOF_H

#include <poll.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

/* Bytes stored. A non-positive poll ends the loop. total stays inside cap. */
static inline size_t wawona_bounded_poll_read(int fd, char *buf, size_t cap,
                                              int timeout_ms) {
    size_t total = 0;
    if (buf == NULL || cap == 0) {
        return 0;
    }
    while (total + 1 < cap) {
        struct pollfd pf;
        int pr;
        ssize_t n;
        pf.fd = fd;
        pf.events = POLLIN;
        pf.revents = 0;
        pr = poll(&pf, 1, timeout_ms);
        if (pr <= 0) {
            break;
        }
        n = read(fd, buf + total, cap - 1 - total);
        if (n <= 0) {
            break;
        }
        total += (size_t)n;
    }
    buf[total] = '\0';
    return total;
}

static inline size_t wawona_copy_capped(void *dst, size_t dst_cap, const void *src,
                                        size_t src_len) {
    size_t n;
    if (dst == NULL || src == NULL || dst_cap == 0) {
        return 0;
    }
    n = src_len < dst_cap ? src_len : dst_cap;
    memcpy(dst, src, n);
    return n;
}

static inline int wawona_shm_rect_in_pool(int32_t offset, int32_t width,
                                          int32_t height, int32_t stride,
                                          size_t pool_size) {
    size_t off;
    size_t row;
    size_t rows;
    size_t end;
    if (offset < 0 || width <= 0 || height <= 0 || stride <= 0) {
        return 0;
    }
    if ((size_t)width > (size_t)stride) {
        return 0;
    }
    off = (size_t)offset;
    row = (size_t)stride;
    rows = (size_t)height;
    if (off > pool_size) {
        return 0;
    }
    if (rows > 0 && row > (pool_size - off) / rows) {
        return 0;
    }
    end = off + row * rows;
    if (end < off || end > pool_size) {
        return 0;
    }
    return 1;
}

static inline int wawona_count_inc(atomic_int *counter) {
    return atomic_fetch_add(counter, 1);
}

static inline int wawona_count_dec(atomic_int *counter) {
    return atomic_fetch_sub(counter, 1);
}

static inline int wawona_count_load(atomic_int *counter) {
    return atomic_load(counter);
}

static inline void wawona_count_store(atomic_int *counter, int value) {
    atomic_store(counter, value);
}

/* Linux KEY_RESERVED is 0. KEY_MAX is typically 0x2ff. */
#ifndef WAWONA_KEY_RESERVED
#define WAWONA_KEY_RESERVED 0u
#endif
#ifndef WAWONA_KEY_MAX
#define WAWONA_KEY_MAX 0x2ffu
#endif

static inline int wawona_linux_keycode_ok(uint32_t code) {
    return code == WAWONA_KEY_RESERVED || code <= WAWONA_KEY_MAX;
}

#ifndef WAWONA_MAX_CACHED_BUFFERS
#define WAWONA_MAX_CACHED_BUFFERS 64
#endif

static inline int wawona_texture_cache_index_ok(int index) {
    return index >= 0 && index < WAWONA_MAX_CACHED_BUFFERS;
}

static inline int wawona_client_map_index_ok(size_t index, size_t count) {
    return index < count;
}

#endif
