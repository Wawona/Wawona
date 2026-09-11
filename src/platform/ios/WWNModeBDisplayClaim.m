#if WWN_MODE_B
#import "WWNModeBDesktop.h"
#import "../../util/WWNLog.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <errno.h>
#import <mach/mach.h>
#import <signal.h>
#import <string.h>
#import <unistd.h>

/* libproc.h is not in the iPhoneOS SDK. The symbols exist on device. */
extern int proc_listallpids(void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);

#if __has_include(<IOKit/hid/IOHIDEventSystemClient.h>)
#import <IOKit/hid/IOHIDEventSystemClient.h>
#import <IOKit/hid/IOHIDEvent.h>
#else
typedef void *IOHIDEventSystemClientRef;
typedef void *IOHIDEventRef;
#ifndef Boolean
typedef unsigned char Boolean;
#endif
#endif

enum {
  kWWNHidDigitizer = 11,
  kWWNHidFieldX = 0x000B0000,
  kWWNHidFieldY = 0x000B0001,
  kWWNHidFieldIndex = 0x000B0005,
  kWWNHidFieldTouch = 0x000B0009,
};

typedef IOHIDEventSystemClientRef (*FnHidCreate)(CFAllocatorRef);
typedef IOHIDEventSystemClientRef (*FnHidCreateType)(CFAllocatorRef, uint32_t, CFDictionaryRef);
typedef void (*FnHidRegister)(IOHIDEventSystemClientRef, void *, void *, void *);
typedef Boolean (*FnHidFilter)(void *, void *, void *, IOHIDEventRef);
typedef void (*FnHidRegisterFilter)(
    IOHIDEventSystemClientRef, FnHidFilter, void *, void *);
typedef void (*FnHidSchedule)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef);
typedef void (*FnHidUnschedule)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef);
typedef double (*FnHidFloat)(IOHIDEventRef, uint32_t);
typedef CFIndex (*FnHidInt)(IOHIDEventRef, uint32_t);
typedef uint32_t (*FnHidType)(IOHIDEventRef);
typedef CFArrayRef (*FnHidChildren)(IOHIDEventRef);

static WWNModeBHidSink gHidSink;
static IOHIDEventSystemClientRef gHidClient;
static FnHidFloat gHidFloat;
static FnHidInt gHidInt;
static FnHidType gHidType;
static FnHidChildren gHidChildren;
static FnHidUnschedule gHidUnschedule;
static BOOL gClaimed;
static pid_t gParked[8];
static size_t gParkedCount;

static BOOL wwn_never_park(const char *name) {
  return strcmp(name, "watchdogd") == 0 || strcmp(name, "launchd") == 0 ||
         strcmp(name, "runningboardd") == 0 || strcmp(name, "logd") == 0;
}

static pid_t wwn_pid_named(const char *want) {
  int needed = proc_listallpids(NULL, 0);
  if (needed <= 0) {
    return 0;
  }
  pid_t *pids = calloc((size_t)needed, sizeof(pid_t));
  if (!pids) {
    return 0;
  }
  int count = proc_listallpids(pids, needed * (int)sizeof(pid_t));
  pid_t found = 0;
  for (int i = 0; i < count; i++) {
    if (pids[i] <= 0) {
      continue;
    }
    char name[64] = {0};
    proc_name(pids[i], name, sizeof(name));
    if (strcmp(name, want) == 0) {
      found = pids[i];
      break;
    }
  }
  free(pids);
  return found;
}

static int32_t wwn_park_pid(pid_t pid, const char *name) {
  if (pid <= 1 || wwn_never_park(name)) {
    return EPERM;
  }
  if (kill(pid, SIGSTOP) == 0) {
    WWNLog("MODEB", @"claim park %s pid=%d via SIGSTOP", name, (int)pid);
    return 0;
  }
  int stopped = errno;
  task_t task = MACH_PORT_NULL;
  kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
  if (kr == KERN_SUCCESS && task != MACH_PORT_NULL) {
    kr = task_suspend(task);
    mach_port_deallocate(mach_task_self(), task);
    if (kr == KERN_SUCCESS) {
      WWNLog("MODEB", @"claim park %s pid=%d via task_suspend", name, (int)pid);
      return 0;
    }
    WWNLog("MODEB", @"claim park %s pid=%d task_suspend kr=%d", name, (int)pid,
           (int)kr);
    return (int32_t)kr;
  }
  WWNLog("MODEB", @"claim park %s pid=%d failed stop=%d tfp=%d", name, (int)pid,
         stopped, (int)kr);
  return stopped != 0 ? stopped : EPERM;
}

static void wwn_resume_pid(pid_t pid, const char *name) {
  if (pid <= 1) {
    return;
  }
  if (kill(pid, SIGCONT) == 0) {
    WWNLog("MODEB", @"claim resume %s pid=%d via SIGCONT", name, (int)pid);
    return;
  }
  task_t task = MACH_PORT_NULL;
  kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
  if (kr == KERN_SUCCESS && task != MACH_PORT_NULL) {
    (void)task_resume(task);
    mach_port_deallocate(mach_task_self(), task);
    WWNLog("MODEB", @"claim resume %s pid=%d via task_resume", name, (int)pid);
    return;
  }
  WWNLog("MODEB", @"claim resume %s pid=%d failed", name, (int)pid);
}

static void wwn_map_hid_point(double rawX, double rawY, double *outX, double *outY) {
  CGRect bounds = UIScreen.mainScreen.bounds;
  double bw = bounds.size.width;
  double bh = bounds.size.height;
  if (bw < 1 || bh < 1) {
    *outX = rawX;
    *outY = rawY;
    return;
  }
  if (rawX >= 0 && rawX <= 1.5 && rawY >= 0 && rawY <= 1.5) {
    *outX = rawX * bw;
    *outY = rawY * bh;
    return;
  }
  uint32_t dw = 0;
  uint32_t dh = 0;
  wwn_modeb_desktop_size(&dw, &dh);
  if (dw > 0 && dh > 0 && (rawX > bw * 1.5 || rawY > bh * 1.5)) {
    *outX = rawX * bw / (double)dw;
    *outY = rawY * bh / (double)dh;
    return;
  }
  *outX = rawX;
  *outY = rawY;
}

static void wwn_hid_emit(int32_t touchId, int state, double rawX, double rawY) {
  double viewX = 0;
  double viewY = 0;
  wwn_map_hid_point(rawX, rawY, &viewX, &viewY);
  static int sLog;
  if (sLog < 8) {
    sLog += 1;
    WWNLog("MODEB", @"hid steal id=%d state=%d raw=%.2f,%.2f view=%.1f,%.1f",
           (int)touchId, state, rawX, rawY, viewX, viewY);
  }
  if (gHidSink) {
    gHidSink(touchId, state, viewX, viewY);
  }
}

static void wwn_hid_handle(void *target, void *refcon, IOHIDEventSystemClientRef client,
                           IOHIDEventRef event) {
  (void)target;
  (void)refcon;
  (void)client;
  if (!event || !gHidType || !gHidFloat) {
    return;
  }
  uint32_t type = gHidType(event);
  if (type != kWWNHidDigitizer) {
    CFArrayRef kids = gHidChildren ? gHidChildren(event) : NULL;
    if (kids) {
      CFIndex n = CFArrayGetCount(kids);
      for (CFIndex i = 0; i < n; i++) {
        wwn_hid_handle(target, refcon, client,
                       (IOHIDEventRef)CFArrayGetValueAtIndex(kids, i));
      }
    }
    return;
  }
  int32_t touchId = 1;
  if (gHidInt) {
    CFIndex idx = gHidInt(event, kWWNHidFieldIndex);
    if (idx > 0) {
      touchId = (int32_t)idx;
    }
  }
  double x = gHidFloat(event, kWWNHidFieldX);
  double y = gHidFloat(event, kWWNHidFieldY);
  int touching = 1;
  if (gHidInt) {
    touching = gHidInt(event, kWWNHidFieldTouch) != 0;
  }
  static uint8_t sDown[16];
  uint32_t slot = (uint32_t)touchId & 15u;
  int state = 2;
  if (touching && !sDown[slot]) {
    state = 1;
    sDown[slot] = 1;
  } else if (!touching && sDown[slot]) {
    state = 0;
    sDown[slot] = 0;
  } else if (!touching) {
    return;
  }
  wwn_hid_emit(touchId, state, x, y);
}

static Boolean wwn_hid_filter(void *target, void *refcon, void *service,
                              IOHIDEventRef event) {
  (void)service;
  if (!event || !gHidType) {
    return false;
  }
  uint32_t type = gHidType(event);
  CFArrayRef kids = gHidChildren ? gHidChildren(event) : NULL;
  BOOL digitizer = type == kWWNHidDigitizer;
  if (!digitizer && kids) {
    CFIndex n = CFArrayGetCount(kids);
    for (CFIndex i = 0; i < n; i++) {
      if (gHidType((IOHIDEventRef)CFArrayGetValueAtIndex(kids, i)) ==
          kWWNHidDigitizer) {
        digitizer = YES;
        break;
      }
    }
  }
  if (!digitizer) {
    return false;
  }
  /* Swallow so SpringBoard / backboardd do not keep the digitizer.
   * Deliver to our sink here in case the filter runs before the
   * client callback. */
  wwn_hid_handle(target, refcon, gHidClient, event);
  return true;
}

static int32_t wwn_hid_start(void) {
  void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
                       RTLD_NOW | RTLD_LOCAL);
  if (!iokit) {
    WWNLog("MODEB", @"claim HID: IOKit missing");
    return ENOENT;
  }
  FnHidCreateType createType =
      (FnHidCreateType)dlsym(iokit, "IOHIDEventSystemClientCreateWithType");
  FnHidCreate create = (FnHidCreate)dlsym(iokit, "IOHIDEventSystemClientCreate");
  FnHidRegister registerCb =
      (FnHidRegister)dlsym(iokit, "IOHIDEventSystemClientRegisterEventCallback");
  FnHidRegisterFilter registerFilter = (FnHidRegisterFilter)dlsym(
      iokit, "IOHIDEventSystemClientRegisterEventFilter");
  FnHidSchedule schedule =
      (FnHidSchedule)dlsym(iokit, "IOHIDEventSystemClientScheduleWithRunLoop");
  gHidUnschedule =
      (FnHidUnschedule)dlsym(iokit, "IOHIDEventSystemClientUnscheduleFromRunLoop");
  gHidFloat = (FnHidFloat)dlsym(iokit, "IOHIDEventGetFloatValue");
  gHidInt = (FnHidInt)dlsym(iokit, "IOHIDEventGetIntegerValue");
  gHidType = (FnHidType)dlsym(iokit, "IOHIDEventGetType");
  gHidChildren = (FnHidChildren)dlsym(iokit, "IOHIDEventGetChildren");
  if ((!createType && !create) || !registerCb || !schedule || !gHidFloat ||
      !gHidType) {
    WWNLog("MODEB", @"claim HID: symbols missing");
    return ENOSYS;
  }
  /* type 0 = admin when the entitlement is present. */
  if (createType) {
    gHidClient = createType(kCFAllocatorDefault, 0, NULL);
  }
  if (!gHidClient && create) {
    gHidClient = create(kCFAllocatorDefault);
  }
  if (!gHidClient) {
    WWNLog("MODEB", @"claim HID: client create failed");
    return EPERM;
  }
  registerCb(gHidClient, (void *)wwn_hid_handle, NULL, NULL);
  if (registerFilter) {
    registerFilter(gHidClient, wwn_hid_filter, NULL, NULL);
  }
  schedule(gHidClient, CFRunLoopGetMain(), kCFRunLoopCommonModes);
  WWNLog("MODEB", @"claim HID: digitizer steal armed filter=%d",
         registerFilter != NULL);
  return 0;
}

static void wwn_hid_stop(void) {
  if (!gHidClient) {
    return;
  }
  if (gHidUnschedule) {
    gHidUnschedule(gHidClient, CFRunLoopGetMain(), kCFRunLoopCommonModes);
  }
  CFRelease(gHidClient);
  gHidClient = NULL;
  WWNLog("MODEB", @"claim HID: released");
}

void wwn_modeb_set_hid_sink(WWNModeBHidSink sink) { gHidSink = sink; }

int32_t wwn_modeb_claim_active(void) { return gClaimed ? 1 : 0; }

int32_t wwn_modeb_claim_host(void) {
  if (gClaimed) {
    return 0;
  }
  [UIApplication sharedApplication].idleTimerDisabled = YES;
  /* Do not SIGSTOP SpringBoard or backboardd. IOMFB swap, CADisplayLink,
     and UIScene activation go through backboardd. Parking it hangs
     wwn_modeb_desktop_start on the last SpringBoard frame (build 32).
     Exclusive IOMFB + HID steal owns the panel. */
  gParkedCount = 0;
  int32_t hid = wwn_hid_start();
  gClaimed = YES;
  WWNLog("MODEB", @"claim host hid=%d (no process park)", (int)hid);
  return 0;
}

int32_t wwn_modeb_release_host(void) {
  if (!gClaimed) {
    return 0;
  }
  wwn_hid_stop();
  static const char *kResume[] = {"backboardd", "SpringBoard"};
  for (size_t i = 0; i < sizeof(kResume) / sizeof(kResume[0]); i++) {
    pid_t pid = wwn_pid_named(kResume[i]);
    if (pid > 0) {
      wwn_resume_pid(pid, kResume[i]);
    }
  }
  for (size_t i = 0; i < gParkedCount; i++) {
    wwn_resume_pid(gParked[i], "parked");
    gParked[i] = 0;
  }
  gParkedCount = 0;
  [UIApplication sharedApplication].idleTimerDisabled = NO;
  gClaimed = NO;
  WWNLog("MODEB", @"claim host released");
  return 0;
}
#endif
