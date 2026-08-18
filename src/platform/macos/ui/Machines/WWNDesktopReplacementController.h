//
// WWNDesktopReplacementController.h
// Wawona. MacOS only
//
// Engages wwn-iland Mode B (libwayland-mac.dylib via DYLD_INSERT_LIBRARIES +
// Dobby) when SIP permits and Desktop Replacement is enabled in Settings.
// Otherwise callers stay on Mode A (in-window libiland_userland.a).
//

#import <Foundation/Foundation.h>

@class WWNMachineProfile;

NS_ASSUME_NONNULL_BEGIN

@interface WWNDesktopReplacementController : NSObject

+ (instancetype)sharedController;

/** SIP allows Mode B AND DesktopReplacementEnabled is on. */
- (BOOL)shouldEngageModeB;

/** True when profile is the configured Desktop Replacement machine. */
- (BOOL)isDesktopMachine:(WWNMachineProfile *)profile;

/**
 * Absolute path to bundled libwayland-mac.dylib, or nil if this build did not
 * ship Mode B (store-safe / Mode A-only).
 */
- (nullable NSString *)bundledDylibPath;

/**
 * Launch the Desktop machine's nested compositor with Mode B insert
 * (privileged). Unloads Apple's WindowServer and starts a KeepAlive
 * LaunchDaemon. Returns YES if the Mode B session was started (or already
 * running). This is a live takeover, not a logout/login handoff.
 */
- (BOOL)engageForProfile:(WWNMachineProfile *)profile
                   error:(NSError *_Nullable *_Nullable)error;

/**
 * Engage the machine stored in DesktopReplacementMachineId. Settings uses
 * this after the user turns the toggle on.
 */
- (BOOL)engageSelectedDesktopMachine:(NSError *_Nullable *_Nullable)error;

/**
 * Stop the Mode B compositor, boot out the LaunchDaemon, and reload Apple's
 * WindowServer.
 */
- (void)disengage;

/** Clear DesktopReplacementEnabled when SIP no longer allows Mode B. */
- (BOOL)reconcilePrefsWithCurrentSip;

@end

NS_ASSUME_NONNULL_END
