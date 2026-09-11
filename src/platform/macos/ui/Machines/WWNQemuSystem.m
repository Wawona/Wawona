#import "WWNQemuSystem.h"

#import <TargetConditionals.h>
#import <errno.h>
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

@implementation WWNQemuSystem {
  NSMutableArray<NSString *> *_arguments;
}

- (instancetype)init {
  if ((self = [super init])) {
    _arguments = [NSMutableArray array];
    _environment = @{};
    _childPid = 0;
  }
  return self;
}

- (NSArray<NSString *> *)arguments {
  return [_arguments copy];
}

- (void)setArguments:(NSArray<NSString *> *)arguments {
  _arguments = [arguments mutableCopy] ?: [NSMutableArray array];
}

- (void)pushArgv:(NSString *)arg {
  if (arg.length == 0) {
    return;
  }
  [_arguments addObject:arg];
}

- (void)clearArgv {
  [_arguments removeAllObjects];
}

- (NSString *)trampolinePath {
  NSString *bundle = [NSBundle mainBundle].bundlePath;
  NSString *beside = [bundle stringByAppendingPathComponent:@"wwn-qemu-run"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:beside]) {
    return beside;
  }
  return [[bundle stringByAppendingPathComponent:@"Frameworks"]
      stringByAppendingPathComponent:@"wwn-qemu-run"];
}

- (NSString *)qemuDylibPath {
  return [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:
          @"Frameworks/qemu-aarch64-softmmu.framework/qemu-aarch64-softmmu"];
}

- (BOOL)startTrampolineWithError:(NSError *_Nullable *_Nullable)error {
  NSString *exe = [self trampolinePath];
  NSString *dylib = [self qemuDylibPath];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:exe]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNQemuSystem"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"wwn-qemu-run is missing from this Mode B tipa."
                 }];
    }
    return NO;
  }
  if (![[NSFileManager defaultManager] fileExistsAtPath:dylib]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNQemuSystem"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"qemu-aarch64-softmmu.framework is not embedded."
                 }];
    }
    return NO;
  }

  NSString *fwDir = [dylib stringByDeletingLastPathComponent];
  fwDir = [fwDir stringByDeletingLastPathComponent];
  NSMutableDictionary<NSString *, NSString *> *env =
      [[NSProcessInfo processInfo].environment mutableCopy];
  if (!env) {
    env = [NSMutableDictionary dictionary];
  }
  [env addEntriesFromDictionary:self.environment ?: @{}];
  env[@"WWN_QEMU_DYLIB"] = dylib;
  env[@"WWN_QEMU_LOG"] = @"/tmp/wwn-modeb-qemu.log";
  env[@"WWN_QEMU_CHDIR"] = self.currentDirectoryPath.length > 0
                               ? self.currentDirectoryPath
                               : fwDir;
  env[@"DYLD_FRAMEWORK_PATH"] = fwDir;
  env[@"DYLD_LIBRARY_PATH"] = fwDir;

  NSMutableArray<NSString *> *argv = [NSMutableArray arrayWithObject:exe];
  [argv addObjectsFromArray:_arguments];

  FILE *ql = fopen("/tmp/wwn-modeb-qemu.log", "a");
  if (ql) {
    fprintf(ql, "qemu trampoline exe=%s argc=%d dylib=%s\n", exe.UTF8String,
            (int)argv.count, dylib.UTF8String);
    for (NSString *a in argv) {
      fprintf(ql, "  %s\n", a.UTF8String);
    }
    fclose(ql);
  }

  const char *cargv[argv.count + 1];
  for (NSUInteger i = 0; i < argv.count; i++) {
    cargv[i] = [argv[i] UTF8String];
  }
  cargv[argv.count] = NULL;

  NSArray<NSString *> *keys = env.allKeys;
  const char *cenv[keys.count + 1];
  NSMutableArray<NSString *> *pairs = [NSMutableArray arrayWithCapacity:keys.count];
  for (NSString *key in keys) {
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, env[key]]];
  }
  for (NSUInteger i = 0; i < pairs.count; i++) {
    cenv[i] = [pairs[i] UTF8String];
  }
  cenv[pairs.count] = NULL;

  pid_t pid = 0;
  int rc = posix_spawn(&pid, exe.UTF8String, NULL, NULL,
                       (char *const *)cargv, (char *const *)cenv);
  FILE *ql2 = fopen("/tmp/wwn-modeb-qemu.log", "a");
  if (ql2) {
    fprintf(ql2, "posix_spawn rc=%d errno=%d pid=%d\n", rc, errno, (int)pid);
    fclose(ql2);
  }
  if (rc != 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNQemuSystem"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"posix_spawn wwn-qemu-run failed rc=%d errno=%d",
                                        rc, errno]
                 }];
    }
    return NO;
  }
  _childPid = pid;
  return YES;
}

- (void)waitInBackground {
  pid_t pid = self.childPid;
  if (pid <= 0) {
    return;
  }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    int status = 0;
    pid_t waited = waitpid(pid, &status, 0);
    FILE *ql = fopen("/tmp/wwn-modeb-qemu.log", "a");
    if (ql) {
      fprintf(ql, "wait pid=%d waited=%d status=%d exit=%d signal=%d\n", (int)pid,
              (int)waited, status, WIFEXITED(status) ? WEXITSTATUS(status) : -1,
              WIFSIGNALED(status) ? WTERMSIG(status) : 0);
      fclose(ql);
    }
  });
}

- (void)stopQemu {
  if (self.childPid > 0) {
    kill(self.childPid, SIGTERM);
    _childPid = 0;
  }
}

@end
