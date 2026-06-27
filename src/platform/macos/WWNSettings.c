#include "WWNSettings.h"
#include <string.h>

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
    .openglDriver = "system"
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
    return g_config.vulkanDrivers;
}

bool WWNSettings_GetEGLDriversEnabled(void) {
  // EGL disabled - Vulkan only mode
  return false;
}

// Graphics Driver Selection
const char *WWNSettings_GetVulkanDriver(void) {
  return g_config.vulkanDriver[0] ? g_config.vulkanDriver : "system";
}

const char *WWNSettings_GetOpenGLDriver(void) {
  return g_config.openglDriver[0] ? g_config.openglDriver : "system";
}

// Dmabuf Support
bool WWNSettings_GetDmabufEnabled(void) {
    // Usually enabled if Vulkan is enabled, or based on platform
    return true; 
}

#endif
