{ lib, pkgs, wawonaSrc, ... }:

rec {
  # Common dependencies
  commonDeps = [
    "waypipe"
    "zstd"
    "lz4"
  ];

  # Source files shared across macOS AND iOS builds.
  # All ObjC filenames use the WWN prefix (global rename from Wawona* in 2026).
  # macOS-only files (WWNWindow*, WWNMacOS*, WWNPopupHost*) live in macos.nix.
  # iOS-only files (WWNCompositorView_ios*, WWNSceneDelegate*) live in ios.nix.
  commonSources = [
    # Platform bridge (shared between macOS and iOS)
    "src/platform/macos/main.m"
    "src/platform/macos/WWNCompositorBridge.m"
    "src/platform/macos/WWNCompositorBridge.h"
    "src/platform/macos/WWNSettings.h"
    "src/platform/macos/WWNSettings.m"
    "src/platform/macos/WWNSettings.c"
    "src/platform/macos/WWNPlatformCallbacks.m"
    "src/platform/macos/WWNPlatformCallbacks.h"
    "src/platform/macos/WWNRustBridge.h"
    # Apple platform UI
    "src/platform/macos/ui/Helpers/WWNImageLoader.m"
    "src/platform/macos/ui/Helpers/WWNImageLoader.h"
    "src/platform/macos/ui/Machines/WWNMachineProfileStore.m"
    "src/platform/macos/ui/Machines/WWNMachineProfileStore.h"
    "src/platform/macos/ui/Machines/WWNMachinesCoordinator.m"
    "src/platform/macos/ui/Machines/WWNMachinesCoordinator.h"
    "src/platform/macos/ui/Settings/WWNPreferences.m"
    "src/platform/macos/ui/Settings/WWNPreferences.h"
    "src/platform/macos/ui/Settings/WWNPreferencesManager.m"
    "src/platform/macos/ui/Settings/WWNPreferencesManager.h"
    "src/platform/macos/ui/About/WWNAboutPanel.m"
    "src/platform/macos/ui/About/WWNAboutPanel.h"
    "src/platform/macos/ui/Settings/WWNSettingsDefines.h"
    "src/platform/macos/ui/Settings/WWNSettingsModel.m"
    "src/platform/macos/ui/Settings/WWNSettingsModel.h"
    "src/platform/macos/ui/Settings/WWNWaypipeRunner.m"
    "src/platform/macos/ui/Settings/WWNWaypipeRunner.h"
    "src/platform/macos/ui/Settings/WWNSSHClient.m"
    "src/platform/macos/ui/Settings/WWNSSHClient.h"
    "src/platform/macos/ui/Settings/WWNSettingsSplitViewController.m"
    "src/platform/macos/ui/Settings/WWNSettingsSplitViewController.h"
    "src/platform/macos/ui/Settings/WWNSettingsSidebarViewController.m"
    "src/platform/macos/ui/Settings/WWNSettingsSidebarViewController.h"
  ];


  # Helper to filter source files that exist
  filterSources = sources: lib.filter (f: 
    if lib.hasPrefix "/" f then lib.pathExists f
    else lib.pathExists (wawonaSrc + "/" + f)
  ) sources;

  # Compiler flags from CMakeLists.txt
  commonCFlags = [
    "-Wall"
    "-Wextra"
    "-Wpedantic"
    "-Werror"
    "-Wstrict-prototypes"
    "-Wmissing-prototypes"
    "-Wold-style-definition"
    "-Wmissing-declarations"
    "-Wuninitialized"
    "-Winit-self"
    "-Wpointer-arith"
    "-Wcast-qual"
    "-Wwrite-strings"
    "-Wconversion"
    "-Wsign-conversion"
    "-Wformat=2"
    "-Wformat-security"
    "-Wundef"
    "-Wshadow"
    "-Wstrict-overflow=5"
    "-Wswitch-default"
    "-Wswitch-enum"
    "-Wunreachable-code"
    "-Wfloat-equal"
    "-Wstack-protector"
    "-fstack-protector-strong"
    "-fPIC"
    "-D_FORTIFY_SOURCE=2"
    "-DUSE_RUST_CORE=1"
    # Suppress warnings
    "-Wno-unused-parameter"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-sign-conversion"
    "-Wno-implicit-float-conversion"
    "-Wno-missing-field-initializers"
    "-Wno-format-nonliteral"
    "-Wno-deprecated-declarations"
    "-Wno-cast-qual"
    "-Wno-empty-translation-unit"
    "-Wno-format-pedantic"
  ];

  # Apple-only deployment target flag (not valid for Android)
  appleCFlags = [ "-mmacosx-version-min=14.0" ];

  commonObjCFlags = [
    "-Wall"
    "-Wextra"
    "-Wpedantic"
    "-Wuninitialized"
    "-Winit-self"
    "-Wpointer-arith"
    "-Wcast-qual"
    "-Wformat=2"
    "-Wformat-security"
    "-Wundef"
    "-Wshadow"
    "-Wstack-protector"
    "-fstack-protector-strong"
    "-fobjc-arc"
    "-Wno-unused-parameter"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-implicit-float-conversion"
    "-Wno-deprecated-declarations"
    "-Wno-cast-qual"
    "-Wno-format-nonliteral"
    "-Wno-format-pedantic"
  ];

  releaseCFlags = [
    "-O3"
    "-DNDEBUG"
    "-flto"
  ];
  releaseObjCFlags = [
    "-O3"
    "-DNDEBUG"
    "-flto"
  ];

  debugCFlags = [
    "-g"
    "-O0"
    "-fno-omit-frame-pointer"
  ];
}
