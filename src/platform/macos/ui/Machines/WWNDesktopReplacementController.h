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
 * Launch the Desktop machine's nested Weston with Mode B insert (privileged).
 * Returns YES if the Mode B session was started (or already running).
 */
- (BOOL)engageForProfile:(WWNMachineProfile *)profile
                   error:(NSError *_Nullable *_Nullable)error;

/** Stop the Mode B weston task if we own it. */
- (void)disengage;

/** Clear DesktopReplacementEnabled when SIP no longer allows Mode B. */
- (BOOL)reconcilePrefsWithCurrentSip;

@end

NS_ASSUME_NONNULL_END
