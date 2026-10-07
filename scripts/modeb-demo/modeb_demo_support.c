#include "modeb_demo_support.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGGeometry.h>
#include <IOSurface/IOSurfaceRef.h>
#include <dlfcn.h>
#include <errno.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <os/log.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

#define PT_TRACE_ME 0
#define PT_DETACH 11
int ptrace(int request, pid_t pid, caddr_t addr, int data);
#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000u
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
extern char **environ;

typedef void *IOMobileFramebufferRef;
typedef int IOMobileFramebufferReturn;
typedef IOMobileFramebufferReturn (*FnGetMain)(IOMobileFramebufferRef *);
typedef IOMobileFramebufferReturn (*FnGetSec)(IOMobileFramebufferRef *);
typedef IOMobileFramebufferReturn (*FnGetSize)(IOMobileFramebufferRef, CGSize *);
typedef IOMobileFramebufferReturn (*FnSwapBegin)(IOMobileFramebufferRef, int *);
typedef IOMobileFramebufferReturn (*FnSwapEnd)(IOMobileFramebufferRef);
typedef IOMobileFramebufferReturn (*FnSwapSet)(
    IOMobileFramebufferRef, int, IOSurfaceRef, CGRect, CGRect, int);

static struct {
  bool ready;
  const char *which;
  int width, height, bpr;
  IOSurfaceRef surface[2];
  int front;
  IOMobileFramebufferRef display;
  FnSwapBegin swapBegin;
  FnSwapEnd swapEnd;
  FnSwapSet swapSet;
} gFb;

static char gHud[512];
static uint32_t gFrame;
static bool gJitOk;
static bool gFbOk;
static uint32_t gFibN = 20;
static uint32_t gFibVal;

int modeb_demo_ptrace_trace_me(void) {
  return ptrace(PT_TRACE_ME, 0, 0, 0);
}

bool modeb_demo_cs_debugged(void) {
  uint32_t flags = 0;
  if (csops(0, CS_OPS_STATUS, &flags, sizeof(flags)) != 0) {
    return false;
  }
  return (flags & CS_DEBUGGED) != 0;
}

void modeb_demo_try_self_enable_jit(const char *argv0) {
  if (modeb_demo_cs_debugged() || argv0 == NULL) {
    return;
  }
  pid_t child = 0;
  char *childArgv[] = {(char *)argv0, "--wwn-jit-child", NULL};
  int rc = posix_spawnp(&child, argv0, NULL, NULL, childArgv, environ);
  if (rc != 0) {
    os_log(OS_LOG_DEFAULT, "ModeBDemo self-JIT spawn errno=%{public}d", rc);
    return;
  }
  int status = 0;
  waitpid(child, &status, WUNTRACED);
  ptrace(PT_DETACH, child, NULL, 0);
  kill(child, SIGTERM);
  waitpid(child, NULL, 0);
}

static uint32_t fib_c(uint32_t n) {
  uint32_t a = 0, b = 1;
  for (uint32_t i = 0; i < n; i++) {
    uint32_t t = a + b;
    a = b;
    b = t;
  }
  return a;
}

static bool probe_map_jit(void) {
  void *p = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
  if (p == MAP_FAILED) {
    return false;
  }
  /* minimal RET */
  ((uint32_t *)p)[0] = 0xD65F03C0u;
  if (mprotect(p, 4096, PROT_READ | PROT_EXEC) != 0) {
    munmap(p, 4096);
    return false;
  }
  typedef uint32_t (*Fn)(void);
  uint32_t got = ((Fn)p)();
  munmap(p, 4096);
  (void)got;
  return true;
}

static IOSurfaceRef fb_make_surface(int width, int height) {
  int bpp = 4;
  int pixelFormat = 0x42475241; /* BGRA */
  CFMutableDictionaryRef props = CFDictionaryCreateMutable(
      NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFNumberRef nW = CFNumberCreate(NULL, kCFNumberIntType, &width);
  CFNumberRef nH = CFNumberCreate(NULL, kCFNumberIntType, &height);
  CFNumberRef nFmt = CFNumberCreate(NULL, kCFNumberIntType, &pixelFormat);
  CFNumberRef nBpe = CFNumberCreate(NULL, kCFNumberIntType, &bpp);
  CFDictionarySetValue(props, CFSTR("IOSurfaceWidth"), nW);
  CFDictionarySetValue(props, CFSTR("IOSurfaceHeight"), nH);
  CFDictionarySetValue(props, CFSTR("IOSurfacePixelFormat"), nFmt);
  CFDictionarySetValue(props, CFSTR("IOSurfaceBytesPerElement"), nBpe);
  IOSurfaceRef surface = IOSurfaceCreate(props);
  CFRelease(nW);
  CFRelease(nH);
  CFRelease(nFmt);
  CFRelease(nBpe);
  CFRelease(props);
  return surface;
}

static bool fb_open(void) {
  if (gFb.ready) {
    return true;
  }
  void *h = dlopen(
      "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer",
      RTLD_LAZY);
  if (!h) {
    snprintf(gHud, sizeof(gHud), "IOMFB dlopen failed");
    return false;
  }
  FnGetMain getMain = (FnGetMain)dlsym(h, "IOMobileFramebufferGetMainDisplay");
  FnGetSec getSec = (FnGetSec)dlsym(h, "IOMobileFramebufferGetSecondaryDisplay");
  FnGetSize getSize = (FnGetSize)dlsym(h, "IOMobileFramebufferGetDisplaySize");
  gFb.swapBegin = (FnSwapBegin)dlsym(h, "IOMobileFramebufferSwapBegin");
  gFb.swapEnd = (FnSwapEnd)dlsym(h, "IOMobileFramebufferSwapEnd");
  gFb.swapSet = (FnSwapSet)dlsym(h, "IOMobileFramebufferSwapSetLayer");
  if (!getMain || !getSize || !gFb.swapBegin || !gFb.swapEnd || !gFb.swapSet) {
    snprintf(gHud, sizeof(gHud), "IOMFB symbols missing");
    return false;
  }

  IOMobileFramebufferRef display = NULL;
  IOMobileFramebufferReturn ret = getMain(&display);
  gFb.which = "main";
  if (ret || !display) {
    if (getSec) {
      ret = getSec(&display);
      gFb.which = "secondary";
    }
  }
  if (ret || !display) {
    snprintf(gHud, sizeof(gHud), "GetDisplay ret=%d", (int)ret);
    return false;
  }

  CGSize size = {0, 0};
  ret = getSize(display, &size);
  if (ret) {
    snprintf(gHud, sizeof(gHud), "GetSize ret=%d", (int)ret);
    return false;
  }
  int width = (int)size.width;
  int height = (int)size.height;
  if (width <= 0 || height <= 0) {
    snprintf(gHud, sizeof(gHud), "bad size %dx%d", width, height);
    return false;
  }

  gFb.surface[0] = fb_make_surface(width, height);
  gFb.surface[1] = fb_make_surface(width, height);
  if (!gFb.surface[0] || !gFb.surface[1]) {
    snprintf(gHud, sizeof(gHud), "IOSurfaceCreate failed");
    return false;
  }
  gFb.width = width;
  gFb.height = height;
  gFb.bpr = (int)IOSurfaceGetBytesPerRow(gFb.surface[0]);
  gFb.display = display;
  gFb.front = 0;
  gFb.ready = true;
  gFbOk = true;
  return true;
}

static void fb_paint_and_swap(void) {
  if (!gFb.ready) {
    return;
  }
  int back = 1 - gFb.front;
  IOSurfaceRef surf = gFb.surface[back];
  IOSurfaceLock(surf, 0, NULL);
  uint8_t *base = (uint8_t *)IOSurfaceGetBaseAddress(surf);
  uint32_t t = gFrame;
  for (int y = 0; y < gFb.height; y++) {
    uint32_t *row = (uint32_t *)(base + y * gFb.bpr);
    for (int x = 0; x < gFb.width; x++) {
      uint8_t r = (uint8_t)((x + t) & 255);
      uint8_t g = (uint8_t)((y + (t >> 1)) & 255);
      uint8_t b = (uint8_t)((x ^ y ^ t) & 255);
      row[x] = 0xff000000u | ((uint32_t)b << 16) | ((uint32_t)g << 8) | r;
    }
  }
  /* Hello strip */
  for (int y = 40; y < 72 && y < gFb.height; y++) {
    uint32_t *row = (uint32_t *)(base + y * gFb.bpr);
    for (int x = 40; x < gFb.width - 40; x++) {
      row[x] = 0xffffffffu;
    }
  }
  IOSurfaceUnlock(surf, 0, NULL);

  int token = 0;
  CGRect full = {0, 0, (double)gFb.width, (double)gFb.height};
  gFb.swapBegin(gFb.display, &token);
  gFb.swapSet(gFb.display, 0, surf, full, full, 0);
  gFb.swapEnd(gFb.display);
  gFb.front = back;
}

void modeb_demo_probe_jit_and_fb(void) {
  gJitOk = modeb_demo_cs_debugged() && probe_map_jit();
  gFibVal = fib_c(gFibN);
  (void)fb_open();
}

void modeb_demo_fb_start(void) {
  modeb_demo_probe_jit_and_fb();
  snprintf(
      gHud, sizeof(gHud),
      "Hello, Wawona World!\nJIT: %s\nIOMFB: %s %s %dx%d\nLIVE fib(%u)=%u",
      gJitOk ? "OK" : "ARMED/FAIL", gFbOk ? "OK" : "FAIL",
      gFb.which ? gFb.which : "?", gFb.width, gFb.height, gFibN, gFibVal);
}

void modeb_demo_fb_tick(void) {
  gFrame++;
  if ((gFrame & 15u) == 0u) {
    gFibN = 10 + (gFrame % 20);
    gFibVal = fib_c(gFibN);
    gJitOk = modeb_demo_cs_debugged() && probe_map_jit();
  }
  if (gFb.ready) {
    fb_paint_and_swap();
  }
  snprintf(
      gHud, sizeof(gHud),
      "Hello, Wawona World!\nJIT: %s cs=%d\nIOMFB: %s %s %dx%d\nLIVE fib(%u)=%u frame=%u",
      gJitOk ? "OK" : "ARMED/FAIL", modeb_demo_cs_debugged() ? 1 : 0,
      gFbOk ? "OK" : "FAIL", gFb.which ? gFb.which : "?", gFb.width, gFb.height,
      gFibN, gFibVal, gFrame);
}

const char *modeb_demo_hud_text(void) { return gHud; }
