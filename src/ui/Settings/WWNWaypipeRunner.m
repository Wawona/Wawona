#import "WWNWaypipeRunner.h"
#import "../../util/WWNLog.h"
#import "WWNSSHClient.h"
#import <errno.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

// Global for signal handler safety
volatile pid_t g_active_waypipe_pgid = 0;

// Internal waypipe entry point (statically linked from Rust)
extern int waypipe_main(int argc, char **argv);
extern int weston_simple_shm_main(int argc, char **argv);
extern int weston_main(int argc, char **argv);
extern int weston_terminal_main(int argc, char **argv);

@interface WWNWaypipeRunner () <WWNSSHClientDelegate>
@property(nonatomic, assign) pid_t currentPid;
#if !TARGET_OS_IPHONE
@property(nonatomic, strong) NSTask *currentTask;
#endif
@property(nonatomic, strong) WWNSSHClient *sshClient;
@property(nonatomic, assign) BOOL running;
@property(nonatomic, assign) BOOL stopping;

@property(nonatomic, assign) BOOL westonSimpleSHMRunning;
@property(nonatomic, assign) BOOL westonRunning;
@property(nonatomic, assign) BOOL westonTerminalRunning;
#if !TARGET_OS_IPHONE
@property(nonatomic, strong) NSTask *westonSimpleSHMTask;
@property(nonatomic, strong) NSTask *westonTask;
@property(nonatomic, strong) NSTask *westonTerminalTask;
#endif
#if TARGET_OS_IPHONE
@property(nonatomic, assign)
    int stderrReadFd; // Pipe read end for stderr capture
@property(nonatomic, assign)
    int stdoutReadFd; // Pipe read end for stdout capture
@property(nonatomic, assign) int savedStderr; // Saved original stderr fd
@property(nonatomic, assign) int savedStdout; // Saved original stdout fd
@property(nonatomic, strong) NSLock *fdLock;  // Protects fd close/access
#endif
@end

@implementation WWNWaypipeRunner

+ (instancetype)sharedRunner {
  static WWNWaypipeRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _running = NO;
    _stopping = NO;
#if TARGET_OS_IPHONE
    _stderrReadFd = -1;
    _stdoutReadFd = -1;
    _savedStderr = -1;
    _savedStdout = -1;
    _fdLock = [[NSLock alloc] init];
#endif
  }
  return self;
}

- (BOOL)isRunning {
  return self.running;
}

- (BOOL)isWestonSimpleSHMRunning {
  return self.westonSimpleSHMRunning;
}

#if TARGET_OS_IPHONE
/// Thread-safe cleanup of all redirected file descriptors.
/// Uses fdLock to ensure only one caller (completion block or stopWaypipe)
/// can close the fds, preventing double-close crashes.
- (void)cleanupFileDescriptors {
  [self.fdLock lock];

  if (self.savedStderr >= 0) {
    dup2(self.savedStderr, STDERR_FILENO);
    close(self.savedStderr);
    self.savedStderr = -1;
  }
  if (self.savedStdout >= 0) {
    dup2(self.savedStdout, STDOUT_FILENO);
    close(self.savedStdout);
    self.savedStdout = -1;
  }
  if (self.stderrReadFd >= 0) {
    close(self.stderrReadFd);
    self.stderrReadFd = -1;
  }
  if (self.stdoutReadFd >= 0) {
    close(self.stdoutReadFd);
    self.stdoutReadFd = -1;
  }

  [self.fdLock unlock];
}
#endif

// MARK: - Binary Discovery

- (NSString *)findWaypipeBinary {
  // Resolve symlinks because Nix often launches via a symlink in bin/
  NSString *realExecPath =
      [[NSBundle mainBundle].executablePath stringByResolvingSymlinksInPath];
  NSString *execDir = [realExecPath stringByDeletingLastPathComponent];
  NSString *path = [execDir stringByAppendingPathComponent:@"waypipe"];

  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }

  // Also check Resources/bin/waypipe as user requested resource-based bundling
  NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"waypipe"
                                                           ofType:nil
                                                      inDirectory:@"bin"];
  if (resourcePath &&
      [[NSFileManager defaultManager] isExecutableFileAtPath:resourcePath]) {
    return resourcePath;
  }

#if TARGET_OS_IPHONE
  // On iOS check bundle root
  NSString *bundlePath =
      [[NSBundle mainBundle].bundlePath stringByResolvingSymlinksInPath];
  path = [bundlePath stringByAppendingPathComponent:@"waypipe"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }
#endif

  return nil;
}

- (NSString *)findWestonSimpleSHMBinary {
  // Resolve symlinks because Nix often launches via a symlink in bin/
  NSString *realExecPath =
      [[NSBundle mainBundle].executablePath stringByResolvingSymlinksInPath];
  NSString *execDir = [realExecPath stringByDeletingLastPathComponent];
  NSString *path =
      [execDir stringByAppendingPathComponent:@"weston-simple-shm"];

  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }

  // Also check Resources/bin/weston-simple-shm as bundled by Nix macos.nix
  NSString *resourcePath =
      [[NSBundle mainBundle] pathForResource:@"weston-simple-shm"
                                      ofType:nil
                                 inDirectory:@"bin"];
  if (resourcePath &&
      [[NSFileManager defaultManager] isExecutableFileAtPath:resourcePath]) {
    return resourcePath;
  }

#if TARGET_OS_IPHONE
  // On iOS check bundle root
  NSString *bundlePath =
      [[NSBundle mainBundle].bundlePath stringByResolvingSymlinksInPath];
  path = [bundlePath stringByAppendingPathComponent:@"weston-simple-shm"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }
#endif

  return nil;
}

- (NSString *)findSshpassBinary {
  NSString *realExecPath =
      [[NSBundle mainBundle].executablePath stringByResolvingSymlinksInPath];
  NSString *execDir = [realExecPath stringByDeletingLastPathComponent];
  NSString *path = [execDir stringByAppendingPathComponent:@"sshpass"];

  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }

#if TARGET_OS_IPHONE
  NSString *bundlePath =
      [[NSBundle mainBundle].bundlePath stringByResolvingSymlinksInPath];
  path = [bundlePath stringByAppendingPathComponent:@"sshpass"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }
#endif

  return nil;
}

// MARK: - Argument Building

- (NSArray<NSString *> *)buildWaypipeArguments:(WWNPreferencesManager *)prefs {
  NSMutableArray *args = [NSMutableArray array];
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];

  NSString * (^trimmed)(NSString *) = ^NSString *(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
      return @"";
    }
    return [value stringByTrimmingCharactersInSet:ws];
  };

  BOOL (^isNonEmpty)(NSString *) = ^BOOL(NSString *value) {
    return trimmed(value).length > 0;
  };

  NSInteger (^intValueOrDefault)(NSString *, NSInteger) =
      ^NSInteger(NSString *value, NSInteger fallback) {
        NSString *clean = trimmed(value);
        return clean.length > 0 ? clean.integerValue : fallback;
      };

  // SSH Destination
  NSString *sshTarget = nil;
  NSString *targetHost =
      prefs.waypipeSSHHost.length > 0 ? prefs.waypipeSSHHost : prefs.sshHost;
  NSString *targetUser =
      prefs.waypipeSSHUser.length > 0 ? prefs.waypipeSSHUser : prefs.sshUser;
  BOOL usingSSHMode = (prefs.waypipeSSHEnabled && targetHost.length > 0);

  // 1. Waypipe Global Options (MUST come before 'ssh')
  NSString *compress = [[trimmed(prefs.waypipeCompress) lowercaseString] copy];
  if (compress.length == 0) {
    compress = @"lz4";
  }
  NSString *compressLevel = trimmed(prefs.waypipeCompressLevel);
  NSString *compressArg = compress;
  if (compressLevel.length > 0 && ![compress isEqualToString:@"none"]) {
    compressArg = [NSString stringWithFormat:@"%@=%@", compress, compressLevel];
  }
  BOOL shouldAddCompress = (compressArg.length > 0);
#if TARGET_OS_IPHONE
  // iOS libssh2 SSH path currently brings up remote waypipe server with default
  // compression. Forcing local "--compress none" causes header mismatch.
  if (usingSSHMode && [compress isEqualToString:@"none"]) {
    shouldAddCompress = NO;
  }
#endif
  if (shouldAddCompress) {
    [args addObject:@"--compress"];
    [args addObject:compressArg];
  }

  if (prefs.waypipeDebug) {
    [args addObject:@"--debug"];
  }
  if (prefs.waypipeNoGpu) {
    [args addObject:@"--no-gpu"];
  }
#if TARGET_OS_IPHONE
  // iOS App Store compliance: ALWAYS force --oneshot in SSH mode.
  // The static libssh2 code path (oneshot) handles SSH in-process;
  // without it waypipe tries to exec an external "ssh" binary which
  // is forbidden on iOS.  The user toggle still works for non-SSH
  // (local) usage.
  if (prefs.waypipeOneshot || usingSSHMode) {
    [args addObject:@"--oneshot"];
  }
#else
  if (prefs.waypipeOneshot) {
    [args addObject:@"--oneshot"];
  }
#endif
  if (prefs.waypipeUnlinkSocket) {
    [args addObject:@"--unlink-socket"];
  }
  if (prefs.waypipeLoginShell) {
    [args addObject:@"--login-shell"];
  }
  if (prefs.waypipeVsock) {
    [args addObject:@"--vsock"];
  }
  if (prefs.waypipeXwls) {
    [args addObject:@"--xwls"];
  }

  NSInteger threadCount = intValueOrDefault(prefs.waypipeThreads, 0);
  if (threadCount >= 0) {
    [args addObject:@"--threads"];
    [args addObject:[NSString stringWithFormat:@"%ld", (long)threadCount]];
  }

  NSString *titlePrefix = trimmed(prefs.waypipeTitlePrefix);
  if (titlePrefix.length > 0) {
    [args addObject:@"--title-prefix"];
    [args addObject:titlePrefix];
  }

  NSString *secCtx = trimmed(prefs.waypipeSecCtx);
  if (secCtx.length > 0) {
    [args addObject:@"--secctx"];
    [args addObject:secCtx];
  }

  NSString *videoCodec = [[trimmed(prefs.waypipeVideo) lowercaseString] copy];
  if (videoCodec.length == 0) {
    videoCodec = @"none";
  }
  NSMutableArray<NSString *> *videoParts = [NSMutableArray array];
  [videoParts addObject:videoCodec];
  if (![videoCodec isEqualToString:@"none"]) {
    NSString *enc =
        [[trimmed(prefs.waypipeVideoEncoding) lowercaseString] copy];
    NSString *dec =
        [[trimmed(prefs.waypipeVideoDecoding) lowercaseString] copy];
    if (enc.length > 0) {
      [videoParts addObject:enc];
    }
    if (dec.length > 0) {
      [videoParts addObject:dec];
    }

    NSString *bpf = trimmed(prefs.waypipeVideoBpf);
    if (bpf.length > 0 && bpf.doubleValue > 0) {
      [videoParts addObject:[NSString stringWithFormat:@"bpf=%@", bpf]];
    }
  }
  if (videoParts.count > 0) {
    [args addObject:@"--video"];
    [args addObject:[videoParts componentsJoinedByString:@","]];
  }

#if !TARGET_OS_IPHONE
  NSString *sshBinary = trimmed(prefs.waypipeSSHBinary);
  if (sshBinary.length > 0 && ![sshBinary isEqualToString:@"ssh"]) {
    [args addObject:@"--ssh-bin"];
    [args addObject:sshBinary];
  }
#endif

#if TARGET_OS_IPHONE
  // iOS sandbox paths are very long (~85 chars for XDG_RUNTIME_DIR).
  // waypipe appends random suffixes to the socket prefix, easily exceeding
  // the Unix socket SUN_LEN limit of 104 bytes.
  // Use a compact path for the socket prefix.
  if (!prefs.waypipeVsock) {
#if TARGET_OS_SIMULATOR
    NSString *tmpDir = @"/tmp";
#else
    NSString *tmpDir = NSTemporaryDirectory();
    if (!tmpDir)
      tmpDir = @"/tmp";
#endif
    NSString *socketPrefix = [tmpDir stringByAppendingPathComponent:@"wp"];
    [args addObject:@"-s"];
    [args addObject:socketPrefix];
  }

#endif

  // In ssh mode, forcing --display to "wayland-0" makes the remote
  // waypipe-server try to bind an existing compositor socket and fail
  // with EADDRINUSE. Let waypipe choose its remote display by default.
  if (!usingSSHMode) {
    NSString *display = trimmed(prefs.waypipeDisplay);
    if (display.length > 0) {
      [args addObject:@"--display"];
      [args addObject:display];
    }
  }

  if (usingSSHMode) {
    // 2. SSH Subcommand (Only if we have a target)
    [args addObject:@"ssh"];

#if !TARGET_OS_IPHONE
    // iOS uses libssh2 in-process (not openssh), so -F is meaningless and
    // can confuse the SSH argument parser in the libssh2 bridge code.
    if (!prefs.waypipeUseSSHConfig) {
      [args addObject:@"-F"];
      [args addObject:@"/dev/null"];
    }
#endif

    // SSH Safety options
    [args addObject:@"-o"];
    [args addObject:@"StrictHostKeyChecking=accept-new"];
    [args addObject:@"-o"];
    [args addObject:@"BatchMode=no"];

    if (prefs.waypipeSSHAuthMethod == 1 &&
        isNonEmpty(prefs.waypipeSSHKeyPath)) {
      [args addObject:@"-i"];
      [args addObject:trimmed(prefs.waypipeSSHKeyPath)];
    }

    if (targetUser.length > 0) {
      sshTarget = [NSString stringWithFormat:@"%@@%@", targetUser, targetHost];
    } else {
      sshTarget = targetHost;
    }
    [args addObject:sshTarget];
  }

  // 3. Remote command for ssh mode
  NSString *remoteCommand = trimmed(prefs.waypipeRemoteCommand);
  if (prefs.waypipeLoginShell && remoteCommand.length == 0) {
    // waypipe server will open a login shell when no command is provided
    // and --login-shell is set.
    return args;
  }
  if (remoteCommand.length > 0) {
    [args addObject:[NSString stringWithFormat:@"\"%@\"", remoteCommand]];
  } else if (prefs.waypipeSSHEnabled) {
    [args addObject:@"\"weston-terminal\""]; // Default remote command
  }

  return args;
}

- (NSString *)generateWaypipePreviewString:(WWNPreferencesManager *)prefs {
  NSString *bin = [self findWaypipeBinary] ?: @"waypipe";
  NSArray *args = [self buildWaypipeArguments:prefs];

  NSString *cmd = [NSString
      stringWithFormat:@"%@ %@", bin, [args componentsJoinedByString:@" "]];

  NSString *targetPass = prefs.waypipeSSHPassword.length > 0
                             ? prefs.waypipeSSHPassword
                             : prefs.sshPassword;

  if (prefs.waypipeSSHAuthMethod == 0 && targetPass.length > 0) {
    NSString *sshpass = [self findSshpassBinary];
    if (sshpass) {
      cmd = [NSString stringWithFormat:@"SSHPASS=**** %@ -e %@",
                                       [sshpass lastPathComponent], cmd];
    }
  }

  return cmd;
}

// MARK: - Pre-flight Validation

- (NSString *)validatePreflightForPrefs:(WWNPreferencesManager *)prefs {
  // 1. Check if already running
  if (self.running) {
    return @"Waypipe is already running. Stop it first.";
  }

  // 2. Check Wayland socket exists
  NSString *display = prefs.waypipeDisplay;
  if (!display || display.length == 0) {
    const char *envDisplay = getenv("WAYLAND_DISPLAY");
    if (envDisplay) {
      display = [NSString stringWithUTF8String:envDisplay];
    } else {
      display = @"wayland-0";
    }
  }

#if TARGET_OS_IPHONE
  NSString *socketDir = prefs.waylandSocketDir;
  if (!socketDir || socketDir.length == 0) {
    const char *envDir = getenv("XDG_RUNTIME_DIR");
    if (envDir) {
      socketDir = [NSString stringWithUTF8String:envDir];
    }
  }
  if (!socketDir || socketDir.length == 0) {
    return @"XDG_RUNTIME_DIR is not set. The compositor may not be running.";
  }

  NSString *socketPath = [socketDir stringByAppendingPathComponent:display];
  if (![[NSFileManager defaultManager] fileExistsAtPath:socketPath]) {
    return [NSString
        stringWithFormat:
            @"Wayland socket not found at: %@\n\nThe compositor may not be "
            @"running, or the display name is incorrect.",
            socketPath];
  }
#else
  NSMutableArray<NSString *> *candidateDirs = [NSMutableArray array];
  const char *envDir = getenv("XDG_RUNTIME_DIR");
  if (envDir) {
    [candidateDirs addObject:[NSString stringWithUTF8String:envDir]];
  }
  if (prefs.waylandSocketDir.length > 0) {
    [candidateDirs addObject:prefs.waylandSocketDir];
  }
  [candidateDirs
      addObject:[NSString stringWithFormat:@"/tmp/wawona-%d", getuid()]];

  NSMutableOrderedSet<NSString *> *uniqueDirs =
      [NSMutableOrderedSet orderedSetWithArray:candidateDirs];
  BOOL socketFound = NO;
  NSString *firstChecked = nil;

  for (NSString *dir in uniqueDirs) {
    if (dir.length == 0) {
      continue;
    }
    NSString *candidatePath = [dir stringByAppendingPathComponent:display];
    if (!firstChecked) {
      firstChecked = candidatePath;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidatePath]) {
      socketFound = YES;
      break;
    }
  }

  if (!socketFound) {
    NSString *fallbackPath =
        firstChecked ?: [@"/tmp" stringByAppendingPathComponent:display];
    return [NSString
        stringWithFormat:
            @"Wayland socket not found at: %@\n\nThe compositor may not be "
            @"running, or the display name is incorrect.",
            fallbackPath];
  }
#endif

  // 3. Check SSH settings are configured (when SSH is enabled)
  if (prefs.waypipeSSHEnabled) {
    NSString *targetHost =
        prefs.waypipeSSHHost.length > 0 ? prefs.waypipeSSHHost : prefs.sshHost;
    if (!targetHost || targetHost.length == 0) {
      return @"SSH host is not configured. Set it in the SSH section or "
             @"Waypipe SSH settings.";
    }

    NSString *targetPass = prefs.waypipeSSHPassword.length > 0
                               ? prefs.waypipeSSHPassword
                               : prefs.sshPassword;
    NSInteger authMethod = prefs.waypipeSSHAuthMethod;
    if (authMethod == 0 && (!targetPass || targetPass.length == 0)) {
      return @"SSH password is not configured. Set it in SSH settings or "
             @"Waypipe SSH password field.\n\nWaypipe on iOS uses libssh2 "
             @"and requires a password for authentication.";
    }
  }

  return nil; // All checks passed
}

// MARK: - Launch

- (void)launchWaypipe:(WWNPreferencesManager *)prefs {
#if !TARGET_OS_IPHONE
  NSString *waypipePath = [self findWaypipeBinary];
  if (!waypipePath) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              @"Waypipe binary not found. Please ensure it is installed."];
    }
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:@"Error: Waypipe binary not found.\n"
                         isError:YES];
    }
    return;
  }

  WWNLog("WAYPIPE", @"Using waypipe binary at: %@", waypipePath);
#endif

#if TARGET_OS_IPHONE && TARGET_OS_SIMULATOR
  WWNLog("WAYPIPE", @"NOTE: Running on iOS Simulator. Local networking may be "
                    @"restricted.");
#endif

  // Pre-flight validation
  NSString *preflightError = [self validatePreflightForPrefs:prefs];
  if (preflightError) {
    WWNLog("WAYPIPE", @"Pre-flight check failed: %@", preflightError);
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:[NSString
                                     stringWithFormat:@"[PRE-FLIGHT] %@\n",
                                                      preflightError]
                         isError:YES];
    }
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate runnerDidReceiveSSHError:preflightError];
    }
    return;
  }

#if TARGET_OS_IPHONE
  [self launchWaypipeInProcess:prefs];
  return;
#else
  // macOS NSTask Implementation
  NSArray *args = [self buildWaypipeArguments:prefs];
  NSTask *task = [[NSTask alloc] init];

  NSString *targetPass = prefs.waypipeSSHPassword.length > 0
                             ? prefs.waypipeSSHPassword
                             : prefs.sshPassword;
  BOOL useSshpass = (prefs.waypipeSSHAuthMethod == 0 && targetPass.length > 0);
  NSString *sshpassPath = useSshpass ? [self findSshpassBinary] : nil;
  NSString *askpassScriptPath = nil;

  if (sshpassPath) {
    task.executableURL = [NSURL fileURLWithPath:sshpassPath];
    NSMutableArray *sshpassArgs = [NSMutableArray arrayWithObject:@"-e"];
    [sshpassArgs addObject:waypipePath];
    [sshpassArgs addObjectsFromArray:args];
    task.arguments = sshpassArgs;
  } else {
    task.executableURL = [NSURL fileURLWithPath:waypipePath];
    task.arguments = args;
  }

  // Env
  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];

  // Waypipe needs to know where the socket IS, and it needs to be an absolute
  // path. We prioritize the environment because main.m sets it correctly.
  const char *envRuntime = getenv("XDG_RUNTIME_DIR");
  NSString *socketDirTask =
      (envRuntime) ? [NSString stringWithUTF8String:envRuntime] : nil;

  if (!socketDirTask || socketDirTask.length == 0) {
    socketDirTask = prefs.waylandSocketDir;
  }

  if (!socketDirTask || socketDirTask.length == 0) {
    socketDirTask = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
    WWNLog("WAYPIPE", @"waylandSocketDir was empty, using default: %@",
           socketDirTask);
  }

  const char *envDisplay = getenv("WAYLAND_DISPLAY");
  NSString *displayNameTask =
      (envDisplay) ? [NSString stringWithUTF8String:envDisplay] : nil;

  if (!displayNameTask || displayNameTask.length == 0) {
    displayNameTask = prefs.waypipeDisplay;
  }

  if (!displayNameTask || displayNameTask.length == 0) {
    displayNameTask = @"wayland-0";
    WWNLog("WAYPIPE", @"waypipeDisplay was empty, using default: %@",
           displayNameTask);
  }

#if !TARGET_OS_IPHONE
  NSString *configuredSocketPath =
      [socketDirTask stringByAppendingPathComponent:displayNameTask];
  if (![[NSFileManager defaultManager] fileExistsAtPath:configuredSocketPath]) {
    NSString *runtimeFallback =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
    NSString *fallbackSocketPath =
        [runtimeFallback stringByAppendingPathComponent:displayNameTask];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fallbackSocketPath]) {
      WWNLog("WAYPIPE", @"Using compositor runtime fallback: %@",
             runtimeFallback);
      socketDirTask = runtimeFallback;
    }
  }
#endif

  WWNLog("WAYPIPE",
         @"Setting environment: XDG_RUNTIME_DIR=%@, "
         @"WAYLAND_DISPLAY=%@, XDG_CURRENT_DESKTOP=Wawona",
         socketDirTask, displayNameTask);

  env[@"XDG_RUNTIME_DIR"] = socketDirTask;
  env[@"WAYLAND_DISPLAY"] = displayNameTask;
  env[@"XDG_CURRENT_DESKTOP"] = @"Wawona";
  env[@"WAWONA_DESKTOP"] = @"Wawona";

  // Sanitize PATH to ensure /usr/bin is available for ssh
  NSString *currentPath = env[@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
  if (![currentPath containsString:@"/usr/bin"]) {
    currentPath = [@"/usr/bin:" stringByAppendingString:currentPath];
  }
  env[@"PATH"] = currentPath;

  if (useSshpass) {
    env[@"SSHPASS"] = targetPass;
  } else if (prefs.waypipeSSHAuthMethod == 0 && targetPass.length > 0) {
    // Password auth fallback without sshpass: force SSH_ASKPASS so ssh does
    // not require /dev/tty (non-interactive app launch context).
    NSString *scriptName =
        [NSString stringWithFormat:@"wawona-waypipe-askpass-%@.sh",
                                   [[NSUUID UUID] UUIDString]];
    askpassScriptPath =
        [NSTemporaryDirectory() stringByAppendingPathComponent:scriptName];
    NSString *script = @"#!/bin/sh\n"
                        "printf '%s\\n' \"$WAWONA_SSH_PASSWORD\"\n";
    NSError *scriptError = nil;
    BOOL wrote = [script writeToFile:askpassScriptPath
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&scriptError];
    if (wrote &&
        chmod([askpassScriptPath fileSystemRepresentation], 0700) == 0) {
      env[@"SSH_ASKPASS"] = askpassScriptPath;
      env[@"SSH_ASKPASS_REQUIRE"] = @"force";
      env[@"DISPLAY"] = env[@"DISPLAY"] ?: @"wawona-waypipe";
      env[@"WAWONA_SSH_PASSWORD"] = targetPass;
      WWNLog("WAYPIPE", @"Using temporary SSH_ASKPASS helper");
    } else {
      WWNLog("WAYPIPE", @"Failed to create SSH_ASKPASS helper: %@",
             scriptError.localizedDescription ?: @"unknown error");
      askpassScriptPath = nil;
    }
  }

  task.environment = env;
  if (askpassScriptPath.length > 0) {
    task.terminationHandler = ^(NSTask *finishedTask) {
      (void)finishedTask;
      [[NSFileManager defaultManager] removeItemAtPath:askpassScriptPath
                                                 error:nil];
    };
  }

  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  task.standardOutput = outPipe;
  task.standardError = errPipe;

  self.running = YES;

  outPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    if (d.length > 0) {
      NSString *s =
          [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
      [self parseOutput:s isError:NO];
    }
  };
  errPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    if (d.length > 0) {
      NSString *s =
          [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
      [self parseOutput:s isError:YES];
    }
  };

  NSError *err;
  if ([task launchAndReturnError:&err]) {
    self.currentPid = task.processIdentifier;
    self.currentTask = task;
    g_active_waypipe_pgid = self.currentPid;
    WWNLog("WAYPIPE", @"Waypipe launched via NSTask PID: %d", self.currentPid);
  } else {
    self.running = NO;
    if (askpassScriptPath.length > 0) {
      [[NSFileManager defaultManager] removeItemAtPath:askpassScriptPath
                                                 error:nil];
    }
    WWNLog("WAYPIPE", @"Launch failed: %@", err);
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:
              [NSString stringWithFormat:@"Failed to launch waypipe: %@\n",
                                         err.localizedDescription]
                         isError:YES];
    }
  }
#endif
}

// MARK: - Output Monitoring

- (void)monitorDescriptor:(int)fd isError:(BOOL)isError {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 ^{
                   char buffer[4096];
                   ssize_t count;
                   while ((count = read(fd, buffer, sizeof(buffer) - 1)) > 0) {
                     buffer[count] = 0;
                     NSString *s = [NSString stringWithUTF8String:buffer];
                     dispatch_async(dispatch_get_main_queue(), ^{
                       [self parseOutput:s isError:isError];
                     });
                   }
                   // Do NOT close(fd) here. The fd is owned by the launch/stop
                   // code paths which handle closing. Closing here races with
                   // the completion block and stopWaypipe, causing double-close
                   // crashes (EXC_BAD_ACCESS / EBADF).
                 });
}

- (void)parseOutput:(NSString *)text isError:(BOOL)isError {
  if (self.stopping)
    return;

  // Write to the saved (original) stderr to avoid feedback loop.
  // When stderr is redirected to a pipe, NSLog may write to the pipe
  // which causes the monitor thread to read it back, creating an infinite loop.
#if TARGET_OS_IPHONE
  [self.fdLock lock];
  int fd = self.savedStderr;
  [self.fdLock unlock];
  if (fd >= 0) {
    WWNLogFd(fd, "WAYPIPE", "[Waypipe %s] %s", isError ? "stderr" : "stdout",
             [text UTF8String]);
  } else {
    WWNLog("WAYPIPE", @"[Waypipe %@] %@", isError ? @"stderr" : @"stdout",
           text);
  }
#else
  WWNLog("WAYPIPE", @"[Waypipe %@] %@", isError ? @"stderr" : @"stdout", text);
#endif

  if ([self.delegate
          respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
    [self.delegate runnerDidReceiveOutput:text isError:isError];
  }

  if ([text containsString:@"password:"] ||
      [text containsString:@"Password:"]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHPasswordPrompt:)]) {
      [self.delegate runnerDidReceiveSSHPasswordPrompt:text];
    }
  } else if ([text containsString:@"Permission denied"] ||
             [text containsString:@"Host key verification failed"]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate runnerDidReceiveSSHError:text];
    }
  } else if ([text containsString:@"Password auth failed"] ||
             [text containsString:@"SSH auth failed"] ||
             [text containsString:@"libssh2 failed"]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate runnerDidReceiveSSHError:text];
    }
  }
}

// MARK: - iOS In-Process Launch

#if TARGET_OS_IPHONE
- (void)launchWaypipeInProcess:(WWNPreferencesManager *)prefs {
  // Build arguments
  NSArray *args = [self buildWaypipeArguments:prefs];

  // App Store compliance / iOS sandbox safety:
  // Never allow paths that require spawning a local external ssh binary.
  BOOL hasSshBinOverride = [args containsObject:@"--ssh-bin"];
  if (hasSshBinOverride) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:
              @"[SAFETY] Blocked launch: iOS forbids external process exec. "
              @"--ssh-bin is not allowed in iOS mode.\n"
                         isError:YES];
    }
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              @"Blocked unsafe iOS launch mode (external process execution)."];
    }
    self.running = NO;
    return;
  }

  NSMutableArray *fullArgs = [NSMutableArray arrayWithObject:@"waypipe"];
  [fullArgs addObjectsFromArray:args];

  // Convert to C arguments
  int argc = (int)fullArgs.count;
  char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
  for (int i = 0; i < argc; i++) {
    argv[i] = strdup([fullArgs[i] UTF8String]);
  }
  argv[argc] = NULL;

  // Resolve environment variables
  NSString *socketDir = prefs.waylandSocketDir;
  if (!socketDir || socketDir.length == 0) {
    const char *envDir = getenv("XDG_RUNTIME_DIR");
    if (envDir) {
      socketDir = [NSString stringWithUTF8String:envDir];
    } else {
      socketDir = NSTemporaryDirectory();
    }
  }

  NSString *display = prefs.waypipeDisplay;
  if (!display || display.length == 0) {
    const char *envDisplay = getenv("WAYLAND_DISPLAY");
    if (envDisplay) {
      display = [NSString stringWithUTF8String:envDisplay];
    } else {
      display = @"wayland-0";
    }
  }

  setenv("XDG_RUNTIME_DIR", [socketDir UTF8String], 1);
  setenv("WAYLAND_DISPLAY", [display UTF8String], 1);
  setenv("USER", "mobile", 1);

  NSString *password = prefs.waypipeSSHPassword.length > 0
                           ? prefs.waypipeSSHPassword
                           : prefs.sshPassword;
  if (password && password.length > 0) {
    setenv("WAYPIPE_SSH_PASSWORD", [password UTF8String], 1);
  }

  // Report configuration to delegate
  NSString *socketPath = [socketDir stringByAppendingPathComponent:display];
  NSString *configInfo = [NSString
      stringWithFormat:@"[CONFIG] XDG_RUNTIME_DIR = %@\n"
                       @"[CONFIG] WAYLAND_DISPLAY = %@\n"
                       @"[CONFIG] Socket path    = %@\n"
                       @"[CONFIG] SSH password   = %@\n"
                       @"[CONFIG] Arguments      = %@\n",
                       socketDir, display, socketPath,
                       (password.length > 0 ? @"(set)" : @"(not set)"),
                       [fullArgs componentsJoinedByString:@" "]];

  if ([self.delegate
          respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
    [self.delegate runnerDidReceiveOutput:configInfo isError:NO];
  }

  WWNLog("WAYPIPE", @"Launching statically linked Waypipe (args: %@)...",
         fullArgs);

  self.running = YES;
  self.stopping = NO;

  // Set up stderr/stdout capture BEFORE calling waypipe_main.
  // We redirect stderr/stdout to pipes so we can read the Rust output
  // and show it in the UI. We also save the original FDs so crash
  // diagnostics and our own logging still work.
  int stderrPipe[2] = {-1, -1};
  int stdoutPipe[2] = {-1, -1};

  if (pipe(stderrPipe) != 0) {
    WWNLog("WAYPIPE", @"WARNING: Failed to create stderr pipe: %s",
           strerror(errno));
  }
  if (pipe(stdoutPipe) != 0) {
    WWNLog("WAYPIPE", @"WARNING: Failed to create stdout pipe: %s",
           strerror(errno));
  }

  // Save original file descriptors so we can log to them directly
  int savedStderr = dup(STDERR_FILENO);
  int savedStdout = dup(STDOUT_FILENO);
  self.savedStderr = savedStderr;
  self.savedStdout = savedStdout;

  // Redirect stderr and stdout to our pipes
  if (stderrPipe[1] >= 0) {
    dup2(stderrPipe[1], STDERR_FILENO);
    close(stderrPipe[1]); // Close write end (stderr now writes to pipe)
    self.stderrReadFd = stderrPipe[0];
  }
  if (stdoutPipe[1] >= 0) {
    dup2(stdoutPipe[1], STDOUT_FILENO);
    close(stdoutPipe[1]); // Close write end (stdout now writes to pipe)
    self.stdoutReadFd = stdoutPipe[0];
  }

  // Start monitoring threads for the pipe read ends
  if (self.stderrReadFd >= 0) {
    [self monitorDescriptor:self.stderrReadFd isError:YES];
  }
  if (self.stdoutReadFd >= 0) {
    [self monitorDescriptor:self.stdoutReadFd isError:NO];
  }

  if ([self.delegate
          respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
    [self.delegate
        runnerDidReceiveOutput:@"[LAUNCH] Starting waypipe_main()...\n"
                       isError:NO];
  }

  // Run waypipe_main on a Utility-QoS background thread.
  // Using QOS_CLASS_UTILITY (not DEFAULT) avoids a priority inversion:
  // the UI thread dispatches at User-initiated QoS, waypipe's internal
  // Rust scoped threads run at Default QoS.  If we dispatched to DEFAULT,
  // GCD would promote this block → higher-QoS thread waiting on lower-QoS
  // Rust threads → hang risk.  Utility QoS is ≤ Default, so no inversion.
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    // Use WWNLogFd to saved stderr - NSLog writes to redirected stderr
    // which would go to the pipe and create a feedback loop
    if (savedStderr >= 0) {
      WWNLogFd(savedStderr, "WAYPIPE",
               "Starting execution via waypipe_main...");
    }

    // Set RUST_BACKTRACE for better diagnostics
    setenv("RUST_BACKTRACE", "1", 1);

    // Verify the function symbol is actually linked (not null)
    void *fn_addr = (void *)waypipe_main;
    if (fn_addr == NULL) {
      if (savedStderr >= 0) {
        WWNLogFd(savedStderr, "WAYPIPE",
                 "FATAL: waypipe_main symbol is NULL! "
                 "The Rust static library may not be linked correctly.");
      }
      [self cleanupFileDescriptors];
      for (int i = 0; i < argc; i++) {
        free(argv[i]);
      }
      free(argv);
      self.running = NO;
      return;
    }

    int result = waypipe_main(argc, argv);
    if (savedStderr >= 0) {
      WWNLogFd(savedStderr, "WAYPIPE", "Execution finished. Exit code: %d",
               result);
    }

    // Flush stderr/stdout so pipe readers get all data
    fflush(stderr);
    fflush(stdout);

    // Small delay to let pipe readers finish draining
    usleep(100000); // 100ms

    // Restore original fds and close pipe ends (thread-safe)
    [self cleanupFileDescriptors];

    // Cleanup C args
    for (int i = 0; i < argc; i++) {
      free(argv[i]);
    }
    free(argv);

    self.running = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *exitMsg = [NSString
          stringWithFormat:@"\n[EXIT] waypipe_main returned %d\n", result];

      if ([self.delegate
              respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
        [self.delegate runnerDidReceiveOutput:exitMsg isError:(result != 0)];
      }

      if ([self.delegate
              respondsToSelector:@selector(runnerDidFinishWithExitCode:)]) {
        [self.delegate runnerDidFinishWithExitCode:result];
      }
    });
  });
}
#endif

// MARK: - Stop

- (void)stopWaypipe {
  self.stopping = YES;

#if !TARGET_OS_IPHONE
  if (self.currentTask) {
    [self.currentTask terminate];
    self.currentTask = nil;
  }
#endif

  if (self.currentPid > 0) {
    kill(-self.currentPid, SIGTERM);
    pid_t pidToKill = self.currentPid;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          kill(-pidToKill, SIGKILL);
        });
    self.currentPid = 0;
    g_active_waypipe_pgid = 0;
  }

#if TARGET_OS_IPHONE
  // On iOS, waypipe runs in-process. We can't kill a thread, but we can
  // restore file descriptors to stop capturing output and signal cleanup.
  [self cleanupFileDescriptors];
#endif

  if (self.sshClient) {
    [self.sshClient disconnect];
    self.sshClient = nil;
  }

  self.running = NO;
  self.stopping = NO;
}

// MARK: - Weston Simple SHM

- (void)launchWestonSimpleSHM {
  if (self.westonSimpleSHMRunning)
    return;

  self.westonSimpleSHMRunning = YES;

#if TARGET_OS_IPHONE
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    void *fn_addr = (void *)weston_simple_shm_main;
    if (fn_addr == NULL) {
      WWNLog("WESTON_SHM", @"FATAL: weston_simple_shm_main symbol is NULL!");
      self.westonSimpleSHMRunning = NO;
      return;
    }

    char *argv_shm[] = {"weston-simple-shm", NULL};
    int argc_shm = 1;

    char saved_cwd[512] = "";
    const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_dir) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      chdir(xdg_dir);
    }

    WWNLog("WESTON_SHM", @"Launching in-process weston-simple-shm...");
    int result = weston_simple_shm_main(argc_shm, argv_shm);
    WWNLog("WESTON_SHM", @"weston_simple_shm_main exit code: %d", result);

    if (saved_cwd[0])
      chdir(saved_cwd);

    self.westonSimpleSHMRunning = NO;
  });
#else
  NSString *path = [self findWestonSimpleSHMBinary];
  if (!path) {
    WWNLog("WESTON_SHM",
           @"Could not find weston-simple-shm executable in app bundle.");
    self.westonSimpleSHMRunning = NO;
    return;
  }

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:path];

  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  const char *envRuntime = getenv("XDG_RUNTIME_DIR");
  if (!envRuntime) {
    NSString *runtimeFallback =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
    env[@"XDG_RUNTIME_DIR"] = runtimeFallback;
  }
  task.environment = env;

  NSError *err;
  if ([task launchAndReturnError:&err]) {
    self.westonSimpleSHMTask = task;
    WWNLog("WESTON_SHM", @"Launched weston-simple-shm with PID %d",
           task.processIdentifier);
  } else {
    WWNLog("WESTON_SHM", @"Failed to launch weston-simple-shm: %@", err);
    self.westonSimpleSHMRunning = NO;
  }
#endif
}

- (void)stopWestonSimpleSHM {
#if TARGET_OS_IPHONE
  // There's no clean way to stop it natively right now since
  // wl_display_dispatch runs forever.
  self.westonSimpleSHMRunning = NO;
#else
  if (self.westonSimpleSHMTask) {
    [self.westonSimpleSHMTask terminate];
    self.westonSimpleSHMTask = nil;
  }
  self.westonSimpleSHMRunning = NO;
#endif
}

// MARK: - Generic Weston Launch Helpers
#if !TARGET_OS_IPHONE
- (NSString *)findBinaryNamed:(NSString *)name {
  NSBundle *bundle = [NSBundle mainBundle];
  NSFileManager *fm = [NSFileManager defaultManager];

  // 1) Contents/MacOS (Nix installs waypipe here; we can add weston/weston-terminal)
  NSString *auxPath = [bundle pathForAuxiliaryExecutable:name];
  if (auxPath && [fm isExecutableFileAtPath:auxPath]) {
    return auxPath;
  }

  // 2) Contents/Resources/bin (Nix macos.nix bundles weston, weston-terminal, etc.)
  NSString *binPath = [bundle pathForResource:name ofType:nil inDirectory:@"bin"];
  if (binPath && [fm isExecutableFileAtPath:binPath]) {
    return binPath;
  }

  // 3) Root resource (legacy)
  NSString *resourcePath = [bundle pathForResource:name ofType:nil];
  if (resourcePath && [fm isExecutableFileAtPath:resourcePath]) {
    return resourcePath;
  }

  // 4) Android: executables bundled as .so
  NSString *androidSoPath = [[bundle bundlePath]
      stringByAppendingPathComponent:
          [NSString stringWithFormat:@"lib/arm64-v8a/lib%@.so", name]];
  if ([fm fileExistsAtPath:androidSoPath]) {
    return androidSoPath;
  }
  return nil;
}

- (void)launchGenericWestonClient:(NSString *)name
                        taskInOut:(NSTask *__strong *)taskPtr
                    runningFlagIn:(BOOL *)runningFlag {
  NSString *path = [self findBinaryNamed:name];
  if (!path) {
    WWNLog("WESTON", @"Could not find executable %@ in app bundle.", name);
    *runningFlag = NO;
    return;
  }
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:path];

  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  const char *envRuntime = getenv("XDG_RUNTIME_DIR");
  if (!envRuntime) {
    env[@"XDG_RUNTIME_DIR"] =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  }
  task.environment = env;
  NSError *err;
  if ([task launchAndReturnError:&err]) {
    *taskPtr = task;
    WWNLog("WESTON", @"Launched %@ with PID %d", name, task.processIdentifier);
  } else {
    WWNLog("WESTON", @"Failed to launch %@: %@", name, err);
    *runningFlag = NO;
  }
}
#endif

// MARK: - Native Weston Executable

- (void)launchWeston {
  if (self.westonRunning)
    return;
  self.westonRunning = YES;
#if TARGET_OS_IPHONE
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    // iOS currently links compatibility shims for weston/weston-terminal.
    // Use the known-good weston-simple-shm in-process entrypoint so toggles
    // reliably produce visible output while shim wiring evolves.
    char *argv_weston[] = {"weston-simple-shm", NULL};
    int argc_weston = 1;

    char saved_cwd[512] = "";
    const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_dir) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      chdir(xdg_dir);
    }

    WWNLog("WESTON", @"Launching iOS compatibility client (weston-simple-shm path)...");
    int result = weston_simple_shm_main(argc_weston, argv_weston);
    WWNLog("WESTON", @"compatibility weston path exit code: %d", result);

    if (saved_cwd[0])
      chdir(saved_cwd);

    self.westonRunning = NO;
  });
#else
  NSTask *task = nil;
  BOOL running = YES;
  [self launchGenericWestonClient:@"weston"
                        taskInOut:&task
                    runningFlagIn:&running];
  self.westonTask = task;
  self.westonRunning = running;
#endif
}

- (void)stopWeston {
#if TARGET_OS_IPHONE
  self.westonRunning = NO;
#else
  if (self.westonTask) {
    [self.westonTask terminate];
    self.westonTask = nil;
  }
  self.westonRunning = NO;
#endif
}

// MARK: - Weston Terminal
- (void)launchWestonTerminal {
  if (self.westonTerminalRunning)
    return;
  self.westonTerminalRunning = YES;
#if TARGET_OS_IPHONE
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    // iOS compatibility fallback: route through weston-simple-shm so the
    // setting is functional even when terminal shim is not yet fully wired.
    char *argv_term[] = {"weston-simple-shm", NULL};
    int argc_term = 1;

    char saved_cwd[512] = "";
    const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_dir) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      chdir(xdg_dir);
    }

    WWNLog("WESTON_TERM", @"Launching iOS compatibility terminal path (weston-simple-shm)...");
    int result = weston_simple_shm_main(argc_term, argv_term);
    WWNLog("WESTON_TERM", @"compatibility weston-terminal path exit code: %d", result);

    if (saved_cwd[0])
      chdir(saved_cwd);

    self.westonTerminalRunning = NO;
  });
#else
  NSString *path = [self findBinaryNamed:@"weston-terminal"];
  if (!path) {
    WWNLog("WESTON_TERM", @"Could not find weston-terminal in app bundle.");
    self.westonTerminalRunning = NO;
    return;
  }

  // ---- Shell title environment setup ----
  // weston-terminal handles OSC 0/2 escape codes from the shell and calls
  // xdg_toplevel_set_title(), but macOS shells don't send them by default.
  // Set up ZDOTDIR (zsh) and PROMPT_COMMAND (bash) so the shell sends
  // OSC 0 title updates on every prompt, making cd/pwd visible in the
  // window title.
  NSString *zdotdir =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"wawona-zdotdir"];
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:zdotdir
      withIntermediateDirectories:YES
                      attributes:nil
                           error:nil];

  // .zshenv — source the user's original .zshenv so PATH etc. are intact
  NSString *zshenv =
      @"_wz=\"${_WAWONA_ORIG_ZDOTDIR:-$HOME}\"\n"
      @"[ -f \"$_wz/.zshenv\" ] && . \"$_wz/.zshenv\"\n"
      @"unset _wz\n";

  // .zshrc — source the user's original .zshrc, then add OSC 0 title hook
  NSString *zshrc =
      @"_wz=\"${_WAWONA_ORIG_ZDOTDIR:-$HOME}\"\n"
      @"[ -f \"$_wz/.zshrc\" ] && . \"$_wz/.zshrc\"\n"
      @"unset _wz\n"
      @"precmd() { print -Pn \"\\e]0;%n@%m: %~\\a\" }\n";

  [zshenv writeToFile:[zdotdir stringByAppendingPathComponent:@".zshenv"]
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];
  [zshrc writeToFile:[zdotdir stringByAppendingPathComponent:@".zshrc"]
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:path];

  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  const char *envRuntime = getenv("XDG_RUNTIME_DIR");
  if (!envRuntime) {
    env[@"XDG_RUNTIME_DIR"] =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  }

  // Preserve original ZDOTDIR for the .zshenv/.zshrc wrappers
  if (env[@"ZDOTDIR"])
    env[@"_WAWONA_ORIG_ZDOTDIR"] = env[@"ZDOTDIR"];
  env[@"ZDOTDIR"] = zdotdir;

  // bash: set PROMPT_COMMAND if not already set
  if (!env[@"PROMPT_COMMAND"]) {
    env[@"PROMPT_COMMAND"] =
        @"printf '\\033]0;%s@%s:%s\\007' \"$USER\" \"${HOSTNAME%%.*}\" "
        @"\"${PWD/#$HOME/~}\"";
  }

  task.environment = env;
  NSError *err;
  if ([task launchAndReturnError:&err]) {
    self.westonTerminalTask = task;
    WWNLog("WESTON_TERM", @"Launched weston-terminal with PID %d",
           task.processIdentifier);
  } else {
    WWNLog("WESTON_TERM", @"Failed to launch weston-terminal: %@", err);
    self.westonTerminalRunning = NO;
  }
#endif
}

- (void)stopWestonTerminal {
#if TARGET_OS_IPHONE
  self.westonTerminalRunning = NO;
#else
  if (self.westonTerminalTask) {
    [self.westonTerminalTask terminate];
    self.westonTerminalTask = nil;
  }
  self.westonTerminalRunning = NO;
#endif
}

@end
