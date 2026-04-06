# foot - Fast, lightweight Wayland terminal emulator
# https://codeberg.org/dnkl/foot
#
# macOS port for Wawona Wayland compositor
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../dependencies/utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  footSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "foot";
    tag = "1.25.0";
    sha256 = "sha256-s7SwIdkWhBKcq9u4V0FLKW6CA36MBvDyB9ELB0V52O0=";
  };
  src = fetchSource footSource;
  
  linuxInputHeaders = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/v6.6/include/uapi/linux/input-event-codes.h";
    sha256 = "14sl96hc8j48ikjgg4jynm4gsvax5ywdypyahzi2816l4xlvxd93";
  };
  
  # Dependencies from buildModule (Wawona's custom macOS ports)
  libwayland = if buildModule != null 
    then buildModule.buildForMacOS "libwayland" {} 
    else pkgs.wayland;
  pixman = if buildModule != null
    then buildModule.buildForMacOS "pixman" {}
    else pkgs.pixman;
  xkbcommon = if buildModule != null
    then buildModule.buildForMacOS "xkbcommon" {}
    else pkgs.libxkbcommon;
  fcft = if buildModule != null
    then buildModule.buildForMacOS "fcft" {}
    else (throw "fcft not available in nixpkgs, use buildModule");
  tllist = if buildModule != null
    then buildModule.buildForMacOS "tllist" {}
    else pkgs.tllist or (throw "tllist not available");
  utf8proc = if buildModule != null
    then buildModule.buildForMacOS "utf8proc" {}
    else pkgs.utf8proc;
  fontconfig = if buildModule != null
    then buildModule.buildForMacOS "fontconfig" {}
    else pkgs.fontconfig;
  freetype = if buildModule != null
    then buildModule.buildForMacOS "freetype" {}
    else pkgs.freetype;
  epoll-shim = if buildModule != null
    then buildModule.buildForMacOS "epoll-shim" {}
    else pkgs.epoll-shim;
in
pkgs.stdenv.mkDerivation {
  pname = "foot";
  version = "1.25.0";
  inherit src;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    scdoc
    wayland-scanner
    python3
    ncurses  # For terminfo/tic
  ];

  buildInputs = [
    libwayland
    pixman
    xkbcommon
    fcft
    tllist
    utf8proc
    fontconfig
    freetype
    pkgs.libiconv
    # epoll-shim is manually linked in preConfigure to ensure correct include order
    pkgs.wayland-protocols
  ];

  __noChroot = true;

  preConfigure = ''
    MACOS_SDK="/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    # Isolate environment from Nix wrapper flags to prevent linker conflicts
    unset DEVELOPER_DIR
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    
    # Add compat headers to include path and link against epoll-shim
    # Explicitly include epoll-shim include dir AFTER compat dir to ensure our overrides work
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC -I$(pwd)/compat -I${epoll-shim}/include/libepoll-shim -D__STDC_ISO_10646__=201103L -Wno-deprecated-declarations -DSIGRTMAX=32 $CFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -L${epoll-shim}/lib -lepoll-shim $LDFLAGS"
  '';

  postPatch = ''
    # Patch for macOS compatibility
    # foot uses Linux-specific APIs that need adaptation
    
    # Create a compat directory for macOS compatibility headers
    mkdir -p compat/linux compat/sys
    
    # Copy Linux input event codes
    cp ${linuxInputHeaders} compat/linux/input-event-codes.h
    
    # Create uchar.h wrapper (macOS lacks this C11 header)
    cat > compat/uchar.h << 'EOF'
#ifndef FOOT_UCHAR_H_COMPAT
#define FOOT_UCHAR_H_COMPAT

/* uchar.h compatibility for macOS */
#include <stdint.h>
#include <wchar.h>

typedef uint_least16_t char16_t;
typedef uint_least32_t char32_t;

/* Minimal mbstate_t-based conversion stubs */
static inline size_t c32rtomb(char *s, char32_t c32, mbstate_t *ps) {
    (void)ps;
    if (c32 < 0x80) {
        if (s) s[0] = (char)c32;
        return 1;
    } else if (c32 < 0x800) {
        if (s) { s[0] = 0xC0 | (c32 >> 6); s[1] = 0x80 | (c32 & 0x3F); }
        return 2;
    } else if (c32 < 0x10000) {
        if (s) { s[0] = 0xE0 | (c32 >> 12); s[1] = 0x80 | ((c32 >> 6) & 0x3F); s[2] = 0x80 | (c32 & 0x3F); }
        return 3;
    } else {
        if (s) { s[0] = 0xF0 | (c32 >> 18); s[1] = 0x80 | ((c32 >> 12) & 0x3F); s[2] = 0x80 | ((c32 >> 6) & 0x3F); s[3] = 0x80 | (c32 & 0x3F); }
        return 4;
    }
}

static inline size_t mbrtoc32(char32_t *pc32, const char *s, size_t n, mbstate_t *ps) {
    (void)ps;
    if (!s || n == 0) return 0;
    unsigned char c = (unsigned char)s[0];
    if (c < 0x80) {
        if (pc32) *pc32 = c;
        return c ? 1 : 0;
    } else if ((c & 0xE0) == 0xC0 && n >= 2) {
        if (pc32) *pc32 = ((c & 0x1F) << 6) | (s[1] & 0x3F);
        return 2;
    } else if ((c & 0xF0) == 0xE0 && n >= 3) {
        if (pc32) *pc32 = ((c & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F);
        return 3;
    } else if ((c & 0xF8) == 0xF0 && n >= 4) {
        if (pc32) *pc32 = ((c & 0x07) << 18) | ((s[1] & 0x3F) << 12) | ((s[2] & 0x3F) << 6) | (s[3] & 0x3F);
        return 4;
    }
    return (size_t)-1;
}

#endif /* FOOT_UCHAR_H_COMPAT */
EOF

    # Create threads.h wrapper using pthreads (macOS lacks C11 threads)
    cat > compat/threads.h << 'EOF'
#ifndef FOOT_THREADS_H_COMPAT
#define FOOT_THREADS_H_COMPAT

/* C11 threads compatibility layer for macOS using pthreads */
#include <pthread.h>
#include <errno.h>
#include <time.h>
#include <sched.h>

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

#endif /* FOOT_THREADS_H_COMPAT */
EOF

    # Create pthread.h wrapper for pthread_setname_np
    cat > compat/pthread.h << 'EOF'
#ifndef FOOT_PTHREAD_H_COMPAT
#define FOOT_PTHREAD_H_COMPAT

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <pthread.h>
#pragma clang diagnostic pop

#ifdef __APPLE__
// macOS pthread_setname_np takes only name (sets calling thread)
#define pthread_setname_np(thread, name) pthread_setname_np(name)
#endif

#endif
EOF

    # Create sys/timerfd.h wrapper for itimerspec
    cat > compat/sys/timerfd.h << 'EOF'
#ifndef FOOT_SYS_TIMERFD_H_COMPAT
#define FOOT_SYS_TIMERFD_H_COMPAT

#include <time.h>

#ifndef _STRUCT_ITIMERSPEC
struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
};
#define _STRUCT_ITIMERSPEC
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <sys/timerfd.h>
#pragma clang diagnostic pop

#endif
EOF

    # Create sys/socket.h wrapper for SOCK_CLOEXEC/NONBLOCK
    cat > compat/sys/socket.h << 'EOF'
#ifndef FOOT_SYS_SOCKET_H_COMPAT
#define FOOT_SYS_SOCKET_H_COMPAT

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <sys/socket.h>
#pragma clang diagnostic pop

#include <fcntl.h>

// Define compat flags since macOS doesn't support them in socket/accept4
#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0x10000000
#endif

#ifndef SOCK_NONBLOCK
#define SOCK_NONBLOCK 0x20000000
#endif

#ifndef SO_DOMAIN
#define SO_DOMAIN SO_TYPE
#endif

#ifdef __APPLE__
static inline int foot_socket_compat(int domain, int type, int protocol) {
    int real_type = type;
    int flags = 0;
    
    if (type & SOCK_CLOEXEC) {
        real_type &= ~SOCK_CLOEXEC;
        flags |= FD_CLOEXEC;
    }
    if (type & SOCK_NONBLOCK) {
        real_type &= ~SOCK_NONBLOCK;
        // Nonblock is file status flag, not FD flag
    }
    
    int fd = (socket)(domain, real_type, protocol);
    if (fd < 0) return -1;
    
    if (flags & FD_CLOEXEC) {
        fcntl(fd, F_SETFD, FD_CLOEXEC);
    }
    if (type & SOCK_NONBLOCK) {
        int fl = fcntl(fd, F_GETFL);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    }
    
    return fd;
}

static inline int accept4(int sockfd, struct sockaddr *addr, socklen_t *addrlen, int flags) {
    int fd = accept(sockfd, addr, addrlen);
    if (fd < 0) return -1;
    
    if (flags & SOCK_CLOEXEC) {
        fcntl(fd, F_SETFD, FD_CLOEXEC);
    }
    if (flags & SOCK_NONBLOCK) {
        int fl = fcntl(fd, F_GETFL);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    }
    
    return fd;
}

#define socket foot_socket_compat
#endif

#endif
EOF

    # Create unistd.h wrapper for pipe2
    cat > compat/unistd.h << 'EOF'
#ifndef FOOT_UNISTD_H_COMPAT
#define FOOT_UNISTD_H_COMPAT

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <unistd.h>
#pragma clang diagnostic pop

#include <fcntl.h>

#ifdef __APPLE__
#ifndef O_CLOEXEC
#define O_CLOEXEC 0
// macOS has O_CLOEXEC but maybe it's not defined for strict std?
// actually it is defined in fcntl.h usually.
#endif

static inline int pipe2(int fds[2], int flags) {
    if (pipe(fds) != 0) return -1;
    if (flags & O_CLOEXEC) {
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    }
    if (flags & O_NONBLOCK) {
        fcntl(fds[0], F_SETFL, O_NONBLOCK);
        fcntl(fds[1], F_SETFL, O_NONBLOCK);
    }
    return 0;
}
#endif

#endif

EOF

    # Create sys/ioctl.h wrapper to suppress TIOCSWINSZ ENOTTY
    cat > compat/sys/ioctl.h << 'EOF'
#ifndef FOOT_SYS_IOCTL_H_COMPAT
#define FOOT_SYS_IOCTL_H_COMPAT

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <sys/ioctl.h>
#pragma clang diagnostic pop
#include <errno.h>
#include <stdarg.h>

#ifdef __APPLE__
static inline int foot_ioctl_compat(int fd, unsigned long request, ...) {
    va_list args;
    va_start(args, request);
    void *argp = va_arg(args, void *);
    va_end(args);
    
    int ret = ioctl(fd, request, argp);
    if (ret == -1 && errno == ENOTTY && request == TIOCSWINSZ) {
        return 0; // Fake success for TIOCSWINSZ on macOS PTY
    }
    return ret;
}
#define ioctl foot_ioctl_compat
#endif

#endif
EOF

    # Create stdlib.h wrapper for reallocarray
    cat > compat/stdlib.h << 'EOF'
#ifndef FOOT_STDLIB_H_COMPAT
#define FOOT_STDLIB_H_COMPAT

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <stdlib.h>
#pragma clang diagnostic pop

#ifdef __APPLE__
static inline void *reallocarray(void *ptr, size_t nmemb, size_t size) {
    if (nmemb && size > SIZE_MAX / nmemb) return NULL;
    return realloc(ptr, nmemb * size);
}
#endif

#endif
EOF

    # Create semaphore.h wrapper for unnamed semaphores
    cat > compat/semaphore.h << 'EOF'
#ifndef FOOT_SEMAPHORE_H_COMPAT
#define FOOT_SEMAPHORE_H_COMPAT

#include <pthread.h>
#include <errno.h>
#include <time.h>

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    unsigned int value;
} sem_t;

#define SEM_FAILED ((sem_t *)0)

static inline int sem_init(sem_t *sem, int pshared, unsigned int value) {
    if (pshared) { errno = ENOSYS; return -1; }
    sem->value = value;
    pthread_mutex_init(&sem->mutex, NULL);
    pthread_cond_init(&sem->cond, NULL);
    return 0;
}

static inline int sem_destroy(sem_t *sem) {
    pthread_mutex_destroy(&sem->mutex);
    pthread_cond_destroy(&sem->cond);
    return 0;
}

static inline int sem_wait(sem_t *sem) {
    pthread_mutex_lock(&sem->mutex);
    while (sem->value == 0) {
        pthread_cond_wait(&sem->cond, &sem->mutex);
    }
    sem->value--;
    pthread_mutex_unlock(&sem->mutex);
    return 0;
}

static inline int sem_trywait(sem_t *sem) {
    int ret = 0;
    pthread_mutex_lock(&sem->mutex);
    if (sem->value > 0) {
        sem->value--;
    } else {
        errno = EAGAIN;
        ret = -1;
    }
    pthread_mutex_unlock(&sem->mutex);
    return ret;
}

static inline int sem_timedwait(sem_t *sem, const struct timespec *abs_timeout) {
    int ret = 0;
    pthread_mutex_lock(&sem->mutex);
    while (sem->value == 0) {
        ret = pthread_cond_timedwait(&sem->cond, &sem->mutex, abs_timeout);
        if (ret != 0) {
            errno = ret;
            ret = -1;
            break;
        }
    }
    if (ret == 0) {
        sem->value--;
    }
    pthread_mutex_unlock(&sem->mutex);
    return ret;
}

static inline int sem_post(sem_t *sem) {
    pthread_mutex_lock(&sem->mutex);
    sem->value++;
    pthread_cond_signal(&sem->cond);
    pthread_mutex_unlock(&sem->mutex);
    return 0;
}

static inline int sem_getvalue(sem_t *sem, int *sval) {
    pthread_mutex_lock(&sem->mutex);
    *sval = (int)sem->value;
    pthread_mutex_unlock(&sem->mutex);
    return 0;
}

#endif
EOF

    # Fix Python script for older Python versions (< 3.10 don't support X | Y union syntax)
    sed -i.bak 's/None|int/typing.Optional[int]/g' scripts/generate-emoji-variation-sequences.py 2>/dev/null || true
    # Use python to insert the import to avoid sed issues with newlines
    python3 -c "import sys; lines = sys.stdin.readlines(); lines.insert(1, 'from typing import Optional\n'); sys.stdout.writelines(lines)" < scripts/generate-emoji-variation-sequences.py > scripts/generate-emoji-variation-sequences.py.tmp && mv scripts/generate-emoji-variation-sequences.py.tmp scripts/generate-emoji-variation-sequences.py
    sed -i.bak 's/typing.Optional\[int\]/Optional[int]/g' scripts/generate-emoji-variation-sequences.py 2>/dev/null || true
    
    sed -i.bak 's/typing.Optional\[int\]/Optional[int]/g' scripts/generate-emoji-variation-sequences.py 2>/dev/null || true
    
    # Add macOS compatibility defines to source files that need them
    MACOS_COMPAT=$(cat <<'EOF'
#ifdef __APPLE__
#include <sys/types.h>
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif
#endif
EOF
)
    
    # Apply to key source files
    for f in terminal.c render.c main.c; do
      if [ -f "$f" ]; then
        echo "$MACOS_COMPAT" | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      fi
    done
  '';

  mesonFlags = [
    "-Ddocs=disabled"
    "-Dthemes=false"
    "-Dime=false"
    "-Dterminfo=disabled"
    "-Dtests=false"
    # Disable systemd (Linux-only)
    "-Dsystemd-units-dir="
  ];

  # Environment setup for Wayland
  postInstall = ''
    # Create wrapper script that sets up Wayland environment for Wawona
    mv $out/bin/foot $out/bin/.foot-wrapped
    cat > $out/bin/foot << 'EOF'
#!/bin/sh
# Foot terminal wrapper for Wawona compositor
export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/tmp/wawona-$(id -u)}"
export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"

# Ensure runtime dir exists
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
fi

exec "$(dirname "$0")/.foot-wrapped" "$@"
EOF
    chmod +x $out/bin/foot
    
    # Create .desktop file for launcher
    mkdir -p $out/share/applications
    cat > $out/share/applications/foot.desktop << 'EOF'
[Desktop Entry]
Name=Foot Terminal
Comment=Fast, lightweight Wayland terminal
Exec=foot
Icon=foot
Type=Application
Categories=System;TerminalEmulator;
Terminal=false
EOF

    # Create app metadata for Wawona launcher
    mkdir -p $out/share/wawona
    cat > $out/share/wawona/app.json << 'EOF'
{
  "id": "org.codeberg.dnkl.foot",
  "name": "Foot Terminal",
  "description": "Fast, lightweight Wayland terminal emulator",
  "version": "1.25.0",
  "icon": "foot.png",
  "executable": "foot",
  "categories": ["Terminal", "System"]
}
EOF
  '';

  meta = with lib; {
    description = "Fast, lightweight and minimalistic Wayland terminal emulator";
    homepage = "https://codeberg.org/dnkl/foot";
    license = licenses.mit;
    platforms = platforms.darwin;
    mainProgram = "foot";
  };
}
