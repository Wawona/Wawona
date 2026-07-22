//
// WWNDesktopReplacementController.m — see header.
//
#import "WWNDesktopReplacementController.h"

#import "WWNMachineProfileStore.h"
#import "WWNPlatformCapabilities.h"
#import "../Settings/WWNPreferencesManager.h"
#import "../Settings/WWNSipStatus.h"
#import "../Settings/WWNWaypipeRunner.h"
#import "../../WWNPlatformCallbacks.h"

#include <signal.h>
#include <sys/types.h>
#include <unistd.h>

#if TARGET_OS_OSX

@interface WWNDesktopReplacementController ()
@property (nonatomic, assign) pid_t modeBPid;
@property (nonatomic, copy, nullable) NSString *modeBMachineId;
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
  NSLog(@"[DesktopReplacement] cleared DesktopReplacementEnabled — SIP status "
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

  NSString *weston = WWNWawonaFindBundledExecutable(@"weston");
  if (weston.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:4
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Bundled weston executable not found."
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
  // Minimal DRM weston.ini; Mode B presents via framebufferd, not pixman.
  NSString *ini = @"[core]\n"
                   @"backend=drm-backend.so\n"
                   @"shell=desktop-shell.so\n"
                   @"\n"
                   @"[shell]\n"
                   @"locking=false\n";
  [ini writeToFile:configPath
        atomically:YES
          encoding:NSUTF8StringEncoding
             error:nil];

  // Privileged launch: Mode B constructor requires root (wayland_mac_load).
  // osascript shows the standard admin dialog; weston is backgrounded so the
  // AppleScript returns the PID immediately (CoreBedtime run-weston.sh model).
  NSString *logPath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"wawona-modeb.log"];
  NSString *shellCmd = [NSString
      stringWithFormat:
          @"export DYLD_INSERT_LIBRARIES=%@; "
          @"export XDG_RUNTIME_DIR=%@; "
          @"nohup %@ --backend=drm --continue-without-input "
          @"--socket=%@ --shell=desktop-shell.so --config=%@ "
          @">%@ 2>&1 & echo $!",
          [self wwnShellQuote:dylib], [self wwnShellQuote:xdg],
          [self wwnShellQuote:weston], [self wwnShellQuote:socketName],
          [self wwnShellQuote:configPath], [self wwnShellQuote:logPath]];

  NSString *osa =
      [NSString stringWithFormat:@"do shell script %@ with administrator "
                                 @"privileges",
                                 [self wwnAppleScriptQuote:shellCmd]];

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
  task.arguments = @[ @"-e", osa ];
  NSPipe *outPipe = [NSPipe pipe];
  task.standardOutput = outPipe;
  task.standardError = [NSPipe pipe];

  NSError *launchErr = nil;
  if (![task launchAndReturnError:&launchErr]) {
    if (error) {
      *error = launchErr ?: [NSError
                                 errorWithDomain:@"WWNDesktopReplacement"
                                            code:5
                                        userInfo:@{
                                          NSLocalizedDescriptionKey :
                                              @"Failed to launch Mode B weston "
                                              @"via administrator privileges."
                                        }];
    }
    return NO;
  }
  [task waitUntilExit];
  NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
  NSString *outStr =
      [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
  outStr = [outStr
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  pid_t pid = (pid_t)[outStr integerValue];
  if (task.terminationStatus != 0 || pid <= 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNDesktopReplacement"
                     code:6
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Mode B privileged launch failed (status=%d "
                           @"output=%@). Check SIP and admin approval.",
                           task.terminationStatus, outStr ?: @""]
                 }];
    }
    return NO;
  }

  self.modeBPid = pid;
  self.modeBMachineId = [profile.machineId copy];
  NSLog(@"[DesktopReplacement] Mode B engaged pid=%d dylib=%@ weston=%@ "
        @"machine=%@ log=%@",
        (int)pid, dylib, weston, profile.machineId, logPath);
  return YES;
}

- (void)disengage {
  if (self.modeBPid > 0) {
    kill(self.modeBPid, SIGTERM);
  }
  self.modeBPid = 0;
  self.modeBMachineId = nil;
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
