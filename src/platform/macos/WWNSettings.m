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
      !wwnDriverIs(vulkan, "kosmickrisp"))
    vulkan = "moltenvk";
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
