#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * System Integrity Protection (SIP) state, as required by the wwn-iland "Mode B"
 * SkyLight/WindowServer replacement used by macOS Desktop Replacement.
 *
 * Mode B unloads Apple's WindowServer and injects `libwayland-mac.dylib`
 * (Dobby + AMFI bypass). That needs SIP **fully disabled** (`csrutil disable`
 * in Recovery). `csrutil enable --without debug` is not enough:
 * `launchctl bootout` of WindowServer returns 150 when only Debugging
 * Restrictions are off.
 *
 * Detection mirrors the plugin-playground Configurator GUI (feat/sip-detection):
 * it shells out to `csrutil status` and classifies the output. Partial disable
 * is reported so Settings can tell the user to finish `csrutil disable`.
 */
typedef NS_ENUM(NSInteger, WWNSipStatusType) {
  WWNSipStatusEnabled,
  WWNSipStatusDisabled,
  WWNSipStatusPartiallyDisabled,
  WWNSipStatusUnknown,
};

@interface WWNSipStatus : NSObject

/** Run `csrutil status` and classify the result. */
+ (WWNSipStatusType)current;

/** Human-readable label for Settings and CLI. Fully off is "Fully Disabled". */
+ (NSString *)describe:(WWNSipStatusType)status;

/**
 * Whether the current SIP configuration permits wwn-iland Mode B (desktop
 * replacement). True only when SIP is fully disabled.
 */
+ (BOOL)allowsDesktopReplacement:(WWNSipStatusType)status;

/** Full how-to text for Desktop Replacement SIP requirements (Settings alert). */
+ (NSString *)desktopReplacementHowToMessage;

@end

NS_ASSUME_NONNULL_END
