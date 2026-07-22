#pragma once

#include <TargetConditionals.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Mirrors Sources/WawonaModel/PlatformCapabilities.swift for ObjC call sites.
static inline bool WWNPlatformAllowsVirtualMachine(void) {
#if TARGET_OS_TV || TARGET_OS_WATCH
  return false;
#else
  return true;
#endif
}

static inline bool WWNPlatformAllowsContainer(void) {
#if TARGET_OS_TV || TARGET_OS_WATCH
  return false;
#else
  return true;
#endif
}

static inline bool WWNPlatformAllowsGpuStack(void) {
#if TARGET_OS_TV || TARGET_OS_WATCH
  return false;
#else
  return true;
#endif
}

static inline bool WWNPlatformAllowsAnowaW(void) {
#if TARGET_OS_OSX
  return true;
#else
  return false;
#endif
}

/// Desktop / LockScreen / Mode B iland — macOS (+ Android separately). Never
/// iOS/iPadOS/tvOS/watchOS/visionOS.
static inline bool WWNPlatformAllowsDesktopReplacement(void) {
#if TARGET_OS_OSX
  return true;
#else
  return false;
#endif
}

static inline bool WWNPlatformAllowsMultiWindowScenes(void) {
#if TARGET_OS_VISION
  return true;
#elif TARGET_OS_IOS && !TARGET_OS_MACCATALYST
  /* iPad only — callers must still check UIUserInterfaceIdiomPad at runtime
   * (see WWNEnablePerWindowHosting / PlatformCapabilities.allowsMultiWindowScenes). */
  return true;
#elif TARGET_OS_OSX
  return true;
#else
  return false;
#endif
}

/// Compile-time gate for tabbed client chrome. Phone idiom is runtime-checked
/// in WWNSceneDelegate (-usesClientTabChrome). Tabs = Wayland clients only.
static inline bool WWNPlatformAllowsClientTabs(void) {
#if TARGET_OS_TV || TARGET_OS_WATCH
  return true;
#elif TARGET_OS_IOS && !TARGET_OS_VISION
  return true; /* phone only at runtime; iPad uses multi-window scenes */
#else
  return false;
#endif
}

#ifdef __cplusplus
}
#endif
