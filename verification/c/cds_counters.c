#include "wawona_cproof.h"

/* CDSChecker target: concurrent inc/dec on one counter. */
int user_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  atomic_int n = 0;
  wawona_count_inc(&n);
  wawona_count_dec(&n);
  return wawona_count_load(&n);
}
