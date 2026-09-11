#!/usr/bin/env bash
# Build Wawona Mode B TrollStore tipa: IOMFB fullscreen graphics via JIT W^X.
#   - W^X paint_frame: every JIT exec full-redraws IOMFB (plasma+orbs); host HUD only
#   - CADisplayLink: host orb physics → JIT paint → persistent IOMFB swap
#   - UIKit is hatch/fallback only; primary canvas is IOMFB
# Never App Store / TestFlight. Never IOWatchdog.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/.agent-device/test-artifacts/dmabuf/vphone-jb}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BUNDLE_ID="com.aspauldingcode.wawona.modeb.fbjit"
APP_NAME="WawonaFbJit"
VERSION="${VERSION:-26.9.2}"
STATE_FILE="${STATE_FILE:-$OUT/.modeb-fbjit-build}"
BUILD="${BUILD:-}"
if [[ -z "$BUILD" ]]; then
  prev=0
  if [[ -f "$STATE_FILE" ]]; then
    prev="$(tr -d '[:space:]' <"$STATE_FILE" || true)"
  fi
  if [[ -f "$OUT/WawonaFbJit-${VERSION}-iOS-arm64.tipa" ]]; then
    tipa_build="$(unzip -p "$OUT/WawonaFbJit-${VERSION}-iOS-arm64.tipa" "Payload/${APP_NAME}.app/Info.plist" 2>/dev/null \
      | plutil -extract CFBundleVersion raw - 2>/dev/null || true)"
    if [[ "$tipa_build" =~ ^[0-9]+$ ]] && (( tipa_build > prev )); then
      prev="$tipa_build"
    fi
  fi
  BUILD=$((prev + 1))
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
LDID="${LDID:-}"
if [[ -z "$LDID" ]]; then
  if command -v ldid >/dev/null 2>&1; then LDID="$(command -v ldid)"
  elif [[ -x "$HOME/.vphone/src/vphone-cli/.tools/bin/ldid" ]]; then
    LDID="$HOME/.vphone/src/vphone-cli/.tools/bin/ldid"
  else
    echo "ERROR: ldid not found (need ldid-procursus)" >&2
    exit 1
  fi
fi

mkdir -p "$OUT" "$STAGE/src" "$STAGE/include/IOMobileFramebuffer" "$STAGE/Payload/${APP_NAME}.app"
echo "Building FbJit tipa VERSION=$VERSION build=$BUILD"

cat >"$STAGE/include/IOMobileFramebuffer/IOMobileframebuffer.h" <<'HDR'
#ifndef WWN_IOMOBILEFRAMEBUFFER_H
#define WWN_IOMOBILEFRAMEBUFFER_H
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOSurface/IOSurfaceRef.h>
typedef int IOMobileFramebufferReturn;
typedef struct __IOMobileFramebuffer *IOMobileFramebufferRef;
typedef CGSize IOMobileFramebufferDisplaySize;
#ifdef __cplusplus
extern "C" {
#endif
IOMobileFramebufferReturn IOMobileFramebufferGetMainDisplay(IOMobileFramebufferRef *pointer);
IOMobileFramebufferReturn IOMobileFramebufferGetSecondaryDisplay(IOMobileFramebufferRef *pointer);
IOMobileFramebufferReturn IOMobileFramebufferGetDisplaySize(IOMobileFramebufferRef pointer, IOMobileFramebufferDisplaySize *size);
IOMobileFramebufferReturn IOMobileFramebufferSwapBegin(IOMobileFramebufferRef pointer, int *token);
IOMobileFramebufferReturn IOMobileFramebufferSwapEnd(IOMobileFramebufferRef pointer);
IOMobileFramebufferReturn IOMobileFramebufferSwapSetLayer(IOMobileFramebufferRef pointer, int layerid, IOSurfaceRef buffer, CGRect bounds, CGRect frame, int flags);
#ifdef __cplusplus
}
#endif
#endif
HDR

cat >"$STAGE/src/main.m" <<'OBJC'
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurfaceRef.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <sys/errno.h>
#import <sys/wait.h>
#import <spawn.h>
#import <unistd.h>
#import <string.h>
#import <dlfcn.h>
#import <signal.h>
#import <setjmp.h>
#import <libkern/OSCacheControl.h>
#import <os/log.h>
#include "IOMobileFramebuffer/IOMobileframebuffer.h"

#define PT_TRACE_ME 0
#define PT_DETACH 11
int ptrace(int request, pid_t pid, caddr_t addr, int data);
#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000u
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
extern char **environ;

static BOOL csDebugged(void) {
  uint32_t flags = 0;
  if (csops(0, CS_OPS_STATUS, &flags, sizeof(flags)) != 0) return NO;
  return (flags & CS_DEBUGGED) != 0;
}

static void trySelfEnableJit(char *argv0) {
  if (csDebugged()) return;
  pid_t child = 0;
  char *childArgv[] = { argv0, "--wwn-jit-child", NULL };
  int rc = posix_spawnp(&child, argv0, NULL, NULL, childArgv, environ);
  if (rc != 0) return;
  int status = 0;
  waitpid(child, &status, WUNTRACED);
  ptrace(PT_DETACH, child, NULL, 0);
  kill(child, SIGTERM);
  waitpid(child, NULL, 0);
}

#define PX_WHITE 0xffffffffu
#define PX_BLACK 0xff0a0e14u
#define PX_GREEN 0xff3ddc84u
#define PX_RED   0xffff5555u
#define PX_CYAN  0xff66ccffu
#define PX_YELL  0xffffcc33u
#define ORB_COUNT 3
#define ORB_STRIDE 3 /* x,y,r per orb */

typedef void (*JitPaintFrame)(uint32_t *base, int width, int height, int bpr,
                              uint32_t t, const int32_t *orbs);

#pragma mark - W^X allocator (never simultaneous W+X)

static sigjmp_buf gJitJmp;
static volatile sig_atomic_t gJitFaulted;
static void jit_fault_handler(int signo) {
  (void)signo;
  gJitFaulted = 1;
  siglongjmp(gJitJmp, 1);
}

static void jitWriteProtect(BOOL execOnly) {
  typedef void (*JitWP)(int);
  JitWP wp = (JitWP)dlsym(RTLD_DEFAULT, "pthread_jit_write_protect_np");
  if (wp) wp(execOnly ? 1 : 0);
}

static void *jitAllocPage(size_t len, const char **kindOut) {
  /* Prefer vm_allocate+RX on TXM guests; MAP_JIT second. */
  vm_address_t addr = 0;
  if (vm_allocate(mach_task_self(), &addr, len, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
    *kindOut = "vm_allocate";
    return (void *)(uintptr_t)addr;
  }
  void *p = mmap(NULL, len, PROT_READ | PROT_WRITE,
                 MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
  if (p != MAP_FAILED) {
    *kindOut = "MAP_JIT";
    return p;
  }
  *kindOut = NULL;
  return MAP_FAILED;
}

static BOOL jitMakeExecutable(void *p, size_t len, const char *kind) {
  if (strcmp(kind, "MAP_JIT") == 0) {
    jitWriteProtect(YES);
    return YES;
  }
  return vm_protect(mach_task_self(), (vm_address_t)(uintptr_t)p, len, FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS;
}

static BOOL jitMakeWritable(void *p, size_t len, const char *kind) {
  if (strcmp(kind, "MAP_JIT") == 0) {
    jitWriteProtect(NO);
    return YES;
  }
  return vm_protect(mach_task_self(), (vm_address_t)(uintptr_t)p, len, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE) == KERN_SUCCESS;
}

#pragma mark - Plasma + orbs (llvm-assembled ARM64 blob in W^X)

/* Verified with llvm-mc / host vm_allocate+RX smoke. Copied into JIT page. */
static const uint32_t kPaintCode[] = {
0xA9BA7BFDu,
0xA90153F3u,
0xA9025BF5u,
0xA90363F7u,
0xA9046BF9u,
0xA90573FBu,
0x910003FDu,
0xAA0003F3u,
0x2A0103F4u,
0x2A0203F5u,
0x2A0303F6u,
0x2A0403F7u,
0xAA0503F8u,
0x531D72F7u,
0x52800019u,
0x9BB67F3Au,
0x8B1A027Au,
0x5280001Bu,
0x0B170368u,
0x52800069u,
0x1B097D08u,
0x0B170329u,
0x528000AAu,
0x1B0A7D29u,
0x0B19036Au,
0x531E754Au,
0x4A09010Bu,
0x4A0A016Bu,
0x4A17016Bu,
0x12001D6Cu,
0x53037D6Du,
0x12001DADu,
0x53067D6Eu,
0x12001DCEu,
0x53185DADu,
0x53103DCEu,
0x2A0D018Cu,
0x2A0E018Cu,
0x52800008u,
0x72BFE008u,
0x2A08018Cu,
0x5280001Cu,
0x52800188u,
0x1B087F88u,
0x8B284308u,
0xB9400109u,
0xB940050Au,
0xB940090Bu,
0x4B09036Du,
0x4B0A032Eu,
0x1B0D7DADu,
0x1B0E7DCEu,
0x0B0E01ADu,
0x1B0B7D6Bu,
0x6B0B01BFu,
0x5400008Au,
0x529C1FEDu,
0x72A0180Du,
0x2A0D018Cu,
0x1100079Cu,
0x71000F9Fu,
0x54FFFDA3u,
0xB83B5B4Cu,
0x1100077Bu,
0x6B14037Fu,
0x54FFFA23u,
0x11000739u,
0x6B15033Fu,
0x54FFF963u,
0xA94573FBu,
0xA9446BF9u,
0xA94363F7u,
0xA9425BF5u,
0xA94153F3u,
0xA8C67BFDu,
0xD65F03C0u
};

typedef struct {
  void *page;
  size_t len;
  JitPaintFrame paint;
  BOOL live;
  const char *allocKind;
  uint64_t ticks;
} JitGfx;

static JitGfx gJit;

static BOOL jitInstallPaint(NSString **detail) {
  if (gJit.live) {
    *detail = [NSString stringWithFormat:@"JIT LIVE via %s (reuse)", gJit.allocKind ?: "?"];
    return YES;
  }
  size_t bodyLen = sizeof(kPaintCode);
  size_t len = (bodyLen + 128 + 0x3fff) & ~((size_t)0x3fff);
  if (len < 16384) len = 16384;
  const char *kind = NULL;
  void *p = jitAllocPage(len, &kind);
  if (p == MAP_FAILED || !kind) {
    *detail = [NSString stringWithFormat:@"JIT alloc failed errno=%d", errno];
    return NO;
  }
  if (!jitMakeWritable(p, len, kind)) {
    *detail = @"JIT writable failed";
    return NO;
  }
  memset(p, 0, len);
  uint32_t *probe = (uint32_t *)p;
  probe[0] = 0x52800540u;
  probe[1] = 0xD65F03C0u;
  size_t paintOff = 64;
  memcpy((uint8_t *)p + paintOff, kPaintCode, bodyLen);
  if (!jitMakeExecutable(p, len, kind)) {
    *detail = @"JIT exec failed";
    return NO;
  }
  sys_icache_invalidate(p, len);

  gJitFaulted = 0;
  struct sigaction sa = {0}, oldBus = {0}, oldSeg = {0};
  sa.sa_handler = jit_fault_handler;
  sigemptyset(&sa.sa_mask);
  struct sigaction oldIll = {0};
  sigaction(SIGBUS, &sa, &oldBus);
  sigaction(SIGSEGV, &sa, &oldSeg);
  sigaction(SIGILL, &sa, &oldIll);
  int probeVal = -1;
  if (sigsetjmp(gJitJmp, 1) == 0) {
    probeVal = ((int (*)(void))p)();
  }
  if (gJitFaulted || probeVal != 0x2a) {
    sigaction(SIGBUS, &oldBus, NULL);
    sigaction(SIGSEGV, &oldSeg, NULL);
    sigaction(SIGILL, &oldIll, NULL);
    *detail = [NSString stringWithFormat:@"probe fail via %s p=%d f=%d", kind, probeVal, (int)gJitFaulted];
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    return NO;
  }

  /* Probe OK. Install paint fn; first real redraw happens on IOMFB via fbJitRedraw. */
  sigaction(SIGBUS, &oldBus, NULL);
  sigaction(SIGSEGV, &oldSeg, NULL);
  sigaction(SIGILL, &oldIll, NULL);

  gJit.page = p;
  gJit.len = len;
  gJit.paint = (JitPaintFrame)((uint8_t *)p + paintOff);
  gJit.live = YES;
  gJit.allocKind = kind;
  gJit.ticks = 0;
  *detail = [NSString stringWithFormat:@"JIT LIVE via %s (%zuB ARM64)", kind, bodyLen];
  return YES;
}

#pragma mark - Tiny glyphs for HUD

static const uint8_t kGlyph[50][7] = {
  /*0*/ {0x0E,0x11,0x13,0x15,0x19,0x11,0x0E},
  /*1*/ {0x04,0x0C,0x04,0x04,0x04,0x04,0x0E},
  /*2*/ {0x0E,0x11,0x01,0x02,0x04,0x08,0x1F},
  /*3*/ {0x0E,0x11,0x01,0x06,0x01,0x11,0x0E},
  /*4*/ {0x02,0x06,0x0A,0x12,0x1F,0x02,0x02},
  /*5*/ {0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E},
  /*6*/ {0x06,0x08,0x10,0x1E,0x11,0x11,0x0E},
  /*7*/ {0x1F,0x01,0x02,0x04,0x08,0x08,0x08},
  /*8*/ {0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E},
  /*9*/ {0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C},
  /*A*/ {0x0E,0x11,0x11,0x1F,0x11,0x11,0x11},
  /*B*/ {0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E},
  /*C*/ {0x0E,0x11,0x10,0x10,0x10,0x11,0x0E},
  /*D*/ {0x1E,0x11,0x11,0x11,0x11,0x11,0x1E},
  /*E*/ {0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F},
  /*F*/ {0x1F,0x10,0x10,0x1E,0x10,0x10,0x10},
  /*G*/ {0x0E,0x11,0x10,0x17,0x11,0x11,0x0F},
  /*H*/ {0x11,0x11,0x11,0x1F,0x11,0x11,0x11},
  /*I*/ {0x0E,0x04,0x04,0x04,0x04,0x04,0x0E},
  /*J*/ {0x01,0x01,0x01,0x01,0x11,0x11,0x0E},
  /*K*/ {0x11,0x12,0x14,0x18,0x14,0x12,0x11},
  /*L*/ {0x10,0x10,0x10,0x10,0x10,0x10,0x1F},
  /*M*/ {0x11,0x1B,0x15,0x15,0x11,0x11,0x11},
  /*N*/ {0x11,0x19,0x15,0x13,0x11,0x11,0x11},
  /*O*/ {0x0E,0x11,0x11,0x11,0x11,0x11,0x0E},
  /*P*/ {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10},
  /*Q*/ {0x0E,0x11,0x11,0x11,0x15,0x12,0x0D},
  /*R*/ {0x1E,0x11,0x11,0x1E,0x14,0x12,0x11},
  /*S*/ {0x0E,0x11,0x10,0x0E,0x01,0x11,0x0E},
  /*T*/ {0x1F,0x04,0x04,0x04,0x04,0x04,0x04},
  /*U*/ {0x11,0x11,0x11,0x11,0x11,0x11,0x0E},
  /*V*/ {0x11,0x11,0x11,0x11,0x11,0x0A,0x04},
  /*W*/ {0x11,0x11,0x11,0x15,0x15,0x1B,0x11},
  /*X*/ {0x11,0x11,0x0A,0x04,0x0A,0x11,0x11},
  /*Y*/ {0x11,0x11,0x0A,0x04,0x04,0x04,0x04},
  /*Z*/ {0x1F,0x01,0x02,0x04,0x08,0x10,0x1F},
  /*.*/ {0x00,0x00,0x00,0x00,0x00,0x0C,0x0C},
  /*:*/ {0x00,0x0C,0x0C,0x00,0x0C,0x0C,0x00},
  /*/ */ {0x01,0x02,0x04,0x04,0x08,0x10,0x10},
  /*- */ {0x00,0x00,0x00,0x1F,0x00,0x00,0x00},
  /*_ */ {0x00,0x00,0x00,0x00,0x00,0x00,0x1F},
  /*= */ {0x00,0x00,0x1F,0x00,0x1F,0x00,0x00},
  /*( */ {0x04,0x08,0x10,0x10,0x10,0x08,0x04},
  /*) */ {0x04,0x02,0x01,0x01,0x01,0x02,0x04},
  /*+ */ {0x00,0x04,0x04,0x1F,0x04,0x04,0x00},
  /*star*/{0x00,0x0A,0x04,0x1F,0x04,0x0A,0x00},
  /*? */ {0x0E,0x11,0x01,0x02,0x04,0x00,0x04},
  /*spc*/{0x00,0x00,0x00,0x00,0x00,0x00,0x00},
  /*, */ {0x00,0x00,0x00,0x00,0x0C,0x04,0x08},
  /*! */ {0x04,0x04,0x04,0x04,0x04,0x00,0x04},
};

static int glyphIndex(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'Z') return 10 + (c - 'A');
  if (c >= 'a' && c <= 'z') return 10 + (c - 'a');
  switch (c) {
    case '.': return 36; case ':': return 37; case '/': return 38;
    case '-': return 39; case '_': return 40; case '=': return 41;
    case '(': return 42; case ')': return 43; case '+': return 44;
    case '*': return 45; case '?': return 46; case ' ': return 47;
    case ',': return 48; case '!': return 49; default: return 47;
  }
}

static void fbPutChar(uint32_t *base, int w, int h, int bpr, int x0, int y0, char c, uint32_t fg, int scale) {
  int gi = glyphIndex(c);
  for (int row = 0; row < 7; row++) {
    uint8_t bits = kGlyph[gi][row];
    for (int col = 0; col < 5; col++) {
      if (!(bits & (0x10 >> col))) continue;
      for (int sy = 0; sy < scale; sy++) {
        for (int sx = 0; sx < scale; sx++) {
          int x = x0 + col * scale + sx;
          int y = y0 + row * scale + sy;
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          uint32_t *px = (uint32_t *)((uint8_t *)base + y * bpr);
          px[x] = fg;
        }
      }
    }
  }
}

static void fbPutString(uint32_t *base, int w, int h, int bpr, int x0, int y0, const char *s, uint32_t fg, int scale) {
  int x = x0;
  for (const char *p = s; *p; p++) {
    fbPutChar(base, w, h, bpr, x, y0, *p, fg, scale);
    x += 6 * scale;
  }
}

#pragma mark - IOMFB session

typedef IOMobileFramebufferReturn (*FnGetMain)(IOMobileFramebufferRef *);
typedef IOMobileFramebufferReturn (*FnGetSec)(IOMobileFramebufferRef *);
typedef IOMobileFramebufferReturn (*FnGetSize)(IOMobileFramebufferRef, IOMobileFramebufferDisplaySize *);
typedef IOMobileFramebufferReturn (*FnSwapBegin)(IOMobileFramebufferRef, int *);
typedef IOMobileFramebufferReturn (*FnSwapEnd)(IOMobileFramebufferRef);
typedef IOMobileFramebufferReturn (*FnSwapSet)(IOMobileFramebufferRef, int, IOSurfaceRef, CGRect, CGRect, int);

typedef struct {
  IOMobileFramebufferRef display;
  IOSurfaceRef surface;
  int width, height, bpr;
  FnSwapBegin swapBegin;
  FnSwapEnd swapEnd;
  FnSwapSet swapSet;
  BOOL ready;
  const char *which;
} FbSession;

static FbSession gFb;

static NSString *fbOpen(void) {
  void *h = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY);
  if (!h) return [NSString stringWithFormat:@"IOMFB dlopen: %s", dlerror() ?: "?"];
  FnGetMain getMain = (FnGetMain)dlsym(h, "IOMobileFramebufferGetMainDisplay");
  FnGetSec getSec = (FnGetSec)dlsym(h, "IOMobileFramebufferGetSecondaryDisplay");
  FnGetSize getSize = (FnGetSize)dlsym(h, "IOMobileFramebufferGetDisplaySize");
  gFb.swapBegin = (FnSwapBegin)dlsym(h, "IOMobileFramebufferSwapBegin");
  gFb.swapEnd = (FnSwapEnd)dlsym(h, "IOMobileFramebufferSwapEnd");
  gFb.swapSet = (FnSwapSet)dlsym(h, "IOMobileFramebufferSwapSetLayer");
  if (!getMain || !getSize || !gFb.swapBegin || !gFb.swapEnd || !gFb.swapSet)
    return @"IOMFB symbols missing";

  IOMobileFramebufferRef display = NULL;
  IOMobileFramebufferReturn ret = getMain(&display);
  gFb.which = "main";
  if (ret || !display) {
    if (getSec) {
      ret = getSec(&display);
      gFb.which = "secondary";
    }
  }
  if (ret || !display) return [NSString stringWithFormat:@"GetDisplay ret=%d", (int)ret];

  IOMobileFramebufferDisplaySize size = {0};
  ret = getSize(display, &size);
  if (ret) return [NSString stringWithFormat:@"GetSize ret=%d", (int)ret];
  int width = (int)size.width, height = (int)size.height;
  if (width <= 0 || height <= 0) return @"bad FB size";

  int bpp = 4, pixelFormat = 0x42475241;
  CFMutableDictionaryRef props = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(props, CFSTR("IOSurfaceIsGlobal"), kCFBooleanFalse);
  CFNumberRef nW = CFNumberCreate(NULL, kCFNumberIntType, &width);
  CFNumberRef nH = CFNumberCreate(NULL, kCFNumberIntType, &height);
  CFNumberRef nFmt = CFNumberCreate(NULL, kCFNumberIntType, &pixelFormat);
  CFNumberRef nBpe = CFNumberCreate(NULL, kCFNumberIntType, &bpp);
  CFDictionarySetValue(props, CFSTR("IOSurfaceWidth"), nW);
  CFDictionarySetValue(props, CFSTR("IOSurfaceHeight"), nH);
  CFDictionarySetValue(props, CFSTR("IOSurfacePixelFormat"), nFmt);
  CFDictionarySetValue(props, CFSTR("IOSurfaceBytesPerElement"), nBpe);
  IOSurfaceRef surface = IOSurfaceCreate(props);
  CFRelease(nW); CFRelease(nH); CFRelease(nFmt); CFRelease(nBpe); CFRelease(props);
  if (!surface) return @"IOSurfaceCreate failed";

  gFb.display = display;
  gFb.surface = surface;
  gFb.width = width;
  gFb.height = height;
  gFb.bpr = (int)IOSurfaceGetBytesPerRow(surface);
  gFb.ready = YES;
  return [NSString stringWithFormat:@"IOMFB %s %dx%d ready", gFb.which, width, height];
}

/* Every JIT paint_frame exec must redraw the live IOMFB surface and swap. */
static BOOL fbJitRedraw(const int32_t *orbs, NSString *hud) {
  if (!gFb.ready || !gJit.live || !gJit.paint) return NO;

  gJitFaulted = 0;
  struct sigaction sa = {0}, oldBus = {0}, oldSeg = {0}, oldIll = {0};
  sa.sa_handler = jit_fault_handler;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGBUS, &sa, &oldBus);
  sigaction(SIGSEGV, &sa, &oldSeg);
  sigaction(SIGILL, &sa, &oldIll);

  IOSurfaceLock(gFb.surface, 0, NULL);
  void *base = IOSurfaceGetBaseAddress(gFb.surface);
  if (sigsetjmp(gJitJmp, 1) == 0) {
    /* Contract: one JIT exec = one full framebuffer paint. */
    gJit.paint((uint32_t *)base, gFb.width, gFb.height, gFb.bpr,
               (uint32_t)gJit.ticks, orbs);
  }
  BOOL faulted = gJitFaulted;
  if (!faulted) {
    int scale = gFb.width >= 800 ? 4 : 3;
    const char *hello = "Hello, Wawona World!";
    int helloLen = 19; /* strlen */
    int helloW = helloLen * 6 * scale;
    int hx = (gFb.width - helloW) / 2;
    if (hx < 16) hx = 16;
    int hy = gFb.height / 5;
    /* dark plate behind title */
    int pad = 10 * scale;
    for (int yy = hy - pad; yy < hy + 8 * scale + pad; yy++) {
      if (yy < 0 || yy >= gFb.height) continue;
      uint32_t *row = (uint32_t *)((uint8_t *)base + yy * gFb.bpr);
      for (int x = hx - pad; x < hx + helloW + pad && x < gFb.width; x++) {
        if (x < 0) continue;
        row[x] = (row[x] >> 2) & 0x3f3f3f3f;
      }
    }
    fbPutString((uint32_t *)base, gFb.width, gFb.height, gFb.bpr, hx, hy,
                hello, PX_YELL, scale);
    if (hud.length) {
      int hscale = gFb.width >= 800 ? 3 : 2;
      int y = gFb.height - 16 * hscale - 24;
      if (y < 0) y = 0;
      for (int yy = y - 8; yy < gFb.height; yy++) {
        if (yy < 0) continue;
        uint32_t *row = (uint32_t *)((uint8_t *)base + yy * gFb.bpr);
        for (int x = 0; x < gFb.width; x++) row[x] = (row[x] >> 2) & 0x3f3f3f3f;
      }
      fbPutString((uint32_t *)base, gFb.width, gFb.height, gFb.bpr, 24, y,
                  hud.UTF8String ?: "", PX_GREEN, hscale);
    }
  }
  IOSurfaceUnlock(gFb.surface, 0, NULL);
  sigaction(SIGBUS, &oldBus, NULL);
  sigaction(SIGSEGV, &oldSeg, NULL);
  sigaction(SIGILL, &oldIll, NULL);
  if (faulted) return NO;

  int token = 0;
  if (gFb.swapBegin(gFb.display, &token)) return NO;
  CGRect full = CGRectMake(0, 0, gFb.width, gFb.height);
  IOMobileFramebufferReturn setRet = gFb.swapSet(gFb.display, 0, gFb.surface, full, full, 0);
  IOMobileFramebufferReturn endRet = gFb.swapEnd(gFb.display);
  return setRet == 0 && endRet == 0;
}

#pragma mark - App

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UILabel *label;
@property (strong, nonatomic) CADisplayLink *displayLink;
@end

@implementation AppDelegate {
  BOOL _requestedMagnifierJit;
  BOOL _started;
  int32_t _orbs[9];
  int32_t _vel[6]; /* vx0,vy0, vx1,vy1, vx2,vy2 */
}

- (void)requestMagnifierJitIfNeeded {
  if (_requestedMagnifierJit) return;
  _requestedMagnifierJit = YES;
  NSURL *url = [NSURL URLWithString:
      @"apple-magnifier://enable-jit?bundle-id=com.aspauldingcode.wawona.modeb.fbjit"];
  if (!url) return;
  if (@available(iOS 10.0, *)) {
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
  }
}

- (void)setupOrbs {
  int w = gFb.width > 0 ? gFb.width : 400;
  int h = gFb.height > 0 ? gFb.height : 800;
  _orbs[0] = w / 4;     _orbs[1] = h / 4;     _orbs[2] = w / 12;
  _orbs[3] = w / 2;     _orbs[4] = h / 3;     _orbs[5] = w / 16;
  _orbs[6] = (3 * w) / 4; _orbs[7] = (2 * h) / 3; _orbs[8] = w / 14;
  _vel[0] = 11; _vel[1] = 7;
  _vel[2] = -9; _vel[3] = 13;
  _vel[4] = 8;  _vel[5] = -10;
}

- (void)stepOrbs {
  int w = gFb.width, h = gFb.height;
  for (int i = 0; i < ORB_COUNT; i++) {
    int32_t *o = &_orbs[i * ORB_STRIDE];
    int32_t vx = _vel[i * 2], vy = _vel[i * 2 + 1];
    o[0] += vx;
    o[1] += vy;
    int32_t r = o[2];
    if (o[0] < r) { o[0] = r; _vel[i * 2] = -vx; }
    if (o[0] > w - r) { o[0] = w - r; _vel[i * 2] = -vx; }
    if (o[1] < r) { o[1] = r; _vel[i * 2 + 1] = -vy; }
    if (o[1] > h - r) { o[1] = h - r; _vel[i * 2 + 1] = -vy; }
  }
}

- (void)tick:(CADisplayLink *)link {
  (void)link;
  if (!gJit.live || !gFb.ready) return;
  gJit.ticks++;
  [self stepOrbs];
  NSString *hud = [NSString stringWithFormat:@"LIVE ticks=%llu via %s",
                   (unsigned long long)gJit.ticks, gJit.allocKind ?: "?"];
  BOOL ok = fbJitRedraw(_orbs, hud);
  if ((gJit.ticks % 30) == 1) {
    self.label.text = [NSString stringWithFormat:
        @"Wawona FbJit\n%@\n\nJIT %@\nIOMFB %s %dx%d\nswap=%@\nticks=%llu",
        @"com.aspauldingcode.wawona.modeb.fbjit",
        gJit.live ? @"LIVE" : @"FAIL",
        gFb.which ?: "?", gFb.width, gFb.height,
        ok ? @"ok" : @"fail",
        (unsigned long long)gJit.ticks];
  }
}

- (void)startLoop {
  if (_started) return;
  _started = YES;
  [self setupOrbs];
  self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  self.displayLink.preferredFramesPerSecond = 30;
  [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)refreshJitAndFb {
  NSString *fbDetail = gFb.ready ? @"open" : fbOpen();
  NSString *jitDetail = nil;
  BOOL jitOk = jitInstallPaint(&jitDetail);
  if (jitOk && gFb.ready) {
    if (!_started) [self setupOrbs];
    gJit.ticks++;
    [self stepOrbs];
    NSString *hud = [NSString stringWithFormat:@"LIVE ticks=%llu via %s",
                     (unsigned long long)gJit.ticks, gJit.allocKind ?: "?"];
    BOOL ok = fbJitRedraw(_orbs, hud);
    self.label.text = [NSString stringWithFormat:
        @"Wawona FbJit (IOMFB + JIT)\n%@\n\nJIT: LIVE\n%@\n\nFB: %@\nredraw=%@\nCS_DEBUGGED=%d",
        @"com.aspauldingcode.wawona.modeb.fbjit",
        jitDetail ?: @"",
        fbDetail ?: @"",
        ok ? @"ok" : @"fail",
        csDebugged() ? 1 : 0];
    [self startLoop];
  } else {
    self.label.text = [NSString stringWithFormat:
        @"Wawona FbJit (IOMFB + JIT)\n%@\n\nJIT: %@\n%@\n\nFB: %@\nCS_DEBUGGED=%d",
        @"com.aspauldingcode.wawona.modeb.fbjit",
        jitOk ? @"LIVE" : @"NEED ATTACH / FAIL",
        jitDetail ?: @"",
        fbDetail ?: @"",
        csDebugged() ? 1 : 0];
    if (!csDebugged()) [self requestMagnifierJitIfNeeded];
  }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
  (void)application;
  [self refreshJitAndFb];
}

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opt {
  (void)app; (void)opt;
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  UIViewController *vc = [UIViewController new];
  vc.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.06 blue:0.09 alpha:1];
  self.label = [[UILabel alloc] initWithFrame:CGRectInset(vc.view.bounds, 20, 60)];
  self.label.numberOfLines = 0;
  self.label.textColor = [UIColor colorWithRed:0.7 green:0.95 blue:0.8 alpha:1];
  self.label.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
  self.label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.label.text =
      @"Wawona FbJit\n"
      @"com.aspauldingcode.wawona.modeb.fbjit\n\n"
      @"Arming JIT + IOMFB…\n"
      @"(open-jit / magnifier)";
  [vc.view addSubview:self.label];
  self.window.rootViewController = vc;
  [self.window makeKeyAndVisible];
  /* Defer heavy work so SpringBoard sees a live UI before W^X / IOMFB. */
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{ [self refreshJitAndFb]; });
  for (int i = 1; i <= 8; i++) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.8 * i) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self refreshJitAndFb]; });
  }
  return YES;
}
@end

int main(int argc, char *argv[]) {
  if (argc == 2 && argv[1] && strcmp(argv[1], "--wwn-jit-child") == 0) {
    return ptrace(PT_TRACE_ME, 0, 0, 0);
  }
  if (argv[0]) trySelfEnableJit(argv[0]);
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
OBJC

"$CLANG" -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=15.0 \
  -I"$STAGE/include" \
  -fobjc-arc \
  -framework UIKit -framework Foundation -framework CoreGraphics \
  -framework QuartzCore -framework IOSurface -framework IOKit \
  -o "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}" \
  "$STAGE/src/main.m"

cat >"$STAGE/Payload/${APP_NAME}.app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>Wawona FbJit</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>CFBundleSupportedPlatforms</key>
  <array><string>iPhoneOS</string></array>
  <key>UIDeviceFamily</key>
  <array><integer>1</integer><integer>2</integer></array>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
  <key>MinimumOSVersion</key><string>15.0</string>
  <key>LSApplicationQueriesSchemes</key>
  <array><string>apple-magnifier</string></array>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
      <key>CFBundleURLSchemes</key>
      <array><string>wawona-fbjit</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

cat >"$STAGE/modeb.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>get-task-allow</key><true/>
  <key>platform-application</key><true/>
  <key>com.apple.private.security.no-sandbox</key><true/>
  <key>com.apple.private.security.storage.AppDataContainers</key><true/>
  <key>com.apple.developer.kernel.increased-memory-limit</key><true/>
  <key>com.apple.developer.kernel.extended-virtual-addressing</key><true/>
  <key>com.apple.private.mapped-memory-buffer</key><true/>
  <key>com.apple.private.IOMobileFramebuffer</key><true/>
  <key>com.apple.private.allow-explicit-graphics-priority</key><true/>
  <key>com.apple.IOSurface.IOSurface</key><true/>
  <key>com.apple.security.exception.iokit-user-client-class</key>
  <array>
    <string>IOMobileFramebufferUserClient</string>
    <string>IOSurfaceRootUserClient</string>
  </array>
  <key>com.apple.security.iokit-user-client-class</key>
  <array>
    <string>IOMobileFramebufferUserClient</string>
    <string>IOSurfaceRootUserClient</string>
  </array>
  <key>com.apple.private.security.storage.AppBundles</key><true/>
</dict>
</plist>
PLIST

echo "signing with $LDID"
"$LDID" -S"$STAGE/modeb.entitlements" "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}"
rm -rf "$STAGE/Payload/${APP_NAME}.app/_CodeSignature"

TIPA="$OUT/WawonaFbJit-${VERSION}-iOS-arm64.tipa"
rm -f "$TIPA"
(cd "$STAGE" && zip -qry "$TIPA" Payload)
printf '%s\n' "$BUILD" >"$STATE_FILE"
echo "wrote $TIPA"
echo "CFBundleShortVersionString=$VERSION CFBundleVersion=$BUILD"
"$LDID" -e "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}" 2>/dev/null | head -40 || true
unzip -l "$TIPA"
ls -la "$TIPA"
