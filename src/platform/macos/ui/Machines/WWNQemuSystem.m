#import "WWNQemuSystem.h"

#import <dlfcn.h>

static int WWNQemuSystemEntry(WWNQemuProcess *process, int argc, const char *argv[],
                              const char *envp[]) {
  WWNQemuSystem *system = (WWNQemuSystem *)process;
  NSString *image =
      [NSString stringWithFormat:@"qemu-%@-softmmu.framework/qemu-%@-softmmu",
                                 system.architecture, system.architecture];
  void *handle = dlopen(image.UTF8String, RTLD_NOLOAD);
  if (!handle) {
    return -1;
  }
  int (*qemu_init)(int, const char *[], const char *[]) = dlsym(handle, "qemu_init");
  void (*qemu_main_loop)(void) = dlsym(handle, "qemu_main_loop");
  void (*qemu_cleanup)(void) = dlsym(handle, "qemu_cleanup");
  if (!qemu_init || !qemu_main_loop || !qemu_cleanup) {
    return -1;
  }
  int ret = qemu_init(argc, argv, envp);
  if (ret != 0) {
    return ret;
  }
  qemu_main_loop();
  qemu_cleanup();
  return 0;
}

@implementation WWNQemuSystem

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments
                     architecture:(NSString *)architecture {
  if ((self = [super initWithArguments:arguments])) {
    _architecture = [architecture copy];
    _resources = @[];
    self.entry = WWNQemuSystemEntry;
  }
  return self;
}

- (void)startQemuWithCompletion:(void (^)(NSError *_Nullable))completion {
  NSString *name = [NSString stringWithFormat:@"qemu-%@-softmmu", self.architecture];
  [self startProcess:name completion:completion];
}

- (void)stopQemu {
  [self stopProcess];
}

@end
