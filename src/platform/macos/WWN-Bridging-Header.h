//
//  WWN-Bridging-Header.h
//  Bridging header for Swift ↔ C interop (zero ObjC product classes).
//

#ifndef WWN_Bridging_Header_h
#define WWN_Bridging_Header_h

// UniFFI C header when available in this build path.
#if __has_include("wwnFFI.h")
#import "wwnFFI.h"
#endif

// Pure C / typedef surface only. Do not import ObjC @interface headers for
// types that now live in Sources/WawonaApple (WWNCompositorBridge,
// WWNMachineProfile, WWNWaypipeRunner, Settings, etc.).
#if __has_include("ui/Settings/WWNSettingsDefines.h")
#import "ui/Settings/WWNSettingsDefines.h"
#endif

#endif /* WWN_Bridging_Header_h */
