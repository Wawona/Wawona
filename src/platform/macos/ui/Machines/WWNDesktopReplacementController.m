//
// WWNDesktopReplacementController.m. See header.
//
#import "WWNDesktopReplacementController.h"

#import "WWNMachineProfileStore.h"
#import "WWNPlatformCapabilities.h"
#import "../Settings/WWNPreferencesManager.h"
#import "../Settings/WWNSipStatus.h"
#import "../../WWNPlatformCallbacks.h"
#import <Security/Security.h>

#include <signal.h>
#include <sys/types.h>
#include <unistd.h>

#if TARGET_OS_OSX
#include <servers/bootstrap.h>
#include <mach/mach.h>

static NSString *const kWWNModeBLaunchdLabel =
    @"com.aspauldingcode.wawona.modeb";
static NSString *const kWWNModeBSupportDir =
    @"/Library/Application Support/Wawona";
static NSString *const kWWNModeBHelperName = @"run-modeb.sh";
static NSString *const kWWNModeBPidPath =
    @"/tmp/libwayland-support/modeb-compositor.pid";
static const char *kWWNFramebufferdService = "com.wayland-mac.framebufferd";

static BOOL WWNFramebufferdRegistered(void) {
  mach_port_t port = MACH_PORT_NULL;
  kern_return_t kr =
      bootstrap_look_up(bootstrap_port, kWWNFramebufferdService, &port);
  if (kr == KERN_SUCCESS) {
    mach_port_deallocate(mach_task_self(), port);
    return YES;
  }
  return NO;
}

@interface WWNDesktopReplacementController ()
@property (nonatomic, assign) pid_t modeBPid;
@property (nonatomic, copy, nullable) NSString *modeBMachineId;
- (BOOL)terminateModeBProcess:(pid_t)pid
                         error:(NSError *_Nullable *_Nullable)error;
- (NSString *)modeBHelperPath;
- (NSString *)modeBPlistPath;
- (NSString *)modeBLaunchScriptForExecutable:(NSString *)executablePath
                                    clientId:(NSString *)clientId
                                         xdg:(NSString *)xdg
                                  socketName:(NSString *)socketName
                                  configPath:(NSString *)configPath
                                       dylib:(NSString *)dylib;
- (NSString *)wwnShellQuote:(NSString *)s;
- (NSString *)wwnAppleScriptQuote:(NSString *)s;
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

- (NSString *)modeBPlistPath {
  return [NSString stringWithFormat:@"/Library/LaunchDaemons/%@.plist",
                                    kWWNModeBLaunchdLabel];
}

- (NSString *)modeBLaunchScriptForExecutable:(NSString *)executablePath
                                    clientId:(NSString *)clientId
                                         xdg:(NSString *)xdg
                                  socketName:(NSString *)socketName
                                  configPath:(NSString *)configPath
                                       dylib:(NSString *)dylib {
  NSMutableString *script = [NSMutableString string];
  [script appendString:@"#!/bin/bash\nset -e\n"];
  [script appendFormat:@"export DYLD_INSERT_LIBRARIES=%@\n",
                       [self wwnShellQuote:dylib]];
  [script appendFormat:@"export XDG_RUNTIME_DIR=%@\n", [self wwnShellQuote:xdg]];
  [script appendFormat:@"mkdir -p %@\nchmod 700 %@\n", [self wwnShellQuote:xdg],
                       [self wwnShellQuote:xdg]];

  NSString *frameworksDir = [[[NSBundle mainBundle] bundlePath]
      stringByAppendingPathComponent:@"Contents/Frameworks"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksDir]) {
    [script appendFormat:@"export DYLD_LIBRARY_PATH=%@\n",
                         [self wwnShellQuote:frameworksDir]];
  }
  [script appendString:@"export ANGLE_DEFAULT_PLATFORM=metal\n"];

  NSString *shareRoot = WWNWawonaShareRoot();
  if (shareRoot.length > 0) {
    [script appendFormat:@"export WAWONA_SHARE_ROOT=%@\n",
                         [self wwnShellQuote:shareRoot]];
    NSString *kdl =
        [shareRoot stringByAppendingPathComponent:@"niri/default-config.kdl"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:kdl]) {
      [script appendFormat:@"export NIRI_CONFIG=%@\n", [self wwnShellQuote:kdl]];
    }
  }
  NSString *bundleBin = [[[NSBundle mainBundle] bundlePath]
      stringByAppendingPathComponent:@"Contents/Resources/bin"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:bundleBin]) {
    [script appendFormat:@"export PATH=%@:\"$PATH\"\n",
                         [self wwnShellQuote:bundleBin]];
  }

  [script appendString:@"/bin/launchctl bootout system/com.apple.WindowServer "
                       @">/dev/null 2>&1 || true\n"];
  [script appendString:@"/bin/launchctl unload -w "
                       @"/System/Library/LaunchDaemons/"
                       @"com.apple.WindowServer.plist >/dev/null 2>&1 || true\n"];
  [script appendString:@"mkdir -p /tmp/libwayland-support\n"];
  [script appendFormat:@"echo $$ > %@\n", [self wwnShellQuote:kWWNModeBPidPath]];

  if ([clientId isEqualToString:@"niri"]) {
    [script appendString:@"export NIRI_BACKEND=tty\n"];
    [script appendFormat:@"exec %@\n", [self wwnShellQuote:executablePath]];
  } else {
    [script appendFormat:@"exec %@ --backend=drm --continue-without-input "
                         @"--socket=%@ --shell=desktop-shell.so --config=%@\n",
                         [self wwnShellQuote:executablePath],
                         [self wwnShellQuote:socketName],
                         [self wwnShellQuote:configPath]];
  }
  return script;
}

- (BOOL)engageSelectedDesktopMachine:(NSError *_Nullable *_Nullable)error {
  NSString *desktopId = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsDesktopReplacementMachineId];
  if (desktopId.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:9
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Pick a Desktop Machine in Settings before enabling "
                       @"Desktop Replacement."
                 }];
    }
    return NO;
  }
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
                       @"blocks injection."
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

  if (self.modeBPid > 0 && kill(self.modeBPid, 0) == 0 &&
      [self.modeBMachineId isEqualToString:profile.machineId]) {
    return YES;
  }
  if (WWNFramebufferdRegistered()) {
    self.modeBMachineId = [profile.machineId copy];
    return YES;
  }
  if (self.modeBPid > 0) {
    /*
     * A different Desktop profile (or a stale PID) must not share the
     * framebufferd/inputd set of the previous injected Weston.  Mode B
     * helpers are owned by the dylib and exit with its Weston process.
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

  NSString *dylib = [self bundledDylibPath];
  if (dylib.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"This Wawona build does not ship libwayland-mac.dylib "
                       @"(Mode B). Use the desktop-host package, or stay on "
                       @"Mode A in-window present."
                 }];
    }
    return NO;
  }

  NSDictionary *so = [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
                         ? profile.settingsOverrides
                         : @{};
  NSString *clientId = [so[@"NativeClientId"] isKindOfClass:[NSString class]]
                           ? so[@"NativeClientId"]
                           : @"weston";
  if (clientId.length == 0) clientId = @"weston";

  NSString *executablePath = WWNWawonaFindBundledExecutable(clientId);
  if (executablePath.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:4
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       [NSString stringWithFormat:@"Bundled %@ executable not found.", clientId]
                 }];
    }
    return NO;
  }

  WWNConfigureBundledRuntimeEnvIfNeeded();

  const char *xdg_c = getenv("XDG_RUNTIME_DIR");
  NSString *xdg =
      xdg_c && xdg_c[0] ? [NSString stringWithUTF8String:xdg_c] : @"/tmp/weston-runtime";
  [[NSFileManager defaultManager] createDirectoryAtPath:xdg
                            withIntermediateDirectories:YES
                                             attributes:@{
                                               NSFilePosixPermissions : @0700
                                             }
                                                  error:nil];

  NSString *socketName = [WWNPreferencesManager preferredNestedSocketName];
  NSString *configPath = [xdg stringByAppendingPathComponent:@"weston-modeb.ini"];
  if ([clientId isEqualToString:@"weston"]) {
    // Minimal DRM weston.ini; Mode B presents via framebufferd, not pixman.
  #if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    CGFloat fontSize = [UIFont systemFontSize];
  #else
    CGFloat fontSize = [NSFont systemFontSize];
  #endif
    NSString *ini = [NSString
        stringWithFormat:@"[core]\n"
                          "backend=drm-backend.so\n"
                          "shell=desktop-shell.so\n"
                          "\n"
                          "[shell]\n"
                          "locking=false\n"
                          "\n"
                          "[terminal]\n"
                          "font=DejaVuSansM Nerd Font Mono\n"
                          "font-size=%.0f\n",
                         fontSize];
    [ini writeToFile:configPath
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];
  }

  /*
   * CoreBedtime model: privileged LaunchDaemon + unload Apple WindowServer,
   * then DYLD_INSERT the Mode B dylib into weston/niri. Logout is the wrong
   * handoff. loginwindow starts Aqua's WindowServer again and nothing injects.
   */
  NSString *helperPath = [self modeBHelperPath];
  NSString *plistPath = [self modeBPlistPath];
  NSString *script = [self modeBLaunchScriptForExecutable:executablePath
                                                 clientId:clientId
                                                      xdg:xdg
                                               socketName:socketName
                                               configPath:configPath
                                                    dylib:dylib];
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpScript =
      [tmpDir stringByAppendingPathComponent:@"wawona-run-modeb.sh"];
  NSString *tmpPlist =
      [tmpDir stringByAppendingPathComponent:@"wawona-modeb.plist"];
  if (![script writeToFile:tmpScript
                atomically:YES
                  encoding:NSUTF8StringEncoding
                     error:error]) {
    return NO;
  }
  NSDictionary *plist = @{
    @"Label" : kWWNModeBLaunchdLabel,
    @"ProgramArguments" : @[ helperPath ],
    @"RunAtLoad" : @YES,
    @"KeepAlive" : @YES,
    @"ThrottleInterval" : @5,
    @"POSIXSpawnType" : @"Interactive",
    @"EnablePressuredExit" : @NO,
    @"UserName" : @"root",
    @"StandardOutPath" : @"/tmp/wawona-modeb.log",
    @"StandardErrorPath" : @"/tmp/wawona-modeb.log",
  };
  if (![plist writeToFile:tmpPlist atomically:YES]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:8
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Failed to write Mode B launchd plist."
                 }];
    }
    return NO;
  }

  NSString *shellCmd = [NSString
      stringWithFormat:
          @"set -e\n"
          @"mkdir -p %@\n"
          @"cp %@ %@\n"
          @"chmod 755 %@\n"
          @"cp %@ %@\n"
          @"chown root:wheel %@ %@\n"
          @"chmod 644 %@\n"
          @"/bin/launchctl bootout system/com.apple.WindowServer "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl unload -w "
          @"/System/Library/LaunchDaemons/com.apple.WindowServer.plist "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootout system/%@ >/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootstrap system %@\n"
          @"i=0\n"
          @"while [ $i -lt 150 ]; do\n"
          @"  if [ -s %@ ]; then\n"
          @"    pid=$(cat %@)\n"
          @"    case \"$pid\" in ''|*[!0-9]*) ;; "
          @"    *) if kill -0 \"$pid\" 2>/dev/null; then echo \"$pid\"; "
          @"exit 0; fi ;; esac\n"
          @"  fi\n"
          @"  sleep 0.1\n"
          @"  i=$((i + 1))\n"
          @"done\n"
          @"/bin/launchctl bootout system/%@ >/dev/null 2>&1 || true\n"
          @"/bin/launchctl load -w "
          @"/System/Library/LaunchDaemons/com.apple.WindowServer.plist "
          @">/dev/null 2>&1 || true\n"
          @"echo 0\n"
          @"exit 1\n",
          [self wwnShellQuote:kWWNModeBSupportDir],
          [self wwnShellQuote:tmpScript], [self wwnShellQuote:helperPath],
          [self wwnShellQuote:helperPath],
          [self wwnShellQuote:tmpPlist], [self wwnShellQuote:plistPath],
          [self wwnShellQuote:helperPath], [self wwnShellQuote:plistPath],
          [self wwnShellQuote:plistPath],
          kWWNModeBLaunchdLabel,
          [self wwnShellQuote:plistPath],
          [self wwnShellQuote:kWWNModeBPidPath],
          [self wwnShellQuote:kWWNModeBPidPath],
          kWWNModeBLaunchdLabel];

  AuthorizationRef authRef;
  OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authRef);
  if (status != errAuthorizationSuccess) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNDesktopReplacement"
                                   code:5
                               userInfo:@{ NSLocalizedDescriptionKey : @"Authorization creation failed." }];
    }
    return NO;
  }

  AuthorizationItem right = {kAuthorizationRightExecute, 0, NULL, 0};
  AuthorizationRights rights = {1, &right};
  AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
  status = AuthorizationCopyRights(authRef, &rights, NULL, flags, NULL);
  if (status != errAuthorizationSuccess) {
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    if (error) {
      *error = [NSError errorWithDomain:@"WWNDesktopReplacement"
                                   code:5
                               userInfo:@{ NSLocalizedDescriptionKey : @"User cancelled administrator authorization." }];
    }
    return NO;
  }

  char *args[] = {"-c", (char *)shellCmd.UTF8String, NULL};
  FILE *pipe = NULL;
  
  // Disable deprecation warnings for this specific block as we are explicitly choosing this approach
  // over an XPC helper for simplicity in this experimental developer tool.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  status = AuthorizationExecuteWithPrivileges(authRef, "/bin/sh", kAuthorizationFlagDefaults, args, &pipe);
#pragma clang diagnostic pop

  if (status != errAuthorizationSuccess) {
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       [NSString stringWithFormat:@"Failed to launch Mode B %@ "
                       @"via administrator privileges (status=%d).", clientId, (int)status]
                 }];
    }
    return NO;
  }

  char buf[128] = {0};
  if (pipe) {
      fgets(buf, sizeof(buf), pipe);
      fclose(pipe);
  }
  AuthorizationFree(authRef, kAuthorizationFlagDefaults);

  NSString *outStr = [NSString stringWithUTF8String:buf];
  NSString *trimmedOut = [outStr
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  pid_t pid = (pid_t)[trimmedOut integerValue];
  if (pid <= 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:6
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Mode B privileged launch failed to return valid PID "
                           @"(output=%@). Check SIP and admin approval.",
                           trimmedOut ?: @""]
                 }];
    }
    return NO;
  }

  self.modeBPid = pid;
  self.modeBMachineId = [profile.machineId copy];
  NSLog(@"[DesktopReplacement] Mode B engaged pid=%d dylib=%@ executable=%@ "
        @"machineId=%@ log=/tmp/wawona-modeb.log",
        (int)pid, dylib, executablePath, profile.machineId);
  return YES;
}

- (void)disengage {
  NSError *error = nil;
  if (![self terminateModeBProcess:self.modeBPid error:&error]) {
    NSLog(@"[DesktopReplacement] Mode B stop failed: %@", error);
    return;
  }
  self.modeBPid = 0;
  self.modeBMachineId = nil;
}

- (BOOL)terminateModeBProcess:(pid_t)pid
                         error:(NSError *_Nullable *_Nullable)error {
  /*
   * Boot out the KeepAlive LaunchDaemon first so launchd does not respawn
   * niri/weston, then TERM the compositor and Mode B helpers, then bring
   * Apple's WindowServer back. Root-owned jobs cannot be killed from the
   * GUI process.
   */
  NSString *shellCmd = [NSString
      stringWithFormat:
          @"/bin/launchctl bootout system/%@ >/dev/null 2>&1 || true\n"
          @"rm -f %@ %@\n"
          @"if [ %d -gt 0 ] && kill -0 %d 2>/dev/null; then "
          @"kill -TERM %d; "
          @"i=0; while kill -0 %d 2>/dev/null && [ $i -lt 50 ]; do "
          @"sleep 0.1; i=$((i + 1)); done; "
          @"if kill -0 %d 2>/dev/null; then kill -KILL %d; fi; "
          @"fi\n"
          @"for helper in framebufferd inputd caffeinate; do "
          @"p=/tmp/libwayland-support/$helper.pid; "
          @"if [ -r \"$p\" ]; then hp=$(cat \"$p\"); "
          @"case \"$hp\" in ''|*[!0-9]*) ;; "
          @"*) kill -TERM \"$hp\" 2>/dev/null || true ;; esac; "
          @"rm -f \"$p\"; fi; done\n"
          @"rm -f %@\n"
          @"/bin/launchctl load -w "
          @"/System/Library/LaunchDaemons/com.apple.WindowServer.plist "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl bootstrap system "
          @"/System/Library/LaunchDaemons/com.apple.WindowServer.plist "
          @">/dev/null 2>&1 || true\n"
          @"/bin/launchctl kickstart -k system/com.apple.WindowServer "
          @">/dev/null 2>&1 || true\n",
          kWWNModeBLaunchdLabel,
          [self wwnShellQuote:[self modeBPlistPath]],
          [self wwnShellQuote:[self modeBHelperPath]],
          (int)pid, (int)pid, (int)pid, (int)pid, (int)pid, (int)pid,
          [self wwnShellQuote:kWWNModeBPidPath]];
  NSString *osa =
      [NSString stringWithFormat:@"do shell script %@ with administrator "
                                 @"privileges",
                                 [self wwnAppleScriptQuote:shellCmd]];

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
  task.arguments = @[ @"-e", osa ];
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
- (void)disengage {
}
- (BOOL)reconcilePrefsWithCurrentSip {
  return NO;
}
@end

#endif
