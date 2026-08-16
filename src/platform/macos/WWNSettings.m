#include "WWNSettings.h"
#include <string.h>

#ifdef __APPLE__
#import <TargetConditionals.h>
#import "./ui/Settings/WWNPreferencesManager.h"

bool WWNSettings_GetUniversalClipboardEnabled(void) {
  return [[WWNPreferencesManager sharedManager] universalClipboardEnabled];
}

bool WWNSettings_GetForceServerSideDecorations(void) {
  return [[WWNPreferencesManager sharedManager] forceServerSideDecorations];
}

bool WWNSettings_GetAutoRetinaScalingEnabled(void) {
  // Use new unified key, fallback to legacy for backward compatibility
  return [[WWNPreferencesManager sharedManager] autoScale];
}

bool WWNSettings_GetRespectSafeArea(void) {
  return [[WWNPreferencesManager sharedManager] respectSafeArea];
}

bool WWNSettings_GetColorSyncSupportEnabled(void) {
  // Use new unified key, fallback to legacy for backward compatibility
  return [[WWNPreferencesManager sharedManager] colorOperations];
}

bool WWNSettings_GetNestedCompositorsSupportEnabled(void) {
  return
      [[WWNPreferencesManager sharedManager] nestedCompositorsSupportEnabled];
}

bool WWNSettings_GetUseMetal4ForNested(void) {
  return [[WWNPreferencesManager sharedManager] useMetal4ForNested];
}

bool WWNSettings_GetRenderMacOSPointer(void) {
  return [[WWNPreferencesManager sharedManager] renderMacOSPointer];
}

bool WWNSettings_GetSwapCmdAsCtrl(void) {
  // Use new unified key (SwapCmdWithAlt), fallback to legacy for backward
  // compatibility
  return [[WWNPreferencesManager sharedManager] swapCmdWithAlt];
}

bool WWNSettings_GetMultipleClientsEnabled(void) {
  return [[WWNPreferencesManager sharedManager] multipleClientsEnabled];
}

bool WWNSettings_GetWaypipeRSSupportEnabled(void) {
  return [[WWNPreferencesManager sharedManager] waypipeRSSupportEnabled];
}

bool WWNSettings_GetEnableTCPListener(void) {
  return [[WWNPreferencesManager sharedManager] enableTCPListener];
}

int WWNSettings_GetTCPListenerPort(void) {
  return (int)[[WWNPreferencesManager sharedManager] tcpListenerPort];
}

bool WWNSettings_GetVulkanDriversEnabled(void) {
  return WWNSettings_ResolveGraphicsDriverSelection().vulkanEnabled;
}

bool WWNSettings_GetEGLDriversEnabled(void) {
  return WWNSettings_ResolveGraphicsDriverSelection().openGLEnabled;
}

bool WWNSettings_GetDmabufEnabled(void) {
  return [[WWNPreferencesManager sharedManager] dmabufEnabled];
}

// Graphics Driver Selection - returns static buffer, copy if needed
const char *WWNSettings_GetVulkanDriver(void) {
  static char buf[32];
  NSString *s = [[WWNPreferencesManager sharedManager] vulkanDriver];
  if (s && s.length > 0 && s.length < sizeof(buf)) {
    [s getCString:buf maxLength:sizeof(buf) encoding:NSUTF8StringEncoding];
    return buf;
  }
  return "moltenvk";
}

const char *WWNSettings_GetOpenGLDriver(void) {
  static char buf[32];
  NSString *s = [[WWNPreferencesManager sharedManager] openglDriver];
  if (s && s.length > 0 && s.length < sizeof(buf)) {
    [s getCString:buf maxLength:sizeof(buf) encoding:NSUTF8StringEncoding];
    return buf;
  }
  return "angle";
}

static bool wwnDriverIs(const char *value, const char *expected) {
  return value && strcmp(value, expected) == 0;
}

WWNGraphicsDriverSelection WWNSettings_ResolveGraphicsDriverSelection(void) {
  const char *vulkan = WWNSettings_GetVulkanDriver();
  const char *openGL = WWNSettings_GetOpenGLDriver();

#if TARGET_OS_TV || TARGET_OS_WATCH
  vulkan = "none";
  openGL = "none";
#elif TARGET_OS_OSX
  if (!wwnDriverIs(vulkan, "none") && !wwnDriverIs(vulkan, "moltenvk") &&
      !wwnDriverIs(vulkan, "kosmickrisp") && !wwnDriverIs(vulkan, "swiftshader"))
    vulkan = "moltenvk";
  if (!wwnDriverIs(openGL, "none") && !wwnDriverIs(openGL, "angle"))
    openGL = "angle";
#elif TARGET_OS_SIMULATOR
  // iOS / iPadOS / visionOS *Simulator*: MoltenVK's Metal pipeline bring-up
  // fatally aborts the whole app on the headless CI simulator (the process is
  // killed with Metal domain 102. See the vkcube crash in the bundled-clients
  // matrix). The bundled SwiftShader CPU Vulkan ICD renders entirely on the CPU
  // without ever touching Metal, so default (and coerce MoltenVK to) SwiftShader
  // on the Simulator. On-device iOS does NOT bundle SwiftShader and keeps
  // MoltenVK (TARGET_OS_SIMULATOR is 0 there).
  if (wwnDriverIs(vulkan, "moltenvk") ||
      (!wwnDriverIs(vulkan, "none") && !wwnDriverIs(vulkan, "swiftshader")))
    vulkan = "swiftshader";
  if (!wwnDriverIs(openGL, "none") && !wwnDriverIs(openGL, "angle"))
    openGL = "angle";
#else
  if (!wwnDriverIs(vulkan, "none") && !wwnDriverIs(vulkan, "moltenvk"))
    vulkan = "moltenvk";
  if (!wwnDriverIs(openGL, "none") && !wwnDriverIs(openGL, "angle"))
    openGL = "angle";
#endif

  return (WWNGraphicsDriverSelection){
      .vulkanDriver = vulkan,
      .openGLDriver = openGL,
      .vulkanEnabled = !wwnDriverIs(vulkan, "none"),
      .openGLEnabled = !wwnDriverIs(openGL, "none"),
  };
}

// Bundled in-process ICD dylib name for a driver, or nil if that driver has no
// dylib in this build. In-process clients (vkcube) dlopen these directly since
// the bundle ships no Vulkan loader.
static NSString *wwnVulkanDylibName(const char *driver) {
  if (driver && strcmp(driver, "kosmickrisp") == 0)
    return @"libvulkan_kosmickrisp.dylib";
  if (driver && strcmp(driver, "moltenvk") == 0)
    return @"libMoltenVK.dylib";
  if (driver && strcmp(driver, "swiftshader") == 0)
    return @"libvk_swiftshader.dylib";
  return nil;
}

// Resolve a driver's bundled ICD dylib to an on-disk path, or nil if absent.
static NSString *wwnVulkanDylibPath(const char *driver, NSBundle *bundle) {
  NSString *name = wwnVulkanDylibName(driver);
  if (!name)
    return nil;
  NSString *candidate =
      [[bundle privateFrameworksPath] stringByAppendingPathComponent:name];
  return [[NSFileManager defaultManager] fileExistsAtPath:candidate] ? candidate
                                                                     : nil;
}

void WWNSettings_ApplyGraphicsDriverSelection(void) {
  WWNGraphicsDriverSelection selection =
      WWNSettings_ResolveGraphicsDriverSelection();
  const char *vkDriver = selection.vulkanDriver;
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *icdName = nil;
  if (vkDriver && strcmp(vkDriver, "kosmickrisp") == 0)
    icdName = @"kosmickrisp_icd";
  else if (vkDriver && strcmp(vkDriver, "moltenvk") == 0)
    icdName = @"MoltenVK_icd";
  else if (vkDriver && strcmp(vkDriver, "swiftshader") == 0)
    icdName = @"vk_swiftshader_icd";

  NSString *icd = icdName
                      ? [bundle pathForResource:icdName
                                        ofType:@"json"
                                   inDirectory:@"vulkan/icd.d"]
                      : nil;
  if (!icd && vkDriver && strcmp(vkDriver, "kosmickrisp") == 0)
    icd = [bundle pathForResource:@"MoltenVK_icd"
                           ofType:@"json"
                      inDirectory:@"vulkan/icd.d"];
  if (icd) {
    setenv("VK_DRIVER_FILES", icd.UTF8String, 1);
    setenv("VK_ICD_FILENAMES", icd.UTF8String, 1);
  } else {
    unsetenv("VK_DRIVER_FILES");
    unsetenv("VK_ICD_FILENAMES");
  }

  // The manifests above only matter to a Vulkan loader, and the bundle ships
  // ICD dylibs without one. In-process clients (vkcube) dlopen the ICD
  // directly, so hand them the resolved library path.
  NSString *icdPath = wwnVulkanDylibPath(vkDriver, bundle);
  if (icdPath)
    setenv("WWN_VULKAN_LIBRARY", icdPath.UTF8String, 1);
  else
    unsetenv("WWN_VULKAN_LIBRARY");

  // Vulkan provider fallback chain (WWN_VULKAN_LIBRARY_FALLBACKS, colon
  // separated). There is no Vulkan loader in the bundle, so vkcube emulates the
  // loader's multi-ICD behaviour: it tries the selected ICD, then these, until
  // one enumerates a physical device. On a headless CI VM / Simulator the
  // selected driver (default KosmicKrisp) can load yet find no device; hardware
  // MoltenVK is tried next, then the SwiftShader CPU device that always
  // enumerates. Order is hardware-before-software, excluding the selection.
  const char *fallbackOrder[] = {"moltenvk", "swiftshader"};
  NSMutableArray<NSString *> *fallbacks = [NSMutableArray array];
  for (size_t i = 0; i < sizeof(fallbackOrder) / sizeof(fallbackOrder[0]); i++) {
    if (vkDriver && strcmp(vkDriver, fallbackOrder[i]) == 0)
      continue;
    NSString *p = wwnVulkanDylibPath(fallbackOrder[i], bundle);
    if (p && (!icdPath || ![p isEqualToString:icdPath]))
      [fallbacks addObject:p];
  }
  if (fallbacks.count > 0)
    setenv("WWN_VULKAN_LIBRARY_FALLBACKS",
           [fallbacks componentsJoinedByString:@":"].UTF8String, 1);
  else
    unsetenv("WWN_VULKAN_LIBRARY_FALLBACKS");

  const char *glDriver = selection.openGLDriver;
  setenv("WWN_OPENGL_DRIVER", glDriver ?: "none", 1);
  if (glDriver && strcmp(glDriver, "angle") == 0) {
    setenv("ANGLE_DEFAULT_PLATFORM", "metal", 1);
    unsetenv("WWN_DISABLE_EGL");
  } else if (!glDriver || strcmp(glDriver, "none") == 0) {
    setenv("WWN_DISABLE_EGL", "1", 1);
    unsetenv("ANGLE_DEFAULT_PLATFORM");
  } else {
    unsetenv("WWN_DISABLE_EGL");
    unsetenv("ANGLE_DEFAULT_PLATFORM");
  }
}

#endif
