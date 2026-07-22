#import "WWNWatchShellEnvironment.h"

#import <stdlib.h>
#import <unistd.h>

@implementation WWNWatchShellEnvironment

+ (NSString *)bundleRootfsPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bundle = [NSBundle mainBundle].bundlePath;
  NSString *atRoot = [bundle stringByAppendingPathComponent:@"wawona-rootfs"];
  if ([fm fileExistsAtPath:atRoot]) {
    return atRoot;
  }
  NSString *resource = [NSBundle mainBundle].resourcePath;
  if (resource.length > 0) {
    NSString *atResources =
        [resource stringByAppendingPathComponent:@"wawona-rootfs"];
    if ([fm fileExistsAtPath:atResources]) {
      return atResources;
    }
  }
  return @"";
}

+ (NSString *)activeRootfsPath {
  NSURL *base = [[NSFileManager defaultManager]
      URLsForDirectory:NSApplicationSupportDirectory
             inDomains:NSUserDomainMask]
                     .firstObject;
  if (!base) {
    return [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"wawona-rootfs"];
  }
  return [[[base URLByAppendingPathComponent:@"Wawona" isDirectory:YES]
      URLByAppendingPathComponent:@"wawona-rootfs"
                     isDirectory:YES] path];
}

+ (NSString *)activeHomePath {
  NSURL *docs = [[NSFileManager defaultManager]
      URLsForDirectory:NSDocumentDirectory
             inDomains:NSUserDomainMask]
                     .firstObject;
  if (!docs) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Wawona/home"];
  }
  return [[docs URLByAppendingPathComponent:@"Wawona/home" isDirectory:YES]
      path];
}

+ (BOOL)copyTreeFrom:(NSString *)src to:(NSString *)dst {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:src];
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
                                error:nil];
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
    [fm copyItemAtPath:srcPath toPath:dstPath error:nil];
  }
  return YES;
}

+ (void)ensureRootfsInstalledFromBundle:(NSString *)bundleRoot {
  if (bundleRoot.length == 0) {
    return;
  }
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *active = [self activeRootfsPath];
  NSString *bundleVerPath =
      [bundleRoot stringByAppendingPathComponent:@"etc/zsh/.template-version"];
  NSString *appliedPath =
      [active stringByAppendingPathComponent:@".template-version-applied"];
  NSString *bundleVer =
      [NSString stringWithContentsOfFile:bundleVerPath
                                encoding:NSUTF8StringEncoding
                                   error:nil]
          ?: @"0";
  bundleVer = [bundleVer
      stringByTrimmingCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *applied =
      [NSString stringWithContentsOfFile:appliedPath
                                encoding:NSUTF8StringEncoding
                                   error:nil]
          ?: @"";
  applied = [applied
      stringByTrimmingCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([applied isEqualToString:bundleVer] &&
      [fm fileExistsAtPath:[active stringByAppendingPathComponent:@"etc"]]) {
    return;
  }
  [fm createDirectoryAtPath:active
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
  for (NSString *sub in @[ @"etc", @"usr" ]) {
    NSString *src = [bundleRoot stringByAppendingPathComponent:sub];
    NSString *dst = [active stringByAppendingPathComponent:sub];
    if (![fm fileExistsAtPath:src]) {
      continue;
    }
    if ([fm fileExistsAtPath:dst]) {
      [fm removeItemAtPath:dst error:nil];
    }
    [self copyTreeFrom:src to:dst];
  }
  [bundleVer writeToFile:appliedPath
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
  NSLog(@"WWNWatchShell: installed rootfs template v%@", bundleVer);
}

+ (void)ensureDotfilesFromBundle:(NSString *)bundleRoot home:(NSString *)home {
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:home
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
  NSArray<NSArray<NSString *> *> *dotfiles = @[
    @[ @"etc/zsh/zshenv.template", @".zshenv" ],
    @[ @"etc/zsh/zshrc.template", @".zshrc" ],
    @[ @"etc/zsh/zlogin.template", @".zlogin" ],
  ];
  for (NSArray<NSString *> *pair in dotfiles) {
    NSString *src = [bundleRoot stringByAppendingPathComponent:pair[0]];
    NSString *dst = [home stringByAppendingPathComponent:pair[1]];
    if (![fm fileExistsAtPath:src] || [fm fileExistsAtPath:dst]) {
      continue;
    }
    [fm copyItemAtPath:src toPath:dst error:nil];
  }
}

+ (void)apply {
  /* Always mark in-process zsh so weston-terminal never fork/execs. */
  setenv("WAWONA_ZSH_IN_PROCESS", "1", 1);
  setenv("WAWONA_SHELL", "/usr/bin/zsh", 1);
  setenv("SHELL", "/usr/bin/zsh", 1);
  setenv("TERM", "xterm-256color", 1);
  setenv("USER", "mobile", 1);
  setenv("PATH", "/usr/bin:/bin", 1);

  NSString *bundleRoot = [self bundleRootfsPath];
  NSString *home = [self activeHomePath];
  NSString *active = [self activeRootfsPath];

  if (bundleRoot.length > 0) {
    [self ensureRootfsInstalledFromBundle:bundleRoot];
    [self ensureDotfilesFromBundle:bundleRoot home:home];
    setenv("WAWONA_BUNDLE_ROOTFS", bundleRoot.UTF8String, 1);
    setenv("WAWONA_ROOTFS", active.UTF8String, 1);
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:home
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
  setenv("HOME", home.UTF8String, 1);
  setenv("ZDOTDIR", home.UTF8String, 1);

  NSString *xdgConfig = [home stringByAppendingPathComponent:@".config"];
  NSString *xdgCache = [home stringByAppendingPathComponent:@".cache"];
  NSString *xdgData = [home stringByAppendingPathComponent:@".local/share"];
  NSString *xdgState = [home stringByAppendingPathComponent:@".local/state"];
  for (NSString *dir in @[ xdgConfig, xdgCache, xdgData, xdgState ]) {
    [fm createDirectoryAtPath:dir
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  }
  setenv("XDG_CONFIG_HOME", xdgConfig.UTF8String, 1);
  setenv("XDG_CACHE_HOME", xdgCache.UTF8String, 1);
  setenv("XDG_DATA_HOME", xdgData.UTF8String, 1);
  setenv("XDG_STATE_HOME", xdgState.UTF8String, 1);

  NSLog(@"WWNWatchShell: in-process zsh; HOME=%@ WAWONA_ROOTFS=%@", home,
        active);
}

@end
