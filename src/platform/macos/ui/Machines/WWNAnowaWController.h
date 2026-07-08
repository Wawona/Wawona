//
// WWNAnowaWController.h — Wawona-side lifecycle owner for the App Bridge
// (anowaW) on macOS.
//
// Thin coordinator between Wawona's machine-session lifecycle and the
// wwn-anowaW `AnowawMacBridge` capture/inject shim. It attaches the bridge to
// the nested Weston socket once the desktop machine is up, and tears it down on
// disconnect. Bridged AppKit windows appear as xdg_toplevels inside the nested
// desktop.
//
#import <Foundation/Foundation.h>

@class WWNMachineProfile;

NS_ASSUME_NONNULL_BEGIN

/// Deterministic nested Weston socket name. MUST match the `--socket=` argument
/// passed to nested weston in WWNWaypipeRunner and the Android
/// AnowawSession.NESTED_SOCKET / android_jni.c value.
extern NSString *const kWWNAnowaWNestedSocket;

@interface WWNAnowaWController : NSObject

+ (instancetype)sharedController;

/// True while a bridge is attached to the nested desktop.
@property (nonatomic, readonly) BOOL active;

/// Attach the anowaW bridge to the nested Weston desktop for @c profile. No-op
/// unless the App Bridge preference is enabled and the profile is eligible
/// (local-only nested-Weston native machine). Safe to call repeatedly.
- (void)attachForProfile:(WWNMachineProfile *)profile;

/// Bridge a chosen AppKit app (by bundle id) into the nested desktop.
- (void)bridgeAppWithBundleId:(NSString *)bundleId;

/// Tear down the bridge and all bridged app toplevels.
- (void)detach;

@end

NS_ASSUME_NONNULL_END
