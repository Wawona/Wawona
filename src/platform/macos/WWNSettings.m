#include "WWNSettings.h"

#ifdef __APPLE__
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
  return [[WWNPreferencesManager sharedManager] vulkanDriversEnabled];
}

bool WWNSettings_GetEGLDriversEnabled(void) {
  // EGL disabled - Vulkan only mode
  return false;
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

#endif
