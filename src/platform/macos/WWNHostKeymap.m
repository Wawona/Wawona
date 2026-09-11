// Host layout dump. Carbon TIS + UCKeyTranslate only. No language enum.

#import "WWNHostKeymap.h"
#import "../../util/WWNLog.h"

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR && !TARGET_OS_TV &&              \
    !TARGET_OS_WATCH && !TARGET_OS_VISION
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

extern void WWNApplyHostKeyLevels(int32_t kind, const int32_t *ids,
                                  const uint32_t *levels4, size_t count);
extern void WWNCoreReloadHostKeymap(void *core);

enum { kWWNHostKeyKindMacVk = 1 };

static void *gWWNHostKeymapCore = NULL;

static BOOL WWNTranslateKvk(const UCKeyboardLayout *layout, uint16_t kvk,
                            uint32_t modifierKeyState, uint32_t *out_utf32) {
  if (!layout || !out_utf32) {
    return NO;
  }
  UInt32 dead = 0;
  UniChar chars[4] = {0};
  UniCharCount n = 0;
  OSStatus st = UCKeyTranslate(
      layout, kvk, kUCKeyActionDisplay, modifierKeyState, LMGetKbdType(),
      kUCKeyTranslateNoDeadKeysBit, &dead, 4, &n, chars);
  if (st != noErr || n == 0) {
    *out_utf32 = 0;
    return YES;
  }
  *out_utf32 = (uint32_t)chars[0];
  return YES;
}

static const UCKeyboardLayout *WWNCurrentUnicodeLayout(TISInputSourceRef *held) {
  *held = TISCopyCurrentKeyboardLayoutInputSource();
  if (!*held) {
    return NULL;
  }
  CFDataRef data = TISGetInputSourceProperty(
      *held, kTISPropertyUnicodeKeyLayoutData);
  if (!data) {
    CFRelease(*held);
    *held = NULL;
    return NULL;
  }
  return (const UCKeyboardLayout *)CFDataGetBytePtr(data);
}

void WWNHostKeymapDumpAndApply(void *core) {
  TISInputSourceRef src = NULL;
  const UCKeyboardLayout *layout = WWNCurrentUnicodeLayout(&src);
  if (!layout) {
    WWNLog("XKB", @"host dump: no kTISPropertyUnicodeKeyLayoutData");
    return;
  }

  // none, Shift, Option, Shift+Option. modifierKeyState is the high byte
  // of Carbon event modifiers (shiftKey >> 8, optionKey >> 8).
  const uint32_t mods[4] = {
      0,
      (uint32_t)(shiftKey >> 8),
      (uint32_t)(optionKey >> 8),
      (uint32_t)((shiftKey | optionKey) >> 8),
  };

  int32_t ids[128];
  uint32_t levels[128 * 4];
  size_t n = 0;
  for (uint16_t kvk = 0; kvk < 128 && n < 128; kvk++) {
    uint32_t lv[4] = {0, 0, 0, 0};
    BOOL ok = YES;
    for (int i = 0; i < 4; i++) {
      if (!WWNTranslateKvk(layout, kvk, mods[i], &lv[i])) {
        ok = NO;
        break;
      }
    }
    if (!ok || (lv[0] == 0 && lv[1] == 0)) {
      continue;
    }
    ids[n] = (int32_t)kvk;
    levels[n * 4 + 0] = lv[0];
    levels[n * 4 + 1] = lv[1];
    levels[n * 4 + 2] = lv[2];
    levels[n * 4 + 3] = lv[3];
    n++;
  }
  CFRelease(src);

  if (n == 0) {
    WWNLog("XKB", @"host dump: UCKeyTranslate produced no keys");
    return;
  }
  WWNApplyHostKeyLevels(kWWNHostKeyKindMacVk, ids, levels, n);
  if (core) {
    WWNCoreReloadHostKeymap(core);
  }
  WWNLog("XKB", @"host dump: applied %zu keys from TIS/UCKeyTranslate", n);
}

static void WWNHostKeymapTISChanged(CFNotificationCenterRef center,
                                    void *observer, CFStringRef name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
  (void)center;
  (void)observer;
  (void)name;
  (void)object;
  (void)userInfo;
  WWNHostKeymapDumpAndApply(gWWNHostKeymapCore);
}

void WWNHostKeymapStartObserving(void *core) {
  gWWNHostKeymapCore = core;
  static BOOL installed = NO;
  if (installed) {
    return;
  }
  installed = YES;
  CFNotificationCenterAddObserver(
      CFNotificationCenterGetDistributedCenter(), NULL, WWNHostKeymapTISChanged,
      kTISNotifySelectedKeyboardInputSourceChanged, NULL,
      CFNotificationSuspensionBehaviorDeliverImmediately);
}

#else

void WWNHostKeymapDumpAndApply(void *core) { (void)core; }
void WWNHostKeymapStartObserving(void *core) { (void)core; }

#endif
