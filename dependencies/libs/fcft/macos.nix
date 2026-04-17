# fcft - Font loading and glyph rasterization library (used by foot terminal)
# https://codeberg.org/dnkl/fcft
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  fcftSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "fcft";
    tag = "3.3.1";
    sha256 = "sha256-qgNNowWQhiu6pr9bmWbBo3mHgdkmNpDHDBeTidk32SE=";
  };
  src = fetchSource fcftSource;
  
  # Dependencies
  freetype = if buildModule != null 
    then buildModule.buildForMacOS "freetype" {} 
    else pkgs.freetype;
  fontconfig = if buildModule != null
    then buildModule.buildForMacOS "fontconfig" {}
    else pkgs.fontconfig;
  pixman = if buildModule != null
    then buildModule.buildForMacOS "pixman" {}
    else pkgs.pixman;
  tllist = if buildModule != null
    then buildModule.buildForMacOS "tllist" {}
    else pkgs.tllist or (throw "tllist not available");
  utf8proc = if buildModule != null
    then buildModule.buildForMacOS "utf8proc" {}
    else pkgs.utf8proc;
in
pkgs.stdenv.mkDerivation {
  pname = "fcft";
  version = "3.3.1";
  inherit src;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    scdoc
  ];

  buildInputs = [
    freetype
    fontconfig
    pixman
    tllist
    utf8proc
  ];

  # Create a C11 threads wrapper for macOS (which lacks threads.h)
  postPatch = ''
    # Create threads.h wrapper using pthreads
    mkdir -p threads_compat
    cat > threads_compat/threads.h << 'EOF'
#ifndef FCFT_THREADS_H_COMPAT
#define FCFT_THREADS_H_COMPAT

/* C11 threads compatibility layer for macOS using pthreads */
#include <pthread.h>
#include <errno.h>
#include <time.h>

typedef pthread_t thrd_t;
typedef pthread_mutex_t mtx_t;
typedef pthread_cond_t cnd_t;
typedef pthread_once_t once_flag;
typedef pthread_key_t tss_t;

typedef void (*tss_dtor_t)(void *);
typedef int (*thrd_start_t)(void *);

enum {
    thrd_success = 0,
    thrd_nomem = ENOMEM,
    thrd_timedout = ETIMEDOUT,
    thrd_busy = EBUSY,
    thrd_error = -1
};

enum {
    mtx_plain = 0,
    mtx_recursive = 1,
    mtx_timed = 2
};

#define ONCE_FLAG_INIT PTHREAD_ONCE_INIT

static inline int thrd_create(thrd_t *thr, thrd_start_t func, void *arg) {
    return pthread_create(thr, NULL, (void*(*)(void*))func, arg) == 0 ? thrd_success : thrd_error;
}

static inline int thrd_join(thrd_t thr, int *res) {
    void *retval;
    int r = pthread_join(thr, &retval);
    if (res) *res = (int)(intptr_t)retval;
    return r == 0 ? thrd_success : thrd_error;
}

static inline thrd_t thrd_current(void) { return pthread_self(); }
static inline int thrd_equal(thrd_t a, thrd_t b) { return pthread_equal(a, b); }
static inline void thrd_yield(void) { sched_yield(); }

static inline int mtx_init(mtx_t *mtx, int type) {
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    if (type & mtx_recursive)
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    int r = pthread_mutex_init(mtx, &attr);
    pthread_mutexattr_destroy(&attr);
    return r == 0 ? thrd_success : thrd_error;
}

static inline int mtx_lock(mtx_t *mtx) {
    return pthread_mutex_lock(mtx) == 0 ? thrd_success : thrd_error;
}

static inline int mtx_unlock(mtx_t *mtx) {
    return pthread_mutex_unlock(mtx) == 0 ? thrd_success : thrd_error;
}

static inline int mtx_trylock(mtx_t *mtx) {
    int r = pthread_mutex_trylock(mtx);
    if (r == 0) return thrd_success;
    if (r == EBUSY) return thrd_busy;
    return thrd_error;
}

static inline void mtx_destroy(mtx_t *mtx) { pthread_mutex_destroy(mtx); }

static inline int cnd_init(cnd_t *cnd) {
    return pthread_cond_init(cnd, NULL) == 0 ? thrd_success : thrd_error;
}

static inline int cnd_signal(cnd_t *cnd) {
    return pthread_cond_signal(cnd) == 0 ? thrd_success : thrd_error;
}

static inline int cnd_broadcast(cnd_t *cnd) {
    return pthread_cond_broadcast(cnd) == 0 ? thrd_success : thrd_error;
}

static inline int cnd_wait(cnd_t *cnd, mtx_t *mtx) {
    return pthread_cond_wait(cnd, mtx) == 0 ? thrd_success : thrd_error;
}

static inline void cnd_destroy(cnd_t *cnd) { pthread_cond_destroy(cnd); }

static inline void call_once(once_flag *flag, void (*func)(void)) {
    pthread_once(flag, func);
}

static inline int tss_create(tss_t *key, tss_dtor_t dtor) {
    return pthread_key_create(key, dtor) == 0 ? thrd_success : thrd_error;
}

static inline void *tss_get(tss_t key) { return pthread_getspecific(key); }

static inline int tss_set(tss_t key, void *val) {
    return pthread_setspecific(key, val) == 0 ? thrd_success : thrd_error;
}

static inline void tss_delete(tss_t key) { pthread_key_delete(key); }

#endif /* FCFT_THREADS_H_COMPAT */
EOF

    # Provide byteswap.h compatibility for Darwin (fcft expects glibc header)
    cat > threads_compat/byteswap.h << 'EOF'
#ifndef FCFT_BYTESWAP_H_COMPAT
#define FCFT_BYTESWAP_H_COMPAT

#include <stdint.h>
#include <libkern/OSByteOrder.h>

#ifndef bswap_16
#define bswap_16(x) OSSwapInt16((uint16_t)(x))
#endif

#ifndef bswap_32
#define bswap_32(x) OSSwapInt32((uint32_t)(x))
#endif

#ifndef bswap_64
#define bswap_64(x) OSSwapInt64((uint64_t)(x))
#endif

#endif /* FCFT_BYTESWAP_H_COMPAT */
EOF
    
    # Fix missing xlocale definitions on macOS
    sed -i '1i#include <xlocale.h>' fcft.c
  '';

  preConfigure = ''
    # Robust SDK detection using xcrun (gold standard for modern macOS)
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 1: Command Line Tools path
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 2: Legacy system path
      MACOS_SDK="/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 3: Custom script
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 4: Global xcode-select
      MACOS_SDK=$(/usr/bin/xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi

    if [ ! -d "$MACOS_SDK" ]; then
      echo "ERROR: MacOSX SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    # Isolate environment from Nix wrapper flags to prevent linker conflicts
    unset DEVELOPER_DIR
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    
    # Add threads_compat to include path for C11 threads compatibility
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC -I$(pwd)/threads_compat $CFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
  '';

  __noChroot = true;

  mesonFlags = [
    "-Ddocs=disabled"
    "-Dtest-text-shaping=false"
    "-Dgrapheme-shaping=disabled"
    "-Drun-shaping=disabled"
  ];

  meta = with lib; {
    description = "Simple library for font loading and glyph rasterization";
    homepage = "https://codeberg.org/dnkl/fcft";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
