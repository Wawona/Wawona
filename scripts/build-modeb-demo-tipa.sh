#!/usr/bin/env bash
# Build Wawona Mode B TrollStore .tipa demo (single app for all Mode B proofs):
#   - IOMFB full-frame graphics via JIT paint_frame (plasma + soft orbs)
#   - Host glyphs: "Hello, Wawona World!" + LIVE HUD
#   - JIT showcase: W^X emit ARM64 fib + probe (MAP_JIT or vm_allocate+RX)
#   - Self-enable PT_TRACE_ME / attach / magnifier (same process)
# Signs with ldid. Never for App Store / TestFlight. Not UTM.
# Does NOT touch IOWatchdog (forbidden; see wawona-mode-b-watchdog-safety).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/.agent-device/test-artifacts/dmabuf/vphone-jb}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BUNDLE_ID="com.aspauldingcode.wawona.modeb.demo"
APP_NAME="WawonaModeBDemo"
VERSION="${VERSION:-26.9.2}"
STATE_FILE="${STATE_FILE:-$OUT/.modeb-demo-build}"
BUILD="${BUILD:-}"
if [[ -z "$BUILD" ]]; then
  prev=0
  if [[ -f "$STATE_FILE" ]]; then
    prev="$(tr -d '[:space:]' <"$STATE_FILE" || true)"
  fi
  if [[ -f "$OUT/WawonaModeBDemo-${VERSION}-iOS-arm64.tipa" ]]; then
    tipa_build="$(unzip -p "$OUT/WawonaModeBDemo-${VERSION}-iOS-arm64.tipa" "Payload/${APP_NAME}.app/Info.plist" 2>/dev/null \
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
echo "Building tipa marketing VERSION=$VERSION build CFBundleVersion=$BUILD"

# Minimal IOMFB decls (mineek/FBVNCPublic include/IOMobileFramebuffer/IOMobileframebuffer.h)
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
IOMobileFramebufferReturn IOMobileFramebufferGetLayerDefaultSurface(IOMobileFramebufferRef pointer, int surface, IOSurfaceRef *buffer);
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
#import <Metal/Metal.h>
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
#import <stdio.h>
#import <stdarg.h>
#import <dlfcn.h>
#import <signal.h>
#import <setjmp.h>
#import <pthread.h>
#import <libkern/OSCacheControl.h>
#import <os/log.h>
#include "IOMobileFramebuffer/IOMobileframebuffer.h"

/* Pojav-style self-JIT (no-sandbox tipa). Not a second UI launch. */
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
  if (rc != 0) {
    os_log(OS_LOG_DEFAULT, "WawonaModeBDemo self-JIT posix_spawn errno=%{public}d", rc);
    return;
  }
  int status = 0;
  waitpid(child, &status, WUNTRACED);
  ptrace(PT_DETACH, child, NULL, 0);
  kill(child, SIGTERM);
  waitpid(child, NULL, 0);
  os_log(OS_LOG_DEFAULT, "WawonaModeBDemo self-JIT done cs_debugged=%{public}d", csDebugged());
}

#define PX_WHITE 0xffffffffu
#define PX_BLACK 0xff101820u
#define PX_GREEN 0xff3ddc84u
#define PX_RED   0xffff5555u
#define PX_CYAN  0xff66ccffu
#define PX_YELL  0xffffcc33u

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UILabel *label;
@property (strong, nonatomic) UIView *statusBar;
@property (strong, nonatomic) UIView *jitStrip;
@property (strong, nonatomic) CADisplayLink *displayLink;
@end

@implementation AppDelegate {
  BOOL _requestedMagnifierJit;
  BOOL _showcaseStarted;
}

#pragma mark - Live JIT showcase (W^X write-then-RX / MAP_JIT)

static sigjmp_buf gJitJmp;
static volatile sig_atomic_t gJitFaulted;

static void jit_fault_handler(int signo) {
  (void)signo;
  gJitFaulted = 1;
  siglongjmp(gJitJmp, 1);
}

typedef uint32_t (*JitFibFn)(uint32_t n);
typedef void (*JitPaintFn)(uint32_t *row, int width, uint32_t frame);
typedef void (*JitPaintFrame)(uint32_t *base, int width, int height, int bpr,
                              uint32_t t, const int32_t *orbs);

/* llvm-assembled plasma+orbs painter (scripts/modeb-fb-jit-paint.s). */
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
0x52800008u,
0x9BB67D09u,
0x8B090349u,
0xB83B592Cu,
0x1100076Au,
0x6B14015Fu,
0x54000042u,
0xB82A592Cu,
0x11000B6Au,
0x6B14015Fu,
0x54000042u,
0xB82A592Cu,
0x11000F6Au,
0x6B14015Fu,
0x54000042u,
0xB82A592Cu,
0x11000508u,
0x7100111Fu,
0x54FFFDE3u,
0x1100137Bu,
0x6B14037Fu,
0x54FFF7E3u,
0x11001339u,
0x6B15033Fu,
0x54FFF723u,
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
  JitFibFn fib;
  JitPaintFn paint;
  JitPaintFrame paintFrame;
  BOOL live;
  const char *allocKind;
  uint64_t ticks;
  uint32_t lastFib;
} JitShow;

static JitShow gJit;

static void jitWriteProtect(BOOL execOnly) {
  typedef void (*JitWP)(int);
  JitWP wp = (JitWP)dlsym(RTLD_DEFAULT, "pthread_jit_write_protect_np");
  if (wp) wp(execOnly ? 1 : 0);
}

// TXM / iOS 26: never ask for simultaneous W+X. UTM tipa succeeds with
// write-then-RX (W^X). Requiring CS_DEBUGGED + vm_protect(RWX) is wrong here.
static void *jitAllocPage(size_t len, const char **kindOut) {
  /* Prefer vm_allocate+RX on TXM; MAP_JIT second. Never simultaneous W+X. */
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
  kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)(uintptr_t)p, len,
                                FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
  return kr == KERN_SUCCESS;
}

static BOOL jitMakeWritable(void *p, size_t len, const char *kind) {
  if (strcmp(kind, "MAP_JIT") == 0) {
    jitWriteProtect(NO);
    return YES;
  }
  kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)(uintptr_t)p, len,
                                FALSE, VM_PROT_READ | VM_PROT_WRITE);
  return kr == KERN_SUCCESS;
}

static uint32_t enc_b(int cond, int imm19) {
  // b.cond imm19 (PC-relative, signed)
  return 0x54000000u | ((imm19 & 0x7FFFF) << 5) | (cond & 0xF);
}

static uint32_t enc_b_imm(int imm26) {
  return 0x14000000u | (imm26 & 0x03FFFFFF);
}

static void jitEmitShowcase(uint32_t *code) {
  // fib(n) at offset 0
  int i = 0;
  code[i++] = 0x7100081F; // cmp w0, #2
  int blo_fix = i;
  code[i++] = 0; // b.lo ret_n  (fill later)
  code[i++] = 0x52800001; // mov w1, #0
  code[i++] = 0x52800022; // mov w2, #1
  code[i++] = 0x52800043; // mov w3, #2
  int loop = i;
  code[i++] = 0x6B00007F; // cmp w3, w0
  int bhi_fix = i;
  code[i++] = 0; // b.hi done
  code[i++] = 0x0B020024; // add w4, w1, w2
  code[i++] = 0x2A0203E1; // mov w1, w2
  code[i++] = 0x2A0403E2; // mov w2, w4
  code[i++] = 0x11000463; // add w3, w3, #1
  {
    int here = i;
    code[i++] = enc_b_imm(loop - here);
  }
  int done = i;
  code[i++] = 0x2A0203E0; // mov w0, w2
  int ret_n = i;
  code[i++] = 0xD65F03C0; // ret
  code[blo_fix] = enc_b(0x3 /*lo*/, ret_n - blo_fix);
  code[bhi_fix] = enc_b(0x8 /*hi*/, done - bhi_fix);

  // paint_strip(row,w,frame) at byte offset 256
  while (i < 64) code[i++] = 0xD503201F;
  code[i++] = 0x52800003;
  int ploop = i;
  code[i++] = 0x6B01007F; // cmp w3, w1
  int bhs_fix = i;
  code[i++] = 0; // b.hs end
  code[i++] = 0x4A020064; // eor w4, w3, w2
  code[i++] = 0x12001C84; // and w4, w4, #0xff
  code[i++] = 0x531C7085; // lsl w5, w4, #4
  code[i++] = 0x2A0503E4; // mov w4, w5
  code[i++] = 0x72BFE084; // movk w4, #0xff00, lsl #16
  code[i++] = 0xB8237804; // str w4, [x0, w3, uxtw #2]
  code[i++] = 0x11000463; // add w3, w3, #1
  {
    int here = i;
    code[i++] = enc_b_imm(ploop - here);
  }
  int pend = i;
  code[i++] = 0xD65F03C0;
  code[bhs_fix] = enc_b(0x2 /*hs*/, pend - bhs_fix);
  (void)i;
}

static BOOL jitInstallShowcase(NSString **detail) {
  if (gJit.live && gJit.page) {
    *detail = [NSString stringWithFormat:@"JIT LIVE via %s (reuse)", gJit.allocKind ?: "?"];
    return YES;
  }
  const char *kind = NULL;
  size_t len = 32768;
  void *p = jitAllocPage(len, &kind);
  if (p == MAP_FAILED || !kind) {
    *detail = [NSString stringWithFormat:
        @"JIT alloc failed (MAP_JIT errno=%d CS_DEBUGGED=%d)",
        errno, csDebugged() ? 1 : 0];
    return NO;
  }

  if (!jitMakeWritable(p, len, kind)) {
    *detail = @"JIT make-writable failed";
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    return NO;
  }
  memset(p, 0, len);
  // Probe 1: minimal thunk (must work before any showcase).
  uint32_t *code = (uint32_t *)p;
  code[0] = 0x52800540; // mov w0, #0x2a
  code[1] = 0xD65F03C0; // ret
  if (!jitMakeExecutable(p, len, kind)) {
    *detail = [NSString stringWithFormat:@"JIT make-executable failed via %s", kind];
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    return NO;
  }
  sys_icache_invalidate(p, 16);

  gJitFaulted = 0;
  struct sigaction sa = {0}, oldBus = {0}, oldSeg = {0};
  sa.sa_handler = jit_fault_handler;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGBUS, &sa, &oldBus);
  sigaction(SIGSEGV, &sa, &oldSeg);

  int probe = -1;
  if (sigsetjmp(gJitJmp, 1) == 0) {
    typedef int (*Thunk)(void);
    probe = ((Thunk)p)();
  }
  if (gJitFaulted || probe != 0x2a) {
    sigaction(SIGBUS, &oldBus, NULL);
    sigaction(SIGSEGV, &oldSeg, NULL);
    *detail = [NSString stringWithFormat:
        @"JIT exec blocked via %s (probe=%d fault=%d)",
        kind, probe, (int)gJitFaulted];
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    memset(&gJit, 0, sizeof(gJit));
    return NO;
  }

  // Probe 2: install fib+paint showcase over the same page.
  if (!jitMakeWritable(p, len, kind)) {
    sigaction(SIGBUS, &oldBus, NULL);
    sigaction(SIGSEGV, &oldSeg, NULL);
    *detail = @"JIT re-writable failed after probe";
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    memset(&gJit, 0, sizeof(gJit));
    return NO;
  }
  memset(p, 0, len);
  jitEmitShowcase(code);
  if (!jitMakeExecutable(p, len, kind)) {
    sigaction(SIGBUS, &oldBus, NULL);
    sigaction(SIGSEGV, &oldSeg, NULL);
    *detail = @"JIT re-executable failed for showcase";
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    memset(&gJit, 0, sizeof(gJit));
    return NO;
  }
  sys_icache_invalidate(p, 512);

  gJitFaulted = 0;
  JitFibFn fib = (JitFibFn)p;
  JitPaintFn paint = (JitPaintFn)((uint8_t *)p + 256);
  uint32_t fib30 = 0;
  uint32_t probeRow[8] = {0};
  if (sigsetjmp(gJitJmp, 1) == 0) {
    fib30 = fib(30);
    paint(probeRow, 8, 7);
  }
  sigaction(SIGBUS, &oldBus, NULL);
  sigaction(SIGSEGV, &oldSeg, NULL);

  if (gJitFaulted || fib30 != 832040) {
    *detail = [NSString stringWithFormat:
        @"Showcase emit faulted (fib30=%u fault=%d; probe OK via %s)",
        fib30, (int)gJitFaulted, kind];
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    memset(&gJit, 0, sizeof(gJit));
    return NO;
  }

  /* Room for fib@0, strip@256, full-frame paint_frame@1024. */
  size_t frameOff = 1024;
  if (frameOff + sizeof(kPaintCode) > len) {
    *detail = @"JIT page too small for paint_frame";
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    memset(&gJit, 0, sizeof(gJit));
    return NO;
  }
  if (!jitMakeWritable(p, len, kind)) {
    *detail = @"JIT writable for paint_frame failed";
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    memset(&gJit, 0, sizeof(gJit));
    return NO;
  }
  memcpy((uint8_t *)p + frameOff, kPaintCode, sizeof(kPaintCode));
  if (!jitMakeExecutable(p, len, kind)) {
    *detail = @"JIT exec for paint_frame failed";
    if (strcmp(kind, "MAP_JIT") == 0) munmap(p, len);
    else vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)p, len);
    memset(&gJit, 0, sizeof(gJit));
    return NO;
  }
  sys_icache_invalidate((uint8_t *)p + frameOff, sizeof(kPaintCode));

  gJit.page = p;
  gJit.len = len;
  gJit.fib = fib;
  gJit.paint = paint;
  gJit.paintFrame = (JitPaintFrame)((uint8_t *)p + frameOff);
  gJit.live = YES;
  gJit.allocKind = kind;
  gJit.lastFib = fib30;
  gJit.ticks = 0;
  *detail = [NSString stringWithFormat:
      @"JIT LIVE via %s: fib(30)=%u + paint_frame", kind, fib30];
  return YES;
}

static BOOL tryMapJit(NSString **detail) {
  return jitInstallShowcase(detail);
}

#pragma mark - Tiny 5x7 glyphs (A-Z 0-9 space . : / -)

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

static void fbFill(uint32_t *base, int w, int h, int bpr, uint32_t color) {
  for (int y = 0; y < h; y++) {
    uint32_t *row = (uint32_t *)((uint8_t *)base + y * bpr);
    for (int x = 0; x < w; x++) row[x] = color;
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
    if (*p == '\n') { y0 += 8 * scale; x = x0; continue; }
    fbPutChar(base, w, h, bpr, x, y0, *p, fg, scale);
    x += 6 * scale;
  }
}

#pragma mark - IOMFB persistent graphics (JIT paint_frame + Hello + HUD)

typedef IOMobileFramebufferReturn (*FnGetMain)(IOMobileFramebufferRef *);
typedef IOMobileFramebufferReturn (*FnGetSec)(IOMobileFramebufferRef *);
typedef IOMobileFramebufferReturn (*FnGetSize)(IOMobileFramebufferRef, IOMobileFramebufferDisplaySize *);
typedef IOMobileFramebufferReturn (*FnSwapBegin)(IOMobileFramebufferRef, int *);
typedef IOMobileFramebufferReturn (*FnSwapEnd)(IOMobileFramebufferRef);
typedef IOMobileFramebufferReturn (*FnSwapSet)(IOMobileFramebufferRef, int, IOSurfaceRef, CGRect, CGRect, int);

#define ORB_COUNT 3
#define ORB_STRIDE 3

typedef struct {
  IOMobileFramebufferRef display;
  IOSurfaceRef surface[2];
  int front;
  int width, height, bpr[2];
  FnSwapBegin swapBegin;
  FnSwapEnd swapEnd;
  FnSwapSet swapSet;
  BOOL ready;
  const char *which;
} FbSession;

static FbSession gFb;
static int32_t gOrbs[9];
static int32_t gVel[6];
static id<MTLDevice> gMetalDevice;
static id<MTLCommandQueue> gMetalQueue;
static id<MTLComputePipelineState> gMetalPipeline;
static id<MTLTexture> gMetalSurfaceTexture[2];
static id<MTLTexture> gMetalScratchTexture;
static BOOL gMetalReady;
static NSString *gMetalDetail;

static void fbWriteStatus(const char *format, ...) {
  FILE *file = fopen("/tmp/WawonaModeBDemo-status.log", "a");
  if (!file) return;
  va_list args;
  va_start(args, format);
  vfprintf(file, format, args);
  va_end(args);
  fputc('\n', file);
  fclose(file);
}

static BOOL fbOpenMetal(void) {
  if (gMetalReady) return YES;
  gMetalDevice = MTLCreateSystemDefaultDevice();
  if (!gMetalDevice) {
    gMetalDetail = @"Metal device unavailable";
    return NO;
  }
  gMetalQueue = [gMetalDevice newCommandQueue];
  NSString *source =
      @"#include <metal_stdlib>\n"
       "using namespace metal;\n"
       "kernel void wwn_modeb_scene(texture2d<float, access::write> out [[texture(0)]],\n"
       "                              constant uint &frame [[buffer(0)]],\n"
       "                              uint2 gid [[thread_position_in_grid]]) {\n"
       "  uint w = out.get_width(), h = out.get_height();\n"
       "  if (gid.x >= w || gid.y >= h) return;\n"
       "  float2 p = (float2(gid) + 0.5) / float2(w, h);\n"
       "  float t = float(frame) * 0.035;\n"
       "  float wave = 0.5 + 0.5 * sin(p.x * 18.0 + t) * cos(p.y * 15.0 - t * 0.7);\n"
       "  float3 c = float3(0.04 + 0.22 * wave, 0.09 + 0.42 * p.y,\n"
       "                    0.16 + 0.64 * (1.0 - p.x) * wave);\n"
       "  float2 centers[3] = { float2(0.5 + 0.27 * sin(t), 0.5 + 0.22 * cos(t * 0.8)),\n"
       "                        float2(0.5 + 0.34 * cos(t * 0.6), 0.5 + 0.30 * sin(t * 1.1)),\n"
       "                        float2(0.5 + 0.20 * sin(t * 1.5), 0.5 + 0.35 * cos(t * 0.5)) };\n"
       "  float3 colors[3] = { float3(1.0, 0.18, 0.45), float3(0.15, 0.85, 1.0),\n"
       "                       float3(1.0, 0.72, 0.12) };\n"
       "  for (uint i = 0; i < 3; ++i) {\n"
       "    float d = distance(p, centers[i]);\n"
       "    c += colors[i] * smoothstep(0.18, 0.0, d) * 0.78;\n"
       "  }\n"
       "  out.write(float4(clamp(c, 0.0, 1.0), 1.0), gid);\n"
       "}\n";
  NSError *error = nil;
  id<MTLLibrary> library =
      [gMetalDevice newLibraryWithSource:source options:nil error:&error];
  id<MTLFunction> function = [library newFunctionWithName:@"wwn_modeb_scene"];
  gMetalPipeline = function
      ? [gMetalDevice newComputePipelineStateWithFunction:function error:&error]
      : nil;
  if (!gMetalPipeline) {
    gMetalDetail = [NSString stringWithFormat:@"Metal pipeline: %@",
                                              error.localizedDescription ?: @"missing function"];
    return NO;
  }
  for (int i = 0; i < 2; ++i) {
    MTLTextureDescriptor *td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:(NSUInteger)gFb.width
                                                          height:(NSUInteger)gFb.height
                                                       mipmapped:NO];
    td.storageMode = MTLStorageModeShared;
    td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    gMetalSurfaceTexture[i] =
        [gMetalDevice newTextureWithDescriptor:td iosurface:gFb.surface[i] plane:0];
    if (!gMetalSurfaceTexture[i]) {
      gMetalDetail = [NSString stringWithFormat:@"Metal IOSurface texture %d failed", i];
      return NO;
    }
  }
  MTLTextureDescriptor *scratch =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                         width:(NSUInteger)gFb.width
                                                        height:(NSUInteger)gFb.height
                                                     mipmapped:NO];
  scratch.storageMode = MTLStorageModePrivate;
  scratch.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
  gMetalScratchTexture = [gMetalDevice newTextureWithDescriptor:scratch];
  if (!gMetalScratchTexture) {
    gMetalDetail = @"Metal private scratch texture failed";
    return NO;
  }
  gMetalReady = YES;
  gMetalDetail = @"Metal direct IOSurface + GPU blit fallback ready";
  fbWriteStatus("op=metal-open width=%d height=%d surface0=%u surface1=%u",
                gFb.width, gFb.height, IOSurfaceGetID(gFb.surface[0]),
                IOSurfaceGetID(gFb.surface[1]));
  return YES;
}

static IOSurfaceRef fbMakeSurface(int width, int height) {
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
  return surface;
}

static NSString *fbOpen(void) {
  if (gFb.ready) return [NSString stringWithFormat:@"IOMFB %s %dx%d (reuse)", gFb.which, gFb.width, gFb.height];
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
    if (getSec) { ret = getSec(&display); gFb.which = "secondary"; }
  }
  if (ret || !display) return [NSString stringWithFormat:@"GetDisplay ret=%d", (int)ret];

  IOMobileFramebufferDisplaySize size = {0};
  ret = getSize(display, &size);
  if (ret) return [NSString stringWithFormat:@"GetSize ret=%d", (int)ret];
  int width = (int)size.width, height = (int)size.height;
  if (width <= 0 || height <= 0) return @"bad FB size";

  IOSurfaceRef a = fbMakeSurface(width, height);
  IOSurfaceRef b = fbMakeSurface(width, height);
  if (!a || !b) {
    if (a) CFRelease(a);
    if (b) CFRelease(b);
    return @"IOSurfaceCreate failed";
  }

  gFb.display = display;
  gFb.surface[0] = a;
  gFb.surface[1] = b;
  gFb.front = 0;
  gFb.width = width;
  gFb.height = height;
  gFb.bpr[0] = (int)IOSurfaceGetBytesPerRow(a);
  gFb.bpr[1] = (int)IOSurfaceGetBytesPerRow(b);
  gFb.ready = YES;
  if (!fbOpenMetal()) {
    fbWriteStatus("op=iomfb-open result=fail detail=%s",
                  gMetalDetail.UTF8String ?: "unknown");
  }

  gOrbs[0] = width / 4;     gOrbs[1] = height / 4;     gOrbs[2] = width / 12;
  gOrbs[3] = width / 2;     gOrbs[4] = height / 3;     gOrbs[5] = width / 16;
  gOrbs[6] = (3 * width) / 4; gOrbs[7] = (2 * height) / 3; gOrbs[8] = width / 14;
  gVel[0] = 11; gVel[1] = 7;
  gVel[2] = -9; gVel[3] = 13;
  gVel[4] = 8;  gVel[5] = -10;
  fbWriteStatus("op=iomfb-open result=ok display=%s width=%d height=%d",
                gFb.which, width, height);
  return [NSString stringWithFormat:@"IOMFB %s %dx%d double-buffer ready | %@",
      gFb.which, width, height,
      gMetalReady ? gMetalDetail : @"vphone JIT CPU fallback"];
}

static void stepOrbs(void) {
  int w = gFb.width, h = gFb.height;
  for (int i = 0; i < ORB_COUNT; i++) {
    int32_t *o = &gOrbs[i * ORB_STRIDE];
    int32_t vx = gVel[i * 2], vy = gVel[i * 2 + 1];
    o[0] += vx; o[1] += vy;
    int32_t r = o[2];
    if (o[0] < r) { o[0] = r; gVel[i * 2] = -vx; }
    if (o[0] > w - r) { o[0] = w - r; gVel[i * 2] = -vx; }
    if (o[1] < r) { o[1] = r; gVel[i * 2 + 1] = -vy; }
    if (o[1] > h - r) { o[1] = h - r; gVel[i * 2 + 1] = -vy; }
  }
}

static BOOL fbJitCpuFallbackRedraw(NSString *hud) {
  if (!gFb.ready || !gJit.live || !gJit.paintFrame) return NO;
  int back = 1 - gFb.front;
  IOSurfaceRef surf = gFb.surface[back];
  int bpr = gFb.bpr[back];

  gJitFaulted = 0;
  struct sigaction sa = {0}, oldBus = {0}, oldSeg = {0}, oldIll = {0};
  sa.sa_handler = jit_fault_handler;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGBUS, &sa, &oldBus);
  sigaction(SIGSEGV, &sa, &oldSeg);
  sigaction(SIGILL, &sa, &oldIll);
  IOSurfaceLock(surf, 0, NULL);
  void *base = IOSurfaceGetBaseAddress(surf);
  if (sigsetjmp(gJitJmp, 1) == 0) {
    gJit.paintFrame((uint32_t *)base, gFb.width, gFb.height, bpr,
                    (uint32_t)gJit.ticks, gOrbs);
  }
  BOOL faulted = gJitFaulted;
  if (!faulted) {
    int scale = gFb.width >= 800 ? 4 : 3;
    const char *hello = "Hello, Wawona World!";
    int helloW = 19 * 6 * scale;
    int hx = MAX(16, (gFb.width - helloW) / 2);
    int hy = gFb.height / 5;
    fbPutString((uint32_t *)base, gFb.width, gFb.height, bpr, hx, hy,
                hello, PX_YELL, scale);
    int hscale = gFb.width >= 800 ? 3 : 2;
    int y = MAX(0, gFb.height - 16 * hscale - 24);
    fbPutString((uint32_t *)base, gFb.width, gFb.height, bpr, 24, y,
                hud.UTF8String ?: "", PX_GREEN, hscale);
  }
  IOSurfaceUnlock(surf, 0, NULL);
  sigaction(SIGBUS, &oldBus, NULL);
  sigaction(SIGSEGV, &oldSeg, NULL);
  sigaction(SIGILL, &oldIll, NULL);
  if (faulted) return NO;

  int token = 0;
  if (gFb.swapBegin(gFb.display, &token)) return NO;
  CGRect full = CGRectMake(0, 0, gFb.width, gFb.height);
  IOMobileFramebufferReturn setRet =
      gFb.swapSet(gFb.display, 0, surf, full, full, 0);
  IOMobileFramebufferReturn endRet = gFb.swapEnd(gFb.display);
  if (setRet == 0 && endRet == 0) {
    gFb.front = back;
    if ((gJit.ticks % 30u) == 0u)
      fbWriteStatus("op=present result=ok backing_id=%u frame=%llu "
                    "route=vphone-jit-cpu copy=cpu",
                    IOSurfaceGetID(surf), (unsigned long long)gJit.ticks);
  }
  return setRet == 0 && endRet == 0;
}

/* Metal renders every frame. JIT remains an independent entitlement smoke. */
static BOOL fbMetalRedraw(NSString *hud) {
  if (!gMetalReady || !gMetalPipeline)
    return fbJitCpuFallbackRedraw(hud);
  if (!gFb.ready) return NO;
  int back = 1 - gFb.front;
  IOSurfaceRef surf = gFb.surface[back];
  int bpr = gFb.bpr[back];
  BOOL direct = (gJit.ticks & 1u) == 0;
  id<MTLTexture> renderTarget =
      direct ? gMetalSurfaceTexture[back] : gMetalScratchTexture;

  id<MTLCommandBuffer> commandBuffer = [gMetalQueue commandBuffer];
  id<MTLComputeCommandEncoder> compute = [commandBuffer computeCommandEncoder];
  [compute setComputePipelineState:gMetalPipeline];
  [compute setTexture:renderTarget atIndex:0];
  uint32_t frame = (uint32_t)gJit.ticks;
  [compute setBytes:&frame length:sizeof(frame) atIndex:0];
  NSUInteger tw = gMetalPipeline.threadExecutionWidth;
  NSUInteger th =
      MAX((NSUInteger)1, gMetalPipeline.maxTotalThreadsPerThreadgroup / tw);
  [compute dispatchThreads:MTLSizeMake((NSUInteger)gFb.width,
                                       (NSUInteger)gFb.height, 1)
      threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
  [compute endEncoding];

  if (!direct) {
    id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
    [blit copyFromTexture:gMetalScratchTexture
              sourceSlice:0
              sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake((NSUInteger)gFb.width,
                                      (NSUInteger)gFb.height, 1)
                toTexture:gMetalSurfaceTexture[back]
         destinationSlice:0
         destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding];
  }
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  if (commandBuffer.status == MTLCommandBufferStatusError) {
    os_log_error(OS_LOG_DEFAULT, "wwn.iomfb metal command failed: %{public}@",
                 commandBuffer.error.localizedDescription);
    return NO;
  }

  /* CPU glyphs are a diagnostic overlay. Scene pixels are Metal-rendered. */
  IOSurfaceLock(surf, 0, NULL);
  void *base = IOSurfaceGetBaseAddress(surf);
  if (base) {
    int scale = gFb.width >= 800 ? 4 : 3;
    const char *hello = "Hello, Wawona World!";
    int helloW = 19 * 6 * scale;
    int hx = (gFb.width - helloW) / 2;
    if (hx < 16) hx = 16;
    int hy = gFb.height / 5;
    int pad = 8 * scale;
    for (int yy = hy - pad; yy < hy + 8 * scale + pad; yy++) {
      if (yy < 0 || yy >= gFb.height) continue;
      uint32_t *row = (uint32_t *)((uint8_t *)base + yy * bpr);
      for (int x = hx - pad; x < hx + helloW + pad && x < gFb.width; x++) {
        if (x < 0) continue;
        row[x] = (row[x] >> 2) & 0x3f3f3f3f;
      }
    }
    fbPutString((uint32_t *)base, gFb.width, gFb.height, bpr, hx, hy,
                hello, PX_YELL, scale);

    if (hud.length) {
      int hscale = gFb.width >= 800 ? 3 : 2;
      int y = gFb.height - 16 * hscale - 24;
      if (y < 0) y = 0;
      for (int yy = y - 8; yy < gFb.height; yy++) {
        if (yy < 0) continue;
        uint32_t *row = (uint32_t *)((uint8_t *)base + yy * bpr);
        for (int x = 0; x < gFb.width; x++)
          row[x] = (row[x] >> 2) & 0x3f3f3f3f;
      }
      fbPutString((uint32_t *)base, gFb.width, gFb.height, bpr, 24, y,
                  hud.UTF8String ?: "", PX_GREEN, hscale);
    }
  }
  IOSurfaceUnlock(surf, 0, NULL);

  int token = 0;
  if (gFb.swapBegin(gFb.display, &token)) return NO;
  CGRect full = CGRectMake(0, 0, gFb.width, gFb.height);
  IOMobileFramebufferReturn setRet =
      gFb.swapSet(gFb.display, 0, surf, full, full, 0);
  IOMobileFramebufferReturn endRet = gFb.swapEnd(gFb.display);
  if (setRet == 0 && endRet == 0) {
    gFb.front = back;
    if ((gJit.ticks % 30u) == 0u) {
      os_log(OS_LOG_DEFAULT,
             "wwn.iomfb op=present sink=iomfb backing_id=%{public}u "
             "frame=%{public}llu route=%{public}s copy=%{public}s",
             IOSurfaceGetID(surf), (unsigned long long)gJit.ticks,
             direct ? "metal-iosurface-direct" : "metal-private-gpu-blit",
             direct ? "zero" : "gpu");
      fbWriteStatus("op=present result=ok backing_id=%u frame=%llu route=%s copy=%s",
                    IOSurfaceGetID(surf), (unsigned long long)gJit.ticks,
                    direct ? "metal-iosurface-direct" : "metal-private-gpu-blit",
                    direct ? "zero" : "gpu");
    }
  }
  return setRet == 0 && endRet == 0;
}

static NSString *runFramebufferTest(BOOL jitOk, NSString *jitDetail) {
  (void)jitOk;
  NSString *open = fbOpen();
  if (!gFb.ready) return open;
  stepOrbs();
  NSString *hud = [NSString stringWithFormat:@"LIVE %s t=%llu fib=%u",
                   gJit.allocKind ?: "?", (unsigned long long)gJit.ticks, gJit.lastFib];
  BOOL ok = fbMetalRedraw(hud);
  NSString *route = gMetalReady
      ? ((gJit.ticks & 1u) == 0 ? @"metal-direct" : @"metal-gpu-blit")
      : @"vphone-jit-cpu";
  return [NSString stringWithFormat:@"%@ | present=%@ route=%@",
      open, ok ? @"ok" : @"fail",
      route];
}

#pragma mark - UI + live JIT showcase

- (void)tickShowcase:(CADisplayLink *)link {
  (void)link;
  if (!gJit.live || !gJit.fib || !gFb.ready) return;
  gJit.ticks++;
  uint32_t n = 20 + (uint32_t)(gJit.ticks % 10);
  gJit.lastFib = gJit.fib(n);
  stepOrbs();
  NSString *hud = [NSString stringWithFormat:@"LIVE %s t=%llu fib(%u)=%u",
                   gJit.allocKind ?: "?", (unsigned long long)gJit.ticks, n, gJit.lastFib];
  BOOL ok = fbMetalRedraw(hud);
  if ((gJit.ticks % 30) == 1) {
    self.label.text = [NSString stringWithFormat:
        @"Wawona Mode B tipa\n"
        @"com.aspauldingcode.wawona.modeb.demo\n\n"
        @"JIT LIVE (%s)\n"
        @"fib(%u)=%u  ticks=%llu\n"
        @"IOMFB graphics + Hello\n"
        @"route=%@ swap=%@",
        gJit.allocKind ?: "?", n, gJit.lastFib,
        (unsigned long long)gJit.ticks,
        gMetalReady
            ? ((gJit.ticks & 1u) == 0 ? @"metal-direct" : @"metal-gpu-blit")
            : @"vphone-jit-cpu",
        ok ? @"ok" : @"fail"];
  }
}

- (void)startShowcaseIfNeeded {
  if (_showcaseStarted || !gJit.live) return;
  _showcaseStarted = YES;
  self.jitStrip.hidden = YES;
  self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tickShowcase:)];
  self.displayLink.preferredFramesPerSecond = 30;
  [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  self.statusBar.backgroundColor = [UIColor colorWithRed:0.05 green:0.65 blue:0.3 alpha:1];
}

- (void)requestMagnifierJitIfNeeded {
  if (_requestedMagnifierJit) return;
  _requestedMagnifierJit = YES;
  NSString *urlStr = [NSString stringWithFormat:
      @"apple-magnifier://enable-jit?bundle-id=%@",
      @"com.aspauldingcode.wawona.modeb.demo"];
  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) return;
  [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)refreshStatus {
  (void)fbOpen();
  NSString *jitDetail = nil;
  BOOL mapOk = tryMapJit(&jitDetail);
  BOOL debugged = csDebugged();
  BOOL jitArmed = debugged && !mapOk;
  if (!debugged) {
    [self requestMagnifierJitIfNeeded];
  }
  NSString *fb = runFramebufferTest(mapOk || gJit.live, jitDetail ?: @"");
  if (mapOk || gJit.live) {
    [self startShowcaseIfNeeded];
    self.label.text = [NSString stringWithFormat:
        @"Wawona Mode B tipa\n"
        @"com.aspauldingcode.wawona.modeb.demo\n\n"
        @"JIT: LIVE\n%@\n\n"
        @"IOMFB graphics + Hello, Wawona World!\n"
        @"%@\n"
        @"open-jit / magnifier if needed",
        jitDetail ?: @"", fb];
    return;
  }
  NSString *jitLabel = jitArmed ? @"ARMED" : @"FAIL";
  self.label.text = [NSString stringWithFormat:
      @"Wawona Mode B tipa\n"
      @"com.aspauldingcode.wawona.modeb.demo\n\n"
      @"JIT: %@\n%@\n\n"
      @"Needs W^X (vm_allocate+RX or MAP_JIT).\n"
      @"Attach: packages tipa open-jit\n"
      @"Framebuffer:\n%@",
      jitLabel, jitDetail, fb];
  self.statusBar.backgroundColor = jitArmed
      ? [UIColor colorWithRed:0.75 green:0.55 blue:0.1 alpha:1]
      : [UIColor colorWithRed:0.55 green:0.15 blue:0.12 alpha:1];
  os_log(OS_LOG_DEFAULT, "WawonaModeBDemo jit=%{public}@ dbg=%{public}d fb=%{public}@",
         jitLabel, debugged, fb);
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
  (void)application;
  [self refreshStatus];
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application; (void)launchOptions;
  unlink("/tmp/WawonaModeBDemo-status.log");
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  UIViewController *vc = [UIViewController new];
  vc.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.08 blue:0.12 alpha:1];

  self.statusBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, vc.view.bounds.size.width, 28)];
  self.statusBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  self.statusBar.backgroundColor = [UIColor darkGrayColor];
  [vc.view addSubview:self.statusBar];

  self.jitStrip = [[UIView alloc] initWithFrame:CGRectMake(16, 36, vc.view.bounds.size.width - 32, 28)];
  self.jitStrip.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  self.jitStrip.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
  self.jitStrip.layer.magnificationFilter = kCAFilterNearest;
  self.jitStrip.hidden = YES;
  [vc.view addSubview:self.jitStrip];

  self.label = [[UILabel alloc] initWithFrame:CGRectInset(vc.view.bounds, 16, 72)];
  self.label.numberOfLines = 0;
  self.label.textColor = UIColor.whiteColor;
  self.label.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
  self.label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.label.text = @"Probing JIT showcase…";
  [vc.view addSubview:self.label];

  self.window.rootViewController = vc;
  [self.window makeKeyAndVisible];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{ [self refreshStatus]; });
  for (int i = 1; i <= 8; i++) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.8 * i) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self refreshStatus]; });
  }
  return YES;
}
@end

int main(int argc, char *argv[]) {
  if (argc == 2 && argv[1] && strcmp(argv[1], "--wwn-jit-child") == 0) {
    return ptrace(PT_TRACE_ME, 0, 0, 0);
  }
  if (argv[0]) {
    trySelfEnableJit(argv[0]);
  }
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}

OBJC

"$CLANG" -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=15.0 \
  -I"$STAGE/include" \
  -fobjc-arc \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework Metal \
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
  <key>CFBundleDisplayName</key><string>Wawona Mode B Demo</string>
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
      <key>CFBundleURLName</key><string>com.aspauldingcode.wawona.modeb.demo</string>
      <key>CFBundleURLSchemes</key>
      <array><string>wawona-modeb-demo</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Tipa ents: JIT + IOMFB. Never IOWatchdog (Mode B watchdog safety).
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
# Do NOT ldid-sign the .app directory (creates _CodeSignature/CodeResources that
# TrollStore Lite rejects / installforce no-ops). Binary-only ldid is enough.
rm -rf "$STAGE/Payload/${APP_NAME}.app/_CodeSignature"

TIPA="$OUT/WawonaModeBDemo-${VERSION}-iOS-arm64.tipa"
rm -f "$TIPA"
(cd "$STAGE" && zip -qry "$TIPA" Payload)
printf '%s\n' "$BUILD" >"$STATE_FILE"
echo "wrote $TIPA"
echo "CFBundleShortVersionString (marketing)=$VERSION"
echo "CFBundleVersion (build)=$BUILD"
"$LDID" -e "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}" 2>/dev/null | head -50 || true
unzip -l "$TIPA"
ls -la "$TIPA"
