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

typedef NS_ENUM(NSInteger, WWNModeBVerdict) {
  WWNModeBVerdictTakeoverNow = 0,
  WWNModeBVerdictReboot = 2,
  WWNModeBVerdictBlocked = 3,
};

/** Shared Classic gate for CLI (`--mode-b-ready`) and Settings. */
@interface WWNModeBReadyReport : NSObject
@property(nonatomic, assign) WWNModeBVerdict verdict;
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) NSString *reason;
@property(nonatomic, copy) NSString *nextStep;
/** Friend-facing paragraph for Settings / alerts. No CLI recipes. */
@property(nonatomic, copy) NSString *userSummary;
/** Blocked only because SIP is not fully disabled. Show SIP How-To. */
@property(nonatomic, assign) BOOL needsSipHowTo;
/**
 * Blocked, but Prepare this Mac can stage the helper and/or arm Path B.
 * Never true when SIP blocks or this build omitted Mode B.
 */
@property(nonatomic, assign) BOOL canPrepareRequirements;
@end

/**
 * Watchdog coverage for Settings → Desktop. Friend-facing; no CLI recipes.
 * `needsHeal` means Restore Apple coverage, never Take Over.
 */
@interface WWNModeBCoverageReport : NSObject
@property(nonatomic, copy) NSString *statusLabel;
@property(nonatomic, copy) NSString *userSummary;
@property(nonatomic, copy) NSString *detailText;
@property(nonatomic, copy) NSString *pathBLabel;
@property(nonatomic, copy) NSString *safetyLabel;
@property(nonatomic, assign) BOOL coverageOk;
@property(nonatomic, assign) BOOL needsHeal;
@property(nonatomic, assign) BOOL needsReboot;
@property(nonatomic, assign) BOOL canPrepare;
@property(nonatomic, assign) BOOL pathBInstalled;
@property(nonatomic, assign) BOOL pathBLive;
@property(nonatomic, assign) BOOL dualPath;
@property(nonatomic, copy, nullable) NSString *watchdogdPid;
@property(nonatomic, copy, nullable) NSString *doctorText;
@end

/**
 * Menubar Desktop row. `state` is ready / takeover / reboot / blocked,
 * colored like Compositor: running / restarting / stopped.
 */
@interface WWNModeBMenuBarStatus : NSObject
@property(nonatomic, copy) NSString *state;
@property(nonatomic, copy) NSString *tooltip;
@property(nonatomic, assign) BOOL canTakeOver;
@property(nonatomic, assign) BOOL canRestore;
@property(nonatomic, assign) BOOL canRestartMac;
/** Play button runs Prepare this Mac (not Take Over). */
@property(nonatomic, assign) BOOL canPrepare;
@end

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
 * Keep DesktopReplacementMachineId pointing at an own-display machine
 * (weston/niri/custom, modeb-tty, or a KMS client). Reuses an existing
 * profile, or creates "Weston Desktop".
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
/** Classic gate: takeover-now (0), reboot required (2), blocked (3). */
- (int)cliReady;
/** Same gate as CLI, with exact reason text for Settings / alerts. */
- (WWNModeBReadyReport *)evaluateClassicReadiness;
/** Live Mode B compositor pid (Classic Take Over or KEEP_WS probe). */
- (BOOL)isModeBCompositorLive;
/** Classic engaged: live pid and WindowServer down. */
- (BOOL)isClassicTakeoverLive;
/**
 * Menubar Desktop row. `refreshGate=YES` when the menu opens (runs the
 * Classic helper ACK check). The 2s poll passes NO and reuses the last
 * gate, overlaying live takeover.
 */
- (WWNModeBMenuBarStatus *)menuBarDesktopStatusRefreshingGate:(BOOL)refreshGate;
/**
 * Ask loginwindow to restart via the Core Event `kAERestart` (TN QA1134).
 * That is the native Restart sheet with the 60-second countdown, not a
 * custom Wawona timer. Aqua must be up.
 */
- (BOOL)requestNativeMacOSRestart:(NSError *_Nullable *_Nullable)error;
/**
 * Stage the Mode B helper if needed and arm Path B
 * (`wwn-iowatchdog-claim-install --path-b`) with administrator
 * authorization. Never unloads watchdogd. Never Take Over.
 */
- (BOOL)installDesktopReplacementRequirements:
    (NSError *_Nullable *_Nullable)error;
/**
 * Friend-facing wizard: SIP How-To, then helper stage + Path B arm,
 * then the native Restart sheet. Never Take Over.
 */
- (void)presentDesktopReplacementPrepareFlow;
/**
 * Local + helper coverage for Settings rows. Does not prompt for
 * administrator. Does not Take Over.
 */
- (WWNModeBCoverageReport *)evaluateWatchdogCoverage;
/**
 * Runs bundled `claim-install --doctor` with administrator authorization.
 * Updates the cached report used by Settings. Never Take Over.
 */
- (nullable WWNModeBCoverageReport *)runWatchdogDoctor:
    (NSError *_Nullable *_Nullable)error;
/**
 * Runs bundled `claim-install --heal`. Restores Apple watchdog coverage.
 * Never unloads watchdogd for Classic. Never Take Over.
 */
- (BOOL)healWatchdogCoverage:(NSError *_Nullable *_Nullable)error;
- (void)presentWatchdogCoverageCheck;
- (void)presentWatchdogHealFlow;
/** CLI: same work as Prepare this Mac. Exit codes match `--mode-b-ready`. */
- (int)cliPrepare;
- (int)cliEngageKeepWindowServer:(BOOL)keepWindowServer;
- (int)cliDisengage;
/** Restage helper + dylib for this build. Does not take over the screen. */
- (int)cliStage;
/**
 * Select Desktop Replacement machine by id, name, or client alias.
 * Persists DesktopReplacementMachineId. Does not engage.
 * Aliases: weston, niri, kmscube, gbm-es2-demo, vkcube, modeb-tty.
 * Weston/niri aliases create nested compositor machines (Mode A still
 * nests them). Take Over uses their DRM backend. Wayland-only clients
 * such as opengl-cube are refused.
 */
- (int)cliSelectDesktopMachine:(NSString *)idOrName;

@end

NS_ASSUME_NONNULL_END
