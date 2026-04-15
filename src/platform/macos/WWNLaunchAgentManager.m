#import "WWNLaunchAgentManager.h"

#import <unistd.h>

static NSString *const kWWNCompositorAgentLabel =
    @"com.aspauldingcode.wawona.compositorhost";
static NSString *const kWWNMenuBarAgentLabel =
    @"com.aspauldingcode.wawona.menubar";
static NSString *const kWWNAppLaunchAgentLabel =
    @"com.aspauldingcode.wawona.applaunch";

@implementation WWNLaunchAgentManager

+ (instancetype)sharedManager {
  static WWNLaunchAgentManager *manager = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    manager = [[self alloc] init];
  });
  return manager;
}

- (NSString *)launchAgentsDirectory {
  NSString *home = NSHomeDirectory();
  return [home stringByAppendingPathComponent:@"Library/LaunchAgents"];
}

- (NSString *)plistPathForLabel:(NSString *)label {
  return [[self launchAgentsDirectory]
      stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", label]];
}

- (NSString *)mainExecutablePath {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *executablePath = bundle.executablePath;
  if (executablePath.length > 0) {
    return executablePath;
  }
  return @"/Applications/Wawona.app/Contents/MacOS/Wawona";
}

- (NSString *)openToolPath {
  if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/open"]) {
    return @"/usr/bin/open";
  }
  return @"/bin/open";
}

- (NSDictionary *)baseEnvironment {
  uid_t uid = getuid();
  NSString *runtimeDir = [NSString stringWithFormat:@"/tmp/wawona-%u", uid];
  return @{
    @"PATH" : @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    @"XDG_RUNTIME_DIR" : runtimeDir,
    @"WAYLAND_DISPLAY" : @"wayland-0",
  };
}

- (NSDictionary *)compositorAgentPlist {
  NSString *execPath = [self mainExecutablePath];
  uid_t uid = getuid();
  return @{
    @"Label" : kWWNCompositorAgentLabel,
    @"ProgramArguments" : @[ execPath, @"--compositor-host" ],
    @"RunAtLoad" : @YES,
    @"KeepAlive" : @YES,
    @"ThrottleInterval" : @5,
    @"StandardOutPath" : [NSString stringWithFormat:@"/tmp/wawona-compositor-%u.log", uid],
    @"StandardErrorPath" : [NSString stringWithFormat:@"/tmp/wawona-compositor-%u.error.log", uid],
    @"EnvironmentVariables" : [self baseEnvironment],
  };
}

- (NSDictionary *)menuBarAgentPlist {
  NSString *execPath = [self mainExecutablePath];
  uid_t uid = getuid();
  return @{
    @"Label" : kWWNMenuBarAgentLabel,
    @"ProgramArguments" : @[ execPath, @"--menubar" ],
    @"RunAtLoad" : @YES,
    @"KeepAlive" : @YES,
    @"ThrottleInterval" : @5,
    @"StandardOutPath" : [NSString stringWithFormat:@"/tmp/wawona-menubar-%u.log", uid],
    @"StandardErrorPath" : [NSString stringWithFormat:@"/tmp/wawona-menubar-%u.error.log", uid],
    @"EnvironmentVariables" : [self baseEnvironment],
  };
}

- (NSDictionary *)appLaunchAgentPlist {
  NSString *bundlePath = NSBundle.mainBundle.bundlePath;
  if (bundlePath.length == 0) {
    bundlePath = @"/Applications/Wawona.app";
  }
  uid_t uid = getuid();
  return @{
    @"Label" : kWWNAppLaunchAgentLabel,
    @"ProgramArguments" : @[ [self openToolPath], @"-a", bundlePath ],
    @"RunAtLoad" : @YES,
    @"KeepAlive" : @NO,
    @"StandardOutPath" : [NSString stringWithFormat:@"/tmp/wawona-applaunch-%u.log", uid],
    @"StandardErrorPath" : [NSString stringWithFormat:@"/tmp/wawona-applaunch-%u.error.log", uid],
    @"EnvironmentVariables" : [self baseEnvironment],
  };
}

- (BOOL)writePlist:(NSDictionary *)plist toPath:(NSString *)path error:(NSError **)error {
  NSString *dir = [path stringByDeletingLastPathComponent];
  if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:error]) {
      return NO;
    }
  }
  BOOL ok = [plist writeToFile:path atomically:YES];
  if (!ok && error) {
    *error = [NSError errorWithDomain:@"com.aspauldingcode.Wawona.LaunchAgent"
                                 code:2
                             userInfo:@{NSLocalizedDescriptionKey : @"Failed to write launch agent plist."}];
  }
  return ok;
}

- (NSString *)launchctlDomain {
  return [NSString stringWithFormat:@"gui/%u", getuid()];
}

- (BOOL)runLaunchctlWithArguments:(NSArray<NSString *> *)arguments {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/launchctl";
  task.arguments = arguments;
  @try {
    [task launch];
    [task waitUntilExit];
    return task.terminationStatus == 0;
  } @catch (__unused NSException *exception) {
    return NO;
  }
}

- (BOOL)bootstrapPlistAtPath:(NSString *)path {
  NSString *domain = [self launchctlDomain];
  // Ignore failures from existing jobs; kickstart handles refresh.
  (void)[self runLaunchctlWithArguments:@[ @"bootout", domain, path ]];
  BOOL ok = [self runLaunchctlWithArguments:@[ @"bootstrap", domain, path ]];
  return ok;
}

- (BOOL)kickstartLabel:(NSString *)label {
  NSString *domain = [self launchctlDomain];
  NSString *target = [NSString stringWithFormat:@"%@/%@", domain, label];
  return [self runLaunchctlWithArguments:@[ @"kickstart", @"-k", target ]];
}

- (BOOL)bootoutLabel:(NSString *)label {
  NSString *domain = [self launchctlDomain];
  NSString *target = [NSString stringWithFormat:@"%@/%@", domain, label];
  return [self runLaunchctlWithArguments:@[ @"bootout", target ]];
}

- (BOOL)isLabelLoaded:(NSString *)label {
  NSString *domain = [self launchctlDomain];
  NSString *target = [NSString stringWithFormat:@"%@/%@", domain, label];
  return [self runLaunchctlWithArguments:@[ @"print", target ]];
}

- (BOOL)installCompositorAndMenuAgents:(NSError **)error {
  NSString *compositorPath = [self plistPathForLabel:kWWNCompositorAgentLabel];
  NSString *menuPath = [self plistPathForLabel:kWWNMenuBarAgentLabel];

  if (![self writePlist:[self compositorAgentPlist] toPath:compositorPath error:error]) {
    return NO;
  }
  if (![self writePlist:[self menuBarAgentPlist] toPath:menuPath error:error]) {
    return NO;
  }

  BOOL compositorOK = [self bootstrapPlistAtPath:compositorPath];
  BOOL menuOK = [self bootstrapPlistAtPath:menuPath];
  BOOL compositorKickstart = [self kickstartLabel:kWWNCompositorAgentLabel];
  BOOL menuKickstart = [self kickstartLabel:kWWNMenuBarAgentLabel];
  return compositorOK && menuOK && compositorKickstart && menuKickstart;
}

- (BOOL)ensureCompositorAndMenuAgents:(NSError **)error {
  (void)error;
  NSString *compositorPath = [self plistPathForLabel:kWWNCompositorAgentLabel];
  NSString *menuPath = [self plistPathForLabel:kWWNMenuBarAgentLabel];
  BOOL missing = ![[NSFileManager defaultManager] fileExistsAtPath:compositorPath] ||
                 ![[NSFileManager defaultManager] fileExistsAtPath:menuPath];
  if (missing) {
    return [self installCompositorAndMenuAgents:error];
  }
  BOOL loadedCompositor = [self isLabelLoaded:kWWNCompositorAgentLabel];
  BOOL loadedMenu = [self isLabelLoaded:kWWNMenuBarAgentLabel];
  if (!loadedCompositor) {
    (void)[self bootstrapPlistAtPath:compositorPath];
  }
  if (!loadedMenu) {
    (void)[self bootstrapPlistAtPath:menuPath];
  }
  (void)[self kickstartLabel:kWWNCompositorAgentLabel];
  (void)[self kickstartLabel:kWWNMenuBarAgentLabel];
  return YES;
}

- (BOOL)restartCompositorAgent {
  return [self kickstartLabel:kWWNCompositorAgentLabel];
}

- (BOOL)stopCompositorAgent {
  return [self bootoutLabel:kWWNCompositorAgentLabel];
}

- (BOOL)startCompositorAgent {
  NSString *compositorPath = [self plistPathForLabel:kWWNCompositorAgentLabel];
  if (![[NSFileManager defaultManager] fileExistsAtPath:compositorPath]) {
    return NO;
  }
  BOOL ok = [self bootstrapPlistAtPath:compositorPath];
  BOOL kicked = [self kickstartLabel:kWWNCompositorAgentLabel];
  return ok && kicked;
}

- (BOOL)isCompositorAgentLoaded {
  return [self isLabelLoaded:kWWNCompositorAgentLabel];
}

- (BOOL)isAppLaunchAgentLoaded {
  return [self isLabelLoaded:kWWNAppLaunchAgentLabel];
}

- (BOOL)enableAppLaunchAtLogin {
  NSString *path = [self plistPathForLabel:kWWNAppLaunchAgentLabel];
  NSError *error = nil;
  if (![self writePlist:[self appLaunchAgentPlist] toPath:path error:&error]) {
    return NO;
  }
  BOOL bootstrapped = [self bootstrapPlistAtPath:path];
  BOOL started = [self kickstartLabel:kWWNAppLaunchAgentLabel];
  return bootstrapped && started;
}

- (BOOL)disableAppLaunchAtLogin {
  NSString *path = [self plistPathForLabel:kWWNAppLaunchAgentLabel];
  BOOL stopped = [self bootoutLabel:kWWNAppLaunchAgentLabel];
  NSError *error = nil;
  [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
  (void)error;
  return stopped;
}

@end
