#import "WWNWaypipeRunner.h"
#import "../../util/WWNLog.h"
#import <dispatch/dispatch.h>
#import <unistd.h>

extern int weston_simple_shm_main(int argc, char **argv);

@interface WWNWaypipeRunner ()
@property(nonatomic, readwrite) BOOL isRunning;
@property(nonatomic, readwrite) BOOL isWestonSimpleSHMRunning;
@property(nonatomic, readwrite) BOOL westonRunning;
@property(nonatomic, readwrite) BOOL westonTerminalRunning;
@property(nonatomic, readwrite) BOOL footRunning;
@end

@implementation WWNWaypipeRunner

+ (instancetype)sharedRunner {
  static WWNWaypipeRunner *runner;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runner = [[WWNWaypipeRunner alloc] init];
  });
  return runner;
}

- (NSString *)findWaypipeBinary {
  return nil;
}

- (NSArray<NSString *> *)buildWaypipeArguments:(WWNPreferencesManager *)prefs {
  (void)prefs;
  return @[];
}

- (NSString *)generateWaypipePreviewString:(WWNPreferencesManager *)prefs {
  (void)prefs;
  return @"Waypipe is unavailable on visionOS.";
}

- (NSString *)validatePreflightForPrefs:(WWNPreferencesManager *)prefs {
  (void)prefs;
  return @"Waypipe launcher is unavailable on visionOS.";
}

- (void)launchWaypipe:(WWNPreferencesManager *)prefs {
  (void)prefs;
  [self.delegate runnerDidReceiveSSHError:@"Waypipe launcher is unavailable on visionOS."];
}

- (void)stopWaypipe {
  self.isRunning = NO;
}

- (void)launchWestonSimpleSHM {
  if (self.isWestonSimpleSHMRunning) {
    return;
  }

  self.isWestonSimpleSHMRunning = YES;

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    void *fnAddr = (void *)weston_simple_shm_main;
    if (fnAddr == NULL) {
      WWNLog("WESTON_SHM", @"FATAL: weston_simple_shm_main symbol is NULL!");
      self.isWestonSimpleSHMRunning = NO;
      [self.delegate runnerDidReceiveSSHError:@"weston-simple-shm is not linked for visionOS."];
      return;
    }

    char *argvShm[] = {"weston-simple-shm", NULL};
    int argcShm = 1;

    char savedCwd[512] = "";
    const char *xdgDir = getenv("XDG_RUNTIME_DIR");
    if (xdgDir != NULL) {
      getcwd(savedCwd, sizeof(savedCwd));
      chdir(xdgDir);
    }

    WWNLog("WESTON_SHM", @"Launching in-process weston-simple-shm...");
    int result = weston_simple_shm_main(argcShm, argvShm);
    WWNLog("WESTON_SHM", @"weston_simple_shm_main exit code: %d", result);

    if (savedCwd[0] != '\0') {
      chdir(savedCwd);
    }

    self.isWestonSimpleSHMRunning = NO;
  });
}

- (void)stopWestonSimpleSHM {
  self.isWestonSimpleSHMRunning = NO;
}

- (void)launchWeston {
  [self.delegate runnerDidReceiveSSHError:@"weston is unavailable on visionOS."];
}

- (void)stopWeston {
  self.westonRunning = NO;
}

- (void)launchWestonTerminal {
  [self.delegate runnerDidReceiveSSHError:@"weston-terminal is unavailable on visionOS."];
}

- (void)stopWestonTerminal {
  self.westonTerminalRunning = NO;
}

- (void)launchFoot {
  [self.delegate runnerDidReceiveSSHError:@"foot is unavailable on visionOS."];
}

- (void)stopFoot {
  self.footRunning = NO;
}

@end

