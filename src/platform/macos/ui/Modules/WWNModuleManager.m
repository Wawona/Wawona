//
//  WWNModuleManager.m
//  Wawona — App Store module manager (wwn-apt host bridge). See header.
//

#import "WWNModuleManager.h"
#import "../../../../util/WWNLog.h"

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

// Swift StoreKit 2 bridge (WWNModuleStore.swift), resolved via
// NSClassFromString so ObjC-only configurations still link.
@interface NSObject (WWNModuleStoreBridge)
+ (void)purchaseProductId:(NSString *)productId
               completion:(void (^)(NSError *_Nullable))completion;
@end

NSErrorDomain const WWNModuleManagerErrorDomain = @"io.wawona.modulemanager";

static NSError *WWNModuleError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:WWNModuleManagerErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

@implementation WWNModuleManager {
  NSArray<NSDictionary *> *_catalog;
  dispatch_queue_t _queue;
  int _serverFd;
  dispatch_source_t _acceptSource;
  BOOL _started;
}

+ (instancetype)sharedManager {
  static WWNModuleManager *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[WWNModuleManager alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _queue = dispatch_queue_create("io.wawona.modulemanager", DISPATCH_QUEUE_SERIAL);
    _serverFd = -1;
  }
  return self;
}

// ---------------------------------------------------------------------------
#pragma mark - Paths
// ---------------------------------------------------------------------------

- (NSString *)_appSupportDir {
  NSString *base = NSSearchPathForDirectoriesInDomains(
                       NSApplicationSupportDirectory, NSUserDomainMask, YES)
                       .firstObject;
  return [base stringByAppendingPathComponent:@"Wawona"];
}

- (NSString *)_modulesDir {
  return [[self _appSupportDir] stringByAppendingPathComponent:@"modules"];
}

- (NSString *)_installedJSONPath {
  return [[self _modulesDir] stringByAppendingPathComponent:@"installed.json"];
}

- (NSString *)_socketPath {
  return [[self _appSupportDir] stringByAppendingPathComponent:@"module-manager.sock"];
}

/// catalog.json ships in the rootfs prefix (usr/share/wawona/apt) or as a
/// plain bundle resource.
- (nullable NSString *)_catalogPath {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *inRootfs = [bundle pathForResource:@"catalog"
                                        ofType:@"json"
                                   inDirectory:@"usr/share/wawona/apt"];
  if (inRootfs) {
    return inRootfs;
  }
  return [bundle pathForResource:@"catalog" ofType:@"json"];
}

// ---------------------------------------------------------------------------
#pragma mark - Catalog / installed state
// ---------------------------------------------------------------------------

- (NSArray<NSDictionary *> *)catalogModules {
  if (_catalog) {
    return _catalog;
  }
  NSString *path = [self _catalogPath];
  if (!path) {
    _catalog = @[];
    return _catalog;
  }
  NSData *data = [NSData dataWithContentsOfFile:path];
  NSDictionary *root =
      data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]
           : nil;
  NSArray *modules = root[@"modules"];
  _catalog = [modules isKindOfClass:[NSArray class]] ? modules : @[];
  return _catalog;
}

- (nullable NSDictionary *)_catalogEntryForId:(NSString *)moduleId {
  for (NSDictionary *entry in [self catalogModules]) {
    if ([entry[@"id"] isEqualToString:moduleId]) {
      return entry;
    }
  }
  return nil;
}

- (NSArray<NSString *> *)installedModuleIds {
  NSData *data = [NSData dataWithContentsOfFile:[self _installedJSONPath]];
  if (!data) {
    return @[];
  }
  NSDictionary *root =
      [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  NSMutableArray<NSString *> *ids = [NSMutableArray array];
  for (NSDictionary *entry in root[@"modules"]) {
    if ([entry isKindOfClass:[NSDictionary class]] && entry[@"id"]) {
      [ids addObject:entry[@"id"]];
    }
  }
  return ids;
}

- (BOOL)_writeInstalledIds:(NSArray<NSDictionary *> *)modules {
  NSDictionary *root = @{@"modules" : modules};
  NSData *data = [NSJSONSerialization dataWithJSONObject:root
                                                 options:NSJSONWritingPrettyPrinted
                                                   error:NULL];
  [[NSFileManager defaultManager] createDirectoryAtPath:[self _modulesDir]
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
  return [data writeToFile:[self _installedJSONPath] atomically:YES];
}

- (BOOL)_recordInstall:(NSString *)moduleId version:(NSString *)version {
  NSMutableArray<NSDictionary *> *modules = [NSMutableArray array];
  NSData *data = [NSData dataWithContentsOfFile:[self _installedJSONPath]];
  if (data) {
    NSDictionary *root =
        [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    for (NSDictionary *entry in root[@"modules"]) {
      if ([entry isKindOfClass:[NSDictionary class]] &&
          ![entry[@"id"] isEqualToString:moduleId]) {
        [modules addObject:entry];
      }
    }
  }
  [modules addObject:@{@"id" : moduleId, @"version" : version ?: @"0"}];
  return [self _writeInstalledIds:modules];
}

- (BOOL)_recordRemove:(NSString *)moduleId {
  NSMutableArray<NSDictionary *> *modules = [NSMutableArray array];
  NSData *data = [NSData dataWithContentsOfFile:[self _installedJSONPath]];
  if (data) {
    NSDictionary *root =
        [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    for (NSDictionary *entry in root[@"modules"]) {
      if ([entry isKindOfClass:[NSDictionary class]] &&
          ![entry[@"id"] isEqualToString:moduleId]) {
        [modules addObject:entry];
      }
    }
  }
  return [self _writeInstalledIds:modules];
}

// ---------------------------------------------------------------------------
#pragma mark - Install / remove
// ---------------------------------------------------------------------------

- (nullable NSDictionary *)_platformSectionForEntry:(NSDictionary *)entry {
  NSDictionary *platforms = entry[@"platforms"];
  if (![platforms isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
#if TARGET_OS_WATCH
  return platforms[@"watchos"];
#elif TARGET_OS_TV
  return platforms[@"tvos"];
#elif TARGET_OS_VISION
  return platforms[@"visionos"];
#elif TARGET_OS_IOS
  return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
             ? (platforms[@"ipados"] ?: platforms[@"ios"])
             : platforms[@"ios"];
#else
  return platforms[@"macos"] ?: platforms[@"ios"];
#endif
}

- (void)installModuleWithId:(NSString *)moduleId
                 completion:(void (^)(NSError *_Nullable))completion {
  void (^finish)(NSError *_Nullable) = ^(NSError *_Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(error);
    });
  };

  NSDictionary *entry = [self _catalogEntryForId:moduleId];
  if (!entry) {
    finish(WWNModuleError(2, [NSString stringWithFormat:
                                           @"'%@' is not in the module catalog",
                                           moduleId]));
    return;
  }
  NSDictionary *platform = [self _platformSectionForEntry:entry];
  NSString *productId = platform[@"storekit"][@"product_id"];
  NSString *odrTag = platform[@"odr"][@"tag"];
  NSString *version = entry[@"version"];

  void (^afterPurchase)(void) = ^{
    [self _fetchODRTag:odrTag
            completion:^(NSError *_Nullable odrError) {
              if (odrError) {
                finish(odrError);
                return;
              }
              [self _recordInstall:moduleId version:version];
              WWNLog("MODULES", @"Installed module '%@' (v%@)", moduleId,
                     version);
              finish(nil);
            }];
  };

  if (productId.length > 0) {
    // StoreKit 2 flow lives in Swift (WWNModuleStore); resolved dynamically so
    // targets without the Swift store (or StoreKit) still link.
    Class storeClass = NSClassFromString(@"WWNModuleStore");
    if (storeClass &&
        [storeClass respondsToSelector:@selector(purchaseProductId:
                                                        completion:)]) {
      [storeClass purchaseProductId:productId
                         completion:^(NSError *_Nullable storeError) {
                           if (storeError) {
                             finish(storeError);
                             return;
                           }
                           afterPurchase();
                         }];
      return;
    }
    finish(WWNModuleError(3, @"StoreKit module store is unavailable in this "
                             @"build"));
    return;
  }
  afterPurchase();
}

- (void)_fetchODRTag:(nullable NSString *)tag
          completion:(void (^)(NSError *_Nullable))completion {
  if (tag.length == 0) {
    completion(nil);
    return;
  }
#if TARGET_OS_WATCH || TARGET_OS_OSX
  // On-Demand Resources are unsupported on watchOS/macOS; payloads ship in
  // the main bundle there and install is entitlement-only.
  completion(nil);
#else
  NSBundleResourceRequest *request = [[NSBundleResourceRequest alloc]
      initWithTags:[NSSet setWithObject:tag]];
  request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent;
  [request beginAccessingResourcesWithCompletionHandler:^(NSError *error) {
    if (error) {
      WWNLog("MODULES", @"ODR fetch failed for tag '%@': %@", tag,
             error.localizedDescription);
      // A missing ODR tag is expected while payloads ship in the main bundle;
      // only report hard network/storage failures.
      if (error.code == NSBundleOnDemandResourceInvalidTagError) {
        completion(nil);
        return;
      }
    }
    [request endAccessingResources];
    completion(error);
  }];
#endif
}

- (void)removeModuleWithId:(NSString *)moduleId
                completion:(void (^)(NSError *_Nullable))completion {
  void (^finish)(NSError *_Nullable) = ^(NSError *_Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(error);
    });
  };
  if (![[self installedModuleIds] containsObject:moduleId]) {
    finish(WWNModuleError(4, [NSString stringWithFormat:@"'%@' is not installed",
                                                        moduleId]));
    return;
  }
  [self _recordRemove:moduleId];
  NSString *payloadDir =
      [[self _modulesDir] stringByAppendingPathComponent:moduleId];
  [[NSFileManager defaultManager] removeItemAtPath:payloadDir error:NULL];
  WWNLog("MODULES", @"Removed module '%@'", moduleId);
  finish(nil);
}

// ---------------------------------------------------------------------------
#pragma mark - IPC socket (apt CLI bridge)
// ---------------------------------------------------------------------------

- (void)start {
  if (_started) {
    return;
  }
  _started = YES;
  [self catalogModules];
  [self _startSocketServer];
}

- (void)_startSocketServer {
  NSString *path = [self _socketPath];
  [[NSFileManager defaultManager] createDirectoryAtPath:[self _appSupportDir]
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
  unlink(path.fileSystemRepresentation);

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    WWNLog("MODULES", @"module-manager socket() failed: %d", errno);
    return;
  }
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strlcpy(addr.sun_path, path.fileSystemRepresentation, sizeof(addr.sun_path));
  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
      listen(fd, 4) < 0) {
    WWNLog("MODULES", @"module-manager bind/listen failed: %d", errno);
    close(fd);
    return;
  }
  _serverFd = fd;
  setenv("WAWONA_MODULE_MANAGER", "1", 1);

  _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                         (uintptr_t)fd, 0, _queue);
  __weak __typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(_acceptSource, ^{
    int client = accept(fd, NULL, NULL);
    if (client >= 0) {
      [weakSelf _handleClient:client];
    }
  });
  dispatch_resume(_acceptSource);
  WWNLog("MODULES", @"module-manager IPC listening at %@", path);
}

/// One JSON request per connection (spec: IPC protocol, W2).
- (void)_handleClient:(int)client {
  char buf[4096];
  ssize_t n = read(client, buf, sizeof(buf) - 1);
  if (n <= 0) {
    close(client);
    return;
  }
  buf[n] = '\0';
  NSData *reqData = [NSData dataWithBytes:buf length:(NSUInteger)n];
  NSDictionary *req =
      [NSJSONSerialization JSONObjectWithData:reqData options:0 error:NULL];
  NSString *op = [req isKindOfClass:[NSDictionary class]] ? req[@"op"] : nil;
  NSString *moduleId = req[@"id"];

  void (^reply)(NSDictionary *) = ^(NSDictionary *response) {
    NSMutableData *out = [[NSJSONSerialization dataWithJSONObject:response
                                                          options:0
                                                            error:NULL]
        mutableCopy];
    [out appendBytes:"\n" length:1];
    write(client, out.bytes, out.length);
    close(client);
  };

  if ([op isEqualToString:@"list-installed"]) {
    reply(@{@"ok" : @YES, @"modules" : [self installedModuleIds]});
  } else if ([op isEqualToString:@"install"] && moduleId.length > 0) {
    [self installModuleWithId:moduleId
                   completion:^(NSError *_Nullable error) {
                     reply(error ? @{
                       @"ok" : @NO,
                       @"error" : error.localizedDescription
                     }
                                 : @{@"ok" : @YES});
                   }];
  } else if ([op isEqualToString:@"remove"] && moduleId.length > 0) {
    [self removeModuleWithId:moduleId
                  completion:^(NSError *_Nullable error) {
                    reply(error ? @{
                      @"ok" : @NO,
                      @"error" : error.localizedDescription
                    }
                                : @{@"ok" : @YES});
                  }];
  } else {
    reply(@{@"ok" : @NO, @"error" : @"unknown op"});
  }
}

@end
