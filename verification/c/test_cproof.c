#include "wawona_cproof.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    char dst[4];
    atomic_int n = 0;
    assert(wawona_copy_capped(dst, sizeof dst, "abcdef", 6) == 4);
    assert(memcmp(dst, "abcd", 4) == 0);
    assert(wawona_shm_rect_in_pool(0, 2, 2, 2, 4) == 1);
    assert(wawona_shm_rect_in_pool(2, 2, 2, 2, 4) == 0);
    assert(wawona_shm_rect_in_pool(-1, 1, 1, 1, 8) == 0);
    wawona_count_inc(&n);
    wawona_count_inc(&n);
    assert(wawona_count_load(&n) == 2);
    wawona_count_dec(&n);
    assert(wawona_count_load(&n) == 1);
    wawona_count_store(&n, 0);
    assert(wawona_count_load(&n) == 0);
    assert(wawona_linux_keycode_ok(0));
    assert(wawona_linux_keycode_ok(28));
    assert(!wawona_linux_keycode_ok(0x400));
    assert(wawona_texture_cache_index_ok(0));
    assert(wawona_texture_cache_index_ok(63));
    assert(!wawona_texture_cache_index_ok(64));
    assert(wawona_client_map_index_ok(0, 15));
    assert(!wawona_client_map_index_ok(15, 15));
    puts("cproof ok");
    return 0;
}
