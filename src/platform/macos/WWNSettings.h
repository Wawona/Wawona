#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Universal Clipboard
bool WWNSettings_GetUniversalClipboardEnabled(void);

// Window Decorations
bool WWNSettings_GetForceServerSideDecorations(void);

// Display
bool WWNSettings_GetAutoRetinaScalingEnabled(void);
bool WWNSettings_GetRespectSafeArea(void);

// Color Management
bool WWNSettings_GetColorSyncSupportEnabled(void);

// Nested Compositors
bool WWNSettings_GetNestedCompositorsSupportEnabled(void);
bool WWNSettings_GetUseMetal4ForNested(void);

// Input
bool WWNSettings_GetRenderMacOSPointer(void);
bool WWNSettings_GetSwapCmdAsCtrl(void);

// Client Management
bool WWNSettings_GetMultipleClientsEnabled(void);

// Waypipe
bool WWNSettings_GetWaypipeRSSupportEnabled(void);

// Network / Remote Access
bool WWNSettings_GetEnableTCPListener(void);
int WWNSettings_GetTCPListenerPort(void);

// Rendering Backend Flags
int WWNSettings_GetRenderingBackend(void);
bool WWNSettings_GetVulkanDriversEnabled(void);
bool WWNSettings_GetEGLDriversEnabled(void);

// Graphics Driver Selection (Settings > Graphics > Drivers)
// Returns pointer to static buffer; valid until next call. Copy if needed.
// Values: Vulkan: "none", "moltenvk", "kosmickrisp" (Apple); "none",
// "swiftshader", "turnip", "system" (Android)
//         OpenGL: "none", "angle", "moltengl" (macOS); "none", "angle",
//         "system" (Android)
const char *WWNSettings_GetVulkanDriver(void);
const char *WWNSettings_GetOpenGLDriver(void);

// Dmabuf Support
bool WWNSettings_GetDmabufEnabled(void);

// Configuration update (mainly for Android/Linux where settings are pushed from
// platform layer)
#ifndef __APPLE__
typedef struct {
  bool universalClipboard;
  bool forceServerSideDecorations;
  bool autoRetinaScaling;
  bool respectSafeArea;
  bool colorSyncSupport;
  bool nestedCompositorsSupport;
  bool useMetal4ForNested;
  bool renderMacOSPointer;
  bool swapCmdAsCtrl;
  bool multipleClients;
  bool waypipeRSSupport;
  bool enableTCPListener;
  int tcpPort;
  // Rendering backend is handled separately or via separate flags
  int renderingBackend; // 0=Automatic, 1=Metal(Vulkan), 2=Cocoa(Surface)
  bool vulkanDrivers;   // derived from backend choice
  bool eglDrivers;      // derived from backend choice
  // Graphics driver dropdown selection (Settings > Graphics > Drivers)
  char vulkanDriver[32]; // "none", "swiftshader", "turnip", "system"
  char openglDriver[32]; // "none", "angle", "system"
} WWNSettingsConfig;

void WWNSettings_UpdateConfig(const WWNSettingsConfig *config);
#endif

#ifdef __cplusplus
}
#endif
