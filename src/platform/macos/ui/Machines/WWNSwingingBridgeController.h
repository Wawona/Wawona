//
// WWNSwingingBridgeController.h. Wawona-side lifecycle owner for
// Wawona Swinging Bridge (formerly anowaW) on macOS.
//
// Thin coordinator between Wawona's machine-session lifecycle and the
// Wawona-Swinging-Bridge `AnowawMacBridge` capture/inject shim (legacy C/ObjC
// ABI name). It attaches the bridge to the nested Weston socket once the
// desktop machine is up, and tears it down on disconnect. Bridged AppKit
// windows appear as xdg_toplevels inside the nested desktop.
//
#import <Foundation/Foundation.h>

@class WWNMachineProfile;

NS_ASSUME_NONNULL_BEGIN

/// Deterministic nested Weston socket name. MUST match the `--socket=` argument
/// passed to nested weston in WWNWaypipeRunner and the Android
/// SwingingBridgeSession.NESTED_SOCKET / android_jni.c value.
extern NSString *const kWWNSwingingBridgeNestedSocket;

/// Deprecated alias for ``kWWNSwingingBridgeNestedSocket``.
extern NSString *const kWWNAnowaWNestedSocket;

@interface WWNSwingingBridgeController : NSObject

+ (instancetype)sharedController;

/// True while a bridge is attached to the nested desktop.
@property (nonatomic, readonly) BOOL active;

/// Attach Swinging Bridge to the nested Weston desktop for @c profile. No-op
/// unless the preference is enabled and the profile is eligible
/// (local-only nested-Weston native machine). Safe to call repeatedly.
- (void)attachForProfile:(WWNMachineProfile *)profile;

/// Bridge a chosen AppKit app (by bundle id) into the nested desktop.
- (void)bridgeAppWithBundleId:(NSString *)bundleId;

/// Tear down the bridge and all bridged app toplevels.
- (void)detach;

@end

/// Deprecated name for ``WWNSwingingBridgeController``.
typedef WWNSwingingBridgeController WWNAnowaWController;

NS_ASSUME_NONNULL_END
