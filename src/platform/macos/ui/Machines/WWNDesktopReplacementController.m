//
// WWNDesktopReplacementController.m. See header.
//
#import "WWNDesktopReplacementController.h"

#import "WWNMachineProfileStore.h"
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#endif
#import "WWNMachineSessionBridge.h"
#import "WWNPlatformCapabilities.h"
#import "../Settings/WWNPreferencesManager.h"
#import "../Settings/WWNSipStatus.h"
#import "../Settings/WWNWaypipeRunner.h"
#import "../../WWNPlatformCallbacks.h"
#import "WWNLog.h"
#import <Security/Security.h>

#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#if TARGET_OS_OSX

static NSString *const kWWNModeBLaunchdLabel =
    @"com.aspauldingcode.wawona.modeb";
static NSString *const kWWNModeBLoginAgentLabel =
    @"com.aspauldingcode.wawona.modeb-login";
static NSString *const kWWNModeBWsGuardLabel =
    @"com.aspauldingcode.wawona.ws-guard";
static NSString *const kWWNModeBSupportDir =
    @"/Library/Application Support/Wawona";
static NSString *const kWWNModeBHelperName = @"run-modeb.sh";
static NSString *const kWWNModeBIowatchdogName = @"wwn-iowatchdog";
static NSString *const kWWNModeBClaimInstallName =
    @"wwn-iowatchdog-claim-install";
static NSString *const kWWNModeBClaimOkPath =
    @"/var/db/wwn-iowatchdog/claim-ok";
static NSString *const kWWNModeBClaimPendingPath =
    @"/var/db/wwn-iowatchdog/claim-pending";
static NSString *const kWWNModeBIowDisabledMarkerPath =
    @"/tmp/libwayland-support/iowatchdog-userspace-disabled";
/** Set only by Classic stop_watchdogd_after_iowatchdog. KEEP_WS never sets it. */
static NSString *const kWWNModeBUnloadedWatchdogdPath =
    @"/tmp/libwayland-support/wawona-unloaded-watchdogd";
static NSString *const kWWNModeBPathBSockPath =
    @"/var/run/wwn-iowatchdog.sock";
static NSString *const kWWNModeBPidPath =
    @"/tmp/libwayland-support/modeb-compositor.pid";
static NSString *const kWWNModeBInstalledDylibRel =
    @"iland/libwayland-mac.dylib";
static NSString *const kWWNModeBSudoersPath =
    @"/etc/sudoers.d/wawona-modeb";
static NSString *const kWWNModeBFailReasonPath =
    @"/tmp/wawona-modeb-failed.reason";
static NSString *const kWWNModeBLogPath = @"/tmp/wawona-modeb.log";
/* Survives force reboot so Classic blank failures leave evidence. */
static NSString *const kWWNModeBPersistLogPath =
    @"/Library/Application Support/Wawona/modeb.log";
static NSString *const kWWNModeBCliLogPath = @"/tmp/wawona-modeb-cli.log";
static NSString *const kWWNModeBKeepWsPath = @"/tmp/wawona-modeb-keep-ws";
static NSString *const kWWNModeBFbReadyPath =
    @"/tmp/libwayland-support/modeb-framebufferd.ready";

/** Classic Take Over needs Path B (preferred) or Path A sticky claim-ok. */
static NSString *WWNModeBTakeOverNeedsAckMessage(void) {
  return @"Desktop Take Over needs the watchdog safety layer first.\n\n"
         @"Use Prepare this Mac in Settings (or the menubar Desktop play "
         @"button). Wawona installs Path B, then asks you to restart. After "
         @"you log back in, use Take Over Screen Now.\n\n"
         @"Prepare does not take over the screen. Take Over stays blocked "
         @"until Path B is live.";
}

/*
 * The Mode B compositor is root. kill(pid, 0) from the Aqua user returns
 * EPERM when that process exists. Only ESRCH means it is gone.
 */
static BOOL WWNProcessExists(pid_t pid) {
  if (pid <= 0) {
    return NO;
  }
  if (kill(pid, 0) == 0) {
    return YES;
  }
  return errno == EPERM;
}

static void WWNModeBCliLog(NSString *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
  va_end(ap);
  NSDateFormatter *df = [[NSDateFormatter alloc] init];
  df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  NSString *full =
      [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]],
                                 line];
  fputs(full.UTF8String, stdout);
  fflush(stdout);
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:kWWNModeBCliLogPath]) {
    [fm createFileAtPath:kWWNModeBCliLogPath contents:nil attributes:nil];
  }
  NSFileHandle *fh =
      [NSFileHandle fileHandleForWritingAtPath:kWWNModeBCliLogPath];
  [fh seekToEndOfFile];
  [fh writeData:[full dataUsingEncoding:NSUTF8StringEncoding]];
  [fh closeFile];
  if (!wwn_log_quiet) {
    NSLog(@"[DesktopReplacement] %@", line);
  }
}

@interface WWNDesktopReplacementController ()
@property (nonatomic, assign) pid_t modeBPid;
@property (nonatomic, copy, nullable) NSString *modeBMachineId;
@property (nonatomic, strong, nullable) WWNModeBMenuBarStatus *menuBarDesktopCache;
- (BOOL)terminateModeBProcess:(pid_t)pid
                         error:(NSError *_Nullable *_Nullable)error;
- (NSString *)modeBHelperPath;
- (NSString *)modeBIowatchdogPath;
- (nullable NSString *)bundledIowatchdogPath;
- (NSString *)modeBPlistPath;
- (NSString *)installedDylibPath;
- (NSString *)modeBLoginAgentPath;
- (NSString *)modeBSudoersBodyForUser:(NSString *)user;
- (NSString *)modeBLaunchScriptForExecutable:(NSString *)executablePath
                                   arguments:(NSArray<NSString *> *)arguments
                                 environment:(NSDictionary<NSString *, NSString *> *)environment
                                       dylib:(NSString *)dylib;
- (NSString *)wwnShellQuote:(NSString *)s;
- (NSString *)wwnAppleScriptQuote:(NSString *)s;
- (int)wwnLaunchctl:(NSArray<NSString *> *)args;
- (BOOL)isAppleWindowServerRunning;
- (BOOL)isLoginAgentLoaded;
- (BOOL)modeBFramebufferdReady;
- (nullable NSString *)consumeSessionFailureReason;
- (NSString *)modeBLogTail;
- (pid_t)startModeBHelperDetachedAndWait;
- (void)restoreAquaIfNeeded;
- (BOOL)sudoersAllowsHelper;
- (pid_t)readLiveCompositorPid;
- (int)runSudoNHelper:(NSArray<NSString *> *)extraArgs;
- (int)runSudoNHelper:(NSArray<NSString *> *)extraArgs
           stdoutText:(NSString *_Nullable *_Nullable)stdoutText;
- (NSDictionary<NSString *, NSString *> *)modeBStrippedEnvironment;
- (NSString *)modeBFileCleanupShell;
- (BOOL)installModeBHelperAndDylibForProfile:(WWNMachineProfile *)profile
                         error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)bundledClaimInstallPath;
- (BOOL)runPrivilegedShellCommand:(NSString *)shellCmd
                    successMarker:(NSString *)marker
                       stdoutText:(NSString *_Nullable *_Nullable)stdoutText
                            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)armPathBClaimInstall:(NSError *_Nullable *_Nullable)error;
- (void)presentRestartAfterPrepareWithMessage:(NSString *)message;
@end

@implementation WWNModeBReadyReport
@end

@implementation WWNModeBMenuBarStatus
@end

@implementation WWNDesktopReplacementController

+ (instancetype)sharedController {
  static WWNDesktopReplacementController *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[WWNDesktopReplacementController alloc] init];
    shared.modeBPid = 0;
  });
  return shared;
}

- (BOOL)reconcilePrefsWithCurrentSip {
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  BOOL enabled = [defs boolForKey:kWWNPrefsDesktopReplacementEnabled];
  if (!enabled) {
    return NO;
  }
  WWNSipStatusType sip = [WWNSipStatus current];
  if ([WWNSipStatus allowsDesktopReplacement:sip]) {
    return NO;
  }
  [defs setBool:NO forKey:kWWNPrefsDesktopReplacementEnabled];
  NSLog(@"[DesktopReplacement] cleared DesktopReplacementEnabled. SIP status "
        @"%@ no longer permits Mode B",
        [WWNSipStatus describe:sip]);
  return YES;
}

- (BOOL)shouldEngageModeB {
  if (!WWNPlatformAllowsDesktopReplacement()) {
    return NO;
  }
  WWNSipStatusType sip = [WWNSipStatus current];
  if (![WWNSipStatus allowsDesktopReplacement:sip]) {
    return NO;
  }
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsDesktopReplacementEnabled];
}

- (BOOL)isDesktopMachine:(WWNMachineProfile *)profile {
  if (!profile.machineId.length) {
    return NO;
  }
  NSString *desktopId = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsDesktopReplacementMachineId];
  if (desktopId.length == 0) {
    return NO;
  }
  return [profile.machineId isEqualToString:desktopId];
}

- (NSString *)bundledDylibPath {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *appRoot = bundle.bundlePath;
  NSArray<NSString *> *candidates = @[
    [appRoot stringByAppendingPathComponent:
                 @"Contents/Library/Wawona/iland/libwayland-mac.dylib"],
    [[WWNWawonaResourcesRoot() stringByAppendingPathComponent:@"iland"]
        stringByAppendingPathComponent:@"libwayland-mac.dylib"],
    [appRoot stringByAppendingPathComponent:
                 @"Contents/Frameworks/libwayland-mac.dylib"],
  ];
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *path in candidates) {
    if ([fm fileExistsAtPath:path]) {
      return path;
    }
  }
  return nil;
}

- (NSString *)modeBHelperPath {
  return [kWWNModeBSupportDir stringByAppendingPathComponent:kWWNModeBHelperName];
}

- (NSString *)modeBIowatchdogPath {
  /* CLI lives under bin/. Path B claim-install owns
   * …/Wawona/wwn-iowatchdog/ as a directory (hook + libs). Staging the CLI
   * at that same path made WWN_IOWATCHDOG a directory; restore then failed
   * "is a directory" and still re-enabled Apple watchdogd (panic 2026-08-20
   * KEEP_WS failure path). */
  return [[kWWNModeBSupportDir stringByAppendingPathComponent:@"bin"]
      stringByAppendingPathComponent:kWWNModeBIowatchdogName];
}

- (NSString *)bundledIowatchdogPath {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *appRoot = bundle.bundlePath;
  NSArray<NSString *> *candidates = @[
    [appRoot stringByAppendingPathComponent:
                 @"Contents/Library/Wawona/wwn-iowatchdog"],
    [WWNWawonaResourcesRoot()
        stringByAppendingPathComponent:@"../Library/Wawona/wwn-iowatchdog"],
  ];
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *path in candidates) {
    NSString *resolved = path.stringByStandardizingPath;
    if ([fm isExecutableFileAtPath:resolved]) {
      return resolved;
    }
  }
  return nil;
}

- (NSString *)bundledClaimInstallPath {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *appRoot = bundle.bundlePath;
  NSArray<NSString *> *candidates = @[
    [appRoot stringByAppendingPathComponent:
                 @"Contents/Library/Wawona/wwn-iowatchdog-claim-install"],
    [WWNWawonaResourcesRoot()
        stringByAppendingPathComponent:
            @"../Library/Wawona/wwn-iowatchdog-claim-install"],
  ];
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *path in candidates) {
    NSString *resolved = path.stringByStandardizingPath;
    if ([fm isExecutableFileAtPath:resolved]) {
      return resolved;
    }
  }
  return nil;
}

- (BOOL)iowatchdogLiveDisablePresent {
  NSFileManager *fm = [NSFileManager defaultManager];
  if ([fm fileExistsAtPath:kWWNModeBIowDisabledMarkerPath]) {
    return YES;
  }
  /*
   * Path B sock is root-only (srw-------). User-run Wawona cannot connect;
   * Classic then falsely refused after KEEP_WS disengage deleted the marker
   * (2026-08-20). Query via passwordless helper --ack-status (never grant
   * NOPASSWD on wwn-iowatchdog disable/enable).
   */
  if (![self sudoersAllowsHelper] ||
      ![fm isExecutableFileAtPath:[self modeBHelperPath]]) {
    return NO;
  }
  return [self runSudoNHelper:@[ @"--ack-status" ]] == 0;
}

- (BOOL)iowatchdogStickyAckPresent {
  NSString *body =
      [NSString stringWithContentsOfFile:kWWNModeBClaimOkPath
                                encoding:NSUTF8StringEncoding
                                   error:nil];
  if (body.length == 0) {
    return NO;
  }
  /* Product Classic Take Over: Path B claim-ok AND live Disable evidence.
   * claim-ok alone is stale after stage re-enables plain Apple watchdogd
   * (2026-08-20 evening SIGTRAP panic). */
  if (![body containsString:@"sticky=1"] || ![body containsString:@"path=b"]) {
    return NO;
  }
  return [self iowatchdogLiveDisablePresent];
}

- (NSString *)iowatchdogStickyAckStatusSummary {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *body =
      [NSString stringWithContentsOfFile:kWWNModeBClaimOkPath
                                encoding:NSUTF8StringEncoding
                                   error:nil];
  BOOL live = [self iowatchdogLiveDisablePresent];
  if (body.length > 0) {
    NSString *trim =
        [body stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trim containsString:@"sticky=1"] &&
        [trim containsString:@"path=b"]) {
      if (live) {
        return @"OK (Path B sticky + live Disable). Take Over may unload.";
      }
      return @"Stale claim-ok (no live Disable marker/sock). Re-arm Path B "
             @"and reboot; do not Take Over. Stage must not re-enable Apple "
             @"watchdogd while Path B is armed.";
    }
    if ([trim containsString:@"path=a"]) {
      return @"Path A ACK only (lab). Product Take Over needs Path B "
             @"sticky claim-ok + live Disable.";
    }
    return [NSString stringWithFormat:@"Unexpected claim-ok: %@", trim];
  }
  if ([fm fileExistsAtPath:kWWNModeBClaimPendingPath]) {
    return @"Pending: Path A/B armed; reboot, then re-check claim-ok + live.";
  }
  if (live) {
    return @"Live Disable present but claim-ok missing; re-arm Path B.";
  }
  return @"Missing: use Prepare this Mac, then restart.";
}

- (NSString *)modeBPlistPath {
  return [NSString stringWithFormat:@"/Library/LaunchDaemons/%@.plist",
                                    kWWNModeBLaunchdLabel];
}

- (NSString *)installedDylibPath {
  return [kWWNModeBSupportDir
      stringByAppendingPathComponent:kWWNModeBInstalledDylibRel];
}

- (NSString *)modeBLoginAgentPath {
  return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"]
      stringByAppendingPathComponent:
          [kWWNModeBLoginAgentLabel stringByAppendingString:@".plist"]];
}

- (NSString *)modeBSudoersBodyForUser:(NSString *)user {
  /*
   * NOPASSWD for one root-owned helper so Take Over Screen Now can
   * `sudo -n` without a second password prompt. Do not wire a login
   * LaunchAgent to this rule. Pin the helper path and wwn-iowatchdog.
   * Spaces in Application Support must be escaped.
   */
  NSString *helperEscaped =
      [[self modeBHelperPath] stringByReplacingOccurrencesOfString:@" "
                                                       withString:@"\\ "];
  return [NSString stringWithFormat:
                       @"# Wawona Desktop Replacement Mode B\n"
                       @"# Installed by Settings. Do not edit by hand.\n"
                       @"Defaults:%@ !requiretty\n"
                       @"%@ ALL=(root) NOPASSWD: %@, %@ --restore-aqua, "
                       @"%@ --kill-compositor, %@ --uninstall, %@ --ack-status\n"
                       @"# wwn-iowatchdog is NOT NOPASSWD. Take Over runs it\n"
                       @"# from the root helper only. Never grant passwordless\n"
                       @"# disable/enable (lldb attach paniced 2026-08-20).\n",
                       user, user, helperEscaped, helperEscaped,
                       helperEscaped, helperEscaped, helperEscaped];
}

- (BOOL)ensureDesktopMachineSelected:(NSError *_Nullable *_Nullable)error {
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSString *desktopId =
      [defs stringForKey:kWWNPrefsDesktopReplacementMachineId];
  WWNMachineProfile *selected =
      desktopId.length > 0 ? [WWNMachineProfileStore profileById:desktopId]
                           : nil;
  if (selected) {
    if ([WWNMachineProfileStore profileIndicatesModeBOwnDisplay:selected]) {
      return YES;
    }
  }

  for (WWNMachineProfile *profile in [WWNMachineProfileStore loadProfiles]) {
    if ([WWNMachineProfileStore profileIndicatesNestedCompositor:profile] &&
        profile.machineId.length > 0) {
      [defs setObject:profile.machineId
               forKey:kWWNPrefsDesktopReplacementMachineId];
      NSLog(@"[DesktopReplacement] selected compositor machine %@",
            profile.machineId);
      return YES;
    }
  }

  for (WWNMachineProfile *profile in [WWNMachineProfileStore loadProfiles]) {
    if ([WWNMachineProfileStore profileIndicatesModeBOwnDisplay:profile] &&
        profile.machineId.length > 0) {
      [defs setObject:profile.machineId
               forKey:kWWNPrefsDesktopReplacementMachineId];
      NSLog(@"[DesktopReplacement] selected own-display machine %@",
            profile.machineId);
      return YES;
    }
  }

  if (error) {
    *error = [NSError
        errorWithDomain:@"WWNDesktopReplacement"
                   code:9
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Pick a Desktop Machine (weston, niri, kmscube, "
                       @"gbm-es2-demo, or vkcube) under Settings → Desktop "
                       @"Replacement. Weston and niri stay nested in Mode A. "
                       @"wwn-igetty always provides VT switching."
                 }];
  }
  return NO;
}

- (NSError *)injectionPreflightError {
  if (!WWNPlatformAllowsDesktopReplacement()) {
    return [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                   code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                     @"Desktop Replacement Mode B is macOS-only."
               }];
  }
  NSString *dylib = [self bundledDylibPath];
  if (dylib.length == 0) {
    return [NSError
        errorWithDomain:@"WWNDesktopReplacement"
                   code:3
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     @"This Wawona build does not ship libwayland-mac.dylib "
                     @"(Mode B). Reinstall with nix run .#install."
               }];
  }
  if ([self bundledIowatchdogPath].length == 0) {
    return [NSError
        errorWithDomain:@"WWNDesktopReplacement"
                   code:3
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     @"This Wawona build does not ship wwn-iowatchdog "
                     @"(Mode B). Reinstall with nix run .#install."
               }];
  }
  NSError *resolveError = nil;
  if (![self ensureDesktopMachineSelected:&resolveError]) {
    return resolveError;
  }
  NSString *desktopId = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsDesktopReplacementMachineId];
  WWNMachineProfile *profile = [WWNMachineProfileStore profileById:desktopId];
  if (!profile) {
    return [NSError
        errorWithDomain:@"WWNDesktopReplacement"
                   code:9
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     @"Pick a Desktop Machine in Settings before enabling "
                     @"Desktop Replacement."
               }];
  }
  NSString *executablePath = nil;
  NSArray<NSString *> *launchArgs = nil;
  NSDictionary<NSString *, NSString *> *launchEnv = nil;
  NSError *specError = nil;
  if (![[WWNWaypipeRunner sharedRunner]
          baremetalCompositorLaunchSpecForProfile:profile
                                       executable:&executablePath
                                        arguments:&launchArgs
                                      environment:&launchEnv
                                            error:&specError]) {
    return specError;
  }
  if (executablePath.length == 0 ||
      ![[NSFileManager defaultManager] isExecutableFileAtPath:executablePath]) {
    return [NSError
        errorWithDomain:@"WWNDesktopReplacement"
                   code:4
               userInfo:@{
                 NSLocalizedDescriptionKey : [NSString
                     stringWithFormat:
                         @"Desktop compositor is not executable: %@",
                         executablePath ?: @"(missing)"]
               }];
  }
  (void)launchArgs;
  (void)launchEnv;
  return nil;
}

- (NSString *)modeBLaunchScriptForExecutable:(NSString *)executablePath
                                   arguments:(NSArray<NSString *> *)arguments
                                 environment:(NSDictionary<NSString *, NSString *> *)environment
                                       dylib:(NSString *)dylib {
  NSMutableString *script = [NSMutableString string];
  NSString *qPid = [self wwnShellQuote:kWWNModeBPidPath];
  NSString *qReason = [self wwnShellQuote:kWWNModeBFailReasonPath];
  NSString *qLog = [self wwnShellQuote:kWWNModeBLogPath];
  NSString *qWsPlist = [self
      wwnShellQuote:@"/System/Library/LaunchDaemons/com.apple.WindowServer.plist"];
  NSString *qWdPlist = [self
      wwnShellQuote:@"/System/Library/LaunchDaemons/com.apple.watchdogd.plist"];
  [script appendString:@"#!/bin/bash\n"];
  /*
   * Apple /bin/* and /usr/bin/sudo are arm64e. The Mode B dylib is arm64
   * (same as nix niri/weston). Never export DYLD_INSERT_LIBRARIES in this
   * helper: dyld would insert into date/mkdir/launchctl and terminate them
   * (have arm64, need arm64e). Unset inherited DYLD_* first.
   */
  [script appendString:@"unset DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH "
                       @"DYLD_FRAMEWORK_PATH DYLD_FALLBACK_LIBRARY_PATH\n"];
  [script appendString:@"# WWN_MODEB_INSERT=compositor-only\n"];
  [script appendString:@"# WWN_MODEB_WD=iowatchdog-then-unload\n"];
  [script appendFormat:@"# WWN_WAWONA_STORE=%@\n",
                       [[NSBundle mainBundle] bundlePath] ?: @""];
  [script appendFormat:@"# WWN_COMPOSITOR=%@\n", executablePath ?: @""];
  [script appendFormat:@"# WWN_MODEB_GUI_CMD=%@\n",
                       environment[@"WWN_IGETTY_GUI_CMD"] ?: @""];
  [script appendFormat:@"# WWN_MODEB_GUI_VT=%@\n",
                       environment[@"WWN_IGETTY_GUI_VT"] ?: @"0"];
  [script appendFormat:@"WWN_MODEB_UID=%u\n", (unsigned)getuid()];
  [script appendFormat:@"WWN_IOWATCHDOG=%@\n",
                       [self wwnShellQuote:[self modeBIowatchdogPath]]];
  [script appendFormat:@"CLAIM_OK=%@\n",
                       [self wwnShellQuote:kWWNModeBClaimOkPath]];
  [script appendFormat:@"REASON=%@\n", qReason];
  [script appendFormat:@"PIDFILE=%@\n", qPid];
  [script appendFormat:@"LOG=%@\n", qLog];
  [script appendFormat:@"PERSIST_LOG=%@\n",
                       [self wwnShellQuote:kWWNModeBPersistLogPath]];
  [script appendFormat:@"WS_PLIST=%@\n", qWsPlist];
  [script appendFormat:@"WD_PLIST=%@\n", qWdPlist];
  [script appendString:@""
                       @"wwn_log() {\n"
                       @"  line=$(printf '%s %s' \"$(date '+%Y-%m-%d %H:%M:%S')\" \"$*\")\n"
                       @"  printf '%s\\n' \"$line\" >> \"$LOG\"\n"
                       @"  printf '%s\\n' \"$line\" >> \"$PERSIST_LOG\" 2>/dev/null || true\n"
                       @"}\n"
                       @"mkdir -p \"/Library/Application Support/Wawona\" "
                       @"2>/dev/null || true\n"
                       @"touch \"$PERSIST_LOG\" 2>/dev/null || true\n"
                       @"chmod 666 \"$PERSIST_LOG\" 2>/dev/null || true\n"
                       @"kill_compositor() {\n"
                       @"  if [ -f \"$PIDFILE\" ]; then\n"
                       @"    cpid=$(cat \"$PIDFILE\" 2>/dev/null || true)\n"
                       @"    if [ -n \"$cpid\" ]; then\n"
                       @"      wwn_log \"kill compositor pid=$cpid\"\n"
                       @"      kill -TERM \"$cpid\" 2>/dev/null || true\n"
                       @"      sleep 0.2\n"
                       @"      kill -KILL \"$cpid\" 2>/dev/null || true\n"
                       @"    fi\n"
                       @"  fi\n"
                       @"  for helper in framebufferd inputd caffeinate; do\n"
                       @"    p=/tmp/libwayland-support/$helper.pid\n"
                       @"    if [ -f \"$p\" ]; then\n"
                       @"      hpid=$(cat \"$p\" 2>/dev/null || true)\n"
                       @"      if [ -n \"$hpid\" ]; then kill -TERM \"$hpid\" 2>/dev/null || true; fi\n"
                       @"    fi\n"
                       @"  done\n"
                       @"  for p in $(pgrep -u 0 -x niri 2>/dev/null; "
                       @"pgrep -u 0 -x weston 2>/dev/null; "
                       @"pgrep -u 0 -x kmscube 2>/dev/null; "
                       @"pgrep -u 0 -x gbm-es2-demo 2>/dev/null; "
                       @"pgrep -u 0 -x gbm_es2_demo 2>/dev/null; "
                       @"pgrep -u 0 -x vkcube-kms 2>/dev/null; "
                       @"pgrep -u 0 -x igettyd 2>/dev/null; "
                       @"pgrep -u 0 -x modeb-ttyd 2>/dev/null); do\n"
                       @"    wwn_log \"kill leftover Mode B client pid=$p\"\n"
                       @"    kill -TERM \"$p\" 2>/dev/null || true\n"
                       @"  done\n"
                       @"  sleep 0.2\n"
                       @"  for p in $(pgrep -u 0 -x niri 2>/dev/null; "
                       @"pgrep -u 0 -x weston 2>/dev/null; "
                       @"pgrep -u 0 -x kmscube 2>/dev/null; "
                       @"pgrep -u 0 -x gbm-es2-demo 2>/dev/null; "
                       @"pgrep -u 0 -x gbm_es2_demo 2>/dev/null; "
                       @"pgrep -u 0 -x vkcube-kms 2>/dev/null; "
                       @"pgrep -u 0 -x igettyd 2>/dev/null; "
                       @"pgrep -u 0 -x modeb-ttyd 2>/dev/null); do\n"
                       @"    kill -KILL \"$p\" 2>/dev/null || true\n"
                       @"  done\n"
                       @"}\n"
                       @"stop_other_helpers() {\n"
                       @"  me=$$\n"
                       @"  wwn_log \"WWN_MODEB_LOCK=helper-argv-only\"\n"
                       @"  ps -axo pid=,command= 2>/dev/null | while read -r pid cmd; do\n"
                       @"    if [ \"$pid\" = \"$me\" ]; then continue; fi\n"
                       @"    case \"$cmd\" in\n"
                       @"      /bin/bash\\ /Library/Application\\ Support/Wawona/run-modeb.sh*|"
                       @"/bin/sh\\ /Library/Application\\ Support/Wawona/run-modeb.sh*|"
                       @"bash\\ /Library/Application\\ Support/Wawona/run-modeb.sh*|"
                       @"/Library/Application\\ Support/Wawona/run-modeb.sh*)\n"
                       @"        wwn_log \"stop leftover helper pid=$pid (KILL)\"\n"
                       @"        kill -KILL \"$pid\" 2>/dev/null || true\n"
                       @"        ;;\n"
                       @"    esac\n"
                       @"  done\n"
                       @"}\n"
                       @"install_ws_guard() {\n"
                       @"  guard=/Library/LaunchDaemons/"
                       @"com.aspauldingcode.wawona.ws-guard.plist\n"
                       @"  cat > \"$guard\" <<'PLIST'\n"
                       @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                       @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
                       @"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
                       @"<plist version=\"1.0\"><dict>\n"
                       @"<key>Label</key>"
                       @"<string>com.aspauldingcode.wawona.ws-guard</string>\n"
                       @"<key>RunAtLoad</key><true/>\n"
                       @"<key>StartInterval</key><integer>10</integer>\n"
                       @"<key>ThrottleInterval</key><integer>5</integer>\n"
                       @"<key>KeepAlive</key><false/>\n"
                       @"<key>ProgramArguments</key><array>\n"
                       @"<string>/bin/bash</string><string>-c</string>\n"
                       @"<string>fpid=$(cat /tmp/libwayland-support/framebufferd.pid 2>/dev/null || true); "
                       @"if [ -n \"$fpid\" ] && kill -0 \"$fpid\" 2>/dev/null; then exit 0; fi; "
                       @"/bin/launchctl enable system/com.apple.WindowServer; "
                       @"/bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.WindowServer.plist; "
                       @"/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.WindowServer.plist; "
                       @"wspid=$(/bin/launchctl print system/com.apple.WindowServer 2>/dev/null | "
                       @"awk '/[[:space:]]pid =/{print $3; exit}'); "
                       @"if [ -z \"$wspid\" ]; then "
                       @"/bin/launchctl kickstart -k system/com.apple.WindowServer; fi</string>\n"
                       @"</array></dict></plist>\n"
                       @"PLIST\n"
                       @"  chown root:wheel \"$guard\" 2>/dev/null || true\n"
                       @"  chmod 644 \"$guard\" 2>/dev/null || true\n"
                       @"  /bin/launchctl bootout system/com.aspauldingcode.wawona.ws-guard "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootstrap system \"$guard\" >/dev/null 2>&1 || true\n"
                       @"  wwn_log \"ws-guard installed (WindowServer only; never touch watchdogd)\"\n"
                       @"}\n"
                       @"restore_watchdogd() {\n"
                       @"  # KEEP_WS never unloads watchdogd. Calling enable/\n"
                       @"  # bootstrap Apple while Path B sticky Disable is\n"
                       @"  # live paniced 2026-08-20 (watchdogd SIGTRAP ns2/\n"
                       @"  # 0x5) after a failed probe. Only reverse Classic.\n"
                       @"  if [ ! -f /tmp/libwayland-support/wawona-unloaded-watchdogd ]; then\n"
                       @"    wwn_log \"skip restore_watchdogd (never unloaded; KEEP_WS-safe)\"\n"
                       @"    return 0\n"
                       @"  fi\n"
                       @"  if [ -f /var/db/wwn-iowatchdog/claim-ok ] || "
                       @"[ -f /Library/LaunchDaemons/com.aspauldingcode.wwn-iowatchdog-pathb.plist ] || "
                       @"[ -f /Library/LaunchDaemons/com.aspauldingcode.wwn-iowatchdog-claim.plist ]; then\n"
                       @"    wwn_log \"Path A/B sticky: refuse Apple enable / "
                       @"iowatchdog enable; re-bootstrap Path B only\"\n"
                       @"    if [ -f /Library/LaunchDaemons/"
                       @"com.aspauldingcode.wwn-iowatchdog-pathb.plist ]; then\n"
                       @"      /bin/launchctl bootstrap system "
                       @"/Library/LaunchDaemons/com.aspauldingcode.wwn-iowatchdog-pathb.plist "
                       @">/dev/null 2>&1 || true\n"
                       @"      /bin/launchctl kickstart "
                       @"system/com.aspauldingcode.wwn-iowatchdog-pathb "
                       @">/dev/null 2>&1 || true\n"
                       @"      wwn_log \"Path B bootstrap after Classic\"\n"
                       @"    fi\n"
                       @"    rm -f /tmp/libwayland-support/wawona-unloaded-watchdogd\n"
                       @"    return 0\n"
                       @"  fi\n"
                       @"  /bin/launchctl enable system/com.apple.watchdogd; "
                       @"wwn_log \"wd_enable_st=$?\"\n"
                       @"  if [ -f /tmp/libwayland-support/iowatchdog-userspace-disabled ]; then\n"
                       @"    if [ -x \"$WWN_IOWATCHDOG\" ] && [ ! -d \"$WWN_IOWATCHDOG\" ]; then\n"
                       @"      \"$WWN_IOWATCHDOG\" enable >>\"$LOG\" 2>&1 || "
                       @"wwn_log \"iowatchdog enable failed (reboot restores)\"\n"
                       @"    else\n"
                       @"      wwn_log \"WWN_IOWATCHDOG missing or is a directory; "
                       @"skip kernel enable\"\n"
                       @"    fi\n"
                       @"    rm -f /tmp/libwayland-support/iowatchdog-userspace-disabled\n"
                       @"  else\n"
                       @"    wwn_log \"skip wwn-iowatchdog enable (no disable marker)\"\n"
                       @"  fi\n"
                       @"  /bin/launchctl load -w \"$WD_PLIST\"; wwn_log \"wd_load_w_st=$?\"\n"
                       @"  /bin/launchctl bootstrap system \"$WD_PLIST\" "
                       @">/dev/null 2>&1 || true\n"
                       @"  rm -f /tmp/libwayland-support/wawona-unloaded-watchdogd\n"
                       @"  wdpid=$(/bin/launchctl print system/com.apple.watchdogd "
                       @"2>/dev/null | awk '/[[:space:]]pid =/{print $3; exit}')\n"
                       @"  if [ -n \"$wdpid\" ] && kill -0 \"$wdpid\" 2>/dev/null; then\n"
                       @"    wwn_log \"watchdogd launchd pid=$wdpid\"\n"
                       @"  else\n"
                       @"    wwn_log \"watchdogd pid missing after bootstrap "
                       @"(no kickstart -k; reboot restores IOWatchdog)\"\n"
                       @"  fi\n"
                       @"}\n"
                       @"stop_watchdogd_after_iowatchdog() {\n"
                       @"  # ONLY after sticky Disable ACK (claim-ok + sock done=1).\n"
                       @"  # Kernel IOWatchdog Disable is sticky after done=1\n"
                       @"  # (wwn-iowatchdog path-a-path-b.md): closing the client\n"
                       @"  # does not Reenable. Classic MUST stop the userspace\n"
                       @"  # watchdogd process: it still expects WindowServer\n"
                       @"  # checkins. Leaving Path B hooked watchdogd up after\n"
                       @"  # WS bootout → panic at 120s (2026-08-21 16:01):\n"
                       @"  # 'no successful checkins from WindowServer',\n"
                       @"  # 'WindowServer appears to not exist in launchd'.\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.aspauldingcode.wwn-iowatchdog-pathb "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.aspauldingcode.wwn-iowatchdog-claim "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.aspauldingcode.wwn-iowatchdog-restore "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootout system/com.apple.watchdogd "
                       @">/dev/null 2>&1 || true\n"
                       @"  /usr/bin/pkill -x watchdogd >/dev/null 2>&1 || true\n"
                       @"  mkdir -p /tmp/libwayland-support 2>/dev/null || true\n"
                       @"  echo unloaded > /tmp/libwayland-support/wawona-unloaded-watchdogd\n"
                       @"  chmod 666 /tmp/libwayland-support/wawona-unloaded-watchdogd "
                       @"2>/dev/null || true\n"
                       @"  wwn_log \"userspace watchdogd stopped after IOWatchdog "
                       @"Disable ACK (kernel Disable stays sticky; no Reenable)\"\n"
                       @"}\n"
                       @"stop_window_server() {\n"
                       @"  # NEVER `launchctl disable` or `unload -w` on\n"
                       @"  # WindowServer. Those stick across reboot. If\n"
                       @"  # restore_aqua does not run (crash/force power),\n"
                       @"  # next login has no WS → userspace watchdog\n"
                       @"  # timeout panic at 120s (2026-08-21 kmscube:\n"
                       @"  # WindowServer appears to not exist in launchd).\n"
                       @"  # Session-only: bootout + TERM the live pid.\n"
                       @"  /bin/launchctl bootout system/com.apple.WindowServer; "
                       @"wwn_log \"ws_bootout_st=$?\"\n"
                       @"  /bin/launchctl kill SIGTERM system/com.apple.WindowServer "
                       @">/dev/null 2>&1 || true\n"
                       @"  ws_i=0\n"
                       @"  while [ \"$ws_i\" -lt 25 ]; do\n"
                       @"    wspid=$(/bin/launchctl print "
                       @"system/com.apple.WindowServer 2>/dev/null | "
                       @"awk '/[[:space:]]pid =/{print $3; exit}')\n"
                       @"    if [ -z \"$wspid\" ]; then\n"
                       @"      wwn_log \"WindowServer job has no pid\"\n"
                       @"      break\n"
                       @"    fi\n"
                       @"    wwn_log \"WindowServer still pid=$wspid try=$ws_i\"\n"
                       @"    kill -TERM \"$wspid\" 2>/dev/null || true\n"
                       @"    sleep 0.2\n"
                       @"    ws_i=$((ws_i + 1))\n"
                       @"  done\n"
                       @"}\n"
                       @"restore_window_server() {\n"
                       @"  /bin/launchctl enable system/com.apple.WindowServer; "
                       @"wwn_log \"enable_st=$?\"\n"
                       @"  /bin/launchctl load -w \"$WS_PLIST\"; wwn_log \"load_w_st=$?\"\n"
                       @"  /bin/launchctl bootstrap system \"$WS_PLIST\" >/dev/null 2>&1 || true\n"
                       @"  wspid=$(/bin/launchctl print "
                       @"system/com.apple.WindowServer 2>/dev/null | "
                       @"awk '/[[:space:]]pid =/{print $3; exit}')\n"
                       @"  if [ -n \"$wspid\" ] && kill -0 \"$wspid\" 2>/dev/null; then\n"
                       @"    wwn_log \"WindowServer launchd pid=$wspid\"\n"
                       @"  else\n"
                       @"    /bin/launchctl kickstart -k system/com.apple.WindowServer "
                       @">/dev/null 2>&1 || true\n"
                       @"    wwn_log \"kickstart WindowServer (launchd pid missing)\"\n"
                       @"  fi\n"
                       @"}\n"
                       @"restore_aqua() {\n"
                       @"  if [ \"${WWN_RESTORING:-0}\" = 1 ]; then return 0; fi\n"
                       @"  WWN_RESTORING=1\n"
                       @"  trap - TERM INT HUP\n"
                       @"  # WindowServer FIRST: userspace watchdogd panics at 120s\n"
                       @"  # without checkins. Do not spend that budget on cleanup.\n"
                       @"  restore_window_server\n"
                       @"  kill_compositor\n"
                       @"  stop_other_helpers\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.wayland-mac.framebufferd "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.wayland-mac.inputd "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.wayland-mac.weston "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.wayland-mac.modeb-client "
                       @">/dev/null 2>&1 || true\n"
                       @"  rm -f /Library/LaunchDaemons/com.wayland-mac.framebufferd.plist "
                       @"/Library/LaunchDaemons/com.wayland-mac.inputd.plist "
                       @"/Library/LaunchDaemons/com.wayland-mac.weston.plist "
                       @"/Library/LaunchDaemons/com.wayland-mac.modeb-client.plist "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.aspauldingcode.wawona.modeb "
                       @">/dev/null 2>&1 || true\n"
                       @"  restore_watchdogd\n"
                       @"  rmdir /tmp/libwayland-support/modeb.lock 2>/dev/null || true\n"
                       @"  rm -rf /tmp/libwayland-support/modeb.lock 2>/dev/null || true\n"
                       @"  wwn_log \"restore_aqua done\"\n"
                       @"  cp \"$LOG\" \"$PERSIST_LOG\" 2>/dev/null || true\n"
                       @"}\n"
                       @"touch \"$LOG\" 2>/dev/null || true\n"
                       @"chmod 666 \"$LOG\" 2>/dev/null || true\n"
                       @"if [ \"${1-}\" = \"--restore-aqua\" ] || "
                       @"[ \"${1-}\" = \"--kill-compositor\" ]; then\n"
                       @"  restore_aqua\n"
                       @"  exit 0\n"
                       @"fi\n"
                       @"if [ \"${1-}\" = \"--ack-status\" ] || "
                       @"[ \"${1-}\" = \"--ready\" ]; then\n"
                       @"  # Same LIVE_DIS as Classic: Path B sock done=1.\n"
                       @"  # Marker alone is not live while pathb plist exists.\n"
                       @"  CLAIM=$(cat \"$CLAIM_OK\" 2>/dev/null | tr '\\n' ' ')\n"
                       @"  PATHB_PLIST=0\n"
                       @"  if [ -f /Library/LaunchDaemons/"
                       @"com.aspauldingcode.wwn-iowatchdog-pathb.plist ]; then\n"
                       @"    PATHB_PLIST=1\n"
                       @"  fi\n"
                       @"  MARKER=0\n"
                       @"  if [ -f /tmp/libwayland-support/"
                       @"iowatchdog-userspace-disabled ]; then MARKER=1; fi\n"
                       @"  SOCK=/var/run/wwn-iowatchdog.sock\n"
                       @"  SOCK_ST=\n"
                       @"  if [ -S \"$SOCK\" ]; then\n"
                       @"    SOCK_ST=$(/usr/bin/python3 -c "
                       @"\"import socket;s=socket.socket(socket.AF_UNIX);"
                       @"s.settimeout(1.0);s.connect('$SOCK');"
                       @"s.send(b'status\\\\n');"
                       @"print(s.recv(256).decode(), end='')\" "
                       @"2>/dev/null || true)\n"
                       @"  fi\n"
                       @"  LIVE=0\n"
                       @"  case \"$SOCK_ST\" in *done=1*) LIVE=1 ;; esac\n"
                       @"  if [ \"$LIVE\" = 0 ] && [ \"$MARKER\" = 1 ] && "
                       @"[ \"$PATHB_PLIST\" != 1 ]; then LIVE=1; fi\n"
                       @"  PENDING=0\n"
                       @"  if [ -f /var/db/wwn-iowatchdog/claim-pending ]; then "
                       @"PENDING=1; fi\n"
                       @"  REBOOT=0\n"
                       @"  case \"$CLAIM\" in\n"
                       @"    *path=b*sticky=1*|*sticky=1*path=b*)\n"
                       @"      if [ \"$LIVE\" != 1 ]; then REBOOT=1; fi\n"
                       @"      ;;\n"
                       @"  esac\n"
                       @"  if [ \"$LIVE\" != 1 ]; then\n"
                       @"    if [ \"$PENDING\" = 1 ] || [ \"$PATHB_PLIST\" = 1 ]; "
                       @"then REBOOT=1; fi\n"
                       @"  fi\n"
                       @"  if [ \"$REBOOT\" = 1 ]; then V=reboot\n"
                       @"  elif [ \"$LIVE\" = 1 ]; then V=takeover-now\n"
                       @"  else V=blocked; fi\n"
                       @"  if [ \"$V\" = takeover-now ]; then\n"
                       @"    R=\"Watchdog safety is live. Use Take Over Screen "
                       @"Now when you want Desktop Replacement.\"\n"
                       @"  elif [ \"$V\" = reboot ]; then\n"
                       @"    R=\"Path B is armed. Restart this Mac so the "
                       @"watchdog safety layer can finish. After you log in, "
                       @"use Take Over Screen Now.\"\n"
                       @"  elif [ -z \"$CLAIM\" ]; then\n"
                       @"    R=\"Desktop Replacement still needs a one-time "
                       @"setup, then a restart. Use Prepare this Mac.\"\n"
                       @"  else\n"
                       @"    R=\"Watchdog safety is not live yet. Use Prepare "
                       @"this Mac, then restart.\"\n"
                       @"  fi\n"
                       @"  echo \"claim_ok=$CLAIM\"\n"
                       @"  echo \"pending=$PENDING\"\n"
                       @"  echo \"pathb_plist=$PATHB_PLIST\"\n"
                       @"  echo \"marker=$MARKER\"\n"
                       @"  echo \"sock=$SOCK_ST\"\n"
                       @"  echo \"ack_live=$LIVE\"\n"
                       @"  echo \"need_reboot=$REBOOT\"\n"
                       @"  echo \"verdict=$V\"\n"
                       @"  echo \"reason=$R\"\n"
                       @"  wwn_log \"ack-status live=$LIVE reboot=$REBOOT "
                       @"verdict=$V sock=$SOCK_ST\"\n"
                       @"  if [ \"$LIVE\" = 1 ]; then exit 0; fi\n"
                       @"  if [ \"$REBOOT\" = 1 ]; then exit 2; fi\n"
                       @"  exit 1\n"
                       @"fi\n"
                       @"if [ \"${1-}\" = \"--drop-lock\" ]; then\n"
                       @"  stop_other_helpers\n"
                       @"  rm -rf /tmp/libwayland-support/modeb.lock\n"
                       @"  wwn_log \"drop-lock done\"\n"
                       @"  exit 0\n"
                       @"fi\n"
                       @"if [ \"${1-}\" = \"--uninstall\" ]; then\n"
                       @"  restore_aqua\n"];
  [script appendString:[self modeBFileCleanupShell]];
  [script appendString:@"  wwn_log \"uninstall done\"\n"
                       @"  exit 0\n"
                       @"fi\n"];
  [script appendString:@"write_reason() {\n"
                       @"  printf '%s\\n' \"$1\" > \"$REASON\"\n"
                       @"  chmod 644 \"$REASON\" 2>/dev/null || true\n"
                       @"  # Sticky /tmp: only the owner can rename/unlink.\n"
                       @"  # Chown to the Aqua user so Wawona can consume it.\n"
                       @"  if [ -n \"${WWN_MODEB_UID-}\" ]; then\n"
                       @"    chown \"$WWN_MODEB_UID\" \"$REASON\" "
                       @"2>/dev/null || true\n"
                       @"  fi\n"
                       @"  wwn_log \"$1\"\n"
                       @"}\n"
                       @"claim_modeb_lock() {\n"
                       @"  mkdir -p /tmp/libwayland-support\n"
                       @"  tries=0\n"
                       @"  while [ \"$tries\" -lt 20 ]; do\n"
                       @"    if mkdir /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null; then\n"
                       @"      echo $$ > /tmp/libwayland-support/modeb.lock/owner "
                       @"2>/dev/null || true\n"
                       @"      return 0\n"
                       @"    fi\n"
                       @"    owner=$(cat /tmp/libwayland-support/modeb.lock/owner "
                       @"2>/dev/null || true)\n"
                       @"    if [ -n \"$owner\" ] && kill -0 \"$owner\" "
                       @"2>/dev/null; then\n"
                       @"      wwn_log \"modeb helper already running "
                       @"helper=$owner\"\n"
                       @"      exit 0\n"
                       @"    fi\n"
                       @"    wwn_log \"stale modeb.lock; stealing try=$tries "
                       @"owner=${owner:-none}\"\n"
                       @"    stop_other_helpers\n"
                       @"    rm -rf /tmp/libwayland-support/modeb.lock\n"
                       @"    mkdir -p /tmp/libwayland-support\n"
                       @"    tries=$((tries + 1))\n"
                       @"    sleep 0.15\n"
                       @"  done\n"
                       @"  write_reason \"Mode B helper could not claim "
                       @"modeb.lock after retries.\"\n"
                       @"  ls -ld /tmp/libwayland-support "
                       @"/tmp/libwayland-support/modeb.lock >> \"$LOG\" "
                       @"2>&1 || true\n"
                       @"  rm -rf /tmp/libwayland-support/modeb.lock\n"
                       @"  exit 0\n"
                       @"}\n"
                       @"abort_classic_leave_aqua() {\n"
                       @"  write_reason \"$1\"\n"
                       @"  /bin/launchctl bootout system/com.wayland-mac.framebufferd "
                       @">/dev/null 2>&1 || true\n"
                       @"  /bin/launchctl bootout system/com.wayland-mac.inputd "
                       @">/dev/null 2>&1 || true\n"
                       @"  /usr/bin/pkill -u 0 -x framebufferd >/dev/null 2>&1 || true\n"
                       @"  /usr/bin/pkill -u 0 -x inputd >/dev/null 2>&1 || true\n"
                       @"  rm -f /Library/LaunchDaemons/com.wayland-mac.framebufferd.plist "
                       @"/Library/LaunchDaemons/com.wayland-mac.inputd.plist\n"
                       @"  rmdir /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"
                       @"  rm -rf /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"
                       @"  exit 0\n"
                       @"}\n"
                       @"wait_machservice_gone() {\n"
                       @"  gi=0\n"
                       @"  while [ \"$gi\" -lt 20 ]; do\n"
                       @"    if ! /bin/launchctl print \"system/$1\" "
                       @">/dev/null 2>&1; then return 0; fi\n"
                       @"    gi=$((gi + 1)); sleep 0.15\n"
                       @"  done\n"
                       @"  wwn_log \"launchd job still loaded after bootout: $1\"\n"
                       @"  return 1\n"
                       @"}\n"
                       @"live_root_pid() {\n"
                       @"  p=$(cat \"$1\" 2>/dev/null || true)\n"
                       @"  if [ -n \"$p\" ] && kill -0 \"$p\" 2>/dev/null; then\n"
                       @"    printf '%s\\n' \"$p\"; return 0\n"
                       @"  fi\n"
                       @"  p=$(pgrep -u 0 -x \"$2\" 2>/dev/null | head -1)\n"
                       @"  if [ -n \"$p\" ] && kill -0 \"$p\" 2>/dev/null; then\n"
                       @"    printf '%s\\n' \"$p\"; return 0\n"
                       @"  fi\n"
                       @"  return 1\n"
                       @"}\n"
                       @"trap '' TERM INT HUP\n"
                       @": > \"$LOG\"\n"
                       @"chmod 666 \"$LOG\" 2>/dev/null || true\n"
                       @"wwn_log \"modeb helper start uid=$(id -u) args=$*\"\n"];
  [script appendString:@"unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY\n"];

  NSArray<NSString *> *keys =
      [[environment allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    if ([key isEqualToString:@"DYLD_INSERT_LIBRARIES"] ||
        [key isEqualToString:@"_"] || [key isEqualToString:@"SHLVL"] ||
        [key isEqualToString:@"OLDPWD"] || [key isEqualToString:@"PWD"]) {
      continue;
    }
    unichar first = key.length > 0 ? [key characterAtIndex:0] : 0;
    BOOL ident = (first == '_' || (first >= 'A' && first <= 'Z') ||
                  (first >= 'a' && first <= 'z'));
    for (NSUInteger i = 1; ident && i < key.length; i++) {
      unichar c = [key characterAtIndex:i];
      ident = (c == '_' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
               (c >= '0' && c <= '9'));
    }
    if (!ident) {
      continue;
    }
    NSString *value = environment[key];
    if (![value isKindOfClass:[NSString class]] || value.length == 0) {
      continue;
    }
    [script appendFormat:@"export %@=%@\n", key, [self wwnShellQuote:value]];
  }
  [script appendFormat:@"WWN_MODEB_DYLIB=%@\n", [self wwnShellQuote:dylib]];

  NSString *xdg = environment[@"XDG_RUNTIME_DIR"];
  if (xdg.length > 0) {
    [script appendFormat:@"mkdir -p %@\nchmod 700 %@\n", [self wwnShellQuote:xdg],
                         [self wwnShellQuote:xdg]];
  }

  /*
   * A leftover KeepAlive system daemon (pre-login-agent installs) can keep
   * niri alive across logout without re-unloading WindowServer. Aqua then
   * comes back and "nothing happens". Boot that job out before we take the
   * display.
   */
  [script appendFormat:@"/bin/launchctl bootout system/%@ >/dev/null 2>&1 || true\n",
                       kWWNModeBLaunchdLabel];
  [script appendString:@"mkdir -p /tmp/libwayland-support\n"];
  [script appendString:@"claim_modeb_lock\n"];
  [script appendString:@"rm -f \"$REASON\" \"$PIDFILE\"\n"];
  [script appendString:@"wwn_log \"dylib=$WWN_MODEB_DYLIB\"\n"];
  [script appendFormat:@"wwn_log \"executable=%@\"\n",
                       [self wwnShellQuote:executablePath]];
  /*
   * Hard abort: never unload WindowServer without a real inject dylib.
   * A stale passwordless helper (or empty DYLD_INSERT_LIBRARIES) previously
   * killed Aqua, launched bare niri, then failed to restore WindowServer,
   * which looks like a post-login WindowServer crash loop.
   */
  [script appendString:@"if [ -z \"$WWN_MODEB_DYLIB\" ] || "
                       @"[ ! -f \"$WWN_MODEB_DYLIB\" ]; then\n"];
  [script appendString:@"  wwn_log \"ABORT: Mode B dylib missing; "
                       @"leaving WindowServer alone\"\n"];
  [script appendString:@"  write_reason \"Mode B refused to start: "
                       @"libwayland-mac.dylib was not set or not found. "
                       @"Apple's WindowServer was left running.\"\n"];
  [script appendString:@"  rmdir /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"  rm -rf /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"  exit 0\n"];
  [script appendString:@"fi\n"];
  /*
   * Classic Take Over: require sticky claim-ok (Path B preferred), then
   * unload watchdogd and WindowServer, then inject compositor.
   * KEEP_WS probe skips unload and leaves Aqua up.
   * Never lldb. Never kickstart -k watchdogd.
   */
  [script appendString:@"wwn_log \"WWN_MODEB_GATE=pidfile-not-pgrep\"\n"];
  [script appendString:@"wwn_log \"WWN_MODEB_GATE=live-fb-before-ws-unload\"\n"];
  [script appendString:@"wwn_log \"WWN_MODEB_WD=iowatchdog-then-unload\"\n"];
  [script appendString:@"rm -f /tmp/libwayland-support/modeb-framebufferd.ready "
                       @"/tmp/libwayland-support/modeb-mach.ready "
                       @"/tmp/libwayland-support/modeb-display-go\n"];
  [script appendString:@"if [ -f /tmp/wawona-modeb-keep-ws ]; then\n"];
  [script appendString:@"  wwn_log \"KEEP_WS=1; leaving WindowServer and "
                       @"watchdogd running\"\n"];
  /* framebufferd skips CoreDisplay panel claim when this is set (Aqua stays
   * interactive). Classic must not export it. */
  [script appendString:@"  export WWN_MODEB_KEEP_WS=1\n"];
  [script appendString:@"  install_ws_guard\n"];
  [script appendString:@"else\n"];
  [script appendString:@"  unset WWN_MODEB_KEEP_WS\n"];
  [script appendString:@"  if [ ! -f \"$CLAIM_OK\" ] || "
                       @"! grep -q 'sticky=1' \"$CLAIM_OK\" 2>/dev/null || "
                       @"! grep -q 'path=b' \"$CLAIM_OK\" 2>/dev/null; then\n"];
  [script appendString:@"    write_reason \"Mode B Take Over refused: missing "
                       @"Path B sticky IOWatchdog ACK at $CLAIM_OK. Arm Path B "
                       @"(claim-install --path-b), reboot, then retry. "
                       @"Apple's WindowServer was left running.\"\n"];
  [script appendString:@"    rmdir /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"    rm -rf /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  wwn_log \"claim-ok present: $(cat \"$CLAIM_OK\" "
                       @"2>/dev/null | tr '\\n' ' ')\"\n"];
  /* Live Disable evidence required. Never invent the marker before unload
   * (2026-08-20 evening: claim-ok stale + fabricated marker + unload →
   * watchdogd SIGTRAP panic while kernel monitoring still armed).
   * Path B: require sock done=1 (marker alone is stale after pathb
   * restart; 2026-08-21 Classic bootout left marker=yes done=0). */
  [script appendString:@"  LIVE_DIS=0\n"];
  [script appendString:@"  MARKER=/tmp/libwayland-support/"
                       @"iowatchdog-userspace-disabled\n"];
  [script appendString:@"  SOCK=/var/run/wwn-iowatchdog.sock\n"];
  [script appendString:@"  if [ -S \"$SOCK\" ]; then\n"];
  [script appendString:@"    SOCK_ST=$(/usr/bin/python3 -c "
                       @"\"import socket;s=socket.socket(socket.AF_UNIX);"
                       @"s.settimeout(1.0);s.connect('$SOCK');"
                       @"s.send(b'status\\\\n');"
                       @"print(s.recv(256).decode(), end='')\" "
                       @"2>/dev/null || true)\n"];
  [script appendString:@"    wwn_log \"pathb sock status: $SOCK_ST\"\n"];
  [script appendString:@"    case \"$SOCK_ST\" in *done=1*) LIVE_DIS=1; "
                       @"wwn_log \"live Disable via Path B sock done=1\" ;; "
                       @"esac\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  if [ \"$LIVE_DIS\" = 0 ] && [ -f \"$MARKER\" ] && "
                       @"[ ! -f /Library/LaunchDaemons/"
                       @"com.aspauldingcode.wwn-iowatchdog-pathb.plist ]; then\n"];
  [script appendString:@"    LIVE_DIS=1; wwn_log \"live Disable marker present "
                       @"(non-Path-B)\"\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  if [ \"$LIVE_DIS\" != 1 ]; then\n"];
  [script appendString:@"    write_reason \"Mode B Take Over refused: claim-ok "
                       @"is present but live IOWatchdog Disable is not "
                       @"(Path B sock not done=1). Re-arm Path B, reboot, "
                       @"confirm sock done=1 before Take Over. Do not unload "
                       @"watchdogd. Apple's WindowServer left running.\"\n"];
  [script appendString:@"    rmdir /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"    rm -rf /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  /*
   * Classic order (25F80):
   *   1. Extract helpers; publish Mach via launchd MachServices
   *      (system bootstrap survives WS bootout). Legacy
   *      bootstrap_register names become look_up-"exception protected"
   *      after WS unload (2026-08-21 blank: out=1 disp=1 present=0).
   *   2. WWN_MODEB_DEFER_DISPLAY waits for modeb-display-go.
   *   3. Unload WD+WS; touch go; DispDrvInit with WS gone.
   *   4. Inject compositor (dylib skips helper-owned framebufferd).
   */
  [script appendString:@"  wwn_log \"Classic: launchd MachServices + "
                       @"Mach-before-WS-unload; DispDrvInit after\"\n"];
  [script appendString:@"  mkdir -p /tmp/libwayland-support\n"];
  [script appendString:@"  rm -f /tmp/libwayland-support/modeb-mach.ready "
                       @"/tmp/libwayland-support/modeb-display-go\n"];
  [script appendString:@"  extract_dylib_section() {\n"];
  [script appendString:@"    /usr/bin/python3 - \"$1\" \"$2\" \"$3\" <<'PY'\n"];
  [script appendString:@"import struct,sys\n"];
  [script appendString:@"dylib,sect,dest=sys.argv[1],sys.argv[2],sys.argv[3]\n"];
  [script appendString:@"data=open(dylib,'rb').read()\n"];
  [script appendString:@"magic=struct.unpack_from('<I',data,0)[0]\n"];
  [script appendString:@"assert magic==0xfeedfacf, hex(magic)\n"];
  [script appendString:@"ncmds=struct.unpack_from('<I',data,16)[0]\n"];
  [script appendString:@"off=32; want=sect.encode(); found=None\n"];
  [script appendString:@"for _ in range(ncmds):\n"];
  [script appendString:@"  cmd,cmdsize=struct.unpack_from('<II',data,off)\n"];
  [script appendString:@"  if cmd==0x19:\n"];
  [script appendString:@"    nsects=struct.unpack_from('<I',data,off+64)[0]\n"];
  [script appendString:@"    soff=off+72\n"];
  [script appendString:@"    for i in range(nsects):\n"];
  [script appendString:@"      sec=data[soff:soff+80]\n"];
  [script appendString:@"      sname=sec[0:16].split(b'\\0',1)[0]\n"];
  [script appendString:@"      seg=sec[16:32].split(b'\\0',1)[0]\n"];
  [script appendString:@"      _a,size,offset=struct.unpack_from('<QQI',sec,32)\n"];
  [script appendString:@"      if seg==b'__DATA_OBJ' and sname==want:\n"];
  [script appendString:@"        found=(offset,size); break\n"];
  [script appendString:@"      soff+=80\n"];
  [script appendString:@"  if found: break\n"];
  [script appendString:@"  off+=cmdsize\n"];
  [script appendString:@"if not found:\n"];
  [script appendString:@"  sys.stderr.write('section __DATA_OBJ,%s missing\\n'%sect); "
                       @"sys.exit(1)\n"];
  [script appendString:@"o,s=found; open(dest,'wb').write(data[o:o+s])\n"];
  [script appendString:@"import os; os.chmod(dest,0o755)\n"];
  [script appendString:@"PY\n"];
  [script appendString:@"  }\n"];
  [script appendString:@"  write_machservice_plist() {\n"];
  [script appendString:@"    # $1=label $2=bin $3=mach $4=hid|display (inputd vs framebufferd defer)\n"];
  [script appendString:@"    plist=/Library/LaunchDaemons/$1.plist\n"];
  [script appendString:@"    defer_key=WWN_MODEB_DEFER_DISPLAY\n"];
  [script appendString:@"    if [ \"$4\" = hid ]; then defer_key=WWN_MODEB_DEFER_HID; fi\n"];
  [script appendString:@"    /bin/cat > \"$plist\" <<PLIST\n"];
  [script appendString:@"<?xml version=\\\"1.0\\\" encoding=\\\"UTF-8\\\"?>\n"];
  [script appendString:@"<!DOCTYPE plist PUBLIC \\\"-//Apple//DTD PLIST 1.0//EN\\\" "
                       @"\\\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\\\">\n"];
  [script appendString:@"<plist version=\\\"1.0\\\"><dict>\n"];
  [script appendString:@"  <key>Label</key><string>$1</string>\n"];
  [script appendString:@"  <key>ProgramArguments</key><array>\n"];
  [script appendString:@"    <string>$2</string>\n"];
  [script appendString:@"  </array>\n"];
  [script appendString:@"  <key>EnvironmentVariables</key><dict>\n"];
  [script appendString:@"    <key>WWN_MODEB_LAUNCHD</key><string>1</string>\n"];
  [script appendString:@"    <key>$defer_key</key><string>1</string>\n"];
  [script appendString:@"  </dict>\n"];
  [script appendString:@"  <key>MachServices</key><dict>\n"];
  [script appendString:@"    <key>$3</key><true/>\n"];
  [script appendString:@"  </dict>\n"];
  [script appendString:@"  <key>RunAtLoad</key><true/>\n"];
  [script appendString:@"  <key>KeepAlive</key><false/>\n"];
  [script appendString:@"  <key>UserName</key><string>root</string>\n"];
  [script appendString:@"  <key>StandardOutPath</key><string>$LOG</string>\n"];
  [script appendString:@"  <key>StandardErrorPath</key><string>$LOG</string>\n"];
  [script appendString:@"</dict></plist>\n"];
  [script appendString:@"PLIST\n"];
  [script appendString:@"    /usr/bin/chmod 644 \"$plist\"\n"];
  [script appendString:@"  }\n"];
  [script appendString:@"  for h in amfiexceptiond framebufferd inputd; do\n"];
  [script appendString:@"    if ! extract_dylib_section \"$WWN_MODEB_DYLIB\" \"$h\" "
                       @"\"/tmp/libwayland-support/$h\"; then\n"];
  [script appendString:@"      write_reason \"Mode B could not extract $h from "
                       @"dylib. Apple's WindowServer left running.\"\n"];
  [script appendString:@"      rmdir /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"      rm -rf /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"      exit 0\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    /usr/bin/codesign -s - --force "
                       @"\"/tmp/libwayland-support/$h\" >/dev/null 2>&1 || true\n"];
  [script appendString:@"  done\n"];
  /* inputd needs IOHIDEventSystem entitlements. Bare --force ad-hoc strips
   * the build-time entitlements from the embedded helper. Re-apply after
   * extract. */
  [script appendString:@"  /bin/cat > /tmp/libwayland-support/inputd.entitlements "
                       @"<<'ENT'\n"];
  [script appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                       @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
                       @"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
                       @"<plist version=\"1.0\"><dict>\n"
                       @"<key>com.apple.hid.manager.user-access-device</key><true/>\n"
                       @"<key>com.apple.hid.manager.user-access-keyboard</key><true/>\n"
                       @"<key>com.apple.hid.manager.user-access-privileged</key><true/>\n"
                       @"<key>com.apple.hid.multitouch.user-access</key><true/>\n"
                       @"<key>com.apple.hid.system.user-access-service</key><true/>\n"
                       @"<key>com.apple.hidpreferences.privileged</key><true/>\n"
                       @"<key>com.apple.iohideventsystem.server</key><true/>\n"
                       @"<key>com.apple.private.tcc.allow</key>\n"
                       @"<array><string>kTCCServiceListenEvent</string>"
                       @"<string>kTCCServicePostEvent</string></array>\n"
                       @"</dict></plist>\n"];
  [script appendString:@"ENT\n"];
  [script appendString:@"  /usr/bin/codesign -s - --force --entitlements "
                       @"/tmp/libwayland-support/inputd.entitlements "
                       @"/tmp/libwayland-support/inputd >/dev/null 2>&1 || "
                       @"wwn_log \"inputd entitlements codesign failed\"\n"];
  /* amfid is on-demand and idle-jetsams on macOS 26. Wake it, then cap the
   * hook so Classic cannot hang before framebufferd / igettyd. Never
   * kickstart watchdogd here. */
  [script appendString:@"  /bin/launchctl kickstart -p "
                       @"system/com.apple.MobileFileIntegrity >>\"$LOG\" 2>&1 "
                       @"|| true\n"];
  [script appendString:@"  /usr/bin/perl -e 'alarm 8; exec @ARGV' "
                       @"/tmp/libwayland-support/amfiexceptiond >>\"$LOG\" 2>&1 "
                       @"|| true\n"];
  [script appendString:@"  /bin/launchctl bootout system/com.wayland-mac.framebufferd "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"  /bin/launchctl bootout system/com.wayland-mac.inputd "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"  /usr/bin/pkill -u 0 -x inputd >/dev/null 2>&1 || true\n"];
  [script appendString:@"  /usr/bin/pkill -u 0 -x framebufferd >/dev/null 2>&1 || true\n"];
  [script appendString:@"  wait_machservice_gone com.wayland-mac.framebufferd || true\n"];
  [script appendString:@"  wait_machservice_gone com.wayland-mac.inputd || true\n"];
  /* Leftover framebufferd swallows SIGTERM while waiting for
   * modeb-display-go. SIGKILL leftovers only here, before Classic
   * bootstrap. Never watchdogd. */
  [script appendString:@"  if pgrep -u 0 -x framebufferd >/dev/null 2>&1; then\n"];
  [script appendString:@"    wwn_log \"leftover framebufferd after bootout; "
                       @"SIGKILL before Classic bootstrap\"\n"];
  [script appendString:@"    /usr/bin/pkill -KILL -u 0 -x framebufferd "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  if pgrep -u 0 -x inputd >/dev/null 2>&1; then\n"];
  [script appendString:@"    wwn_log \"leftover inputd after bootout; "
                       @"SIGKILL before Classic bootstrap\"\n"];
  [script appendString:@"    /usr/bin/pkill -KILL -u 0 -x inputd "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  sleep 0.3\n"];
  [script appendString:@"  unset WWN_MODEB_KEEP_WS\n"];
  [script appendString:@"  write_machservice_plist com.wayland-mac.inputd "
                       @"/tmp/libwayland-support/inputd com.wayland-mac.inputd hid\n"];
  [script appendString:@"  write_machservice_plist com.wayland-mac.framebufferd "
                       @"/tmp/libwayland-support/framebufferd "
                       @"com.wayland-mac.framebufferd display\n"];
  /* Do not plutil a live inputd plist: launchd SIGTERMs the job to reload,
   * KeepAlive is false, HID path dies before WS unload. */
  [script appendString:@"  /bin/launchctl bootstrap system "
                       @"/Library/LaunchDaemons/com.wayland-mac.inputd.plist "
                       @">>\"$LOG\" 2>&1 || true\n"];
  [script appendString:@"  /bin/launchctl bootstrap system "
                       @"/Library/LaunchDaemons/com.wayland-mac.framebufferd.plist "
                       @">>\"$LOG\" 2>&1\n"];
  [script appendString:@"  fb_bs=$?\n"];
  [script appendString:@"  if [ \"$fb_bs\" != 0 ]; then\n"];
  [script appendString:@"    wwn_log \"framebufferd bootstrap st=$fb_bs; "
                       @"retry after bootout (EIO=already loaded)\"\n"];
  [script appendString:@"    /bin/launchctl bootout "
                       @"system/com.wayland-mac.framebufferd "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"    wait_machservice_gone com.wayland-mac.framebufferd "
                       @"|| true\n"];
  [script appendString:@"    /usr/bin/pkill -KILL -u 0 -x framebufferd "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"    sleep 0.3\n"];
  [script appendString:@"    write_machservice_plist com.wayland-mac.framebufferd "
                       @"/tmp/libwayland-support/framebufferd "
                       @"com.wayland-mac.framebufferd display\n"];
  [script appendString:@"    /bin/launchctl bootstrap system "
                       @"/Library/LaunchDaemons/com.wayland-mac.framebufferd.plist "
                       @">>\"$LOG\" 2>&1\n"];
  [script appendString:@"    fb_bs=$?\n"];
  [script appendString:@"    wwn_log \"framebufferd bootstrap retry st=$fb_bs\"\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  mach_ok=0\n"];
  [script appendString:@"  mi=0\n"];
  [script appendString:@"  while [ \"$mi\" -lt 80 ]; do\n"];
  [script appendString:@"    fpid=$(live_root_pid "
                       @"/tmp/libwayland-support/framebufferd.pid framebufferd "
                       @"|| true)\n"];
  [script appendString:@"    if [ -n \"$fpid\" ] && "
                       @"[ -f /tmp/libwayland-support/modeb-mach.ready ] && "
                       @"grep -q '\\[framebufferd\\] listening' \"$LOG\" "
                       @"2>/dev/null; then\n"];
  [script appendString:@"      mach_ok=1; break\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    if grep -q '\\[framebufferd\\] bootstrap_check_in' "
                       @"\"$LOG\" 2>/dev/null && "
                       @"! grep -q '\\[framebufferd\\] listening' \"$LOG\" "
                       @"2>/dev/null; then\n"];
  [script appendString:@"      break\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    if grep -q '\\[framebufferd\\] bootstrap_register' "
                       @"\"$LOG\" 2>/dev/null && "
                       @"! grep -q '\\[framebufferd\\] listening' \"$LOG\" "
                       @"2>/dev/null; then\n"];
  [script appendString:@"      break\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    if [ -n \"$fpid\" ] && ! kill -0 \"$fpid\" 2>/dev/null; then\n"];
  [script appendString:@"      wwn_log \"framebufferd exited before Mach ready\"\n"];
  [script appendString:@"      break\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    mi=$((mi + 1)); sleep 0.25\n"];
  [script appendString:@"  done\n"];
  [script appendString:@"  if [ \"$mach_ok\" != 1 ]; then\n"];
  [script appendString:@"    abort_classic_leave_aqua \"Mode B framebufferd failed "
                       @"to publish MachServices while WindowServer was still up. "
                       @"Left Aqua running. See $PERSIST_LOG.\"\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  fpid=$(live_root_pid "
                       @"/tmp/libwayland-support/framebufferd.pid framebufferd "
                       @"|| true)\n"];
  [script appendString:@"  if [ -z \"$fpid\" ]; then\n"];
  [script appendString:@"    abort_classic_leave_aqua \"Mode B framebufferd was "
                       @"not live before WindowServer unload (bootstrap st=$fb_bs). "
                       @"Left Aqua running. See $PERSIST_LOG.\"\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  ipid=$(live_root_pid "
                       @"/tmp/libwayland-support/inputd.pid inputd || true)\n"];
  [script appendString:@"  if [ -z \"$ipid\" ]; then\n"];
  [script appendString:@"    abort_classic_leave_aqua \"Mode B inputd died before "
                       @"WindowServer unload (no keyboard path). Left Aqua running. "
                       @"See $PERSIST_LOG.\"\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  wwn_log \"framebufferd MachServices ready "
                       @"pid=$fpid inputd=$ipid; stop userspace watchdogd + unload WS\"\n"];
  [script appendString:@"  stop_watchdogd_after_iowatchdog\n"];
  /* Do NOT install_ws_guard before WS unload: RunAtLoad can race the
   * stop_window_server loop (restore WS while helper is killing it),
   * and a false-dead framebufferd.pid then kickstarts Aqua → login.
   * Arm the guard only after CAWindowServer is proven ready. */
  [script appendString:@"  stop_window_server\n"];
  [script appendString:@"  touch /tmp/libwayland-support/modeb-display-go\n"];
  [script appendString:@"  chmod 644 /tmp/libwayland-support/modeb-display-go "
                       @"2>/dev/null || true\n"];
  [script appendString:@"  wwn_log \"modeb-display-go touched; waiting for "
                       @"framebufferd CoreDisplay / CAWindowServer ready\"\n"];
  [script appendString:@"  disp_pre=0\n"];
  [script appendString:@"  di=0\n"];
  /* DispDrvInit + CAWindowServer can take 30-45s on 25F80. */
  [script appendString:@"  while [ \"$di\" -lt 200 ]; do\n"];
  [script appendString:@"    cp \"$LOG\" \"$PERSIST_LOG\" 2>/dev/null || true\n"];
  /* Never grep bare 'display=yes': helper wwn_log used to contain that
   * substring and falsely passed this gate (2026-08-21 Mode B TTY: client
   * started before framebufferd DispDrvInit; fb died; lockscreen restore).
   * Require the CAWindowServer ready line specifically (CoreDisplay alone
   * is not enough; printf buffering used to hide that line). */
  [script appendString:@"    if grep -q '\\[framebufferd\\] CAWindowServer ready, "
                       @"display=yes' \"$LOG\" 2>/dev/null; then "
                       @"disp_pre=1; break; fi\n"];
  [script appendString:@"    if grep -q \"FAIL: no CAWindowServerDisplay\" "
                       @"\"$LOG\" 2>/dev/null || "
                       @"grep -q '\\[framebufferd\\] FAIL:' \"$LOG\" "
                       @"2>/dev/null; then\n"];
  [script appendString:@"      write_reason \"Mode B framebufferd display pipeline "
                       @"failed after WS unload. Restored Aqua. See "
                       @"$PERSIST_LOG.\"\n"];
  [script appendString:@"      restore_aqua\n"];
  [script appendString:@"      exit 0\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    fpid=$(live_root_pid "
                       @"/tmp/libwayland-support/framebufferd.pid framebufferd "
                       @"|| true)\n"];
  [script appendString:@"    if [ -z \"$fpid\" ]; then\n"];
  [script appendString:@"      write_reason \"Mode B framebufferd died during "
                       @"CoreDisplay bring-up. Restored Aqua. See "
                       @"$PERSIST_LOG.\"\n"];
  [script appendString:@"      restore_aqua\n"];
  [script appendString:@"      exit 0\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    di=$((di + 1)); sleep 0.25\n"];
  [script appendString:@"  done\n"];
  [script appendString:@"  if [ \"$disp_pre\" != 1 ]; then\n"];
  [script appendString:@"    write_reason \"Mode B timed out waiting for "
                       @"framebufferd CAWindowServer ready after WS unload. "
                       @"Restored Aqua. See $PERSIST_LOG.\"\n"];
  [script appendString:@"    restore_aqua\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  install_ws_guard\n"];
  [script appendString:@"  wwn_log \"waiting for inputd IOHIDEventSystem capture "
                       @"(keyboard required for escape chords)\"\n"];
  [script appendString:@"  hid_ok=0\n"];
  [script appendString:@"  hi=0\n"];
  [script appendString:@"  while [ \"$hi\" -lt 80 ]; do\n"];
  [script appendString:@"    cp \"$LOG\" \"$PERSIST_LOG\" 2>/dev/null || true\n"];
  [script appendString:@"    if grep -q '\\[inputd\\] IOHIDEventSystem capture started' "
                       @"\"$LOG\" 2>/dev/null; then hid_ok=1; break; fi\n"];
  [script appendString:@"    if grep -q '\\[inputd\\] FAIL: IOHIDEventSystemCreate "
                       @"exhausted' \"$LOG\" 2>/dev/null; then break; fi\n"];
  [script appendString:@"    hi=$((hi + 1)); sleep 0.25\n"];
  [script appendString:@"  done\n"];
  [script appendString:@"  if [ \"$hid_ok\" != 1 ]; then\n"];
  [script appendString:@"    write_reason \"Mode B inputd never started HID capture "
                       @"(no keyboard / no Ctrl+Option escape). Restored Aqua. "
                       @"See $PERSIST_LOG.\"\n"];
  [script appendString:@"    restore_aqua\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  wwn_log \"framebufferd display pipeline ready; "
                       @"inputd HID capture ok; starting Mode B client\"\n"];
  [script appendString:@"  unset WWN_MODEB_DEFER_DISPLAY\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"set +e\n"];
  /* gl-renderer needs GLES in the flat namespace; Mode B owns EGL. Insert
   * matching ANGLE libEGL_angle (or legacy libEGL) + libGLESv2 after the
   * dylib. Never put the iland libEGL shim before Mode B.
   * Classic: spawn client via launchd so it is born on the system
   * bootstrap (session subset look_up stays KERN_EXCEPTION_PROTECTED
   * even after bootstrap_parent walk, 2026-08-21). KEEP_WS: shell spawn.
   * Classic proof client is currently kmscube (DRM/KMS), not weston. */
  {
    NSString *fw =
        [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:@"Contents/Frameworks"];
    NSString *eglAnglePath =
        [fw stringByAppendingPathComponent:@"libEGL_angle.dylib"];
    NSString *eglPath =
        [fw stringByAppendingPathComponent:@"libEGL.dylib"];
    NSString *glesPath =
        [fw stringByAppendingPathComponent:@"libGLESv2.dylib"];
    NSString *eglForModeB = nil;
    if (eglAnglePath.length > 0 &&
        [[NSFileManager defaultManager] fileExistsAtPath:eglAnglePath]) {
      eglForModeB = eglAnglePath;
    } else if (eglPath.length > 0 &&
               [[NSFileManager defaultManager] fileExistsAtPath:eglPath]) {
      eglForModeB = eglPath;
    }
    BOOL haveEgl = eglForModeB.length > 0;
    BOOL haveGles = glesPath.length > 0 &&
                    [[NSFileManager defaultManager] fileExistsAtPath:glesPath];
    if (haveEgl && haveGles) {
      [script appendFormat:
          @"WWN_MODEB_INSERT=\"$WWN_MODEB_DYLIB:%@:%@\"\n", eglForModeB,
          glesPath];
    } else if (haveGles) {
      [script appendFormat:@"WWN_MODEB_INSERT=\"$WWN_MODEB_DYLIB:%@\"\n",
                           glesPath];
    } else if (haveEgl) {
      [script appendFormat:@"WWN_MODEB_INSERT=\"$WWN_MODEB_DYLIB:%@\"\n",
                           eglForModeB];
    } else {
      [script appendString:@"WWN_MODEB_INSERT=\"$WWN_MODEB_DYLIB\"\n"];
    }
  }
  {
    NSString *base = [executablePath lastPathComponent];
    BOOL skipWestonOut =
        [base isEqualToString:@"kmscube"] ||
        [base isEqualToString:@"igettyd"] ||
        [base isEqualToString:@"modeb-ttyd"] ||
        [base isEqualToString:@"modeb-tty"];
    [script appendFormat:@"WWN_MODEB_PROOF_KMSCUBE=%d\n", skipWestonOut ? 1 : 0];
  }
  [script appendString:@"WWN_MODEB_CLIENT_ARGV=("];
  [script appendFormat:@"%@ ", [self wwnShellQuote:executablePath]];
  for (NSString *arg in arguments) {
    [script appendFormat:@"%@ ", [self wwnShellQuote:arg]];
  }
  [script appendString:@")\n"];
  [script appendString:@"if [ -f /tmp/wawona-modeb-keep-ws ]; then\n"];
  [script appendString:@"  DYLD_INSERT_LIBRARIES=\"$WWN_MODEB_INSERT\" "
                       @"\"${WWN_MODEB_CLIENT_ARGV[@]}\" >>\"$LOG\" 2>&1 &\n"];
  [script appendString:@"  pid=$!\n"];
  [script appendString:@"else\n"];
  [script appendString:@"  wwn_log \"Classic: launch Mode B client via launchd "
                       @"(system bootstrap; proof=$WWN_MODEB_PROOF_KMSCUBE)\"\n"];
  [script appendString:@"  /bin/launchctl bootout system/com.wayland-mac.modeb-client "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"  /bin/launchctl bootout system/com.wayland-mac.weston "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"  WRAP=/tmp/libwayland-support/run-modeb-client.sh\n"];
  [script appendString:@"  EXPORTS=/tmp/libwayland-support/modeb-client-exports.sh\n"];
  [script appendString:@"  export -p > \"$EXPORTS\" 2>/dev/null || true\n"];
  [script appendString:@"  {\n"];
  [script appendString:@"    echo '#!/bin/bash'\n"];
  [script appendString:@"    echo 'set -a'\n"];
  [script appendString:@"    echo \". \\\"$EXPORTS\\\" 2>/dev/null || true\"\n"];
  [script appendString:@"    echo 'set +a'\n"];
  [script appendString:@"    echo \"export DYLD_INSERT_LIBRARIES=$(printf %q "
                       @"\"$WWN_MODEB_INSERT\")\"\n"];
  [script appendString:@"    echo -n 'exec'\n"];
  [script appendString:@"    for a in \"${WWN_MODEB_CLIENT_ARGV[@]}\"; do\n"];
  [script appendString:@"      printf ' %q' \"$a\"\n"];
  [script appendString:@"    done\n"];
  [script appendString:@"    printf ' >>%q 2>&1\\n' \"$LOG\"\n"];
  [script appendString:@"  } > \"$WRAP\"\n"];
  [script appendString:@"  /bin/chmod 755 \"$WRAP\"\n"];
  [script appendString:@"  /bin/cat > /Library/LaunchDaemons/com.wayland-mac.modeb-client.plist "
                       @"<<PLIST\n"];
  [script appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
  [script appendString:@"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
                       @"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"];
  [script appendString:@"<plist version=\"1.0\"><dict>\n"];
  [script appendString:@"  <key>Label</key><string>com.wayland-mac.modeb-client</string>\n"];
  [script appendString:@"  <key>ProgramArguments</key><array>\n"];
  [script appendString:@"    <string>/tmp/libwayland-support/run-modeb-client.sh</string>\n"];
  [script appendString:@"  </array>\n"];
  [script appendString:@"  <key>RunAtLoad</key><true/>\n"];
  [script appendString:@"  <key>KeepAlive</key><false/>\n"];
  [script appendString:@"  <key>UserName</key><string>root</string>\n"];
  [script appendString:@"  <key>StandardOutPath</key><string>/tmp/wawona-modeb.log</string>\n"];
  [script appendString:@"  <key>StandardErrorPath</key><string>/tmp/wawona-modeb.log</string>\n"];
  [script appendString:@"</dict></plist>\n"];
  [script appendString:@"PLIST\n"];
  [script appendString:@"  /usr/bin/chmod 644 "
                       @"/Library/LaunchDaemons/com.wayland-mac.modeb-client.plist\n"];
  [script appendString:@"  /bin/launchctl bootstrap system "
                       @"/Library/LaunchDaemons/com.wayland-mac.modeb-client.plist "
                       @">>\"$LOG\" 2>&1\n"];
  [script appendString:@"  boot_st=$?\n"];
  [script appendString:@"  wwn_log \"modeb-client bootstrap_st=$boot_st\"\n"];
  [script appendString:@"  pid=$(/bin/launchctl print "
                       @"system/com.wayland-mac.modeb-client 2>/dev/null | "
                       @"/usr/bin/awk '/[[:space:]]pid = /{print $3; exit}')\n"];
  [script appendString:@"  if [ -z \"$pid\" ]; then\n"];
  [script appendString:@"    sleep 0.5\n"];
  [script appendString:@"    pid=$(/bin/launchctl print "
                       @"system/com.wayland-mac.modeb-client 2>/dev/null | "
                       @"/usr/bin/awk '/[[:space:]]pid = /{print $3; exit}')\n"];
  [script appendString:@"  fi\n"];
  /* 2026-08-21: bootstrap 141 Reentrancy avoided under Classic (ws-guard /
   * concurrent launchd). Fall back to direct root spawn with DYLD_INSERT so
   * Mode B TTY/kmscube still start; Mach look_up may need parent walk. */
  [script appendString:@"  if [ -z \"$pid\" ]; then\n"];
  [script appendString:@"    wwn_log \"launchd client missing after bootstrap; "
                       @"falling back to direct spawn\"\n"];
  [script appendString:@"    DYLD_INSERT_LIBRARIES=\"$WWN_MODEB_INSERT\" "
                       @"\"${WWN_MODEB_CLIENT_ARGV[@]}\" >>\"$LOG\" 2>&1 &\n"];
  [script appendString:@"    pid=$!\n"];
  [script appendString:@"    sleep 0.3\n"];
  [script appendString:@"    if ! kill -0 \"$pid\" 2>/dev/null; then\n"];
  [script appendString:@"      pid=\"\"\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  if [ -z \"$pid\" ]; then\n"];
  [script appendString:@"    write_reason \"Mode B failed to launch client "
                       @"(launchd + direct spawn). Restored Aqua. See "
                       @"$PERSIST_LOG.\"\n"];
  [script appendString:@"    restore_aqua\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"echo \"$pid\" > \"$PIDFILE\"\n"];
  [script appendString:@"chmod 644 \"$PIDFILE\" 2>/dev/null || true\n"];
  [script appendString:@"wwn_log \"Mode B client pid=$pid "
                       @"proof_kmscube=$WWN_MODEB_PROOF_KMSCUBE\"\n"];
  [script appendString:@"ps -p \"$pid\" -o pid,user,command >>\"$LOG\" 2>&1 || true\n"];
  [script appendString:@"fb_live=0\n"];
  [script appendString:@"fb_i=0\n"];
  [script appendString:@"while [ \"$fb_i\" -lt 40 ]; do\n"];
  [script appendString:@"  fpid=$(cat /tmp/libwayland-support/framebufferd.pid "
                       @"2>/dev/null || true)\n"];
  [script appendString:@"  if [ -n \"$fpid\" ] && kill -0 \"$fpid\" 2>/dev/null; then\n"];
  [script appendString:@"    fb_live=1\n"];
  [script appendString:@"    wwn_log \"framebufferd pid=$fpid live (kill -0)\"\n"];
  [script appendString:@"    break\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  if [ -n \"$fpid\" ]; then\n"];
  [script appendString:@"    wwn_log \"framebufferd.pid=$fpid dead\"\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  if ! kill -0 \"$pid\" 2>/dev/null; then\n"];
  [script appendString:@"    wwn_log \"compositor died before framebufferd\"\n"];
  [script appendString:@"    break\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  fb_i=$((fb_i + 1))\n"];
  [script appendString:@"  sleep 0.25\n"];
  [script appendString:@"done\n"];
  [script appendString:@"ls -la /tmp/libwayland-support >>\"$LOG\" 2>&1 || true\n"];
  /* 2026-08-21: bootstrap_register failure left WS down with no present. */
  [script appendString:@"if grep -q '\\[framebufferd\\] bootstrap_register' "
                       @"\"$LOG\" 2>/dev/null && "
                       @"! grep -q '\\[framebufferd\\] listening' \"$LOG\" "
                       @"2>/dev/null; then\n"];
  [script appendString:@"  write_reason \"Mode B framebufferd bootstrap_register "
                       @"failed (no Mach present). Restored Aqua immediately. "
                       @"See $PERSIST_LOG.\"\n"];
  [script appendString:@"  restore_aqua\n"];
  [script appendString:@"  exit 0\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"if [ \"$fb_live\" != 1 ]; then\n"];
  [script appendString:@"  write_reason \"Mode B did not start framebufferd. "
                       @"Apple's WindowServer was restored. See "
                       @"/tmp/wawona-modeb.log and $PERSIST_LOG.\"\n"];
  [script appendString:@"  restore_aqua\n"];
  [script appendString:@"  exit 0\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"cp \"$LOG\" \"$PERSIST_LOG\" 2>/dev/null || true\n"];
  /* KEEP_WS: ready as soon as Mach framebufferd is live (no panel).
   * Classic weston: Output enabled + present.
   * Classic kmscube proof: display + present only (no weston Output line). */
  [script appendString:@"if [ -f /tmp/wawona-modeb-keep-ws ]; then\n"];
  [script appendString:@"  touch /tmp/libwayland-support/modeb-framebufferd.ready\n"];
  [script appendString:@"  chmod 644 /tmp/libwayland-support/modeb-framebufferd.ready "
                       @"2>/dev/null || true\n"];
  [script appendString:@"else\n"];
  [script appendString:@"  out_ok=0\n"];
  [script appendString:@"  disp_ok=0\n"];
  [script appendString:@"  present_ok=0\n"];
  [script appendString:@"  oi=0\n"];
  [script appendString:@"  while [ \"$oi\" -lt 80 ]; do\n"];
  [script appendString:@"    cp \"$LOG\" \"$PERSIST_LOG\" 2>/dev/null || true\n"];
  [script appendString:@"    if grep -q '\\[framebufferd\\] CoreDisplay "
                       @"initialised' \"$LOG\" 2>/dev/null; then "
                       @"disp_ok=1; fi\n"];
  [script appendString:@"    if grep -q '\\[framebufferd\\] CAWindowServer ready, "
                       @"display=yes' \"$LOG\" 2>/dev/null; then "
                       @"disp_ok=1; fi\n"];
  [script appendString:@"    if grep -q \"FAIL: no CAWindowServerDisplay\" "
                       @"\"$LOG\" 2>/dev/null; then\n"];
  [script appendString:@"      write_reason \"Mode B framebufferd has no "
                       @"CAWindowServerDisplay (blank panel). Restored Aqua. "
                       @"See $PERSIST_LOG.\"\n"];
  [script appendString:@"      restore_aqua\n"];
  [script appendString:@"      exit 0\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    if [ \"$WWN_MODEB_PROOF_KMSCUBE\" = 1 ]; then\n"];
  [script appendString:@"      out_ok=1\n"];
  [script appendString:@"    elif grep -q '\\[igettyd\\] ready' \"$LOG\" "
                       @"2>/dev/null; then\n"];
  [script appendString:@"      out_ok=1\n"];
  [script appendString:@"    elif grep -E -q \"Output '.*' enabled\" \"$LOG\" "
                       @"2>/dev/null; then\n"];
  [script appendString:@"      out_ok=1\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    if grep -q 'presentSurface n=' \"$LOG\" 2>/dev/null; then\n"];
  [script appendString:@"      present_ok=1\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    if [ \"$out_ok\" = 1 ] && [ \"$disp_ok\" = 1 ] && "
                       @"[ \"$present_ok\" = 1 ]; then\n"];
  [script appendString:@"      break\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    if ! kill -0 \"$pid\" 2>/dev/null; then\n"];
  [script appendString:@"      wwn_log \"Mode B client died before present\"\n"];
  [script appendString:@"      break\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    oi=$((oi + 1))\n"];
  [script appendString:@"    sleep 0.25\n"];
  [script appendString:@"  done\n"];
  [script appendString:@"  cp \"$LOG\" \"$PERSIST_LOG\" 2>/dev/null || true\n"];
  [script appendString:@"  if [ \"$out_ok\" != 1 ] || [ \"$disp_ok\" != 1 ] || "
                       @"[ \"$present_ok\" != 1 ]; then\n"];
  [script appendString:@"    write_reason \"Mode B Classic blank fail-closed "
                       @"(out=$out_ok disp=$disp_ok present=$present_ok "
                       @"kmscube=$WWN_MODEB_PROOF_KMSCUBE within 20s). Restored "
                       @"Aqua. See $PERSIST_LOG.\"\n"];
  [script appendString:@"    restore_aqua\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  wwn_log \"Classic CoreDisplay+present ok "
                       @"(proof=$WWN_MODEB_PROOF_KMSCUBE)\"\n"];
  [script appendString:@"  touch /tmp/libwayland-support/modeb-framebufferd.ready\n"];
  [script appendString:@"  chmod 644 /tmp/libwayland-support/modeb-framebufferd.ready "
                       @"2>/dev/null || true\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"trap 'restore_aqua; exit 0' TERM INT HUP\n"];
  [script appendString:@"sleep 0.4\n"];
  /*
   * Classic kmscube/weston are born under launchd (system bootstrap). That
   * pid is not a shell child, so `wait $pid` returns immediately and used to
   * restore Aqua ~1s after the first present (2026-08-21 kmscube flash).
   * Poll kill -0 instead; KEEP_WS shell-backgrounded clients still use wait.
   */
  [script appendString:@"if [ -f /tmp/wawona-modeb-keep-ws ]; then\n"];
  [script appendString:@"  if ! kill -0 \"$pid\" 2>/dev/null; then\n"];
  [script appendString:@"    wait \"$pid\"\n"];
  [script appendString:@"    status=$?\n"];
  [script appendString:@"    restore_aqua\n"];
  [script appendString:@"    write_reason \"The nested compositor failed to start "
                       @"(status $status). See /tmp/wawona-modeb.log.\"\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  wait \"$pid\"\n"];
  [script appendString:@"  status=$?\n"];
  [script appendString:@"else\n"];
  [script appendString:@"  wwn_log \"Classic hold: poll Mode B client pid=$pid "
                       @"(launchd; not a shell child)\"\n"];
  [script appendString:@"  status=0\n"];
  [script appendString:@"  while kill -0 \"$pid\" 2>/dev/null; do\n"];
  [script appendString:@"    if [ -f /tmp/libwayland-support/modeb-restore-aqua ]; then\n"];
  [script appendString:@"      wwn_log \"modeb-restore-aqua stamp; restoring Aqua\"\n"];
  [script appendString:@"      rm -f /tmp/libwayland-support/modeb-restore-aqua\n"];
  [script appendString:@"      restore_aqua\n"];
  [script appendString:@"      exit 0\n"];
  [script appendString:@"    fi\n"];
  [script appendString:@"    cp \"$LOG\" \"$PERSIST_LOG\" 2>/dev/null || true\n"];
  [script appendString:@"    sleep 1\n"];
  [script appendString:@"  done\n"];
  [script appendString:@"  wait \"$pid\" 2>/dev/null\n"];
  [script appendString:@"  status=$?\n"];
  [script appendString:@"  if [ \"$status\" -eq 127 ]; then status=0; fi\n"];
  [script appendString:@"  if [ -f /tmp/libwayland-support/modeb-restore-aqua ]; then\n"];
  [script appendString:@"    wwn_log \"modeb-restore-aqua after client exit; restoring Aqua\"\n"];
  [script appendString:@"    rm -f /tmp/libwayland-support/modeb-restore-aqua\n"];
  [script appendString:@"    restore_aqua\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  wwn_log \"Classic Mode B client pid=$pid exited "
                       @"status=$status\"\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"set -e\n"];
  /*
   * 0 / SIGTERM (143) / SIGHUP (129) / SIGINT (130): logout or disengage.
   * Restore Aqua and stay quiet. Any other exit is a failed session.
   */
  [script appendString:@""
                       @"if [ \"$status\" -eq 0 ] || [ \"$status\" -eq 143 ] || "
                       @"[ \"$status\" -eq 129 ] || [ \"$status\" -eq 130 ] || "
                       @"[ \"$status\" -eq 15 ]; then\n"
                       @"  restore_aqua\n"
                       @"  exit 0\n"
                       @"fi\n"
                       @"restore_aqua\n"
                       @"write_reason \"The nested compositor exited "
                       @"(status $status). Wawona restored Apple's "
                       @"WindowServer. Details: /tmp/wawona-modeb.log.\"\n"
                       @"exit 0\n"];
  return script;
}

- (BOOL)installModeBHelperAndDylibForProfile:(WWNMachineProfile *)profile
                                       error:(NSError *_Nullable *_Nullable)error {
  NSString *bundledDylib = [self bundledDylibPath];
  if (bundledDylib.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"This Wawona build does not ship libwayland-mac.dylib "
                       @"(Mode B). Reinstall with nix run .#install."
                 }];
    }
    return NO;
  }

  NSString *executablePath = nil;
  NSArray<NSString *> *launchArgs = nil;
  NSDictionary<NSString *, NSString *> *launchEnv = nil;
  NSError *specError = nil;
  if (![[WWNWaypipeRunner sharedRunner]
          baremetalCompositorLaunchSpecForProfile:profile
                                       executable:&executablePath
                                        arguments:&launchArgs
                                      environment:&launchEnv
                                            error:&specError]) {
    if (error) {
      *error = specError;
    }
    return NO;
  }

  NSString *installedDylib = [self installedDylibPath];
  NSString *installedDylibDir =
      [installedDylib stringByDeletingLastPathComponent];
  NSString *helperPath = [self modeBHelperPath];
  NSString *iowPath = [self modeBIowatchdogPath];
  NSString *bundledIow = [self bundledIowatchdogPath];
  if (bundledIow.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"This Wawona build does not ship wwn-iowatchdog "
                       @"(Mode B). Reinstall with nix run .#install."
                 }];
    }
    return NO;
  }
  NSString *userName = NSUserName();
  uid_t uid = getuid();
  NSString *script = [self modeBLaunchScriptForExecutable:executablePath
                                                arguments:launchArgs ?: @[]
                                              environment:launchEnv ?: @{}
                                                    dylib:installedDylib];
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpScript =
      [tmpDir stringByAppendingPathComponent:@"wawona-modeb-helper.src"];
  NSString *tmpSudoers =
      [tmpDir stringByAppendingPathComponent:@"wawona-modeb-sudoers"];
  if (![script writeToFile:tmpScript
                atomically:YES
                  encoding:NSUTF8StringEncoding
                     error:error]) {
    return NO;
  }
  NSString *sudoers = [self modeBSudoersBodyForUser:userName];
  if (![sudoers writeToFile:tmpSudoers
          atomically:YES
            encoding:NSUTF8StringEncoding
                      error:error]) {
    return NO;
  }

  NSString *loginAgentPath = [self modeBLoginAgentPath];
  NSString *shellCmd = [NSString
        stringWithFormat:
          @"set +e\n"
          @"STAGELOG=/tmp/wawona-modeb-stage.log\n"
          @": > \"$STAGELOG\"\n"
          @"chmod 666 \"$STAGELOG\" 2>/dev/null || true\n"
          @"log() { echo \"$(date) $*\" >>\"$STAGELOG\"; }\n"
          @"log stage-start\n"
          @"/bin/launchctl enable system/com.apple.WindowServer >/dev/null 2>&1 || true\n"
          @"/bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.WindowServer.plist >/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.WindowServer.plist >/dev/null 2>&1 || true\n"
          @"wspid=$(/bin/launchctl print system/com.apple.WindowServer 2>/dev/null | awk '/[[:space:]]pid =/{print $3; exit}')\n"
          @"if [ -z \"$wspid\" ]; then "
          @"/bin/launchctl kickstart -k system/com.apple.WindowServer >/dev/null 2>&1 || true; "
          @"log ws-kickstart; else log \"ws-pid=$wspid\"; fi\n"
          @"ps -axo pid=,command= 2>/dev/null | while read -r pid cmd; do\n"
          @"  case \"$cmd\" in\n"
          @"    /bin/bash\\ /Library/Application\\ Support/Wawona/run-modeb.sh*|"
          @"/bin/sh\\ /Library/Application\\ Support/Wawona/run-modeb.sh*|"
          @"bash\\ /Library/Application\\ Support/Wawona/run-modeb.sh*|"
          @"/Library/Application\\ Support/Wawona/run-modeb.sh*)\n"
          @"      log \"kill leftover helper pid=$pid\"\n"
          @"      kill -KILL \"$pid\" 2>/dev/null || true\n"
          @"      ;;\n"
          @"  esac\n"
          @"done\n"
          @"/bin/rm -rf /tmp/libwayland-support/modeb.lock\n"
          @"log lock-cleared\n"
          @"/bin/rm -f %@ %@ "
          @"/tmp/libwayland-support/modeb-framebufferd.ready\n"
          @"set -e\n"
          @"trap 'log stage-fail st=$? line=$LINENO' ERR\n"
          @"log copying\n"
          @"mkdir -p %@ %@\n"
          @"cp %@ %@\n"
          @"chmod 755 %@\n"
          @"cp %@ %@\n"
          @"cp %@ %@\n"
          @"chown root:wheel %@ %@ %@\n"
          @"chmod 755 %@ %@ %@\n"
          @"# Prior Take Over may leave com.apple.watchdogd disabled. Re-enable "
          @"the launchd job only (never kickstart -k, never attach lldb, never "
          @"call wwn-iowatchdog disable/enable here). Install stage probe via "
          @"lldb paniced 2026-08-20: watchdogd exited SIGTRAP (namespace 2 "
          @"subcode 0x5) while kernel IOWatchdog was still armed.\n"
          @"log watchdogd-ensure\n"
          @"# Never re-enable Apple watchdogd when Path B/A is armed or has\n"
          @"# claim-ok. Stage used to bootstrap Apple here and raced Path B:\n"
          @"# plain Apple watchdogd came up with monitoring armed while\n"
          @"# claim-ok still said sticky=1. Classic Take Over then unloaded\n"
          @"# and 25F80 paniced (watchdogd exited SIGTRAP ns2/0x5,\n"
          @"# 2026-08-20 evening).\n"
          @"if [ -f /var/db/wwn-iowatchdog/claim-ok ] || "
          @"[ -f /var/db/wwn-iowatchdog/claim-pending ] || "
          @"[ -f /Library/LaunchDaemons/com.aspauldingcode.wwn-iowatchdog-pathb.plist ] || "
          @"[ -f /Library/LaunchDaemons/com.aspauldingcode.wwn-iowatchdog-claim.plist ]; then\n"
          @"  log 'watchdogd-ensure SKIP (Path A/B arm or claim-ok present)'\n"
          @"else\n"
          @"  /bin/launchctl enable system/com.apple.watchdogd "
          @">/dev/null 2>&1 || true\n"
          @"  /bin/launchctl load -w "
          @"/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
          @">/dev/null 2>&1 || true\n"
          @"  /bin/launchctl bootstrap system "
          @"/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
          @">/dev/null 2>&1 || true\n"
          @"  log watchdogd-ensure-done\n"
          @"fi\n"
          @"/usr/sbin/visudo -cf %@ >/dev/null\n"
          @"/usr/bin/install -m 440 -o root -g wheel %@ %@\n"
          @"/usr/sbin/visudo -cf /etc/sudoers >/dev/null\n"
          @"rm -f %@\n"
          @"/bin/launchctl bootout gui/%u/%@ >/dev/null 2>&1 || true\n"
          @"rm -f %@ %@\n"
          @"touch %@\n"
          @"chmod 666 %@\n"
          @"chown %@ %@\n"
          @"/bin/launchctl bootout system/%@ >/dev/null 2>&1 || true\n"
          @"rm -f %@\n"
          @"# Stage must NOT install ws-guard. Guard is installed only on "
          @"Classic Take Over / KEEP_WS engage (see run-modeb.sh).\n"
          @"/bin/launchctl bootout system/com.aspauldingcode.wawona.ws-guard "
          @">/dev/null 2>&1 || true\n"
          @"rm -f /Library/LaunchDaemons/com.aspauldingcode.wawona.ws-guard.plist\n"
          @"log copied-ok\n"
          @"echo WWN_MODEB_INSTALLED=1\n"
          @"log done\n"
          @"exit 0\n",
          [self wwnShellQuote:kWWNModeBPidPath],
          [self wwnShellQuote:kWWNModeBFailReasonPath],
          [self wwnShellQuote:[kWWNModeBSupportDir
                                  stringByAppendingPathComponent:@"bin"]],
          [self wwnShellQuote:installedDylibDir],
          [self wwnShellQuote:tmpScript], [self wwnShellQuote:helperPath],
          [self wwnShellQuote:helperPath],
          [self wwnShellQuote:bundledDylib], [self wwnShellQuote:installedDylib],
          [self wwnShellQuote:bundledIow], [self wwnShellQuote:iowPath],
          [self wwnShellQuote:helperPath], [self wwnShellQuote:installedDylib],
          [self wwnShellQuote:iowPath],
          [self wwnShellQuote:helperPath], [self wwnShellQuote:installedDylib],
          [self wwnShellQuote:iowPath],
          [self wwnShellQuote:tmpSudoers],
          [self wwnShellQuote:tmpSudoers],
          [self wwnShellQuote:kWWNModeBSudoersPath],
          [self wwnShellQuote:loginAgentPath],
          (unsigned)uid, kWWNModeBLoginAgentLabel,
          [self wwnShellQuote:kWWNModeBPidPath],
          [self wwnShellQuote:kWWNModeBFailReasonPath],
          [self wwnShellQuote:kWWNModeBLogPath],
          [self wwnShellQuote:kWWNModeBLogPath],
          [self wwnShellQuote:userName], [self wwnShellQuote:kWWNModeBLogPath],
          kWWNModeBLaunchdLabel,
          [self wwnShellQuote:[self modeBPlistPath]]];

  /*
   * Prefer passwordless sudo when available (dev machines / CI). Avoid hanging
   * on AuthorizationExecuteWithPrivileges GUI when `sudo -n` works.
   */
  {
    NSTask *sudoProbe = [[NSTask alloc] init];
    sudoProbe.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
    sudoProbe.arguments = @[ @"-n", @"true" ];
    sudoProbe.standardOutput = [NSPipe pipe];
    sudoProbe.standardError = [NSPipe pipe];
    NSError *probeErr = nil;
    BOOL probed = [sudoProbe launchAndReturnError:&probeErr];
    if (probed) {
      [sudoProbe waitUntilExit];
    }
    if (probed && sudoProbe.terminationStatus == 0) {
      NSTask *sudoInstall = [[NSTask alloc] init];
      sudoInstall.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
      sudoInstall.arguments = @[ @"-n", @"/bin/sh", @"-c", shellCmd ];
      NSPipe *outPipe = [NSPipe pipe];
      NSPipe *errPipe = [NSPipe pipe];
      sudoInstall.standardOutput = outPipe;
      sudoInstall.standardError = errPipe;
      NSError *launchErr = nil;
      if (![sudoInstall launchAndReturnError:&launchErr]) {
        if (error) {
          *error = launchErr ?: [NSError
                                    errorWithDomain:@"WWNDesktopReplacement"
                                               code:5
                                           userInfo:@{
                                             NSLocalizedDescriptionKey :
                                                 @"sudo -n stage launch failed."
                                           }];
        }
        return NO;
      }
      [sudoInstall waitUntilExit];
      NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
      NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
      NSMutableString *outStr = [NSMutableString string];
      if (outData.length) {
        [outStr appendString:[[NSString alloc] initWithData:outData
                                                   encoding:NSUTF8StringEncoding]
                                 ?: @""];
      }
      if (errData.length) {
        [outStr appendString:[[NSString alloc] initWithData:errData
                                                   encoding:NSUTF8StringEncoding]
                                 ?: @""];
      }
      BOOL ok = [outStr containsString:@"WWN_MODEB_INSTALLED=1"] ||
                sudoInstall.terminationStatus == 0;
      if (!ok) {
        NSString *stageLog = [NSString
            stringWithContentsOfFile:@"/tmp/wawona-modeb-stage.log"
                            encoding:NSUTF8StringEncoding
                               error:nil];
        if (error) {
          *error = [NSError
              errorWithDomain:@"WWNDesktopReplacement"
                         code:5
                     userInfo:@{
                       NSLocalizedDescriptionKey : [NSString
                           stringWithFormat:
                               @"sudo -n Mode B stage failed (status=%d). "
                               @"output=%@ stage-log=%@",
                               (int)sudoInstall.terminationStatus, outStr,
                               stageLog ?: @"(empty)"]
                     }];
        }
        return NO;
      }
      return YES;
    }
  }

  AuthorizationRef authRef;
  OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                        kAuthorizationFlagDefaults, &authRef);
  if (status != errAuthorizationSuccess) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                                   code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Authorization creation failed."
                 }];
    }
    return NO;
  }

  AuthorizationItem right = {kAuthorizationRightExecute, 0, NULL, 0};
  AuthorizationRights rights = {1, &right};
  AuthorizationFlags flags = kAuthorizationFlagDefaults |
                             kAuthorizationFlagInteractionAllowed |
                             kAuthorizationFlagPreAuthorize |
                             kAuthorizationFlagExtendRights;
  status = AuthorizationCopyRights(authRef, &rights, NULL, flags, NULL);
  if (status != errAuthorizationSuccess) {
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                                   code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"User cancelled administrator authorization."
                 }];
    }
    return NO;
  }

  char *args[] = {"-c", (char *)shellCmd.UTF8String, NULL};
  FILE *pipe = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  status = AuthorizationExecuteWithPrivileges(
      authRef, "/bin/sh", kAuthorizationFlagDefaults, args, &pipe);
#pragma clang diagnostic pop
  if (status != errAuthorizationSuccess) {
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Failed to install Mode B helper "
                           @"(status=%d).",
                           (int)status]
                 }];
    }
    return NO;
  }

  NSMutableString *outStr = [NSMutableString string];
  if (pipe) {
    char buf[256];
    while (fgets(buf, sizeof(buf), pipe)) {
      [outStr appendFormat:@"%s", buf];
    }
      fclose(pipe);
  }
  AuthorizationFree(authRef, kAuthorizationFlagDefaults);
  BOOL ok = [outStr containsString:@"WWN_MODEB_INSTALLED=1"];
  if (!ok) {
    NSString *stageLog =
        [NSString stringWithContentsOfFile:@"/tmp/wawona-modeb-stage.log"
                                  encoding:NSUTF8StringEncoding
                                     error:nil];
    stageLog = [stageLog
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:6
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Mode B helper install did not finish "
                           @"(output=%@). stage-log=%@",
                           [outStr stringByTrimmingCharactersInSet:
                                       [NSCharacterSet
                                           whitespaceAndNewlineCharacterSet]],
                           stageLog.length ? stageLog : @"(empty)"]
                 }];
    }
    return NO;
  }
  WWNModeBCliLog(@"installed Mode B helper %@ dylib %@ executable=%@",
                 helperPath, installedDylib, executablePath);
  return YES;
}

- (BOOL)engageSelectedDesktopMachine:(NSError *_Nullable *_Nullable)error {
  if (![self ensureDesktopMachineSelected:error]) {
    return NO;
  }
  NSString *desktopId = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsDesktopReplacementMachineId];
  WWNMachineProfile *profile = [WWNMachineProfileStore profileById:desktopId];
  if (!profile) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:9
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"The selected Desktop Machine no longer exists."
                 }];
    }
    return NO;
  }
  return [self engageForProfile:profile error:error];
}

- (BOOL)engageForProfile:(WWNMachineProfile *)profile
                   error:(NSError *_Nullable *_Nullable)error {
  if (![self shouldEngageModeB]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Desktop Replacement Mode B is not enabled or SIP "
                       @"is not fully disabled (need csrutil disable)."
                 }];
    }
    return NO;
  }
  /*
   * Classic Take Over unloads watchdogd only after sticky claim-ok.
   * KEEP_WS probe may inject with Aqua up without ACK.
   */
  BOOL keepWs =
      [[NSFileManager defaultManager] fileExistsAtPath:kWWNModeBKeepWsPath];
  if (!keepWs && ![self iowatchdogStickyAckPresent]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:10
                 userInfo:@{
                   NSLocalizedDescriptionKey : WWNModeBTakeOverNeedsAckMessage()
                 }];
    }
    return NO;
  }
  if (![self isDesktopMachine:profile]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Profile is not the configured Desktop Replacement "
                       @"machine."
                 }];
    }
    return NO;
  }

  if (self.modeBPid > 0 && WWNProcessExists(self.modeBPid) &&
      [self.modeBMachineId isEqualToString:profile.machineId]) {
    return YES;
  }
  if (self.modeBPid > 0) {
    /*
     * A different Desktop profile (or a stale PID) must not share the
     * framebufferd/inputd set of the previous injected compositor. Mode B
     * helpers are owned by the dylib and exit with its compositor process.
     */
    NSError *stopError = nil;
    if (![self terminateModeBProcess:self.modeBPid error:&stopError]) {
      if (error) {
        *error = stopError;
      }
      return NO;
    }
    self.modeBPid = 0;
    self.modeBMachineId = nil;
  }

  NSString *bundledDylib = [self bundledDylibPath];
  if (bundledDylib.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"This Wawona build does not ship libwayland-mac.dylib "
                       @"(Mode B). Reinstall with nix run .#install."
                 }];
    }
    return NO;
  }

  NSString *executablePath = nil;
  NSArray<NSString *> *launchArgs = nil;
  NSDictionary<NSString *, NSString *> *launchEnv = nil;
  NSError *specError = nil;
  if (![[WWNWaypipeRunner sharedRunner]
          baremetalCompositorLaunchSpecForProfile:profile
                                       executable:&executablePath
                                        arguments:&launchArgs
                                      environment:&launchEnv
                                            error:&specError]) {
    if (error) {
      *error = specError;
    }
    return NO;
  }
  (void)launchArgs;
  (void)launchEnv;

  NSString *installedDylib = [self installedDylibPath];
  NSString *helperPath = [self modeBHelperPath];
  BOOL passwordless =
      [self sudoersAllowsHelper] &&
      [[NSFileManager defaultManager] isExecutableFileAtPath:helperPath];
  BOOL helperMatchesLaunch = NO;
  if (passwordless) {
    NSString *existingHelper =
        [NSString stringWithContentsOfFile:helperPath
                                  encoding:NSUTF8StringEncoding
                                     error:nil];
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    helperMatchesLaunch =
        existingHelper.length > 0 && bundlePath.length > 0 &&
        [existingHelper containsString:@"WWN_MODEB_INSERT=compositor-only"] &&
        [existingHelper containsString:@"WWN_MODEB_DYLIB="] &&
        [existingHelper containsString:installedDylib] &&
        [existingHelper containsString:executablePath] &&
        [existingHelper containsString:@"WWN_MODEB_GATE=pidfile-not-pgrep"] &&
        [existingHelper containsString:@"WWN_MODEB_GATE=live-fb-before-ws-unload"] &&
        [existingHelper containsString:@"WWN_MODEB_LOCK=helper-argv-only"] &&
        [existingHelper containsString:@"WWN_MODEB_WD=iowatchdog-then-unload"] &&
        [existingHelper containsString:@"stop_watchdogd_after_iowatchdog"] &&
        [existingHelper containsString:@"LIVE_DIS"] &&
        [existingHelper containsString:@"done=1"] &&
        [existingHelper containsString:@"skip restore_watchdogd"] &&
        [existingHelper containsString:@"wawona-unloaded-watchdogd"] &&
        [existingHelper containsString:@"stale modeb.lock"] &&
        [existingHelper containsString:@"# WWN_WAWONA_STORE="] &&
        [existingHelper containsString:bundlePath] &&
        ![existingHelper containsString:@"reap WindowServer"] &&
        ![existingHelper containsString:@"WWN_MODEB_WD=launchctl-unload"] &&
        ![existingHelper containsString:@"WWN_MODEB_WD=blocked-no-iowatchdog"] &&
        ![existingHelper containsString:@"echo path-b-takeover"] &&
        ![existingHelper
            containsString:@"kickstart -k system/com.apple.watchdogd"] &&
        ![existingHelper containsString:@"Mode B helper DISABLED"];
    NSString *guiCmd = launchEnv[@"WWN_IGETTY_GUI_CMD"] ?: @"";
    NSString *guiVt = launchEnv[@"WWN_IGETTY_GUI_VT"] ?: @"0";
    NSString *guiStamp =
        [NSString stringWithFormat:@"# WWN_MODEB_GUI_CMD=%@\n", guiCmd];
    NSString *vtStamp =
        [NSString stringWithFormat:@"# WWN_MODEB_GUI_VT=%@\n", guiVt];
    helperMatchesLaunch = helperMatchesLaunch &&
                          [existingHelper containsString:guiStamp] &&
                          [existingHelper containsString:vtStamp];
    if (!helperMatchesLaunch) {
      WWNModeBCliLog(
          @"passwordless helper at %@ is stale/broken (missing dylib/exec or "
          @"recovery stub). Requiring admin reinstall so we do not disable "
          @"WindowServer without injection.",
          helperPath);
    }
  }
  if (!(passwordless && helperMatchesLaunch)) {
    if (![self installModeBHelperAndDylibForProfile:profile error:error]) {
      return NO;
    }
  } else {
    WWNModeBCliLog(
        @"passwordless helper present at %@ and matches this engage.",
        helperPath);
    [self removeUserLoginAgent];
  }

  pid_t pid = [self startModeBHelperDetachedAndWait];
  NSString *trimmedOut = @"";
  if (pid <= 0) {
    [self restoreAquaIfNeeded];
      NSString *reason = [self consumeSessionFailureReason];
    if (error) {
      NSString *logTail = [self modeBLogTail];
      NSString *detail = reason;
      if (detail.length == 0 && logTail.length > 0) {
        detail = [NSString stringWithFormat:
                               @"Mode B helper ran but did not keep a compositor "
                               @"PID. Log:\n%@",
                               logTail];
      }
      if (detail.length == 0) {
        detail = [NSString stringWithFormat:
                               @"Mode B privileged launch failed to return a "
                               @"valid PID (output=%@). Take Over does not "
                               @"unload WindowServer or watchdogd. Probe "
                               @"may start the compositor while Aqua stays "
                               @"up. See /tmp/wawona-modeb.log.",
                               trimmedOut ?: @""];
      }
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:6
                 userInfo:@{NSLocalizedDescriptionKey : detail}];
    }
    return NO;
  }

  usleep(1500000);
  if (!WWNProcessExists(pid)) {
    [self restoreAquaIfNeeded];
    NSString *reason = [self consumeSessionFailureReason];
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:6
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       (reason.length
                            ? reason
                            : @"The nested compositor exited immediately. "
                              @"Wawona restored Apple's WindowServer. See "
                              @"/tmp/wawona-modeb.log.")
                 }];
    }
    return NO;
  }

  self.modeBPid = pid;
  self.modeBMachineId = [profile.machineId copy];
  NSLog(@"[DesktopReplacement] Mode B engaged pid=%d dylib=%@ executable=%@ "
        @"machineId=%@ log=/tmp/wawona-modeb.log",
        (int)pid, installedDylib, executablePath, profile.machineId);
  return YES;
}

- (NSString *)modeBFileCleanupShell {
  uid_t uid = getuid();
  NSString *wsGuardPlist = [NSString
      stringWithFormat:@"/Library/LaunchDaemons/%@.plist",
                       kWWNModeBWsGuardLabel];
  return [NSString
      stringWithFormat:
          @"/bin/launchctl bootout gui/%u/%@ >/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootout system/%@ >/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootout system/%@ >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x niri >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x weston >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x kmscube >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x gbm-es2-demo >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x gbm_es2_demo >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x vkcube-kms >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x igettyd >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x modeb-ttyd >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x framebufferd >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x inputd >/dev/null 2>&1 || true\n"
          @"rm -f %@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@\n"
          @"rmdir /tmp/libwayland-support/modeb.lock >/dev/null 2>&1 || true\n"
          @"rm -rf /tmp/libwayland-support/modeb.lock >/dev/null 2>&1 || true\n"
          @"rm -f /tmp/libwayland-support/framebufferd "
          @"/tmp/libwayland-support/modeb-framebufferd.ready "
          @"/tmp/libwayland-support/modeb-mach.ready "
          @"/tmp/libwayland-support/modeb-display-go "
          @"/tmp/libwayland-support/inputd "
          @"/tmp/libwayland-support/amfiexceptiond "
          @"/tmp/libwayland-support/*.pid\n"
          @"/bin/launchctl enable system/com.apple.WindowServer "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl load -w "
          @"/System/Library/LaunchDaemons/com.apple.WindowServer.plist "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootstrap system "
          @"/System/Library/LaunchDaemons/com.apple.WindowServer.plist "
          @">/dev/null 2>&1 || true\n"
          @"# restore_aqua only re-enables Apple watchdogd when Classic\n"
          @"# left wawona-unloaded-watchdogd. Blind enable while Path B is\n"
          @"# live paniced 2026-08-20 KEEP_WS failure (SIGTRAP ns2/0x5).\n"
          @"# Keep Path B Disable marker while sticky claim-ok / pathb plist\n"
          @"# is armed (user CLI live-Disable gate; 2026-08-20 blank-screen\n"
          @"# session lost marker and Classic refused).\n"
          @"if [ ! -f /var/db/wwn-iowatchdog/claim-ok ] && "
          @"[ ! -f /Library/LaunchDaemons/com.aspauldingcode.wwn-iowatchdog-pathb.plist ]; then\n"
          @"  rm -f /tmp/libwayland-support/iowatchdog-userspace-disabled\n"
          @"fi\n"
          @"if [ -f /tmp/libwayland-support/wawona-unloaded-watchdogd ] && "
          @"[ ! -f /var/db/wwn-iowatchdog/claim-ok ] && "
          @"[ ! -f /Library/LaunchDaemons/com.aspauldingcode.wwn-iowatchdog-pathb.plist ]; then\n"
          @"  /bin/launchctl enable system/com.apple.watchdogd "
          @">/dev/null 2>&1 || true\n"
          @"  /bin/launchctl load -w "
          @"/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
          @">/dev/null 2>&1 || true\n"
          @"  /bin/launchctl bootstrap system "
          @"/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
          @">/dev/null 2>&1 || true\n"
          @"  rm -f /tmp/libwayland-support/wawona-unloaded-watchdogd\n"
          @"fi\n",
          (unsigned)uid, kWWNModeBLoginAgentLabel, kWWNModeBLaunchdLabel,
          kWWNModeBWsGuardLabel,
          [self wwnShellQuote:[self modeBPlistPath]],
          [self wwnShellQuote:[self modeBLoginAgentPath]],
          [self wwnShellQuote:kWWNModeBSudoersPath],
          [self wwnShellQuote:[self modeBHelperPath]],
          [self wwnShellQuote:[self installedDylibPath]],
          [self wwnShellQuote:[self modeBIowatchdogPath]],
          [self wwnShellQuote:wsGuardPlist],
          [self wwnShellQuote:kWWNModeBPidPath],
          [self wwnShellQuote:kWWNModeBKeepWsPath],
          [self wwnShellQuote:kWWNModeBFailReasonPath],
          [self wwnShellQuote:[kWWNModeBFailReasonPath
                                  stringByAppendingString:@".showing"]]];
}

- (void)removeUserLoginAgent {
  uid_t uid = getuid();
  NSString *target = [NSString
      stringWithFormat:@"gui/%u/%@", (unsigned)uid, kWWNModeBLoginAgentLabel];
  (void)[self wwnLaunchctl:@[ @"bootout", target ]];
  [[NSFileManager defaultManager] removeItemAtPath:[self modeBLoginAgentPath]
                                             error:nil];
}

- (BOOL)disengage {
  [self removeUserLoginAgent];
  if ([self sudoersAllowsHelper] &&
      [[NSFileManager defaultManager]
          isExecutableFileAtPath:[self modeBHelperPath]]) {
    int st = [self runSudoNHelper:@[ @"--uninstall" ]];
    if (st == 0) {
      self.modeBPid = 0;
      self.modeBMachineId = nil;
      NSLog(@"[DesktopReplacement] Mode B uninstalled via sudo -n helper");
      return YES;
    }
    NSLog(@"[DesktopReplacement] sudo -n --uninstall status=%d; "
          @"falling back to admin uninstall",
          st);
  }
  NSError *error = nil;
  if (![self terminateModeBProcess:self.modeBPid error:&error]) {
    NSLog(@"[DesktopReplacement] Mode B uninstall failed: %@", error);
    return NO;
  }
  self.modeBPid = 0;
  self.modeBMachineId = nil;
  return YES;
}

- (BOOL)terminateModeBProcess:(pid_t)pid
                         error:(NSError *_Nullable *_Nullable)error {
  (void)pid;
  /*
   * Restore Aqua, kill leftover root compositors/helpers, delete every
   * Mode B install artifact, re-enable WindowServer. kickstart -k only
   * if WindowServer is not already running.
   */
  NSMutableString *shellCmd = [NSMutableString string];
  [shellCmd appendFormat:@"HELPER=%@\n",
                         [self wwnShellQuote:[self modeBHelperPath]]];
  [shellCmd appendString:@"if [ -x \"$HELPER\" ]; then "
                         @"\"$HELPER\" --restore-aqua >/dev/null 2>&1 || true; "
                         @"fi\n"];
  [shellCmd appendString:[self modeBFileCleanupShell]];
  NSString *osa =
      [NSString stringWithFormat:@"do shell script %@ with administrator "
                                 @"privileges",
                                 [self wwnAppleScriptQuote:shellCmd]];

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
  task.arguments = @[ @"-e", osa ];
  task.environment = [self modeBStrippedEnvironment];
  NSPipe *errPipe = [NSPipe pipe];
  task.standardError = errPipe;

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    if (error) {
      *error = launchError;
    }
    return NO;
  }
  [task waitUntilExit];
  if (task.terminationStatus == 0) {
    NSLog(@"[DesktopReplacement] Mode B disengaged pid=%d", (int)pid);
    return YES;
  }

  NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
  NSString *errText =
      [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
  if (error) {
    *error = [NSError
        errorWithDomain:@"WWNDesktopReplacement"
                   code:7
               userInfo:@{
                 NSLocalizedDescriptionKey : [NSString
                     stringWithFormat:@"Mode B privileged stop failed "
                                      @"(status=%d output=%@).",
                                      task.terminationStatus, errText ?: @""]
               }];
  }
  return NO;
}

- (NSDictionary<NSString *, NSString *> *)modeBStrippedEnvironment {
  NSDictionary *src = [[NSProcessInfo processInfo] environment];
  NSMutableDictionary *env = [src mutableCopy];
  for (NSString *key in src) {
    if ([key hasPrefix:@"DYLD_"]) {
      [env removeObjectForKey:key];
    }
  }
  return env;
}

- (NSString *)wwnShellQuote:(NSString *)s {
  // Single-quote for /bin/sh, escaping embedded quotes.
  NSString *escaped =
      [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
  return [NSString stringWithFormat:@"'%@'", escaped];
}

- (NSString *)wwnAppleScriptQuote:(NSString *)s {
  NSString *escaped =
      [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"\""
                                               withString:@"\\\""];
  return [NSString stringWithFormat:@"\"%@\"", escaped];
}

- (int)wwnLaunchctl:(NSArray<NSString *> *)args {
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
  task.arguments = args;
  task.environment = [self modeBStrippedEnvironment];
  task.standardOutput = [NSPipe pipe];
  task.standardError = [NSPipe pipe];
  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    return 1;
  }
  [task waitUntilExit];
  return task.terminationStatus;
}

- (BOOL)isAppleWindowServerRunning {
  return [self wwnLaunchctl:@[ @"print", @"system/com.apple.WindowServer" ]] ==
         0;
}

- (BOOL)isLoginAgentLoaded {
  NSString *target =
      [NSString stringWithFormat:@"gui/%u/%@", (unsigned)getuid(),
                                 kWWNModeBLoginAgentLabel];
  return [self wwnLaunchctl:@[ @"print", target ]] == 0;
}

- (void)resumeAfterAquaLogin {
  [self presentPendingSessionFailureAlert];
  [self removeUserLoginAgent];
  if (![self shouldEngageModeB]) {
    return;
  }
  NSLog(@"[DesktopReplacement] enabled, but login does not take over the "
        @"screen. Open Settings → Desktop → Take Over Screen Now.");
}

- (BOOL)modeBFramebufferdReady {
  return [[NSFileManager defaultManager] fileExistsAtPath:kWWNModeBFbReadyPath];
}

- (pid_t)startModeBHelperDetachedAndWait {
  [self removeUserLoginAgent];
  NSString *helper = [self modeBHelperPath];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) {
    WWNModeBCliLog(@"helper missing at %@", helper);
    return 0;
  }

  NSString *lockPath = @"/tmp/libwayland-support/modeb.lock";
  /*
   * Only --restore-aqua when WindowServer is already gone. Calling it while
   * Aqua is healthy used to run wwn-iowatchdog enable (lldb) against a live
   * watchdogd and paniced on open/engage (2026-08-20).
   */
  if (![self isAppleWindowServerRunning]) {
    WWNModeBCliLog(@"WindowServer down; --restore-aqua then --drop-lock");
    (void)[self runSudoNHelper:@[ @"--restore-aqua" ]];
  } else {
    WWNModeBCliLog(@"WindowServer up; skip --restore-aqua before engage");
  }
  (void)[self runSudoNHelper:@[ @"--drop-lock" ]];
  for (int j = 0; j < 25; j++) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:lockPath]) {
      break;
    }
    if (j == 0 || j == 24) {
      WWNModeBCliLog(@"waiting for leftover helper lock to drop (%@)", lockPath);
    }
    usleep(200000);
  }
  if ([[NSFileManager defaultManager] fileExistsAtPath:lockPath]) {
    WWNModeBCliLog(@"lock still present after drop-lock");
    if (![self isAppleWindowServerRunning]) {
      (void)[self runSudoNHelper:@[ @"--restore-aqua" ]];
    }
    (void)[self runSudoNHelper:@[ @"--drop-lock" ]];
    usleep(400000);
  }

  [[NSFileManager defaultManager] removeItemAtPath:kWWNModeBFailReasonPath
                                             error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:kWWNModeBFbReadyPath
                                             error:nil];
  [@"" writeToFile:kWWNModeBLogPath
        atomically:YES
          encoding:NSUTF8StringEncoding
             error:nil];
  [[NSFileManager defaultManager]
      setAttributes:@{NSFilePosixPermissions : @0666}
       ofItemAtPath:kWWNModeBLogPath
              error:nil];

  /*
   * Sudoers is NOPASSWD for this helper path only. Wrapping it in
   * `bash -c nohup ...` is a different command and returns status 1
   * (2026-08-19 11:56). `sudo -b` backgrounds the helper while staying
   * on the allowed argv.
   *
   * Do not waitUntilExit on sudo: the helper `wait`s the compositor, so
   * KEEP_WS (and Classic) would block the engage CLI for the whole
   * session (2026-08-20). Poll pidfile + framebufferd.ready instead.
   */
  WWNModeBCliLog(@"starting sudo -n -b helper "
                 @"(never unload WindowServer or watchdogd; probe injects "
                 @"while Aqua stays up)");
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
  task.arguments = @[ @"-n", @"-b", helper ];
  task.environment = [self modeBStrippedEnvironment];
  task.standardInput = [NSFileHandle fileHandleWithNullDevice];
  task.standardOutput = [NSPipe pipe];
  task.standardError = [NSPipe pipe];
  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    WWNModeBCliLog(@"sudo -n -b helper launch failed: %@", launchError);
    return 0;
  }
  /* Detach: do not wait for sudo/helper. Poll below. */

  for (int n = 0; n < 400; n++) {
    NSString *reason = [NSString
        stringWithContentsOfFile:kWWNModeBFailReasonPath
                        encoding:NSUTF8StringEncoding
                           error:nil];
    if (reason.length > 0) {
      WWNModeBCliLog(@"helper reported failure: %@", reason);
      return 0;
    }
    pid_t pid = [self readLiveCompositorPid];
    BOOL keepWs =
        [[NSFileManager defaultManager] fileExistsAtPath:kWWNModeBKeepWsPath];
    if (pid > 0 && [self modeBFramebufferdReady]) {
      if (keepWs || ![self isAppleWindowServerRunning]) {
        WWNModeBCliLog(@"compositor pid=%d framebufferd ready ws=%d keepWs=%d",
                       (int)pid, [self isAppleWindowServerRunning] ? 1 : 0,
                       keepWs ? 1 : 0);
        return pid;
      }
    }
    if (n == 0 || n % 20 == 19) {
      NSString *pidText = [NSString
          stringWithContentsOfFile:kWWNModeBPidPath
                          encoding:NSUTF8StringEncoding
                             error:nil];
      WWNModeBCliLog(@"wait %d/400 pidfile=%@ fb-ready=%d helper-log-bytes=%lu "
                     @"ws=%d",
                     n, pidText.length ? pidText : @"(missing)",
                     [self modeBFramebufferdReady] ? 1 : 0,
                     (unsigned long)[self modeBLogTail].length,
                     [self isAppleWindowServerRunning] ? 1 : 0);
    }
    usleep(100000);
  }
  WWNModeBCliLog(@"timed out waiting for framebufferd. helper owns restore. "
                 @"log:\n%@",
                 [self modeBLogTail] ?: @"(empty)");
  return 0;
}

- (NSString *)modeBLogTail {
  NSData *data = [NSData dataWithContentsOfFile:kWWNModeBLogPath];
  if (data.length == 0) {
    return nil;
  }
  NSString *text =
      [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSString *trimmed = [text
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    return nil;
  }
  if (trimmed.length > 1200) {
    return [trimmed substringFromIndex:trimmed.length - 1200];
  }
  return trimmed;
}

- (NSString *)consumeSessionFailureReason {
  NSString *src = kWWNModeBFailReasonPath;
  NSString *dst = [src stringByAppendingString:@".showing"];
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm removeItemAtPath:dst error:nil];
  NSString *text = nil;
  if ([fm moveItemAtPath:src toPath:dst error:nil]) {
    text = [NSString stringWithContentsOfFile:dst
                                     encoding:NSUTF8StringEncoding
                                        error:nil];
    [fm removeItemAtPath:dst error:nil];
  } else {
    /* Root-owned reason on sticky /tmp cannot be renamed by Aqua. Read it. */
    text = [NSString stringWithContentsOfFile:src
                                     encoding:NSUTF8StringEncoding
                                        error:nil];
    [fm removeItemAtPath:src error:nil];
  }
  NSString *trimmed = [text
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  return trimmed.length > 0 ? trimmed : nil;
}

- (void)restoreAquaIfNeeded {
  if ([self isAppleWindowServerRunning]) {
    return;
  }
  NSString *helper = [self modeBHelperPath];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) {
    return;
  }
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
  task.arguments = @[ @"-n", helper, @"--restore-aqua" ];
  task.environment = [self modeBStrippedEnvironment];
  task.standardOutput = [NSPipe pipe];
  task.standardError = [NSPipe pipe];
  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    NSLog(@"[DesktopReplacement] restore-aqua launch failed: %@", launchError);
    return;
  }
  [task waitUntilExit];
  NSLog(@"[DesktopReplacement] restore-aqua sudo -n status=%d",
        task.terminationStatus);
}

- (BOOL)sudoersAllowsHelper {
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
  task.arguments = @[ @"-n", @"-l" ];
  task.environment = [self modeBStrippedEnvironment];
  NSPipe *out = [NSPipe pipe];
  task.standardOutput = out;
  task.standardError = [NSPipe pipe];
  NSError *err = nil;
  if (![task launchAndReturnError:&err]) {
    WWNModeBCliLog(@"sudo -n -l launch failed: %@", err);
    return NO;
  }
  [task waitUntilExit];
  NSData *data = [out.fileHandleForReading readDataToEndOfFile];
  NSString *text =
      [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  return [text containsString:kWWNModeBHelperName];
}

- (int)runSudoNHelper:(NSArray<NSString *> *)extraArgs {
  NSString *ignored = nil;
  return [self runSudoNHelper:extraArgs stdoutText:&ignored];
}

- (int)runSudoNHelper:(NSArray<NSString *> *)extraArgs
           stdoutText:(NSString *_Nullable *_Nullable)stdoutText {
  NSString *helper = [self modeBHelperPath];
  NSMutableArray<NSString *> *args =
      [NSMutableArray arrayWithObjects:@"-n", helper, nil];
  if (extraArgs.count > 0) {
    [args addObjectsFromArray:extraArgs];
  }
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
  task.arguments = args;
  task.environment = [self modeBStrippedEnvironment];
  NSPipe *out = [NSPipe pipe];
  task.standardOutput = out;
  task.standardError = [NSPipe pipe];
  NSError *err = nil;
  if (![task launchAndReturnError:&err]) {
    WWNModeBCliLog(@"sudo -n helper launch failed: %@", err);
    if (stdoutText) {
      *stdoutText = @"";
    }
    return 1;
  }
  [task waitUntilExit];
  NSData *data = [out.fileHandleForReading readDataToEndOfFile];
  NSString *text =
      [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  if (stdoutText) {
    *stdoutText = text;
  }
  return task.terminationStatus;
}

- (pid_t)readLiveCompositorPid {
  NSString *pidText = [NSString
      stringWithContentsOfFile:kWWNModeBPidPath
                      encoding:NSUTF8StringEncoding
                         error:nil];
  pid_t pid = (pid_t)[pidText integerValue];
  return WWNProcessExists(pid) ? pid : 0;
}

- (NSString *)nativeClientIdForProfile:(WWNMachineProfile *)profile {
  NSDictionary *so =
      [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
          ? profile.settingsOverrides
          : @{};
  NSString *cid = [so[@"NativeClientId"] isKindOfClass:[NSString class]]
                      ? so[@"NativeClientId"]
                      : @"";
  return cid ?: @"";
}

- (WWNMachineProfile *)ownDisplayProfileMatchingIdOrName:(NSString *)idOrName {
  if (idOrName.length == 0) {
    return nil;
  }
  WWNMachineProfile *byId = [WWNMachineProfileStore profileById:idOrName];
  if (byId &&
      [WWNMachineProfileStore profileIndicatesModeBOwnDisplay:byId]) {
    return byId;
  }
  NSString *needle = idOrName.lowercaseString;
  for (WWNMachineProfile *profile in [WWNMachineProfileStore loadProfiles]) {
    if (![WWNMachineProfileStore profileIndicatesModeBOwnDisplay:profile]) {
      continue;
    }
    if ([profile.name.lowercaseString isEqualToString:needle] ||
        [profile.machineId.lowercaseString isEqualToString:needle]) {
      return profile;
    }
    NSString *cid = [self nativeClientIdForProfile:profile];
    if ([cid.lowercaseString isEqualToString:needle]) {
      return profile;
    }
  }
  return nil;
}

- (WWNMachineProfile *)nestedProfileMatchingIdOrName:(NSString *)idOrName {
  return [self ownDisplayProfileMatchingIdOrName:idOrName];
}

- (WWNMachineProfile *)createNativeDesktopMachineNamed:(NSString *)name
                                              clientId:(NSString *)clientId
                                         enableWeston:(BOOL)enableWeston {
  WWNMachineProfile *created = [WWNMachineProfile defaultProfile];
  created.name = name;
  NSMutableDictionary *so =
      [created.settingsOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
  so[@"NativeClientId"] = clientId;
  so[@"WestonEnabled"] = @(enableWeston);
  so[@"WestonTerminalEnabled"] = @NO;
  so[@"EnableLauncher"] = @(enableWeston);
  created.settingsOverrides = so;
  [WWNMachineProfileStore upsertProfile:created];
  return created.machineId.length > 0 ? created : nil;
}

- (WWNMachineProfile *)createWestonDesktopMachine {
  return [self createNativeDesktopMachineNamed:@"Weston Desktop"
                                      clientId:@"weston"
                                 enableWeston:YES];
}

- (WWNMachineProfile *)createNiriDesktopMachine {
  return [self createNativeDesktopMachineNamed:@"Niri Desktop"
                                      clientId:@"niri"
                                 enableWeston:NO];
}

- (WWNMachineProfile *)createKmscubeProofMachine {
  return [self createNativeDesktopMachineNamed:@"KMS Cube"
                                      clientId:@"kmscube"
                                 enableWeston:NO];
}

- (WWNMachineProfile *)createGbmEs2ProofMachine {
  return [self createNativeDesktopMachineNamed:@"GBM ES2 Demo"
                                      clientId:@"gbm-es2-demo"
                                 enableWeston:NO];
}

- (WWNMachineProfile *)createVkcubeKmsProofMachine {
  return [self createNativeDesktopMachineNamed:@"Vulkan Cube KMS"
                                      clientId:@"vkcube"
                                 enableWeston:NO];
}

- (WWNMachineProfile *)createModeBTtyMachine {
  return [self createNativeDesktopMachineNamed:@"Mode B TTY"
                                      clientId:@"modeb-tty"
                                 enableWeston:NO];
}

- (WWNMachineProfile *)profileWithClientId:(NSString *)clientId {
  for (WWNMachineProfile *profile in [WWNMachineProfileStore loadProfiles]) {
    if ([[self nativeClientIdForProfile:profile] isEqualToString:clientId]) {
      return profile;
    }
  }
  return nil;
}

- (int)cliSelectDesktopMachine:(NSString *)idOrName {
  WWNModeBCliLog(@"mode-b-machine %@", idOrName ?: @"(nil)");
  if (idOrName.length == 0) {
    WWNModeBCliLog(@"RESULT need id, name, or alias "
                   @"(weston|niri|kmscube|gbm-es2-demo|vkcube|modeb-tty)");
    return 2;
  }

  WWNMachineProfile *profile = [self ownDisplayProfileMatchingIdOrName:idOrName];
  NSString *alias = idOrName.lowercaseString;
  if (!profile) {
    if ([alias isEqualToString:@"modeb-tty"] ||
        [alias isEqualToString:@"modeb-ttyd"]) {
      profile = [self profileWithClientId:@"modeb-tty"]
                    ?: [self profileWithClientId:@"modeb-ttyd"]
                    ?: [self createModeBTtyMachine];
    } else if ([alias isEqualToString:@"kmscube"]) {
      profile = [self profileWithClientId:@"kmscube"]
                    ?: [self createKmscubeProofMachine];
    } else if ([alias isEqualToString:@"gbm-es2-demo"] ||
               [alias isEqualToString:@"gbm_es2_demo"]) {
      profile = [self profileWithClientId:@"gbm-es2-demo"]
                    ?: [self createGbmEs2ProofMachine];
    } else if ([alias isEqualToString:@"vkcube"] ||
               [alias isEqualToString:@"vkcube-kms"]) {
      profile = [self profileWithClientId:@"vkcube"]
                    ?: [self profileWithClientId:@"vkcube-kms"]
                    ?: [self createVkcubeKmsProofMachine];
    } else if ([alias isEqualToString:@"niri"]) {
      profile = [self profileWithClientId:@"niri"]
                    ?: [self createNiriDesktopMachine];
    } else if ([alias isEqualToString:@"weston"]) {
      profile = [self profileWithClientId:@"weston"]
                    ?: [self createWestonDesktopMachine];
    }
    if (profile && ![self ownDisplayProfileMatchingIdOrName:profile.machineId]) {
      WWNModeBCliLog(@"created own-display machine %@", profile.machineId);
    }
  }

  if (!profile) {
    WWNMachineProfile *any = [WWNMachineProfileStore profileById:idOrName];
    if (any &&
        ![WWNMachineProfileStore profileIndicatesModeBOwnDisplay:any]) {
      WWNModeBCliLog(@"RESULT refused: %@ is not own-display "
                     @"(need weston/niri/custom, modeb-tty, kmscube, "
                     @"gbm-es2-demo, or vkcube-kms). opengl-cube is a "
                     @"Wayland client of the GUI compositor.",
                     idOrName);
      return 2;
    }
    WWNModeBCliLog(@"RESULT no own-display machine matching %@", idOrName);
    return 2;
  }

  [[NSUserDefaults standardUserDefaults]
      setObject:profile.machineId
         forKey:kWWNPrefsDesktopReplacementMachineId];
  [[NSUserDefaults standardUserDefaults] synchronize];
  WWNModeBCliLog(@"RESULT selected id=%@ name=%@ client=%@", profile.machineId,
                 profile.name ?: @"", [self nativeClientIdForProfile:profile]);
  return 0;
}

- (int)cliStatus {
  WWNSipStatusType sip = [WWNSipStatus current];
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  pid_t pid = [self readLiveCompositorPid];
  NSString *pidText = [NSString
      stringWithContentsOfFile:kWWNModeBPidPath
                      encoding:NSUTF8StringEncoding
                         error:nil];
  int kr = -1;
  int kerrno = 0;
  pid_t rawPid = (pid_t)[pidText integerValue];
  if (rawPid > 0) {
    kr = kill(rawPid, 0);
    kerrno = (kr == 0) ? 0 : errno;
  }
  NSString *selectedId =
      [defs stringForKey:kWWNPrefsDesktopReplacementMachineId];
  WWNMachineProfile *selected =
      selectedId.length > 0 ? [WWNMachineProfileStore profileById:selectedId]
                            : nil;
  WWNModeBCliLog(@"mode-b-status");
  WWNModeBCliLog(@"  sip=%@ allows=%d", [WWNSipStatus describe:sip],
                 [WWNSipStatus allowsDesktopReplacement:sip] ? 1 : 0);
  WWNModeBCliLog(@"  DesktopReplacementEnabled=%d machine=%@ name=%@ client=%@",
                 [defs boolForKey:kWWNPrefsDesktopReplacementEnabled] ? 1 : 0,
                 selectedId ?: @"(none)", selected.name ?: @"",
                 selected ? [self nativeClientIdForProfile:selected] : @"");
  WWNModeBCliLog(@"  eligible Desktop machines:");
  BOOL anyEligible = NO;
  for (WWNMachineProfile *p in [WWNMachineProfileStore loadProfiles]) {
    if (![WWNMachineProfileStore profileIndicatesNestedCompositor:p]) {
      continue;
    }
    anyEligible = YES;
    BOOL isSel = selectedId.length > 0 &&
                 [p.machineId isEqualToString:selectedId];
    WWNModeBCliLog(@"    %@%@  name=%@  client=%@", isSel ? @"* " : @"  ",
                   p.machineId ?: @"?", p.name ?: @"",
                   [self nativeClientIdForProfile:p]);
  }
  if (!anyEligible) {
    WWNModeBCliLog(@"    (none; Wawona --mode-b-machine weston)");
  }
  WWNModeBCliLog(@"  bundledDylib=%@", [self bundledDylibPath] ?: @"(missing)");
  WWNModeBCliLog(@"  installedHelper=%@ executable=%d", [self modeBHelperPath],
                 [[NSFileManager defaultManager]
                     isExecutableFileAtPath:[self modeBHelperPath]]
                     ? 1
                     : 0);
  WWNModeBCliLog(@"  sudoersAllowsHelper=%d", [self sudoersAllowsHelper] ? 1 : 0);
  WWNModeBCliLog(@"  pidfile=%@ kill0=%d errno=%d live=%d",
                 pidText.length ? [pidText
                                       stringByTrimmingCharactersInSet:
                                           [NSCharacterSet
                                               whitespaceAndNewlineCharacterSet]]
                                : @"(missing)",
                 kr, kerrno, pid > 0 ? 1 : 0);
  WWNModeBCliLog(@"  WindowServer=%d loginAgent=%d",
                 [self isAppleWindowServerRunning] ? 1 : 0,
                 [self isLoginAgentLoaded] ? 1 : 0);
  WWNModeBCliLog(@"  helper-log:\n%@", [self modeBLogTail] ?: @"(empty)");
  NSError *pre = [self injectionPreflightError];
  if (pre) {
    WWNModeBCliLog(@"  preflight: %@", pre.localizedDescription);
  } else {
    WWNModeBCliLog(@"  preflight: ok");
  }
  (void)[self cliReady];
  if (pid > 0) {
    WWNModeBCliLog(@"RESULT live compositor pid=%d", (int)pid);
    return 0;
  }
  WWNModeBCliLog(@"RESULT no live compositor pid");
  return 1;
}

- (WWNModeBReadyReport *)evaluateClassicReadiness {
  WWNModeBReadyReport *r = [[WWNModeBReadyReport alloc] init];
  r.verdict = WWNModeBVerdictBlocked;
  r.token = @"blocked";
  r.reason = @"Classic Take Over is blocked.";
  r.nextStep = @"Use Prepare this Mac, then restart.";
  r.userSummary = @"Desktop Replacement still needs a one-time setup on this "
                  @"Mac, then a restart.";
  BOOL haveModeB =
      [self bundledDylibPath].length > 0 &&
      [self bundledClaimInstallPath].length > 0;

  pid_t pid = [self readLiveCompositorPid];
  BOOL wsUp = [self isAppleWindowServerRunning];
  if (pid > 0 && !wsUp) {
    r.verdict = WWNModeBVerdictTakeoverNow;
    r.token = @"takeover-now";
    r.reason = [NSString
        stringWithFormat:
            @"Classic is already engaged (compositor pid %d, WindowServer down).",
            (int)pid];
    r.nextStep =
        @"Already on Classic. Ctrl+Option+Backspace restores Aqua.";
    r.userSummary =
        @"Desktop Replacement is already running. "
        @"Ctrl+Option+Backspace restores macOS.";
    return r;
  }

  WWNSipStatusType sip = [WWNSipStatus current];
  if (![WWNSipStatus allowsDesktopReplacement:sip]) {
    r.needsSipHowTo = YES;
    r.reason = [NSString
        stringWithFormat:
            @"SIP is not fully disabled (%@). Mode B Classic needs "
            @"`csrutil disable` in Recovery (first line must read "
            @"System Integrity Protection status: disabled). Partial SIP "
            @"(Debugging Restrictions off) is refused.",
            [WWNSipStatus describe:sip]];
    r.nextStep = @"Open SIP Requirements & How-To, fully disable SIP in "
                 @"Recovery, then restart.";
    r.userSummary =
        @"System Integrity Protection must be fully disabled in Recovery "
        @"before Desktop Replacement can run. Open SIP Requirements & How-To.";
    return r;
  }

  BOOL helperOk = [[NSFileManager defaultManager]
      isExecutableFileAtPath:[self modeBHelperPath]];
  BOOL sudoOk = [self sudoersAllowsHelper];
  if (!helperOk || !sudoOk) {
    r.canPrepareRequirements = haveModeB;
    r.reason = [NSString
        stringWithFormat:
            @"Mode B helper is not staged for passwordless Take Over "
            @"(helper executable=%d, sudoers NOPASSWD=%d). Path=%@.",
            helperOk ? 1 : 0, sudoOk ? 1 : 0, [self modeBHelperPath]];
    r.nextStep = @"Use Prepare this Mac (administrator once), then restart "
                 @"if asked.";
    r.userSummary =
        @"Wawona still needs to install its Desktop helper on this Mac "
        @"(one administrator approval). Use Prepare this Mac. That does "
        @"not take over the screen.";
    return r;
  }

  NSError *pre = [self injectionPreflightError];
  if (pre) {
    r.canPrepareRequirements = haveModeB;
    r.reason = pre.localizedDescription;
    r.nextStep = @"Use Prepare this Mac. Wawona will pick a Desktop Machine "
                 @"if needed.";
    r.userSummary = pre.localizedDescription;
    return r;
  }

  NSString *ackOut = nil;
  int ack = [self runSudoNHelper:@[ @"--ack-status" ] stdoutText:&ackOut];
  NSString *verdict = @"blocked";
  BOOL needReboot = NO;
  BOOL live = NO;
  NSString *helperReason = nil;
  NSString *sock = nil;
  NSString *claim = nil;
  for (NSString *line in [ackOut componentsSeparatedByCharactersInSet:
                                     [NSCharacterSet newlineCharacterSet]]) {
    if ([line hasPrefix:@"verdict="]) {
      verdict = [line substringFromIndex:8];
    } else if ([line hasPrefix:@"need_reboot="]) {
      needReboot = [[line substringFromIndex:12] isEqualToString:@"1"];
    } else if ([line hasPrefix:@"ack_live="]) {
      live = [[line substringFromIndex:9] isEqualToString:@"1"];
    } else if ([line hasPrefix:@"reason="]) {
      helperReason = [line substringFromIndex:7];
    } else if ([line hasPrefix:@"sock="]) {
      sock = [line substringFromIndex:5];
    } else if ([line hasPrefix:@"claim_ok="]) {
      claim = [line substringFromIndex:9];
    }
  }
  if (ackOut.length == 0) {
    if (ack == 0) {
      live = YES;
      verdict = @"takeover-now";
    } else {
      NSString *fileClaim =
          [NSString stringWithContentsOfFile:kWWNModeBClaimOkPath
                                    encoding:NSUTF8StringEncoding
                                       error:nil];
      if ([fileClaim containsString:@"path=b"] &&
          [fileClaim containsString:@"sticky=1"]) {
        needReboot = YES;
        verdict = @"reboot";
        helperReason =
            @"Path B claim-ok is sticky but helper --ack-status returned no "
            @"text. Reboot so Path B can Disable IOWatchdog (sock done=1).";
      } else {
        helperReason = [NSString
            stringWithFormat:
                @"Helper --ack-status failed (exit %d) with no output. "
                @"claim-ok file=%@",
                ack, fileClaim.length ? fileClaim : @"(missing)"];
      }
    }
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL pending = [fm fileExistsAtPath:kWWNModeBClaimPendingPath];
  BOOL pathbPlist = [fm
      fileExistsAtPath:@"/Library/LaunchDaemons/"
                       @"com.aspauldingcode.wwn-iowatchdog-pathb.plist"];
  if (!live && (pending || pathbPlist)) {
    needReboot = YES;
    if (![verdict isEqualToString:@"takeover-now"]) {
      verdict = @"reboot";
    }
  }

  if (live || [verdict isEqualToString:@"takeover-now"]) {
    r.verdict = WWNModeBVerdictTakeoverNow;
    r.token = @"takeover-now";
    r.reason = helperReason.length
                   ? helperReason
                   : @"Path B IOWatchdog is live. Classic Take Over may run now.";
    r.nextStep = @"Use Take Over Screen Now.";
    r.userSummary =
        @"Watchdog safety is in place. Use Take Over Screen Now when you "
        @"want Desktop Replacement.";
    return r;
  }
  if (needReboot || [verdict isEqualToString:@"reboot"] || ack == 2) {
    r.verdict = WWNModeBVerdictReboot;
    r.token = @"reboot";
    r.reason = helperReason.length
                   ? helperReason
                   : [NSString
                         stringWithFormat:
                             @"Path B is armed but not live yet. sock=%@ "
                             @"claim-ok=%@",
                             sock.length ? sock : @"(empty)",
                             claim.length ? claim : @"(empty)"];
    r.nextStep = @"Restart this Mac. After you log in, use Take Over Screen "
                 @"Now.";
    r.userSummary =
        @"Setup is waiting on a restart. After you log back in, use Take "
        @"Over Screen Now.";
    return r;
  }
  r.verdict = WWNModeBVerdictBlocked;
  r.token = @"blocked";
  r.canPrepareRequirements = haveModeB;
  r.reason = helperReason.length
                 ? helperReason
                 : [NSString
                       stringWithFormat:
                           @"Classic Take Over is blocked. helper_exit=%d "
                           @"verdict=%@ sock=%@ claim-ok=%@",
                           ack, verdict, sock.length ? sock : @"(empty)",
                           claim.length ? claim : @"(empty)"];
  r.nextStep = @"Use Prepare this Mac, then restart.";
  r.userSummary =
      @"Desktop Replacement needs a one-time setup on this Mac: install the "
      @"watchdog safety layer, then restart. After you log back in, use "
      @"Take Over Screen Now. Setup does not take over the screen.";
  return r;
}

- (BOOL)isModeBCompositorLive {
  return [self readLiveCompositorPid] > 0;
}

- (BOOL)isClassicTakeoverLive {
  return [self isModeBCompositorLive] && ![self isAppleWindowServerRunning];
}

- (WWNModeBMenuBarStatus *)menuBarDesktopStatusRefreshingGate:(BOOL)refreshGate {
  WWNModeBMenuBarStatus *s = [[WWNModeBMenuBarStatus alloc] init];
  s.state = @"blocked";
  s.tooltip = @"Classic Take Over is blocked.";

  pid_t pid = [self readLiveCompositorPid];
  if (pid > 0) {
    BOOL classic = ![self isAppleWindowServerRunning];
    s.state = @"takeover";
    s.canRestore = YES;
    s.tooltip = classic
                    ? [NSString stringWithFormat:
                                    @"Classic is engaged (compositor pid %d, "
                                    @"WindowServer down).",
                                    (int)pid]
                    : [NSString stringWithFormat:
                                    @"Mode B compositor is live (pid %d). "
                                    @"WindowServer is still up (KEEP_WS / probe).",
                                    (int)pid];
    self.menuBarDesktopCache = s;
    return s;
  }

  if (!refreshGate && self.menuBarDesktopCache &&
      ![self.menuBarDesktopCache.state isEqualToString:@"takeover"]) {
    return self.menuBarDesktopCache;
  }

  if (![self bundledDylibPath]) {
    s.state = @"blocked";
    s.tooltip = @"This build does not ship libwayland-mac.dylib. Desktop "
                @"Replacement is desktop-host only.";
    self.menuBarDesktopCache = s;
    return s;
  }

  if (!refreshGate) {
    s.state = @"blocked";
    s.tooltip = @"Open the menu to refresh Classic readiness.";
    return s;
  }

  WWNModeBReadyReport *r = [self evaluateClassicReadiness];
  if (r.verdict == WWNModeBVerdictTakeoverNow) {
    s.state = @"ready";
    s.canTakeOver = YES;
  } else if (r.verdict == WWNModeBVerdictReboot) {
    s.state = @"reboot";
    s.canRestartMac = YES;
  } else {
    s.state = @"blocked";
    s.canPrepare = r.canPrepareRequirements || r.needsSipHowTo;
  }
  s.tooltip = r.userSummary.length
                  ? r.userSummary
                  : (r.reason.length ? r.reason : @"Classic Take Over is blocked.");
  self.menuBarDesktopCache = s;
  return s;
}

- (BOOL)requestNativeMacOSRestart:(NSError *_Nullable *_Nullable)error {
  /*
   * TN QA1134: send kAERestart to the system process. loginwindow shows
   * the standard Restart sheet (apps quit, 60-second countdown).
   */
  AEAddressDesc targetDesc;
  static const ProcessSerialNumber kPSNOfSystemProcess = {0, kSystemProcess};
  AppleEvent eventReply = {typeNull, NULL};
  AppleEvent appleEventToSend = {typeNull, NULL};
  OSStatus err = AECreateDesc(typeProcessSerialNumber, &kPSNOfSystemProcess,
                              sizeof(kPSNOfSystemProcess), &targetDesc);
  if (err != noErr) {
    if (error) {
      *error = [NSError
          errorWithDomain:NSOSStatusErrorDomain
                     code:err
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Could not address the system process for Restart "
                       @"(Apple Event kAERestart / QA1134)."
                 }];
    }
    return NO;
  }
  err = AECreateAppleEvent(kCoreEventClass, kAERestart, &targetDesc,
                           kAutoGenerateReturnID, kAnyTransactionID,
                           &appleEventToSend);
  AEDisposeDesc(&targetDesc);
  if (err != noErr) {
    if (error) {
      *error = [NSError
          errorWithDomain:NSOSStatusErrorDomain
                     code:err
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Could not create the Restart Apple Event (kAERestart)."
                 }];
    }
    return NO;
  }
  err = AESendMessage(&appleEventToSend, &eventReply, kAENormalPriority,
                      kAEDefaultTimeout);
  AEDisposeDesc(&appleEventToSend);
  if (err == noErr) {
    AEDisposeDesc(&eventReply);
    return YES;
  }
  if (error) {
    *error = [NSError
        errorWithDomain:NSOSStatusErrorDomain
                   code:err
               userInfo:@{
                 NSLocalizedDescriptionKey : [NSString
                     stringWithFormat:
                         @"macOS Restart sheet failed (OSStatus %d). Aqua "
                         @"must be running. Open  → Restart if this persists.",
                         (int)err]
               }];
  }
  return NO;
}

- (BOOL)runPrivilegedShellCommand:(NSString *)shellCmd
                    successMarker:(NSString *)marker
                       stdoutText:(NSString *_Nullable *_Nullable)stdoutText
                            error:(NSError *_Nullable *_Nullable)error {
  NSMutableString *outStr = [NSMutableString string];
  {
    NSTask *sudoProbe = [[NSTask alloc] init];
    sudoProbe.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
    sudoProbe.arguments = @[ @"-n", @"true" ];
    sudoProbe.standardOutput = [NSPipe pipe];
    sudoProbe.standardError = [NSPipe pipe];
    NSError *probeErr = nil;
    BOOL probed = [sudoProbe launchAndReturnError:&probeErr];
    if (probed) {
      [sudoProbe waitUntilExit];
    }
    if (probed && sudoProbe.terminationStatus == 0) {
      NSTask *task = [[NSTask alloc] init];
      task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
      task.arguments = @[ @"-n", @"/bin/sh", @"-c", shellCmd ];
      NSPipe *outPipe = [NSPipe pipe];
      NSPipe *errPipe = [NSPipe pipe];
      task.standardOutput = outPipe;
      task.standardError = errPipe;
      NSError *launchErr = nil;
      if (![task launchAndReturnError:&launchErr]) {
        if (error) {
          *error = launchErr ?: [NSError
                                    errorWithDomain:@"WWNDesktopReplacement"
                                               code:5
                                           userInfo:@{
                                             NSLocalizedDescriptionKey :
                                                 @"sudo -n launch failed."
                                           }];
        }
        return NO;
      }
      [task waitUntilExit];
      NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
      NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
      if (outData.length) {
        [outStr appendString:[[NSString alloc] initWithData:outData
                                                   encoding:NSUTF8StringEncoding]
                                 ?: @""];
      }
      if (errData.length) {
        [outStr appendString:[[NSString alloc] initWithData:errData
                                                   encoding:NSUTF8StringEncoding]
                                 ?: @""];
      }
      if (stdoutText) {
        *stdoutText = [outStr copy];
      }
      BOOL ok = task.terminationStatus == 0;
      if (!ok && marker.length > 0) {
        ok = [outStr containsString:marker];
      }
      if (!ok) {
        if (error) {
          *error = [NSError
              errorWithDomain:@"WWNDesktopReplacement"
                         code:5
                     userInfo:@{
                       NSLocalizedDescriptionKey : [NSString
                           stringWithFormat:
                               @"Privileged command failed (status=%d). %@",
                               (int)task.terminationStatus,
                               outStr.length ? outStr : @"(no output)"]
                     }];
        }
        return NO;
      }
      return YES;
    }
  }

  AuthorizationRef authRef;
  OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                        kAuthorizationFlagDefaults, &authRef);
  if (status != errAuthorizationSuccess) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Authorization creation failed."
                 }];
    }
    return NO;
  }

  AuthorizationItem right = {kAuthorizationRightExecute, 0, NULL, 0};
  AuthorizationRights rights = {1, &right};
  AuthorizationFlags flags = kAuthorizationFlagDefaults |
                             kAuthorizationFlagInteractionAllowed |
                             kAuthorizationFlagPreAuthorize |
                             kAuthorizationFlagExtendRights;
  status = AuthorizationCopyRights(authRef, &rights, NULL, flags, NULL);
  if (status != errAuthorizationSuccess) {
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"User cancelled administrator authorization."
                 }];
    }
    return NO;
  }

  char *args[] = {"-c", (char *)shellCmd.UTF8String, NULL};
  FILE *pipe = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  status = AuthorizationExecuteWithPrivileges(
      authRef, "/bin/sh", kAuthorizationFlagDefaults, args, &pipe);
#pragma clang diagnostic pop
  if (status != errAuthorizationSuccess) {
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Failed to run administrator command (status=%d).",
                           (int)status]
                 }];
    }
    return NO;
  }

  if (pipe) {
    char buf[256];
    while (fgets(buf, sizeof(buf), pipe)) {
      [outStr appendFormat:@"%s", buf];
    }
    fclose(pipe);
  }
  AuthorizationFree(authRef, kAuthorizationFlagDefaults);
  if (stdoutText) {
    *stdoutText = [outStr copy];
  }
  BOOL ok = marker.length == 0 || [outStr containsString:marker];
  if (!ok) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:6
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Administrator command did not finish. %@",
                           outStr.length ? outStr : @"(no output)"]
                 }];
    }
    return NO;
  }
  return YES;
}

- (BOOL)armPathBClaimInstall:(NSError *_Nullable *_Nullable)error {
  NSString *exe = [self bundledClaimInstallPath];
  if (exe.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"This Wawona build does not ship "
                       @"wwn-iowatchdog-claim-install. Install the Desktop "
                       @"Replacement build, then try Prepare this Mac again."
                 }];
    }
    return NO;
  }
  NSString *pkg = [exe stringByDeletingLastPathComponent];
  NSString *hook =
      [pkg stringByAppendingPathComponent:@"lib/libwwn_watchdogd_hook.dylib"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:hook]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Path B hook is missing at %@. Reinstall the "
                           @"Desktop Replacement build.",
                           hook]
                 }];
    }
    return NO;
  }
  NSString *shellCmd = [NSString
      stringWithFormat:@"%@ --path-b %@ 2>&1", [self wwnShellQuote:exe],
                       [self wwnShellQuote:pkg]];
  NSString *out = nil;
  if (![self runPrivilegedShellCommand:shellCmd
                         successMarker:@"Path B sticky armed"
                            stdoutText:&out
                                 error:error]) {
    return NO;
  }
  WWNModeBCliLog(@"path-b arm output: %@", out.length ? out : @"(empty)");
  return YES;
}

- (BOOL)installDesktopReplacementRequirements:
    (NSError *_Nullable *_Nullable)error {
  if ([self bundledDylibPath].length == 0 ||
      [self bundledClaimInstallPath].length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"This Wawona is Mode A only. Install the Desktop "
                       @"Replacement build, then use Prepare this Mac."
                 }];
    }
    return NO;
  }

  WWNSipStatusType sip = [WWNSipStatus current];
  if (![WWNSipStatus allowsDesktopReplacement:sip]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"System Integrity Protection must be fully disabled "
                       @"in Recovery first. Open SIP Requirements & How-To."
                 }];
    }
    return NO;
  }

  if (![self ensureDesktopMachineSelected:error]) {
    int sel = [self cliSelectDesktopMachine:@"weston"];
    if (sel != 0 || ![self ensureDesktopMachineSelected:error]) {
      return NO;
    }
  }

  BOOL helperOk = [[NSFileManager defaultManager]
      isExecutableFileAtPath:[self modeBHelperPath]];
  BOOL sudoOk = [self sudoersAllowsHelper];
  if (!helperOk || !sudoOk) {
    NSString *desktopId = [[NSUserDefaults standardUserDefaults]
        stringForKey:kWWNPrefsDesktopReplacementMachineId];
    WWNMachineProfile *profile =
        [WWNMachineProfileStore profileById:desktopId];
    if (!profile) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"WWNDesktopReplacement"
                       code:9
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"Could not select a Desktop Machine to stage the "
                         @"helper."
                   }];
      }
      return NO;
    }
    if (![self installModeBHelperAndDylibForProfile:profile error:error]) {
      return NO;
    }
  }

  WWNModeBReadyReport *ready = [self evaluateClassicReadiness];
  if (ready.verdict == WWNModeBVerdictTakeoverNow ||
      ready.verdict == WWNModeBVerdictReboot) {
    return YES;
  }

  return [self armPathBClaimInstall:error];
}

- (void)presentRestartAfterPrepareWithMessage:(NSString *)message {
  NSAlert *confirm = [[NSAlert alloc] init];
  confirm.alertStyle = NSAlertStyleInformational;
  confirm.messageText = @"Restart required";
  confirm.informativeText = message.length
                                ? message
                                : @"Restart this Mac so the watchdog safety "
                                  @"layer can finish. After you log in, use "
                                  @"Take Over Screen Now.";
  [confirm addButtonWithTitle:@"Restart"];
  [confirm addButtonWithTitle:@"Later"];
  if ([confirm runModal] != NSAlertFirstButtonReturn) {
    return;
  }
  NSError *rst = nil;
  if (![self requestNativeMacOSRestart:&rst]) {
    NSAlert *fail = [[NSAlert alloc] init];
    fail.alertStyle = NSAlertStyleCritical;
    fail.messageText = @"Could not open Restart";
    fail.informativeText = rst.localizedDescription
                               ?: @"Use the Apple menu → Restart.";
    [fail addButtonWithTitle:@"OK"];
    [fail runModal];
  }
}

- (void)presentDesktopReplacementPrepareFlow {
  void (^show)(void) = ^{
    [NSApp activateIgnoringOtherApps:YES];
    if ([self bundledDylibPath].length == 0 ||
        [self bundledClaimInstallPath].length == 0) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.alertStyle = NSAlertStyleWarning;
      alert.messageText = @"Desktop Replacement is not in this Wawona";
      alert.informativeText =
          @"This copy is Mode A only (in-window). Install the Desktop "
          @"Replacement build, then try Prepare this Mac again.";
      [alert addButtonWithTitle:@"OK"];
      [alert runModal];
      return;
    }

    WWNSipStatusType sip = [WWNSipStatus current];
    if (![WWNSipStatus allowsDesktopReplacement:sip]) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.alertStyle = NSAlertStyleWarning;
      alert.messageText = @"Desktop Replacement. SIP Requirements";
      alert.informativeText = [WWNSipStatus desktopReplacementHowToMessage];
      [alert addButtonWithTitle:@"OK"];
      [alert addButtonWithTitle:@"Copy csrutil Command"];
      if ([alert runModal] == NSAlertSecondButtonReturn) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:@"csrutil disable" forType:NSPasteboardTypeString];
      }
      return;
    }

    WWNModeBReadyReport *ready = [self evaluateClassicReadiness];
    if (ready.verdict == WWNModeBVerdictTakeoverNow) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.alertStyle = NSAlertStyleInformational;
      alert.messageText = @"This Mac is ready";
      alert.informativeText =
          @"Watchdog safety is in place. Use Take Over Screen Now when you "
          @"want Desktop Replacement. Setup does not start Take Over by "
          @"itself.";
      [alert addButtonWithTitle:@"OK"];
      [alert runModal];
      return;
    }
    if (ready.verdict == WWNModeBVerdictReboot) {
      [self presentRestartAfterPrepareWithMessage:ready.userSummary];
      return;
    }

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.alertStyle = NSAlertStyleInformational;
    confirm.messageText = @"Prepare this Mac for Desktop Replacement?";
    confirm.informativeText =
        @"Wawona will install a watchdog safety layer (administrator "
        @"password), then ask you to restart. After you log back in, open "
        @"Wawona and use Take Over Screen Now.\n\n"
        @"This does not take over the screen, and it does not unload Apple's "
        @"watchdog. Restart is required before Take Over can run.";
    [confirm addButtonWithTitle:@"Prepare this Mac"];
    [confirm addButtonWithTitle:@"Cancel"];
    if ([confirm runModal] != NSAlertFirstButtonReturn) {
      return;
    }

    NSError *err = nil;
    if (![self installDesktopReplacementRequirements:&err]) {
      NSAlert *fail = [[NSAlert alloc] init];
      fail.alertStyle = NSAlertStyleCritical;
      fail.messageText = @"Could not prepare this Mac";
      fail.informativeText = err.localizedDescription
                                 ?: @"See /tmp/wawona-modeb-cli.log.";
      [fail addButtonWithTitle:@"OK"];
      [fail runModal];
      return;
    }

    ready = [self evaluateClassicReadiness];
    if (ready.verdict == WWNModeBVerdictTakeoverNow) {
      NSAlert *ok = [[NSAlert alloc] init];
      ok.alertStyle = NSAlertStyleInformational;
      ok.messageText = @"This Mac is ready";
      ok.informativeText =
          @"Watchdog safety is in place. Use Take Over Screen Now when you "
          @"want Desktop Replacement.";
      [ok addButtonWithTitle:@"OK"];
      [ok runModal];
      return;
    }
    [self presentRestartAfterPrepareWithMessage:
              @"Setup finished. Restart this Mac so the watchdog safety "
              @"layer can finish. After you log in, use Take Over Screen "
              @"Now."];
  };
  if ([NSThread isMainThread]) {
    show();
  } else {
    dispatch_sync(dispatch_get_main_queue(), show);
  }
}

- (int)cliPrepare {
  WWNModeBCliLog(@"mode-b-prepare");
  NSError *err = nil;
  if (![self installDesktopReplacementRequirements:&err]) {
    WWNModeBCliLog(@"prepare failed: %@", err.localizedDescription);
    WWNModeBReadyReport *blocked = [self evaluateClassicReadiness];
    WWNModeBCliLog(@"VERDICT %@", blocked.token);
    WWNModeBCliLog(@"REASON %@",
                   err.localizedDescription ?: blocked.reason);
    WWNModeBCliLog(@"next: %@", blocked.nextStep);
    return blocked.verdict == WWNModeBVerdictTakeoverNow
               ? 1
               : (int)blocked.verdict;
  }
  WWNModeBReadyReport *r = [self evaluateClassicReadiness];
  WWNModeBCliLog(@"VERDICT %@", r.token);
  WWNModeBCliLog(@"REASON %@", r.reason);
  WWNModeBCliLog(@"next: %@", r.nextStep);
  if (r.verdict == WWNModeBVerdictTakeoverNow) {
    return 0;
  }
  WWNModeBCliLog(@"opening native macOS Restart sheet (kAERestart / QA1134)");
  NSError *rst = nil;
  if (![self requestNativeMacOSRestart:&rst]) {
    WWNModeBCliLog(@"restart sheet failed: %@", rst.localizedDescription);
  }
  return (int)WWNModeBVerdictReboot;
}

- (int)cliReady {
  WWNModeBCliLog(@"mode-b-ready");
  WWNModeBReadyReport *r = [self evaluateClassicReadiness];
  WWNModeBCliLog(@"  sip=%@", [WWNSipStatus describe:[WWNSipStatus current]]);
  WWNModeBCliLog(@"VERDICT %@", r.token);
  WWNModeBCliLog(@"REASON %@", r.reason);
  WWNModeBCliLog(@"next: %@", r.nextStep);
  return (int)r.verdict;
}

- (int)cliEngageKeepWindowServer:(BOOL)keepWindowServer {
  WWNModeBCliLog(@"mode-b-engage keepWindowServer=%d",
                 keepWindowServer ? 1 : 0);
  if (!keepWindowServer) {
    WWNModeBReadyReport *ready = [self evaluateClassicReadiness];
    WWNModeBCliLog(@"VERDICT %@", ready.token);
    WWNModeBCliLog(@"REASON %@", ready.reason);
    if (ready.verdict == WWNModeBVerdictReboot) {
      WWNModeBCliLog(@"opening native macOS Restart sheet (kAERestart / QA1134)");
      NSError *rst = nil;
      if (![self requestNativeMacOSRestart:&rst]) {
        WWNModeBCliLog(@"restart sheet failed: %@", rst.localizedDescription);
        WWNModeBCliLog(@"next: %@", ready.nextStep);
        return (int)ready.verdict;
      }
      return (int)ready.verdict;
    }
    if (ready.verdict != WWNModeBVerdictTakeoverNow) {
      WWNModeBCliLog(@"engage aborted (blocked)");
      WWNModeBCliLog(@"next: %@", ready.nextStep);
      return (int)ready.verdict;
    }
  }
  if (keepWindowServer) {
    [@"" writeToFile:kWWNModeBKeepWsPath atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];
  } else {
    [[NSFileManager defaultManager] removeItemAtPath:kWWNModeBKeepWsPath
                                               error:nil];
  }

  NSError *pre = [self injectionPreflightError];
  if (pre) {
    WWNModeBCliLog(@"preflight failed: %@", pre.localizedDescription);
    return 2;
  }
  WWNSipStatusType sip = [WWNSipStatus current];
  if (![WWNSipStatus allowsDesktopReplacement:sip]) {
    WWNModeBCliLog(@"SIP does not allow Mode B: %@",
                   [WWNSipStatus describe:sip]);
    return 2;
  }

  pid_t existing = [self readLiveCompositorPid];
  BOOL wsUp = [self isAppleWindowServerRunning];
  if (existing > 0 && !wsUp) {
    WWNModeBCliLog(@"already engaged pid=%d (WindowServer down)", (int)existing);
    [[NSUserDefaults standardUserDefaults]
        setBool:YES
         forKey:kWWNPrefsDesktopReplacementEnabled];
    self.modeBPid = existing;
    return 0;
  }
  if (keepWindowServer && existing > 0) {
    WWNModeBCliLog(@"probe: live root compositor pid=%d (EPERM-aware). "
                   @"Not restarting because KEEP_WS was requested and the "
                   @"installed helper may still unload WindowServer.",
                   (int)existing);
    return 0;
  }

  [[NSUserDefaults standardUserDefaults]
      setBool:YES
       forKey:kWWNPrefsDesktopReplacementEnabled];
  [[NSUserDefaults standardUserDefaults] synchronize];

  NSError *err = nil;
  if (![self engageSelectedDesktopMachine:&err]) {
    WWNModeBCliLog(@"engage failed: %@", err.localizedDescription);
    WWNModeBCliLog(@"helper-log:\n%@", [self modeBLogTail] ?: @"(empty)");
    return 1;
  }
  pid_t pid = self.modeBPid > 0 ? self.modeBPid : [self readLiveCompositorPid];
  WWNModeBCliLog(@"engaged pid=%d WindowServer=%d", (int)pid,
                 [self isAppleWindowServerRunning] ? 1 : 0);
  if (pid <= 0) {
    return 1;
  }
  if (!keepWindowServer && [self isAppleWindowServerRunning]) {
    WWNModeBCliLog(@"WARNING: compositor is live but WindowServer is still up");
    return 1;
  }
  WWNModeBCliLog(@"RESULT success pid=%d", (int)pid);
  return 0;
}

- (int)cliDisengage {
  WWNModeBCliLog(@"mode-b-disengage");
  [[NSUserDefaults standardUserDefaults]
      setBool:NO
       forKey:kWWNPrefsDesktopReplacementEnabled];
  BOOL ok = [self disengage];
  pid_t pid = [self readLiveCompositorPid];
  WWNModeBCliLog(@"after disengage livePid=%d WindowServer=%d ok=%d", (int)pid,
                 [self isAppleWindowServerRunning] ? 1 : 0, ok ? 1 : 0);
  return (ok && [self isAppleWindowServerRunning] && pid == 0) ? 0 : 1;
}

- (int)cliStage {
  WWNModeBCliLog(@"mode-b-stage");
  /* Stage Mode B TTY so helper argv matches Classic engage. */
  int sel = [self cliSelectDesktopMachine:@"modeb-tty"];
  if (sel != 0) {
    WWNModeBCliLog(@"stage failed: could not select modeb-tty machine");
    return sel;
  }
  NSError *err = nil;
  if (![self ensureDesktopMachineSelected:&err]) {
    WWNModeBCliLog(@"stage failed: %@", err.localizedDescription);
    return 2;
  }
  NSString *desktopId = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsDesktopReplacementMachineId];
  WWNMachineProfile *profile = [WWNMachineProfileStore profileById:desktopId];
  if (!profile) {
    WWNModeBCliLog(@"stage failed: no Desktop Machine");
    return 2;
  }
  if (![self installModeBHelperAndDylibForProfile:profile error:&err]) {
    WWNModeBCliLog(@"stage failed: %@", err.localizedDescription);
    return 1;
  }
  NSString *helper = [self modeBHelperPath];
  NSString *helperText =
      [NSString stringWithContentsOfFile:helper
                                encoding:NSUTF8StringEncoding
                                   error:nil];
  NSString *exe = nil;
  NSArray<NSString *> *args = nil;
  NSDictionary<NSString *, NSString *> *env = nil;
  if (![[WWNWaypipeRunner sharedRunner]
          baremetalCompositorLaunchSpecForProfile:profile
                                       executable:&exe
                                        arguments:&args
                                      environment:&env
                                            error:&err] ||
      exe.length == 0 || ![helperText containsString:exe]) {
    WWNModeBCliLog(@"stage verify failed: helper missing %@ (%@)", exe,
                   err.localizedDescription);
    return 1;
  }
  WWNModeBCliLog(@"RESULT staged helper=%@ executable=%@", helper, exe);
  return 0;
}

- (void)presentPendingSessionFailureAlert {
  NSString *reason = [self consumeSessionFailureReason];
  if (reason.length == 0) {
    return;
  }
  [self restoreAquaIfNeeded];
  [[NSUserDefaults standardUserDefaults]
      setBool:NO
       forKey:kWWNPrefsDesktopReplacementEnabled];
  void (^show)(void) = ^{
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = @"Desktop Replacement ended";
    alert.informativeText = [NSString
        stringWithFormat:@"%@\n\nThe Enable Desktop Replacement switch was "
                         @"turned off so the next login will not take over "
                         @"the screen again. Use Take Over Screen Now to retry.",
                         reason];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
  };
  if ([NSThread isMainThread]) {
    show();
  } else {
    dispatch_async(dispatch_get_main_queue(), show);
  }
}

@end

#else // !TARGET_OS_OSX

@implementation WWNModeBReadyReport
@end

@implementation WWNModeBMenuBarStatus
@end

@implementation WWNDesktopReplacementController
+ (instancetype)sharedController {
  static WWNDesktopReplacementController *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[WWNDesktopReplacementController alloc] init];
  });
  return shared;
}
- (BOOL)shouldEngageModeB {
  return NO;
}
- (BOOL)isDesktopMachine:(WWNMachineProfile *)profile {
  (void)profile;
  return NO;
}
- (NSString *)bundledDylibPath {
  return nil;
}
- (NSError *)injectionPreflightError {
  return [NSError errorWithDomain:@"WWNDesktopReplacement"
                             code:100
                         userInfo:@{
                           NSLocalizedDescriptionKey :
                               @"Desktop Replacement Mode B is macOS-only."
                         }];
}
- (BOOL)ensureDesktopMachineSelected:(NSError *_Nullable *_Nullable)error {
  if (error) {
    *error = [self injectionPreflightError];
  }
  return NO;
}
- (BOOL)engageForProfile:(WWNMachineProfile *)profile
                   error:(NSError *_Nullable *_Nullable)error {
  (void)profile;
  if (error) {
    *error = [NSError errorWithDomain:@"WWNDesktopReplacement"
                                 code:100
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Desktop Replacement Mode B is macOS-only."
                             }];
  }
  return NO;
}
- (BOOL)engageSelectedDesktopMachine:(NSError *_Nullable *_Nullable)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNDesktopReplacement"
                                 code:100
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Desktop Replacement Mode B is macOS-only."
                             }];
  }
  return NO;
}
- (BOOL)disengage {
  return YES;
}
- (void)resumeAfterAquaLogin {
}
- (void)presentPendingSessionFailureAlert {
}
- (BOOL)reconcilePrefsWithCurrentSip {
  return NO;
}
- (int)cliStatus {
  return 2;
}
- (int)cliReady {
  return 2;
}
- (WWNModeBReadyReport *)evaluateClassicReadiness {
  WWNModeBReadyReport *r = [[WWNModeBReadyReport alloc] init];
  r.verdict = WWNModeBVerdictBlocked;
  r.token = @"blocked";
  r.reason = @"Desktop Replacement Mode B is macOS-only.";
  r.nextStep = @"";
  r.userSummary = r.reason;
  return r;
}
- (BOOL)isModeBCompositorLive {
  return NO;
}
- (BOOL)isClassicTakeoverLive {
  return NO;
}
- (WWNModeBMenuBarStatus *)menuBarDesktopStatusRefreshingGate:(BOOL)refreshGate {
  (void)refreshGate;
  WWNModeBMenuBarStatus *s = [[WWNModeBMenuBarStatus alloc] init];
  s.state = @"blocked";
  s.tooltip = @"Desktop Replacement Mode B is macOS-only.";
  return s;
}
- (BOOL)requestNativeMacOSRestart:(NSError *_Nullable *_Nullable)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNDesktopReplacement"
                                 code:100
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Desktop Replacement Mode B is macOS-only."
                             }];
  }
  return NO;
}
- (BOOL)installDesktopReplacementRequirements:
    (NSError *_Nullable *_Nullable)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNDesktopReplacement"
                                 code:100
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Desktop Replacement Mode B is macOS-only."
                             }];
  }
  return NO;
}
- (void)presentDesktopReplacementPrepareFlow {
}
- (int)cliPrepare {
  return 2;
}
- (int)cliEngageKeepWindowServer:(BOOL)keepWindowServer {
  (void)keepWindowServer;
  return 2;
}
- (int)cliDisengage {
  return 2;
}
- (int)cliStage {
  return 2;
}
- (int)cliSelectDesktopMachine:(NSString *)idOrName {
  (void)idOrName;
  return 2;
}
@end

#endif
