#ifndef __SYMREZ_BASE__
#define __SYMREZ_BASE__

#include <stdio.h>
#include <stdbool.h>
#include <os/base.h>

#if __has_feature(nullability)
#define SR_NULLABLE _Nullable
#define SR_NONNULL _Nonnull
#else
#define SR_NULLABLE
#define SR_NONNULL
#endif

#ifndef SR_INLINE
#define SR_INLINE OS_INLINE OS_ALWAYS_INLINE
#endif

typedef const struct mach_header_64* mach_header_t;
typedef struct symrez* symrez_t;
typedef struct sr_iterator* sr_iterator_t;
typedef struct sr_iter_result * SR_NULLABLE sr_iter_result_t;
typedef void * SR_NULLABLE sr_ptr_t;
typedef char* sr_symbol_t;

#endif
