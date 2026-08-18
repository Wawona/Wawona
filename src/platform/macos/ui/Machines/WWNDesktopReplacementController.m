//
// WWNDesktopReplacementController.m. See header.
//
#import "WWNDesktopReplacementController.h"

#import "WWNMachineProfileStore.h"
#import "WWNPlatformCapabilities.h"
#import "../Settings/WWNPreferencesManager.h"
#import "../Settings/WWNSipStatus.h"
#import "../Settings/WWNWaypipeRunner.h"
#import "../../WWNPlatformCallbacks.h"
#import <Security/Security.h>

#include <signal.h>
#include <sys/types.h>
#include <unistd.h>

#if TARGET_OS_OSX

@interface WWNDesktopReplacementController ()
@property (nonatomic, assign) pid_t modeBPid;
@property (nonatomic, copy, nullable) NSString *modeBMachineId;
- (BOOL)terminateModeBProcess:(pid_t)pid
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

  // Privileged launch: Mode B constructor requires root (wayland_mac_load).
  // osascript shows the standard admin dialog; weston is backgrounded so the
  // AppleScript returns the PID immediately (CoreBedtime run-weston.sh model).
  NSString *logPath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"wawona-modeb.log"];
  NSString *shellCmd;
  if ([clientId isEqualToString:@"niri"]) {
    shellCmd = [NSString
        stringWithFormat:
            @"export DYLD_INSERT_LIBRARIES=%@; "
            @"export XDG_RUNTIME_DIR=%@; "
            @"%@ >%@ 2>&1 & echo $!",
            [self wwnShellQuote:dylib], [self wwnShellQuote:xdg],
            [self wwnShellQuote:executablePath], [self wwnShellQuote:logPath]];
  } else {
    shellCmd = [NSString
        stringWithFormat:
            @"export DYLD_INSERT_LIBRARIES=%@; "
            @"export XDG_RUNTIME_DIR=%@; "
            @"%@ --backend=drm --continue-without-input "
            @"--socket=%@ --shell=desktop-shell.so --config=%@ "
            @">%@ 2>&1 & echo $!",
            [self wwnShellQuote:dylib], [self wwnShellQuote:xdg],
            [self wwnShellQuote:executablePath], [self wwnShellQuote:socketName],
            [self wwnShellQuote:configPath], [self wwnShellQuote:logPath]];
  }

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
        @"machineId=%@ log=%@",
        (int)pid, dylib, executablePath, profile.machineId, logPath);
  return YES;
}

- (void)disengage {
  NSError *error = nil;
  if (self.modeBPid > 0 &&
      ![self terminateModeBProcess:self.modeBPid error:&error]) {
    NSLog(@"[DesktopReplacement] Mode B stop failed: %@", error);
    return;
  }
  self.modeBPid = 0;
  self.modeBMachineId = nil;
}

- (BOOL)terminateModeBProcess:(pid_t)pid
                         error:(NSError *_Nullable *_Nullable)error {
  if (pid <= 0) {
    return YES;
  }

  /*
   * Mode B Weston was launched by osascript with administrator privileges,
   * therefore an ordinary GUI-process kill(2) commonly returns EPERM.  Stop
   * the root-owned session through the same privilege boundary, wait for its
   * dylib destructor to stop framebufferd/inputd/caffeinate, then escalate
   * only if the process failed to leave. `pid` is an integer from the prior
   * launch output, not user-controlled shell text.
   */
  NSString *shellCmd = [NSString
      stringWithFormat:
          @"if kill -0 %d 2>/dev/null; then "
          @"kill -TERM %d; "
          @"i=0; while kill -0 %d 2>/dev/null && [ $i -lt 50 ]; do "
          @"sleep 0.1; i=$((i + 1)); done; "
          @"if kill -0 %d 2>/dev/null; then "
          @"kill -KILL %d; "
          @"for helper in framebufferd inputd caffeinate; do "
          @"p=/tmp/libwayland-support/$helper.pid; "
          @"if [ -r \"$p\" ]; then hp=$(cat \"$p\"); "
          @"case \"$hp\" in ''|*[!0-9]*) ;; "
          @"*) kill -TERM \"$hp\" 2>/dev/null || true ;; esac; "
          @"rm -f \"$p\"; fi; done; "
          @"fi; "
          @"fi",
          (int)pid, (int)pid, (int)pid, (int)pid, (int)pid];
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
- (void)disengage {
}
- (BOOL)reconcilePrefsWithCurrentSip {
  return NO;
}
@end

#endif
