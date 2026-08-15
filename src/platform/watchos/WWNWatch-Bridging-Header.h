// Bridging header for Wawona watchOS target.
// Exposes the watchOS compositor bridge and WatchKit settings UI to Swift.

#ifndef WWNWatch_Bridging_Header_h
#define WWNWatch_Bridging_Header_h

#import "WWNWatchCompositorBridge.h"
#import "ui/Settings/WWNWatchSettingsBridge.h"
#import "WWNWatchPreferencesCoordinator.h"
#import "../macos/ui/Helpers/WWNSSHKeygen.h"
#import "../../util/WWNStartupLogger.h"

#endif /* WWNWatch_Bridging_Header_h */
