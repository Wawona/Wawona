#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WESTON_DIR="$SCRIPT_DIR/weston"
BUILD_DIR="$SCRIPT_DIR/build-weston"
SHIM_BUILD="$SCRIPT_DIR/build"
DEPS_DIR="$BUILD_DIR/deps"
STUB_INCDIR="$DEPS_DIR/include"
STUB_LIBDIR="$DEPS_DIR/lib"
STUB_PCDIR="$DEPS_DIR/pkgconfig"
SHIM_DYLIB="$SHIM_BUILD/libwayland-mac.dylib"

# ============================================================
# 0. Clone weston source if not present
# ============================================================
if [ ! -d "$WESTON_DIR/.git" ]; then
    echo "=== Cloning weston ==="
    git clone --depth 1 --branch 15.0 \
        https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/wayland/weston.git \
        "$WESTON_DIR"
fi

# ============================================================
# 1. Build the shim
# ============================================================
echo "=== Building shim ==="
if [ ! -f "$SHIM_DYLIB" ]; then
    (cd "$SCRIPT_DIR" && ./compile.sh)
fi
echo "Shim: $SHIM_DYLIB"

# ============================================================
# 2. Create stub headers + stub libraries for Linux-only deps
# ============================================================
# Clean build dir before creating deps (so --wipe doesn't nuke them)
rm -rf "$BUILD_DIR"
echo "=== Creating stubs ==="
mkdir -p "$STUB_INCDIR/libevdev" "$STUB_INCDIR/linux" "$STUB_LIBDIR" "$STUB_PCDIR"

cat > "$STUB_INCDIR/linux/types.h" << 'EOF'
typedef unsigned char __u8;
typedef unsigned short __u16;
typedef unsigned int __u32;
typedef unsigned long long __u64;
typedef signed char __s8;
typedef short __s16;
typedef int __s32;
typedef long long __s64;
EOF

cat > "$STUB_INCDIR/pty.h" << 'EOF'
/* macOS: pty.h maps to util.h */
#include <util.h>
EOF

cat > "$STUB_INCDIR/malloc.h" << 'EOF'
#include <stdlib.h>
EOF

cat > "$STUB_INCDIR/drm.h" << 'EOF'
#include <stdint.h>

#define DRM_MODE_CONNECTOR_LVDS 7
#define DRM_MODE_CONNECTOR_eDP  14

/* Color management LUT entry used by weston DRM backend */
struct drm_color_lut {
    uint16_t red;
    uint16_t green;
    uint16_t blue;
    uint16_t reserved;
};
EOF

cat > "$STUB_INCDIR/linux/limits.h" << 'EOF'
#ifndef _LINUX_LIMITS_H
#define _LINUX_LIMITS_H
/* linux/limits.h maps to <sys/syslimits.h> on macOS. */
#include <sys/syslimits.h>
#endif
EOF

cat > "$STUB_INCDIR/endian.h" << 'EOF'
/* Stub <endian.h> using macOS <machine/endian.h>. */
#include <machine/endian.h>
#ifndef __LITTLE_ENDIAN
#define __LITTLE_ENDIAN 1234
#endif
#ifndef __BIG_ENDIAN
#define __BIG_ENDIAN 4321
#endif
#ifndef __BYTE_ORDER
#if defined(__LITTLE_ENDIAN__) || defined(__arm64__) || defined(__i386__) || defined(__x86_64__)
#define __BYTE_ORDER __LITTLE_ENDIAN
#else
#define __BYTE_ORDER __BIG_ENDIAN
#endif
#endif
EOF

cat > "$STUB_INCDIR/values.h" << 'EOF'
/* System V values.h — constants for machine-dependent values.
 * On modern systems these come from <limits.h> and <float.h>. */
#include <limits.h>
#include <float.h>
#ifndef MAXINT
#define MAXINT  INT_MAX
#endif
#ifndef MAXLONG
#define MAXLONG LONG_MAX
#endif
#ifndef MAXFLOAT
#define MAXFLOAT FLT_MAX
#endif
#ifndef MAXDOUBLE
#define MAXDOUBLE DBL_MAX
#endif
EOF

cat > "$STUB_INCDIR/linux/types.h" << 'EOF'
#ifndef _LINUX_TYPES_H
#define _LINUX_TYPES_H
/* Minimal linux/types.h stub for weston. */
#include <stdint.h>
typedef int8_t   __s8;
typedef uint8_t  __u8;
typedef int16_t  __s16;
typedef uint16_t __u16;
typedef int32_t  __s32;
typedef uint32_t __u32;
typedef int64_t  __s64;
typedef uint64_t __u64;
#endif
EOF

cat > "$STUB_INCDIR/linux/ioctl.h" << 'EOF'
#ifndef _LINUX_IOCTL_H
#define _LINUX_IOCTL_H
/* Minimal linux/ioctl.h stub for weston. Provides _IOWR needed by
 * linux-sync-file-uapi.h and the _IO/_IOR/_IOW/_IOWR macros.
 * On macOS these come from <sys/ioccom.h>; only define if missing. */
#include <linux/types.h>
#include <sys/ioccom.h>

#ifndef _IOC_NONE
#define _IOC_NONE  0U
#endif
#ifndef _IOC_WRITE
#define _IOC_WRITE 1U
#endif
#ifndef _IOC_READ
#define _IOC_READ  2U
#endif

#ifndef _IOC
#define _IOC(inout, group, nr, len) \
    (((inout) << 30) | ((nr) << 0) | ((group) << 8) | ((len) << 16))
#endif

#ifndef _IO
#define _IO(type, nr)        _IOC(_IOC_NONE, (type), (nr), 0)
#endif
#ifndef _IOR
#define _IOR(type, nr, size) _IOC(_IOC_READ,  (type), (nr), sizeof(size))
#endif
#ifndef _IOW
#define _IOW(type, nr, size) _IOC(_IOC_WRITE, (type), (nr), sizeof(size))
#endif
#ifndef _IOWR
#define _IOWR(type, nr, size) _IOC(_IOC_READ | _IOC_WRITE, (type), (nr), sizeof(size))
#endif
#endif
EOF

cat > "$STUB_INCDIR/linux/dma-buf.h" << 'EOF'
#ifndef _LINUX_DMA_BUF_H
#define _LINUX_DMA_BUF_H
#include <linux/types.h>
#include <linux/ioctl.h>

#define DMA_BUF_SYNC_READ      (1 << 0)
#define DMA_BUF_SYNC_WRITE     (1 << 1)
#define DMA_BUF_SYNC_START     (0 << 2)
#define DMA_BUF_SYNC_END       (1 << 2)

struct dma_buf_sync {
	__u64 flags;
};

#define DMA_BUF_IOCTL_SYNC     _IOW('b', 0, struct dma_buf_sync)
#endif
EOF

cat > "$STUB_INCDIR/linux/udmabuf.h" << 'EOF'
#ifndef _LINUX_UDMABUF_H
#define _LINUX_UDMABUF_H
#include <linux/types.h>
#include <linux/ioctl.h>

#define UDMABUF_PATH "/dev/udmabuf"

struct udmabuf_create_item {
	__u32 memfd;
	__u32 __pad;
	__u64 offset;
	__u64 size;
};

struct udmabuf_create {
	__u32 memfd;
	__u32 flags;
	__u64 offset;
	__u64 size;
};

struct udmabuf_create_list {
	__u32 flags;
	__u32 count;
	struct udmabuf_create_item list[];
};

#define UDMABUF_FLAGS_CLOEXEC  0x01
#define UDMABUF_CREATE       _IOW('u', 0x42, struct udmabuf_create)
#define UDMABUF_CREATE_LIST  _IOW('u', 0x43, struct udmabuf_create_list)
#endif
EOF

cat > "$STUB_INCDIR/linux/vt.h" << 'EOF'
/* stubs for macos */
#include <sys/ioctl.h>
EOF

cat > "$STUB_INCDIR/linux/input.h" << 'EOF'
#ifndef _LINUX_INPUT_H
#define _LINUX_INPUT_H
/* Minimal stub: only what weston actually uses (55+ files include this).
 * Real linux/input.h is ~2500 lines; these 30 constants suffice. */
#define EV_KEY          0x01

#define KEY_RESERVED    0
#define KEY_ESC         1
#define KEY_BACKSPACE   14
#define KEY_TAB         15
#define KEY_C           46
#define KEY_D           32
#define KEY_F           33
#define KEY_H           35
#define KEY_K           37
#define KEY_M           50
#define KEY_O           24
#define KEY_R           19
#define KEY_S           31
#define KEY_V           47
#define KEY_F1          59
#define KEY_F2          60
#define KEY_F3          61
#define KEY_F4          62
#define KEY_F5          63
#define KEY_F6          64
#define KEY_F7          65
#define KEY_F8          66
#define KEY_F9          67
#define KEY_F10         68
#define KEY_F11         87
#define KEY_Q           16
#define KEY_SPACE       57
#define KEY_LEFTSHIFT   42
#define KEY_UP          103
#define KEY_DOWN        108
#define KEY_LEFT        105
#define KEY_RIGHT       106
#define KEY_BRIGHTNESSDOWN 224
#define KEY_BRIGHTNESSUP   225

#define BTN_LEFT        0x110
#define BTN_RIGHT       0x111
#define BTN_MIDDLE      0x112
#define BTN_SIDE        0x113
#define BTN_EXTRA       0x114
#define BTN_TOUCH       0x14a
#endif
EOF

# ---- macOS compat stubs for Linux-only symbols that meson detects via has_function() ----
cat > "$STUB_INCDIR/_macos_stubs.h" << 'EOF'
#ifndef _MACOS_STUBS_H
#define _MACOS_STUBS_H
/* Provide implementations for functions meson detected via has_function()
 * but that don't actually exist on macOS (because b_lundef=false fools the check). */
#include <sys/fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/ioctl.h>
#include <glibc-compat.h>

/* macOS howmany uses modulo which fails with double operands; override */
#undef howmany
#define howmany(x, y) (((x) + ((y) - 1)) / (y))
/* struct itimerspec is Linux-only; macOS has <time.h> with struct timespec */
#ifndef _STRUCT_ITIMERSPEC
#define _STRUCT_ITIMERSPEC
struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
};
#endif

/* pipe2 is Linux-only; emulate via pipe() + fcntl */
static inline int pipe2(int pipefd[2], int flags) {
    int ret = pipe(pipefd);
    if (ret == -1) return -1;
    if (flags & O_CLOEXEC) {
        fcntl(pipefd[0], F_SETFD, FD_CLOEXEC);
        fcntl(pipefd[1], F_SETFD, FD_CLOEXEC);
    }
    if (flags & O_NONBLOCK) {
        int fl0 = fcntl(pipefd[0], F_GETFL);
        int fl1 = fcntl(pipefd[1], F_GETFL);
        fcntl(pipefd[0], F_SETFL, fl0 | O_NONBLOCK);
        fcntl(pipefd[1], F_SETFL, fl1 | O_NONBLOCK);
    }
    return 0;
}

/* Linux-specific coarse monotonic clock; macOS has no equivalent */
#ifndef CLOCK_MONOTONIC_COARSE
#define CLOCK_MONOTONIC_COARSE CLOCK_MONOTONIC
#endif
#ifndef CLOCK_REALTIME_COARSE
#define CLOCK_REALTIME_COARSE CLOCK_REALTIME
#endif

#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif
#ifndef MFD_ALLOW_SEALING
#define MFD_ALLOW_SEALING 0x0002U
#endif
#ifndef F_ADD_SEALS
#define F_ADD_SEALS 1033
#endif
#ifndef F_GET_SEALS
#define F_GET_SEALS 1034
#endif
#ifndef F_SEAL_SHRINK
#define F_SEAL_SHRINK 0x0001
#endif
#ifndef F_SEAL_GROW
#define F_SEAL_GROW 0x0002
#endif
#ifndef F_SEAL_WRITE
#define F_SEAL_WRITE 0x0004
#endif

static inline int memfd_create(const char *name, unsigned int flags) {
    (void)name; (void)flags;
    errno = ENOSYS;
    return -1;
}
static inline int posix_fallocate(int fd, off_t offset, off_t len) {
    (void)fd; (void)offset; (void)len;
    /* macOS: fstore_t + fcntl(F_PREALLOCATE) or just ftruncate */
    errno = ENOSYS;
    return -1;
}
#endif
EOF
# Add forced include of the stubs header
FORCE_INCLUDE="-include ${STUB_INCDIR}/_macos_stubs.h"

# ---- libevdev stub ----
cat > "$STUB_INCDIR/libevdev/libevdev.h" << 'EOF'
int libevdev_event_code_from_name(unsigned int type, const char *name);
EOF

cat > "$DEPS_DIR/libevdev-stub.c" << 'EOF'
int libevdev_event_code_from_name(const char *name, int len) { return -1; }
EOF
cc -dynamiclib -o "$STUB_LIBDIR/libevdev.dylib" "$DEPS_DIR/libevdev-stub.c" -install_name "$STUB_LIBDIR/libevdev.dylib"

# ---- libseat stub ----
cat > "$STUB_INCDIR/libseat.h" << 'EOF'
#include <stddef.h>
#include <stdarg.h>
struct libseat { int fd; int vt; };
struct libseat_device { int dummy; };
enum libseat_log_level { LIBSEAT_LOG_LEVEL_NONE=0, LIBSEAT_LOG_LEVEL_INFO=1,
    LIBSEAT_LOG_LEVEL_DEBUG=2 };
struct libseat_seat_listener {
    void (*enable_seat)(struct libseat *, void *);
    void (*disable_seat)(struct libseat *, void *);
};
struct libseat *libseat_open_seat(const struct libseat_seat_listener *, void *);
void libseat_close_seat(struct libseat *);
int libseat_get_fd(struct libseat *);
int libseat_dispatch(struct libseat *, int);
int libseat_get_vt(struct libseat *);
int libseat_open_device(struct libseat *, const char *, int *);
int libseat_close_device(struct libseat *, int);
int libseat_disable_seat(struct libseat *);
int libseat_switch_session(struct libseat *, int);
typedef void (*libseat_log_handler)(enum libseat_log_level level, const char *fmt, va_list ap);
void libseat_set_log_handler(libseat_log_handler handler);
void libseat_set_log_level(enum libseat_log_level);
EOF

cat > "$DEPS_DIR/libseat-stub.c" << 'EOF'
#include <stddef.h>
#include "libseat.h"
struct libseat *libseat_open_seat(const struct libseat_seat_listener *l, void *d) { return NULL; }
void libseat_close_seat(struct libseat *s) {}
int libseat_get_fd(struct libseat *s) { return -1; }
int libseat_dispatch(struct libseat *s, int t) { return 0; }
int libseat_get_vt(struct libseat *s) { return -1; }
int libseat_open_device(struct libseat *s, const char *p, int *fd) { return -1; }
int libseat_close_device(struct libseat *s, int id) { return 0; }
int libseat_disable_seat(struct libseat *s) { return 0; }
int libseat_switch_session(struct libseat *s, int n) { return 0; }
void libseat_set_log_handler(libseat_log_handler handler) { (void)handler; }
void libseat_set_log_level(enum libseat_log_level l) {}
EOF
cc -I"$STUB_INCDIR" -dynamiclib -o "$STUB_LIBDIR/libseat.dylib" "$DEPS_DIR/libseat-stub.c" \
    -install_name "$STUB_LIBDIR/libseat.dylib"

echo "Stub libraries built in $STUB_LIBDIR"

# ============================================================
# 3. Create pkg-config files
# ============================================================
echo "=== Creating pkg-config files ==="

cat > "$STUB_PCDIR/libdrm.pc" << EOF
prefix=${SCRIPT_DIR}
exec_prefix=\${prefix}
libdir=${SHIM_BUILD}
includedir=${SCRIPT_DIR}/shims/include
Name: libdrm
Description: DRM via wayland-mac shim
Version: 2.4.108
Libs: -L\${libdir} -lwayland-mac
Cflags: -I\${includedir} -I${STUB_INCDIR}
EOF

cat > "$STUB_PCDIR/gbm.pc" << EOF
prefix=${SCRIPT_DIR}
exec_prefix=\${prefix}
libdir=${SHIM_BUILD}
includedir=${SCRIPT_DIR}/shims/include
Name: gbm
Description: GBM via wayland-mac shim
Version: 22.0.0
Libs: -L\${libdir} -lwayland-mac
Cflags: -I\${includedir}
Requires: libdrm
EOF

for pkg in wayland-server wayland-client wayland-cursor wayland-egl; do
    case "$pkg" in wayland-server) desc="Server" ;; wayland-client) desc="Client" ;; wayland-cursor) desc="Cursor" ;; wayland-egl) desc="EGL" ;; esac
    cat > "$STUB_PCDIR/$pkg.pc" << EOF
prefix=/opt/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: Wayland $desc
Description: Wayland $desc library
Version: 1.22.0
Libs: -L\${libdir} -l$pkg
Cflags: -I\${includedir}
EOF
done

cat > "$STUB_PCDIR/wayland-scanner.pc" << EOF
prefix=/opt/local
exec_prefix=\${prefix}
bindir=\${prefix}/bin
wayland_scanner=\${bindir}/wayland-scanner
Name: Wayland Scanner
Description: Wayland scanner
Version: 1.23.0
Cflags: -I\${prefix}/include
EOF

# libudev .pc — symbols in wayland-mac.dylib via -force_load
cat > "$STUB_PCDIR/libudev.pc" << EOF
prefix=${SCRIPT_DIR}
exec_prefix=\${prefix}
libdir=${SHIM_BUILD}
includedir=${SCRIPT_DIR}/shims/udev/include
Name: libudev
Description: udev via wayland-mac shim
Version: 255
Libs: -L\${libdir} -lwayland-mac
Cflags: -I\${includedir}
EOF

# libinput .pc — symbols in wayland-mac.dylib via -force_load
# Requires libudev for its headers (libinput.h includes <libudev.h>)
cat > "$STUB_PCDIR/libinput.pc" << EOF
prefix=${SCRIPT_DIR}
exec_prefix=\${prefix}
libdir=${SHIM_BUILD}
includedir=${SCRIPT_DIR}/shims/libinput/include
Name: libinput
Description: libinput via wayland-mac shim
Version: 1.2.0
Libs: -L\${libdir} -lwayland-mac
Cflags: -I\${includedir}
Requires: libudev
EOF

# Generic loop for remaining stubs
for pkg in libevdev:evdev libseat:seat; do
    name="${pkg%%:*}"
    link="${pkg##*:}"
    cat > "$STUB_PCDIR/$name.pc" << EOF
prefix=${STUB_LIBDIR}/..
exec_prefix=\${prefix}
libdir=${STUB_LIBDIR}
includedir=${STUB_INCDIR}
Name: $name
Description: $name stub
Version: 2.0.0
Libs: -L\${libdir} -l$link
Cflags: -I\${includedir}
EOF
done

HW_DATADIR="$STUB_PCDIR/../share/hwdata"
mkdir -p "$HW_DATADIR"
touch "$HW_DATADIR/pnp.ids"
cat > "$STUB_PCDIR/hwdata.pc" << EOF
prefix=${STUB_PCDIR}/..
datarootdir=\${prefix}/share
pkgdatadir=${HW_DATADIR}
Name: hwdata
Description: hwdata stub
Version: 0.390
EOF

echo "pkg-config files created in $STUB_PCDIR"

# ============================================================
# 4. Fetch wayland-protocols (needed by weston for protocol XMLs)
# ============================================================
WP_DIR="$DEPS_DIR/wayland-protocols"
if [ ! -d "$WP_DIR/.git" ]; then
    echo "=== Fetching wayland-protocols ==="
    git clone --depth 1 --branch 1.49 \
        https://gitlab.freedesktop.org/wayland/wayland-protocols.git \
        "$WP_DIR"
else
    echo "=== wayland-protocols already fetched ==="
fi

cat > "$STUB_PCDIR/wayland-protocols.pc" << EOF
prefix=${WP_DIR}
datarootdir=\${prefix}
pkgdatadir=\${datarootdir}
Name: Wayland Protocols
Description: Wayland protocol files
Version: 1.49
EOF

# ============================================================
# 5. Configure and build weston
# ============================================================
echo "=== Creating compiler wrapper (strips -Wl,--version-script for macOS ld) ==="
WRAPPER_DIR="$BUILD_DIR/wrapper"
mkdir -p "$WRAPPER_DIR"
# Wrap clang to strip -Wl,--version-script (macOS ld64 doesn't support it)
cat > "$WRAPPER_DIR/cc" << 'WRAPEOF'
#!/bin/bash
args=()
skip=0
for arg in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    # Strip -Wl,--version-script,/path or -Wl,--version-script,/path
    if [[ "$arg" == *--version-script* ]]; then
        if [[ "$arg" == -Wl,--version-script,* ]]; then continue; fi
        if [[ "$arg" == -Wl,--version-script ]]; then skip=1; continue; fi
    fi
    args+=("$arg")
done
exec /usr/bin/clang "${args[@]}"
WRAPEOF
chmod +x "$WRAPPER_DIR/cc"
ln -sf "$WRAPPER_DIR/cc" "$WRAPPER_DIR/clang"
# Also wrap c++ for the edid-decode subproject
cat > "$WRAPPER_DIR/c++" << 'WRAPEOF'
#!/bin/bash
args=()
skip=0
for arg in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    if [[ "$arg" == *--version-script* ]]; then
        if [[ "$arg" == -Wl,--version-script,* ]]; then continue; fi
        if [[ "$arg" == -Wl,--version-script ]]; then skip=1; continue; fi
    fi
    args+=("$arg")
done
exec /usr/bin/clang++ "${args[@]}"
WRAPEOF
chmod +x "$WRAPPER_DIR/c++"
ln -sf "$WRAPPER_DIR/c++" "$WRAPPER_DIR/clang++"
export PATH="$WRAPPER_DIR:$PATH"

echo "=== Configuring weston ==="
export PKG_CONFIG_PATH="$STUB_PCDIR:/opt/local/lib/pkgconfig"
export CFLAGS="-I$STUB_INCDIR -DHAVE_MKOSTEMP=1 -DHAVE_STRCHRNUL=1 -DHAVE_INITGROUPS=1"
export LDFLAGS="-Wl,-undefined,dynamic_lookup"

meson setup "$BUILD_DIR" "$WESTON_DIR" --reconfigure \
    -Dbackend-drm=true \
    -Dbackend-headless=true \
    -Dbackend-wayland=false \
    -Dbackend-x11=false \
    -Dbackend-rdp=false \
    -Dbackend-vnc=false \
    -Dbackend-pipewire=false \
    -Dpipewire=false \
    -Dremoting=false \
    -Dbackend-default=drm \
    -Drenderer-gl=true \
    -Drenderer-vulkan=false \
    -Dshell-desktop=true \
    -Dshell-ivi=false \
    -Dshell-kiosk=true \
    -Dshell-lua=false \
    -Dxwayland=false \
    -Ddemo-clients=true \
    -Dsimple-clients=shm \
    -Dtests=false \
    -Dcolor-management-lcms=false \
    -Dimage-jpeg=false \
    -Dimage-webp=false \
    -Dresize-pool=false \
    -Dsystemd=false \
    -Db_lundef=false \
    -Dc_args="$CFLAGS -I${SCRIPT_DIR}/shims/gbm/include -I${SCRIPT_DIR}/shims/glibc/include -I${SCRIPT_DIR}/build/shims/epoll/install-include -Dprogram_invocation_short_name=getprogname() $FORCE_INCLUDE" \
    -Dc_link_args="$LDFLAGS" \
    2>&1 | tee "$BUILD_DIR/meson-setup.log"

echo "=== Building weston ==="
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
meson compile -C "$BUILD_DIR" -j "$JOBS" 2>&1 | tee "$BUILD_DIR/meson-build.log"

echo ""
echo "=== Done ==="
echo "Binaries in: $BUILD_DIR"
echo "Run: sudo build-weston/frontend/weston"
