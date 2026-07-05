#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * System Integrity Protection (SIP) state, as required by the wwn-iland "Mode B"
 * SkyLight/WindowServer replacement used by macOS Desktop Replacement.
 *
 * Mode B injects into system-signed processes (Dobby + AMFI bypass), which the
 * kernel only permits when debugging restrictions are lifted — i.e. SIP either
 * fully disabled or partially disabled via `csrutil enable --without debug`.
 *
 * Detection mirrors the plugin-playground Configurator GUI (feat/sip-detection):
 * it shells out to `csrutil status` and classifies the output. Partial disable
 * ("Debugging Restrictions: disabled") is the recommended, minimal configuration.
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

/** Human-readable label for a SIP status (for Settings display). */
+ (NSString *)describe:(WWNSipStatusType)status;

/**
 * Whether the current SIP configuration permits wwn-iland Mode B (desktop
 * replacement). True for fully disabled or partially disabled (debug off).
 */
+ (BOOL)allowsDesktopReplacement:(WWNSipStatusType)status;

/** Full how-to text for Desktop Replacement SIP requirements (Settings alert). */
+ (NSString *)desktopReplacementHowToMessage;

@end

NS_ASSUME_NONNULL_END
