//
//  WWN-Bridging-Header.h
//  Bridging header for Swift-Objective-C interop
//

#ifndef WWN_Bridging_Header_h
#define WWN_Bridging_Header_h

// Import UniFFI C header for Swift access when available in this build path.
#if __has_include("wwnFFI.h")
#import "wwnFFI.h"
#endif
#import "WWNCompositorBridge.h"
#import "WWNPlatformCallbacks.h"

#if __has_include("ui/Helpers/WWNSSHKeygen.h")
#import "ui/Helpers/WWNSSHKeygen.h"
#endif

// Legacy Apple UI bridge headers needed by Swift files in src/platform/macos/ui.
#if __has_include("ui/Machines/WWNMachineProfileStore.h")
#import "ui/Machines/WWNMachineProfileStore.h"
#endif
#if __has_include("ui/Machines/WWNMachinesCoordinator.h")
#import "ui/Machines/WWNMachinesCoordinator.h"
#endif
#if __has_include("ui/Machines/WWNMachineSessionBridge.h")
#import "ui/Machines/WWNMachineSessionBridge.h"
#endif
#if __has_include("ui/Machines/WWNCLIMachineRecipes.h")
#import "ui/Machines/WWNCLIMachineRecipes.h"
#endif
#if __has_include("ui/Settings/WWNPreferencesManager.h")
#import "ui/Settings/WWNPreferencesManager.h"
#endif
#if __has_include("ui/Settings/WWNPreferences.h")
#import "ui/Settings/WWNPreferences.h"
#endif
// Settings section/item model + setting-type enum: lets SwiftUI render the
// shared ObjC `buildSections` output (WWNUnifiedWindow redesign).
#if __has_include("ui/Settings/WWNSettingsModel.h")
#import "ui/Settings/WWNSettingsModel.h"
#endif
#if __has_include("ui/Settings/WWNSettingsDefines.h")
#import "ui/Settings/WWNSettingsDefines.h"
#endif
// Rootfs provider (Local Shell section rows, iCloud sync toggle) + its
// preference key constant.
#if __has_include("WWNRootfsProvider.h")
#import "WWNRootfsProvider.h"
#endif
#if __has_include("WWNRootfsICloudSync.h")
#import "WWNRootfsICloudSync.h"
#endif
#if __has_include("ui/Settings/WWNWaypipeRunner.h")
#import "ui/Settings/WWNWaypipeRunner.h"
#endif
#if __has_include("ui/Settings/WWNSettingsSplitViewController.h")
#import "ui/Settings/WWNSettingsSplitViewController.h"
#endif

#endif /* WWN_Bridging_Header_h */
