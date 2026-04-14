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

// Legacy Apple UI bridge headers needed by Swift files in src/platform/macos/ui.
#if __has_include("ui/Machines/WWNMachineProfileStore.h")
#import "ui/Machines/WWNMachineProfileStore.h"
#endif
#if __has_include("ui/Machines/WWNMachinesCoordinator.h")
#import "ui/Machines/WWNMachinesCoordinator.h"
#endif
#if __has_include("ui/Settings/WWNPreferencesManager.h")
#import "ui/Settings/WWNPreferencesManager.h"
#endif
#if __has_include("ui/Settings/WWNPreferences.h")
#import "ui/Settings/WWNPreferences.h"
#endif
#if __has_include("ui/Settings/WWNWaypipeRunner.h")
#import "ui/Settings/WWNWaypipeRunner.h"
#endif
#if __has_include("ui/Settings/WWNSettingsSplitViewController.h")
#import "ui/Settings/WWNSettingsSplitViewController.h"
#endif

#endif /* WWN_Bridging_Header_h */
