//
// WWNDesktopReplacementController.m. See header.
//
#import "WWNDesktopReplacementController.h"

#import "WWNMachineProfileStore.h"
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
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
#include <sys/types.h>
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
static NSString *const kWWNModeBPidPath =
    @"/tmp/libwayland-support/modeb-compositor.pid";
static NSString *const kWWNModeBInstalledDylibRel =
    @"iland/libwayland-mac.dylib";
static NSString *const kWWNModeBSudoersPath =
    @"/etc/sudoers.d/wawona-modeb";
static NSString *const kWWNModeBFailReasonPath =
    @"/tmp/wawona-modeb-failed.reason";
static NSString *const kWWNModeBLogPath = @"/tmp/wawona-modeb.log";
static NSString *const kWWNModeBCliLogPath = @"/tmp/wawona-modeb-cli.log";
static NSString *const kWWNModeBKeepWsPath = @"/tmp/wawona-modeb-keep-ws";
static NSString *const kWWNModeBFbReadyPath =
    @"/tmp/libwayland-support/modeb-framebufferd.ready";

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
- (NSDictionary<NSString *, NSString *> *)modeBStrippedEnvironment;
- (NSString *)modeBFileCleanupShell;
- (BOOL)installModeBHelperAndDylibForProfile:(WWNMachineProfile *)profile
                                       error:(NSError *_Nullable *_Nullable)error;
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
  return [kWWNModeBSupportDir
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
                       @"%@ --kill-compositor, %@ --uninstall\n"
                       @"# wwn-iowatchdog is NOT NOPASSWD. Take Over runs it\n"
                       @"# from the root helper only. Never grant passwordless\n"
                       @"# disable/enable (lldb attach paniced 2026-08-20).\n",
                       user, user, helperEscaped, helperEscaped,
                       helperEscaped, helperEscaped];
}

- (BOOL)ensureDesktopMachineSelected:(NSError *_Nullable *_Nullable)error {
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSString *desktopId =
      [defs stringForKey:kWWNPrefsDesktopReplacementMachineId];
  WWNMachineProfile *selected =
      desktopId.length > 0 ? [WWNMachineProfileStore profileById:desktopId]
                           : nil;
  if (selected &&
      [WWNMachineProfileStore profileIndicatesNestedCompositor:selected]) {
    return YES;
  }

  for (WWNMachineProfile *profile in [WWNMachineProfileStore loadProfiles]) {
    if ([WWNMachineProfileStore profileIndicatesNestedCompositor:profile] &&
        profile.machineId.length > 0) {
      [defs setObject:profile.machineId
               forKey:kWWNPrefsDesktopReplacementMachineId];
      NSLog(@"[DesktopReplacement] selected existing compositor machine %@",
            profile.machineId);
      return YES;
    }
  }

  WWNMachineProfile *created = [WWNMachineProfile defaultProfile];
  created.name = @"Weston Desktop";
  NSMutableDictionary *so =
      [created.settingsOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
  so[@"NativeClientId"] = @"weston";
  so[@"WestonEnabled"] = @YES;
  so[@"WestonTerminalEnabled"] = @NO;
  so[@"EnableLauncher"] = @YES;
  created.settingsOverrides = so;
  [WWNMachineProfileStore upsertProfile:created];
  if (created.machineId.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:9
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Could not create a Weston Desktop machine."
                 }];
    }
    return NO;
  }
  [defs setObject:created.machineId
           forKey:kWWNPrefsDesktopReplacementMachineId];
  NSLog(@"[DesktopReplacement] created Weston Desktop machine %@",
        created.machineId);
  return YES;
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
  [script appendFormat:@"WWN_MODEB_UID=%u\n", (unsigned)getuid()];
  [script appendFormat:@"WWN_IOWATCHDOG=%@\n",
                       [self wwnShellQuote:[self modeBIowatchdogPath]]];
  [script appendFormat:@"REASON=%@\n", qReason];
  [script appendFormat:@"PIDFILE=%@\n", qPid];
  [script appendFormat:@"LOG=%@\n", qLog];
  [script appendFormat:@"WS_PLIST=%@\n", qWsPlist];
  [script appendFormat:@"WD_PLIST=%@\n", qWdPlist];
  [script appendString:@""
                       @"wwn_log() {\n"
                       @"  printf '%s %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" \"$*\" >> \"$LOG\"\n"
                       @"}\n"
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
                       @"pgrep -u 0 -x weston 2>/dev/null); do\n"
                       @"    wwn_log \"kill leftover compositor pid=$p\"\n"
                       @"    kill -TERM \"$p\" 2>/dev/null || true\n"
                       @"  done\n"
                       @"  sleep 0.2\n"
                       @"  for p in $(pgrep -u 0 -x niri 2>/dev/null; "
                       @"pgrep -u 0 -x weston 2>/dev/null); do\n"
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
                       @"  # Reverse of Take Over. Never attach lldb / call\n"
                       @"  # wwn-iowatchdog enable unless Take Over left the\n"
                       @"  # disabled marker. Blind enable paniced 2026-08-20\n"
                       @"  # (watchdogd exited SIGTRAP while kernel monitor\n"
                       @"  # still armed) on --restore-aqua and app open.\n"
                       @"  /bin/launchctl enable system/com.apple.watchdogd; "
                       @"wwn_log \"wd_enable_st=$?\"\n"
                       @"  if [ -f /tmp/libwayland-support/iowatchdog-userspace-disabled ]; then\n"
                       @"    if [ -x \"$WWN_IOWATCHDOG\" ]; then\n"
                       @"      \"$WWN_IOWATCHDOG\" enable >>\"$LOG\" 2>&1 || "
                       @"wwn_log \"iowatchdog enable failed (reboot restores)\"\n"
                       @"    else\n"
                       @"      wwn_log \"WWN_IOWATCHDOG missing; skip kernel enable\"\n"
                       @"    fi\n"
                       @"    rm -f /tmp/libwayland-support/iowatchdog-userspace-disabled\n"
                       @"  else\n"
                       @"    wwn_log \"skip wwn-iowatchdog enable (no disable marker)\"\n"
                       @"  fi\n"
                       @"  /bin/launchctl load -w \"$WD_PLIST\"; wwn_log \"wd_load_w_st=$?\"\n"
                       @"  /bin/launchctl bootstrap system \"$WD_PLIST\" "
                       @">/dev/null 2>&1 || true\n"
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
                       @"  # ONLY after wwn-iowatchdog disable succeeded.\n"
                       @"  /bin/launchctl disable system/com.apple.watchdogd; "
                       @"wwn_log \"wd_disable_st=$?\"\n"
                       @"  /bin/launchctl bootout system/com.apple.watchdogd; "
                       @"wwn_log \"wd_bootout_st=$?\"\n"
                       @"  /bin/launchctl unload -w \"$WD_PLIST\" "
                       @">/dev/null 2>&1 || true\n"
                       @"  wwn_log \"watchdogd unloaded after IOWatchdog disable\"\n"
                       @"}\n"
                       @"stop_window_server() {\n"
                       @"  /bin/launchctl bootout system/com.apple.WindowServer; "
                       @"wwn_log \"ws_bootout_st=$?\"\n"
                       @"  /bin/launchctl disable system/com.apple.WindowServer; "
                       @"wwn_log \"ws_disable_st=$?\"\n"
                       @"  /bin/launchctl unload -w \"$WS_PLIST\"; "
                       @"wwn_log \"ws_unload_w_st=$?\"\n"
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
                       @"  kill_compositor\n"
                       @"  stop_other_helpers\n"
                       @"  /bin/launchctl bootout "
                       @"system/com.aspauldingcode.wawona.modeb "
                       @">/dev/null 2>&1 || true\n"
                       @"  restore_window_server\n"
                       @"  restore_watchdogd\n"
                       @"  rmdir /tmp/libwayland-support/modeb.lock 2>/dev/null || true\n"
                       @"  rm -rf /tmp/libwayland-support/modeb.lock 2>/dev/null || true\n"
                       @"  wwn_log \"restore_aqua done\"\n"
                       @"}\n"
                       @"touch \"$LOG\" 2>/dev/null || true\n"
                       @"chmod 666 \"$LOG\" 2>/dev/null || true\n"
                       @"if [ \"${1-}\" = \"--restore-aqua\" ] || "
                       @"[ \"${1-}\" = \"--kill-compositor\" ]; then\n"
                       @"  restore_aqua\n"
                       @"  exit 0\n"
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
                       @"    fpid=$(cat \"$PIDFILE\" 2>/dev/null || true)\n"
                       @"    if [ -n \"$fpid\" ] && kill -0 \"$fpid\" "
                       @"2>/dev/null; then\n"
                       @"      wwn_log \"modeb helper already running "
                       @"compositor=$fpid\"\n"
                       @"      exit 0\n"
                       @"    fi\n"
                       @"    wwn_log \"stale modeb.lock; stealing try=$tries\"\n"
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
                       @"trap '' TERM INT HUP\n"
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
   * macOS 26: unloading watchdogd without IOWatchdog disable panics
   * immediately. Leaving WindowServer missing while watchdogd runs panics
   * at ~120s. Take Over: disable IOWatchdog, then unload watchdogd, then
   * WindowServer, then inject. Probe (KEEP_WS) injects with Aqua up.
   * Never kickstart -k watchdogd.
   */
  [script appendString:@"wwn_log \"WWN_MODEB_GATE=pidfile-not-pgrep\"\n"];
  [script appendString:@"wwn_log \"WWN_MODEB_WD=iowatchdog-then-unload\"\n"];
  [script appendString:@"rm -f /tmp/libwayland-support/modeb-framebufferd.ready\n"];
  [script appendString:@"install_ws_guard\n"];
  [script appendString:@"if [ -f /tmp/wawona-modeb-keep-ws ]; then\n"];
  [script appendString:@"  wwn_log \"KEEP_WS=1; leaving WindowServer and "
                       @"watchdogd running\"\n"];
  [script appendString:@"else\n"];
  [script appendString:@"  if [ ! -x \"$WWN_IOWATCHDOG\" ]; then\n"];
  [script appendString:@"    write_reason \"Mode B refused Take Over: "
                       @"wwn-iowatchdog is missing. Re-run nix run .#install. "
                       @"Apple's WindowServer was left running.\"\n"];
  [script appendString:@"    rmdir /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"    rm -rf /tmp/libwayland-support/modeb.lock "
                       @"2>/dev/null || true\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  if ! \"$WWN_IOWATCHDOG\" disable >>\"$LOG\" 2>&1; then\n"];
  [script appendString:@"    write_reason \"Mode B refused Take Over: "
                       @"IOWatchdog disable failed. Unloading watchdogd "
                       @"without that panics on macOS 26. Apple's "
                       @"WindowServer was left running.\"\n"];
  [script appendString:@"    restore_aqua\n"];
  [script appendString:@"    exit 0\n"];
  [script appendString:@"  fi\n"];
  [script appendString:@"  wwn_log \"IOWatchdog userspace monitoring disabled\"\n"];
  [script appendString:@"  mkdir -p /tmp/libwayland-support\n"];
  [script appendString:@"  : > /tmp/libwayland-support/iowatchdog-userspace-disabled\n"];
  [script appendString:@"  chmod 644 /tmp/libwayland-support/iowatchdog-userspace-disabled "
                       @"2>/dev/null || true\n"];
  [script appendString:@"  stop_watchdogd_after_iowatchdog\n"];
  [script appendString:@"  stop_window_server\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"set +e\n"];
  [script appendString:@"DYLD_INSERT_LIBRARIES=\"$WWN_MODEB_DYLIB\" "];
  [script appendFormat:@"%@ ", [self wwnShellQuote:executablePath]];
  for (NSString *arg in arguments) {
    [script appendFormat:@"%@ ", [self wwnShellQuote:arg]];
  }
  [script appendString:@">>\"$LOG\" 2>&1 &\n"];
  [script appendString:@"pid=$!\n"];
  [script appendString:@"echo \"$pid\" > \"$PIDFILE\"\n"];
  [script appendString:@"chmod 644 \"$PIDFILE\" 2>/dev/null || true\n"];
  [script appendString:@"wwn_log \"compositor pid=$pid\"\n"];
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
  [script appendString:@"if [ \"$fb_live\" != 1 ]; then\n"];
  [script appendString:@"  write_reason \"Mode B did not start framebufferd. "
                       @"Apple's WindowServer was restored. See "
                       @"/tmp/wawona-modeb.log.\"\n"];
  [script appendString:@"  restore_aqua\n"];
  [script appendString:@"  exit 0\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"touch /tmp/libwayland-support/modeb-framebufferd.ready\n"];
  [script appendString:@"chmod 644 /tmp/libwayland-support/modeb-framebufferd.ready "
                       @"2>/dev/null || true\n"];
  [script appendString:@"trap 'restore_aqua; exit 0' TERM INT HUP\n"];
  [script appendString:@"sleep 0.4\n"];
  [script appendString:@"if ! kill -0 \"$pid\" 2>/dev/null; then\n"];
  [script appendString:@"  wait \"$pid\"\n"];
  [script appendString:@"  status=$?\n"];
  [script appendString:@"  restore_aqua\n"];
  [script appendString:@"  write_reason \"The nested compositor failed to start "
                       @"(status $status). See /tmp/wawona-modeb.log.\"\n"];
  [script appendString:@"  exit 0\n"];
  [script appendString:@"fi\n"];
  [script appendString:@"wait \"$pid\"\n"];
  [script appendString:@"status=$?\n"];
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
          @"/bin/launchctl enable system/com.apple.watchdogd "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl load -w "
          @"/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootstrap system "
          @"/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
          @">/dev/null 2>&1 || true\n"
          @"log watchdogd-ensure-done\n"
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
          @"guard=/Library/LaunchDaemons/com.aspauldingcode.wawona.ws-guard.plist\n"
          @"cat > \"$guard\" <<'PLIST'\n"
          @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
          @"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
          @"<plist version=\"1.0\"><dict>\n"
          @"<key>Label</key><string>com.aspauldingcode.wawona.ws-guard</string>\n"
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
          @"wspid=$(/bin/launchctl print system/com.apple.WindowServer 2>/dev/null | awk '/[[:space:]]pid =/{print $3; exit}'); "
          @"if [ -z \"$wspid\" ]; then /bin/launchctl kickstart -k system/com.apple.WindowServer; fi</string>\n"
          @"</array></dict></plist>\n"
          @"PLIST\n"
          @"chown root:wheel \"$guard\" 2>/dev/null || true\n"
          @"chmod 644 \"$guard\" 2>/dev/null || true\n"
          @"/bin/launchctl bootout system/com.aspauldingcode.wawona.ws-guard >/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootstrap system \"$guard\" >/dev/null 2>&1 || true\n"
          @"log copied-ok\n"
          @"echo WWN_MODEB_INSTALLED=1\n"
          @"log done\n"
          @"exit 0\n",
          [self wwnShellQuote:kWWNModeBPidPath],
          [self wwnShellQuote:kWWNModeBFailReasonPath],
          [self wwnShellQuote:kWWNModeBSupportDir],
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
        [existingHelper containsString:@"WWN_MODEB_LOCK=helper-argv-only"] &&
        [existingHelper containsString:@"WWN_MODEB_WD=iowatchdog-then-unload"] &&
        [existingHelper containsString:@"stop_watchdogd_after_iowatchdog"] &&
        [existingHelper containsString:@"stale modeb.lock"] &&
        [existingHelper containsString:@"# WWN_WAWONA_STORE="] &&
        [existingHelper containsString:bundlePath] &&
        ![existingHelper containsString:@"reap WindowServer"] &&
        ![existingHelper containsString:@"WWN_MODEB_WD=launchctl-unload"] &&
        ![existingHelper containsString:@"WWN_MODEB_WD=hands-off"] &&
        ![existingHelper
            containsString:@"kickstart -k system/com.apple.watchdogd"] &&
        ![existingHelper containsString:@"Mode B helper DISABLED"];
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
          @"/usr/bin/pkill -u 0 -x framebufferd >/dev/null 2>&1 || true\n"
          @"/usr/bin/pkill -u 0 -x inputd >/dev/null 2>&1 || true\n"
          @"rm -f %@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@\n"
          @"rmdir /tmp/libwayland-support/modeb.lock >/dev/null 2>&1 || true\n"
          @"rm -rf /tmp/libwayland-support/modeb.lock >/dev/null 2>&1 || true\n"
          @"rm -f /tmp/libwayland-support/framebufferd "
          @"/tmp/libwayland-support/modeb-framebufferd.ready "
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
          @"# restore_aqua already re-enabled IOWatchdog if the disable\n"
          @"# marker was set. Never lldb-attach here (blind enable panics).\n"
          @"rm -f /tmp/libwayland-support/iowatchdog-userspace-disabled\n"
          @"/bin/launchctl enable system/com.apple.watchdogd "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl load -w "
          @"/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootstrap system "
          @"/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
          @">/dev/null 2>&1 || true\n",
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
   */
  WWNModeBCliLog(@"starting sudo -n -b helper "
                 @"(never unload WindowServer or watchdogd; probe injects "
                 @"while Aqua stays up)");
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
  task.arguments = @[ @"-n", @"-b", helper ];
  task.environment = [self modeBStrippedEnvironment];
  task.standardInput = [NSFileHandle fileHandleWithNullDevice];
  NSPipe *errPipe = [NSPipe pipe];
  task.standardOutput = [NSPipe pipe];
  task.standardError = errPipe;
  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    WWNModeBCliLog(@"sudo -n -b helper launch failed: %@", launchError);
    return 0;
  }
  [task waitUntilExit];
  NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
  NSString *errText = [[NSString alloc] initWithData:errData
                                            encoding:NSUTF8StringEncoding];
  errText = [errText
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  if (task.terminationStatus != 0) {
    WWNModeBCliLog(@"sudo -n -b helper start status=%d stderr=%@",
                   task.terminationStatus,
                   errText.length ? errText : @"(empty)");
    NSString *reason = [NSString
        stringWithFormat:
            @"sudo could not start the Mode B helper (status %d). "
            @"Sudoers must allow the helper path with no extra wrapper. %@",
            task.terminationStatus,
            errText.length ? errText : @""];
    [reason writeToFile:kWWNModeBFailReasonPath
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:nil];
    return 0;
  }

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
  if (![fm moveItemAtPath:src toPath:dst error:nil]) {
    return nil;
  }
  NSString *text = [NSString stringWithContentsOfFile:dst
                                             encoding:NSUTF8StringEncoding
                                                error:nil];
  [fm removeItemAtPath:dst error:nil];
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
  task.standardOutput = [NSPipe pipe];
  task.standardError = [NSPipe pipe];
  NSError *err = nil;
  if (![task launchAndReturnError:&err]) {
    WWNModeBCliLog(@"sudo -n helper launch failed: %@", err);
    return 1;
  }
  [task waitUntilExit];
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
  WWNModeBCliLog(@"mode-b-status");
  WWNModeBCliLog(@"  sip=%@ allows=%d", [WWNSipStatus describe:sip],
                 [WWNSipStatus allowsDesktopReplacement:sip] ? 1 : 0);
  WWNModeBCliLog(@"  DesktopReplacementEnabled=%d machine=%@",
                 [defs boolForKey:kWWNPrefsDesktopReplacementEnabled] ? 1 : 0,
                 [defs stringForKey:kWWNPrefsDesktopReplacementMachineId]
                     ?: @"(none)");
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
  if (pid > 0) {
    WWNModeBCliLog(@"RESULT live compositor pid=%d", (int)pid);
    return 0;
  }
  WWNModeBCliLog(@"RESULT no live compositor pid");
  return 1;
}

- (int)cliEngageKeepWindowServer:(BOOL)keepWindowServer {
  WWNModeBCliLog(@"mode-b-engage keepWindowServer=%d",
                 keepWindowServer ? 1 : 0);
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
@end

#endif
