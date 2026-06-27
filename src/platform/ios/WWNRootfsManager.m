#import "WWNRootfsManager.h"

#if TARGET_OS_IPHONE

#import <unistd.h>

@implementation WWNRootfsManager

+ (NSString *)bundleRootfsPath {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *resource = [bundle resourcePath];
  if (resource.length == 0) {
    return @"";
  }
  return [resource stringByAppendingPathComponent:@"wawona-rootfs"];
}

+ (NSString *)activeRootfsPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSURL *base = [[fm URLsForDirectory:NSApplicationSupportDirectory
                            inDomains:NSUserDomainMask] firstObject];
  if (!base) {
    return [[NSTemporaryDirectory() stringByAppendingPathComponent:@"wawona-rootfs"]
        copy];
  }
  return [[[base URLByAppendingPathComponent:@"Wawona" isDirectory:YES]
      URLByAppendingPathComponent:@"wawona-rootfs"
                     isDirectory:YES] path];
}

+ (BOOL)copyTreeFrom:(NSString *)src to:(NSString *)dst error:(NSError **)error {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *enumerator =
      [fm enumeratorAtPath:src];
  NSString *rel;
  while ((rel = [enumerator nextObject])) {
    NSString *srcPath = [src stringByAppendingPathComponent:rel];
    NSString *dstPath = [dst stringByAppendingPathComponent:rel];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:srcPath isDirectory:&isDir]) {
      continue;
    }
    if (isDir) {
      [fm createDirectoryAtPath:dstPath
          withIntermediateDirectories:YES
                           attributes:nil
                                error:error];
      if (error && *error) {
        return NO;
      }
      continue;
    }
    NSString *parent = [dstPath stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:parent
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
    if ([fm fileExistsAtPath:dstPath]) {
      [fm removeItemAtPath:dstPath error:nil];
    }
    if (![fm copyItemAtPath:srcPath toPath:dstPath error:error]) {
      return NO;
    }
  }
  return YES;
}

+ (BOOL)ensureRootfsInstalled:(NSError **)error {
  NSString *bundleRoot = [self bundleRootfsPath];
  NSString *activeRoot = [self activeRootfsPath];
  NSFileManager *fm = [NSFileManager defaultManager];

  if (bundleRoot.length == 0 || ![fm fileExistsAtPath:bundleRoot]) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNRootfs"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Bundled wawona-rootfs not found in app resources."
                               }];
    }
    return NO;
  }

  [fm createDirectoryAtPath:activeRoot
      withIntermediateDirectories:YES
                       attributes:nil
                            error:error];
  if (error && *error) {
    return NO;
  }

  NSString *marker = [activeRoot stringByAppendingPathComponent:@".installed"];
  if ([fm fileExistsAtPath:marker]) {
    return YES;
  }

  for (NSString *subdir in @[ @"usr", @"etc" ]) {
    NSString *src = [bundleRoot stringByAppendingPathComponent:subdir];
    NSString *dst = [activeRoot stringByAppendingPathComponent:subdir];
    if (![fm fileExistsAtPath:src]) {
      continue;
    }
    if ([fm fileExistsAtPath:dst]) {
      [fm removeItemAtPath:dst error:nil];
    }
    if (![self copyTreeFrom:src to:dst error:error]) {
      return NO;
    }
  }

  NSString *home = [activeRoot stringByAppendingPathComponent:@"home"];
  [fm createDirectoryAtPath:home
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

  NSString *zdot = [home stringByAppendingPathComponent:@".zshrc"];
  if (![fm fileExistsAtPath:zdot]) {
    NSString *template =
        [activeRoot stringByAppendingPathComponent:@"etc/zsh/zshrc.template"];
    if ([fm fileExistsAtPath:template]) {
      [fm copyItemAtPath:template toPath:zdot error:nil];
    }
  }

  [@"installed" writeToFile:marker
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
  return YES;
}

+ (void)applyShellEnvironment {
  NSError *error = nil;
  if (![self ensureRootfsInstalled:&error]) {
    NSLog(@"WWNRootfs: install failed: %@", error.localizedDescription);
    return;
  }

  NSString *bundleRoot = [self bundleRootfsPath];
  NSString *activeRoot = [self activeRootfsPath];
  NSString *home = [activeRoot stringByAppendingPathComponent:@"home"];
  NSString *shell = [activeRoot stringByAppendingPathComponent:@"usr/bin/zsh"];
  NSString *path = [activeRoot stringByAppendingPathComponent:@"usr/bin"];

  setenv("WAWONA_BUNDLE_ROOTFS", bundleRoot.UTF8String, 1);
  setenv("WAWONA_ROOTFS", activeRoot.UTF8String, 1);
  setenv("WAWONA_SHELL", shell.UTF8String, 1);
  setenv("HOME", home.UTF8String, 1);
  setenv("ZDOTDIR", home.UTF8String, 1);
  setenv("PATH", path.UTF8String, 1);
  setenv("SHELL", shell.UTF8String, 1);
  setenv("TERM", "xterm-256color", 1);
  setenv("USER", "mobile", 1);
}

@end

#endif
