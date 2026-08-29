#include "WWNSettings.h"
#include <string.h>

/*
 * wwn_startup_log_sink. Default NULL definition for non-iOS builds.
 * On iOS/tvOS/visionOS/watchOS, WWNStartupLogger.m provides the real
 * function pointer. On macOS there is no startup log overlay so the sink
 * stays NULL and all WWNLog() calls fall through to dprintf only.
 */
#if !TARGET_OS_IPHONE
void (*wwn_startup_log_sink)(const char *module, const char *msg) = NULL;
int wwn_log_quiet = 0;
#endif

#ifndef __APPLE__

static WWNSettingsConfig g_config = {
    .forceServerSideDecorations = false,
    .autoRetinaScaling = true,
    .respectSafeArea = true,
    .renderMacOSPointer = true,
    .universalClipboard = true,
    .colorSyncSupport = true,
    .nestedCompositorsSupport = true,
    .multipleClients = true,
    .waypipeRSSupport = true,
    .enableTCPListener = false,
    .tcpPort = 0,
    .renderingBackend = 0,
    .vulkanDrivers = false,
    .eglDrivers = false,
    .vulkanDriver = "system",
    .openglDriver = "system",
    .compositorBackend = "auto"
};

void WWNSettings_UpdateConfig(const WWNSettingsConfig *config) {
    if (config) {
        g_config = *config;
    }
}

// Universal Clipboard
bool WWNSettings_GetUniversalClipboardEnabled(void) {
    return g_config.universalClipboard;
}

// Window Decorations
bool WWNSettings_GetForceServerSideDecorations(void) {
    return g_config.forceServerSideDecorations;
}

// Display
bool WWNSettings_GetAutoRetinaScalingEnabled(void) {
    return g_config.autoRetinaScaling;
}

bool WWNSettings_GetRespectSafeArea(void) {
    return g_config.respectSafeArea;
}

// Color Management
bool WWNSettings_GetColorSyncSupportEnabled(void) {
    return g_config.colorSyncSupport;
}

// Nested Compositors
bool WWNSettings_GetNestedCompositorsSupportEnabled(void) {
    return g_config.nestedCompositorsSupport;
}

bool WWNSettings_GetUseMetal4ForNested(void) {
    return g_config.useMetal4ForNested;
}

// Input
bool WWNSettings_GetRenderMacOSPointer(void) {
    return g_config.renderMacOSPointer;
}

bool WWNSettings_GetSwapCmdAsCtrl(void) {
    return g_config.swapCmdAsCtrl;
}

// Client Management
bool WWNSettings_GetMultipleClientsEnabled(void) {
    return g_config.multipleClients;
}

// Waypipe
bool WWNSettings_GetWaypipeRSSupportEnabled(void) {
    return g_config.waypipeRSSupport;
}

// Network / Remote Access
bool WWNSettings_GetEnableTCPListener(void) {
    return g_config.enableTCPListener;
}

int WWNSettings_GetTCPListenerPort(void) {
    return g_config.tcpPort;
}

// Rendering Backend Flags
int WWNSettings_GetRenderingBackend(void) {
    return g_config.renderingBackend;
}

bool WWNSettings_GetVulkanDriversEnabled(void) {
    return WWNSettings_ResolveGraphicsDriverSelection().vulkanEnabled;
}

bool WWNSettings_GetEGLDriversEnabled(void) {
  return WWNSettings_ResolveGraphicsDriverSelection().openGLEnabled;
}

// Graphics Driver Selection
const char *WWNSettings_GetVulkanDriver(void) {
  return g_config.vulkanDriver[0] ? g_config.vulkanDriver : "system";
}

const char *WWNSettings_GetOpenGLDriver(void) {
  return g_config.openglDriver[0] ? g_config.openglDriver : "system";
}

static bool wwnDriverIs(const char *value, const char *expected) {
  return value && strcmp(value, expected) == 0;
}

const char *WWNSettings_GetCompositorBackend(void) {
  return g_config.compositorBackend[0] ? g_config.compositorBackend : "auto";
}

const char *WWNSettings_ResolveCompositorBackend(void) {
  const char *choice = WWNSettings_GetCompositorBackend();
  if (wwnDriverIs(choice, "drm")) {
    /* DRM presents through iland; without a GL stack there is nothing behind
     * it, so fall back rather than hang a nested compositor. */
    if (wwnDriverIs(WWNSettings_GetOpenGLDriver(), "none"))
      return "wayland";
    return "drm";
  }
  if (wwnDriverIs(choice, "wayland"))
    return "wayland";
  return "wayland"; /* auto */
}

WWNGraphicsDriverSelection WWNSettings_ResolveGraphicsDriverSelection(void) {
  const char *vulkan = WWNSettings_GetVulkanDriver();
  const char *openGL = WWNSettings_GetOpenGLDriver();

  if (!wwnDriverIs(vulkan, "none") && !wwnDriverIs(vulkan, "system") &&
      !wwnDriverIs(vulkan, "swiftshader"))
    vulkan = "system";
  if (!wwnDriverIs(openGL, "none") && !wwnDriverIs(openGL, "system") &&
      !wwnDriverIs(openGL, "angle"))
    openGL = "system";

  return (WWNGraphicsDriverSelection){
      .vulkanDriver = vulkan,
      .openGLDriver = openGL,
      .vulkanEnabled = !wwnDriverIs(vulkan, "none"),
      .openGLEnabled = !wwnDriverIs(openGL, "none"),
  };
}

// Dmabuf Support
bool WWNSettings_GetDmabufEnabled(void) {
    // Usually enabled if Vulkan is enabled, or based on platform
    return true; 
}

#endif
