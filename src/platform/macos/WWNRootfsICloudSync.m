#import "WWNRootfsICloudSync.h"

#import <TargetConditionals.h>

#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV && !TARGET_OS_WATCH

NSString *const WWNRootfsICloudSyncPreferenceKey =
    @"wawona.pref.localShellICloudSyncEnabled";

static NSString *const kICloudContainerID = @"iCloud.com.aspauldingcode.Wawona";

@implementation WWNRootfsICloudSync

+ (BOOL)isSupported {
  return YES;
}

+ (BOOL)isEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:WWNRootfsICloudSyncPreferenceKey];
}

+ (NSURL *)containerURL {
  return [[NSFileManager defaultManager]
      URLForUbiquityContainerIdentifier:kICloudContainerID];
}

+ (BOOL)isContainerAvailable {
  return [self containerURL] != nil;
}

+ (NSString *)localHomePath {
  NSURL *docs = [[NSFileManager defaultManager]
      URLsForDirectory:NSDocumentDirectory
             inDomains:NSUserDomainMask]
      .firstObject;
  if (!docs) {
    return @"";
  }
  return [[docs URLByAppendingPathComponent:@"Wawona/home" isDirectory:YES] path];
}

+ (NSString *)icloudHomePath {
  NSURL *container = [self containerURL];
  if (!container) {
    return nil;
  }
  return [[container URLByAppendingPathComponent:@"Documents/Wawona/home"
                                       isDirectory:YES] path];
}

+ (NSString *)statusSummary {
  if (![self isEnabled]) {
    return @"Off — shell HOME stays on this device only.";
  }
  if (![self isContainerAvailable]) {
    return @"On — waiting for iCloud sign-in (using local HOME until available).";
  }
  return @"On — shell HOME syncs via iCloud Drive (Settings → Apple ID → iCloud).";
}

+ (void)prepareICloudLayout {
  NSURL *container = [self containerURL];
  if (!container) {
    return;
  }
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *home = [self icloudHomePath];
  if (home.length) {
    [fm createDirectoryAtPath:home
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  }
}

+ (BOOL)copyTreeFrom:(NSString *)src to:(NSString *)dst error:(NSError **)error {
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:src]) {
    return YES;
  }
  BOOL isDir = NO;
  [fm fileExistsAtPath:src isDirectory:&isDir];
  if (!isDir) {
    [fm createDirectoryAtPath:[dst stringByDeletingLastPathComponent]
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
    if ([fm fileExistsAtPath:dst]) {
      [fm removeItemAtPath:dst error:nil];
    }
    return [fm copyItemAtPath:src toPath:dst error:error];
  }

  [fm createDirectoryAtPath:dst
      withIntermediateDirectories:YES
                       attributes:nil
                            error:error];
  if (error && *error) {
    return NO;
  }

  NSArray *entries = [fm contentsOfDirectoryAtPath:src error:error];
  if (!entries) {
    return NO;
  }
  for (NSString *name in entries) {
    if ([name hasPrefix:@"."] && [name isEqualToString:@".DS_Store"]) {
      continue;
    }
    NSString *srcPath = [src stringByAppendingPathComponent:name];
    NSString *dstPath = [dst stringByAppendingPathComponent:name];
    if ([fm fileExistsAtPath:dstPath]) {
      continue;
    }
    if (![self copyTreeFrom:srcPath to:dstPath error:error]) {
      return NO;
    }
  }
  return YES;
}

+ (BOOL)migrateFrom:(NSString *)src to:(NSString *)dst error:(NSError **)error {
  if (src.length == 0 || dst.length == 0) {
    return YES;
  }
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:dst
      withIntermediateDirectories:YES
                       attributes:nil
                            error:error];
  if (error && *error) {
    return NO;
  }
  return [self copyTreeFrom:src to:dst error:error];
}

+ (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
  BOOL wasEnabled = [self isEnabled];
  if (enabled == wasEnabled) {
    [self prepareICloudLayout];
    return YES;
  }

  NSString *local = [self localHomePath];
  NSString *cloud = [self icloudHomePath];

  if (enabled) {
    [self prepareICloudLayout];
    cloud = [self icloudHomePath];
    if (cloud.length == 0) {
      [[NSUserDefaults standardUserDefaults] setBool:YES
                                              forKey:WWNRootfsICloudSyncPreferenceKey];
      return YES;
    }
    if (![self migrateFrom:local to:cloud error:error]) {
      return NO;
    }
    [[NSUserDefaults standardUserDefaults] setBool:YES
                                            forKey:WWNRootfsICloudSyncPreferenceKey];
    return YES;
  }

  if (cloud.length > 0 &&
      ![self migrateFrom:cloud to:local error:error]) {
    return NO;
  }
  [[NSUserDefaults standardUserDefaults] setBool:NO
                                          forKey:WWNRootfsICloudSyncPreferenceKey];
  return YES;
}

@end

#else

NSString *const WWNRootfsICloudSyncPreferenceKey =
    @"wawona.pref.localShellICloudSyncEnabled";

@implementation WWNRootfsICloudSync

+ (BOOL)isSupported {
  return NO;
}
+ (BOOL)isEnabled {
  return NO;
}
+ (BOOL)isContainerAvailable {
  return NO;
}
+ (NSString *)icloudHomePath {
  return nil;
}
+ (NSString *)statusSummary {
  return @"Not available on this platform.";
}
+ (void)prepareICloudLayout {
}
+ (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
  (void)enabled;
  if (error) {
    *error = [NSError errorWithDomain:@"WWNRootfs"
                                 code:200
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"iCloud sync is not available on this platform."
                             }];
  }
  return NO;
}

@end

#endif
