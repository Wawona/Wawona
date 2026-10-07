// Bridging header for Wawona watchOS target.
// Pure C / UniFFI only. Swift types live in Sources/WawonaApple + WawonaWatch.

#ifndef WWNWatch_Bridging_Header_h
#define WWNWatch_Bridging_Header_h

#if __has_include("wwnFFI.h")
#import "wwnFFI.h"
#endif

#if __has_include("WWNMiniWaylandServer.h")
#import "WWNMiniWaylandServer.h"
#endif

#endif /* WWNWatch_Bridging_Header_h */
