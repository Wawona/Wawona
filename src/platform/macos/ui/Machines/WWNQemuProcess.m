#import "WWNQemuProcess.h"

#import <dlfcn.h>
#import <pthread.h>
#import <os/log.h>
#import <unistd.h>

static os_log_t WWNQemuLog(void) {
  static os_log_t log;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    log = os_log_create("com.aspauldingcode.Wawona", "WWNQemu");
  });
  return log;
}

@interface WWNQemuProcess ()
@property(nonatomic) dispatch_queue_t completionQueue;
@property(nonatomic) dispatch_semaphore_t done;
@property(nonatomic, nullable) NSString *processName;
@property(nonatomic) int fatal;
@end

@implementation WWNQemuProcess {
  NSMutableArray<NSString *> *_argv;
}

@synthesize argv = _argv;

- (instancetype)init {
  return [self initWithArguments:@[]];
}

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments {
  if ((self = [super init])) {
    _argv = [arguments mutableCopy];
    dispatch_queue_attr_t attr =
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
    _completionQueue = dispatch_queue_create("WWNQemu Completion", attr);
    _done = dispatch_semaphore_create(0);
    _entry = NULL;
    _status = 0;
    _fatal = 0;
    _environment = @{};
  }
  return self;
}

- (void)dealloc {
  [self stopProcess];
}

static void *WWNQemuStartThread(void *args) {
  WWNQemuProcess *self = (__bridge WWNQemuProcess *)args;
  NSArray<NSString *> *processArgv = self.argv;
  NSMutableArray<NSString *> *environment =
      [NSMutableArray arrayWithCapacity:self.environment.count];
  [self.environment enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value,
                                                          BOOL *stop) {
    (void)stop;
    [environment addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    setenv(key.UTF8String, value.UTF8String, 1);
  }];
  NSUInteger envc = environment.count;
  const char *envp[envc + 1];
  for (NSUInteger i = 0; i < envc; i++) {
    envp[i] = environment[i].UTF8String;
  }
  envp[envc] = NULL;
  setenv("TMPDIR", NSTemporaryDirectory().UTF8String, 1);

  if (self.currentDirectoryUrl.path.length > 0) {
    chdir(self.currentDirectoryUrl.path.UTF8String);
  }

  int argc = (int)processArgv.count + 1;
  const char *argv[argc];
  argv[0] = [self.processName cStringUsingEncoding:NSUTF8StringEncoding];
  if (!argv[0]) {
    argv[0] = "qemu";
  }
  for (int i = 0; i < processArgv.count; i++) {
    argv[i + 1] = processArgv[i].UTF8String;
  }

  if (self.entry) {
    self->_status = self.entry(self, argc, argv, envp);
  } else {
    self->_status = -1;
  }
  dispatch_semaphore_signal(self.done);
  return NULL;
}

- (void)pushArgv:(NSString *)arg {
  NSAssert(arg.length > 0, @"empty argv");
  [_argv addObject:arg];
}

- (void)clearArgv {
  [_argv removeAllObjects];
}

- (void)startProcess:(NSString *)name completion:(void (^)(NSError *_Nullable))completion {
  if (!self.entry) {
    if (completion) {
      completion([NSError errorWithDomain:@"WWNQemuProcess"
                                     code:1
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"Missing QEMU entry callback."
                                 }]);
    }
    return;
  }

  self.processName = name;
  _status = 0;
  self.fatal = 0;

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_VISION
  NSString *base = @"";
#else
  NSString *base = @"Versions/A/";
#endif
  NSString *frameworksDir = self.currentDirectoryUrl.path;
  if (frameworksDir.length == 0) {
    frameworksDir = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks"];
  }
  NSString *dylib = [NSString stringWithFormat:@"%@/%@.framework/%@%@", frameworksDir, name, base, name];
  os_log(WWNQemuLog(), "Loading %{public}@", dylib);
  void *dlctx = dlopen(dylib.UTF8String, RTLD_LOCAL);
  if (!dlctx) {
    const char *err = dlerror();
    if (completion) {
      completion([NSError
          errorWithDomain:@"WWNQemuProcess"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       [NSString stringWithUTF8String:err ?: "dlopen failed"]
                 }]);
    }
    return;
  }

  pthread_t qemuThread;
  pthread_attr_t qosAttribute;
  pthread_attr_init(&qosAttribute);
  pthread_attr_set_qos_class_np(&qosAttribute, QOS_CLASS_USER_INTERACTIVE, 0);
  pthread_create(&qemuThread, &qosAttribute, WWNQemuStartThread, (__bridge void *)self);
  pthread_attr_destroy(&qosAttribute);

  dispatch_async(self.completionQueue, ^{
    dispatch_semaphore_wait(self.done, DISPATCH_TIME_FOREVER);
    if (dlclose(dlctx) < 0) {
      const char *err = dlerror();
      os_log_error(WWNQemuLog(), "dlclose failed: %{public}s", err ?: "unknown");
    }
    if (completion) {
      completion(nil);
    }
  });
}

- (void)stopProcess {
}

@end
