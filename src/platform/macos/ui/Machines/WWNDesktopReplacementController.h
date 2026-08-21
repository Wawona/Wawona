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
 * Classic Take Over gate: Path B `/var/db/wwn-iowatchdog/claim-ok`
 * (`path=b sticky=1`) plus live Disable evidence (marker file or Path B sock
 * `status` with `done=1`). claim-ok alone is stale after Apple watchdogd is
 * re-enabled without the hook.
 */
- (BOOL)iowatchdogStickyAckPresent;

/** Short status for Settings: missing / pending / stale / ok. */
- (NSString *)iowatchdogStickyAckStatusSummary;

/**
 * Bundle dylib present, a nested compositor Desktop Machine is selected
 * (created if needed), and a Mode B launch spec can be built. Does not
 * require DesktopReplacementEnabled to already be on. Settings calls this
 * before the take-over confirmation.
 */
- (nullable NSError *)injectionPreflightError;

/**
 * Keep DesktopReplacementMachineId pointing at a nested compositor. Reuses
 * an existing weston/niri/custom profile, or creates "Weston Desktop".
 */
- (BOOL)ensureDesktopMachineSelected:(NSError *_Nullable *_Nullable)error;

/**
 * Launch the Desktop machine's nested compositor with Mode B insert
 * (privileged). Installs a root-owned helper and a tight sudoers NOPASSWD
 * rule. Does not install a login LaunchAgent. Take Over Screen Now is the
 * only activate step. Logout and the next Aqua login return normal macOS.
 * Injects into the nested compositor (niri or weston), not into
 * WindowServer. WindowServer is unloaded only after framebufferd is live.
 */
- (BOOL)engageForProfile:(WWNMachineProfile *)profile
                   error:(NSError *_Nullable *_Nullable)error;

/**
 * Engage the machine stored in DesktopReplacementMachineId. Settings uses
 * this after the user turns the toggle on.
 */
- (BOOL)engageSelectedDesktopMachine:(NSError *_Nullable *_Nullable)error;

/**
 * Full Mode B teardown. Restores Apple's WindowServer, kills the root
 * compositor and framebufferd/inputd, and removes the login LaunchAgent,
 * sudoers drop-in, helper, installed dylib, and ws-guard. Settings Disable
 * must call this. Returns NO if privileged uninstall did not finish.
 */
- (BOOL)disengage;

/**
 * After Aqua login: never unload WindowServer. Boots out any leftover
 * Mode B login LaunchAgent from older builds. Take Over Screen Now is
 * the only activate path.
 */
- (void)resumeAfterAquaLogin;

/**
 * If the Mode B compositor died and restored Aqua, show why and clear
 * DesktopReplacementEnabled so login does not immediately take over again.
 */
- (void)presentPendingSessionFailureAlert;

/** Clear DesktopReplacementEnabled when SIP no longer allows Mode B. */
- (BOOL)reconcilePrefsWithCurrentSip;

/**
 * Headless CLI. No Machines UI, no instance lock, no alerts.
 * Logs to stdout and /tmp/wawona-modeb-cli.log. Returns a process exit code.
 */
- (int)cliStatus;
- (int)cliEngageKeepWindowServer:(BOOL)keepWindowServer;
- (int)cliDisengage;
/** Restage helper + dylib for this build. Does not take over the screen. */
- (int)cliStage;

@end

NS_ASSUME_NONNULL_END
