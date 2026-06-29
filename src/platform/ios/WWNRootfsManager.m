#import "WWNRootfsManager.h"
#import "../macos/WWNPlatformCallbacks.h"

#if TARGET_OS_IPHONE

#import <unistd.h>

@implementation WWNRootfsManager

+ (NSString *)bundleRootfsPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *appRoot = WWNWawonaAppBundleRoot();
  NSString *atBundleRoot = [appRoot stringByAppendingPathComponent:@"wawona-rootfs"];
  if ([fm fileExistsAtPath:atBundleRoot]) {
    return atBundleRoot;
  }
  NSString *resource = WWNWawonaResourcesRoot();
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

+ (NSString *)bundledTemplateVersion:(NSString *)bundleRoot {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *path =
      [bundleRoot stringByAppendingPathComponent:@"etc/zsh/.template-version"];
  if (![fm fileExistsAtPath:path]) {
    return @"0";
  }
  NSString *ver =
      [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  return ver.length ? [ver stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"0";
}

+ (BOOL)refreshDotfilesFromBundle:(NSString *)bundleRoot home:(NSString *)home {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray<NSArray<NSString *> *> *dotfiles = @[
    @[ @"etc/zsh/zshenv.template", @".zshenv" ],
    @[ @"etc/zsh/zshrc.template", @".zshrc" ],
    @[ @"etc/zsh/zlogin.template", @".zlogin" ],
  ];
  for (NSArray<NSString *> *pair in dotfiles) {
    NSString *src = [bundleRoot stringByAppendingPathComponent:pair[0]];
    NSString *dst = [home stringByAppendingPathComponent:pair[1]];
    if (![fm fileExistsAtPath:src]) {
      continue;
    }
    if ([fm fileExistsAtPath:dst]) {
      [fm removeItemAtPath:dst error:nil];
    }
    if (![fm copyItemAtPath:src toPath:dst error:nil]) {
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

  // v13: always refresh HOME dotfiles from bundle templates (small, safe to
  // overwrite every launch). Older installs kept stale .zshrc/.zshenv with
  // unconditional `compinit` because the marker short-circuited dotfile copy.
  NSString *home = [activeRoot stringByAppendingPathComponent:@"home"];
  [fm createDirectoryAtPath:home
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
  if (![self refreshDotfilesFromBundle:bundleRoot home:home]) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNRootfs"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to refresh zsh dotfiles from bundle templates."
                               }];
    }
    return NO;
  }
  NSLog(@"WWNRootfs: refreshed zsh dotfiles from bundle templates → %@", home);

  NSString *bundleTemplateVer = [self bundledTemplateVersion:bundleRoot];
  NSString *appliedVerPath =
      [activeRoot stringByAppendingPathComponent:@".template-version-applied"];
  NSString *appliedVer =
      [NSString stringWithContentsOfFile:appliedVerPath
                                encoding:NSUTF8StringEncoding
                                   error:nil];
  appliedVer = appliedVer.length
      ? [appliedVer stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]]
      : @"";

  NSString *markerV13 = [activeRoot stringByAppendingPathComponent:@".installed-v13"];
  BOOL needSystemTreeRefresh =
      ![fm fileExistsAtPath:markerV13] ||
      ![appliedVer isEqualToString:bundleTemplateVer];

  if (!needSystemTreeRefresh) {
    return YES;
  }

  if (appliedVer.length > 0 && ![appliedVer isEqualToString:bundleTemplateVer]) {
    NSLog(@"WWNRootfs: bundle template v%@ → v%@; refreshing etc/usr tree",
          appliedVer, bundleTemplateVer);
  }

  // Always refresh the read-only system tree (etc/usr) from the bundle so the
  // device picks up new share/zsh functions and template versions.
  for (NSString *subdir in @[ @"etc", @"usr" ]) {
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

  // Drop superseded markers from older installs.
  for (NSString *old in @[
         @".installed-v5", @".installed-v6", @".installed-v7", @".installed-v8",
         @".installed-v9", @".installed-v10", @".installed-v11", @".installed-v12"
       ]) {
    NSString *p = [activeRoot stringByAppendingPathComponent:old];
    if ([fm fileExistsAtPath:p]) {
      [fm removeItemAtPath:p error:nil];
    }
  }

  [@"installed" writeToFile:markerV13
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
  [bundleTemplateVer writeToFile:appliedVerPath
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];
  return YES;
}

+ (NSString *)bundleNeovimRootfsPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *appRoot = WWNWawonaAppBundleRoot();
  NSString *atBundleRoot = [appRoot stringByAppendingPathComponent:@"neovim-rootfs"];
  if ([fm fileExistsAtPath:atBundleRoot]) {
    return atBundleRoot;
  }
  NSString *resource = WWNWawonaResourcesRoot();
  if (resource.length == 0) {
    return @"";
  }
  return [resource stringByAppendingPathComponent:@"neovim-rootfs"];
}

+ (NSString *)activeNeovimConfigPath {
  NSURL *base = [[[NSFileManager defaultManager]
      URLsForDirectory:NSApplicationSupportDirectory
             inDomains:NSUserDomainMask] firstObject];
  if (!base) {
    return [[NSTemporaryDirectory() stringByAppendingPathComponent:@"neovim-rootfs"]
        stringByAppendingPathComponent:@"home/.config"];
  }
  NSURL *configURL =
      [[[[base URLByAppendingPathComponent:@"Wawona" isDirectory:YES]
          URLByAppendingPathComponent:@"neovim-rootfs" isDirectory:YES]
         URLByAppendingPathComponent:@"home" isDirectory:YES]
        URLByAppendingPathComponent:@".config" isDirectory:YES];
  return configURL.path;
}

+ (NSString *)bundledNeovimRuntimePath {
  return [[self bundleNeovimRootfsPath]
      stringByAppendingPathComponent:@"usr/share/nvim/runtime"];
}

+ (NSString *)bundledShellPath {
  return @"/usr/bin/zsh";
}

+ (NSString *)bundledZshSharePath {
  return [[self bundleRootfsPath]
      stringByAppendingPathComponent:@"usr/share/zsh"];
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
  NSString *shell = [self bundledShellPath];

  setenv("WAWONA_BUNDLE_ROOTFS", bundleRoot.UTF8String, 1);
  setenv("WAWONA_ROOTFS", activeRoot.UTF8String, 1);
  // Signals "run zsh in-process (statically linked wawona_zsh_main)" to the
  // wawona-pty layer: it allows the virtual /usr/bin/zsh path and keeps the
  // in-process environ guard active.
  setenv("WAWONA_ZSH_IN_PROCESS", "1", 1);
  setenv("WAWONA_SHELL", shell.UTF8String, 1);
  setenv("HOME", home.UTF8String, 1);
  setenv("ZDOTDIR", home.UTF8String, 1);
  setenv("PATH", "/usr/bin:/bin", 1);
  setenv("SHELL", shell.UTF8String, 1);
  setenv("TERM", "xterm-256color", 1);
  setenv("USER", "mobile", 1);

  NSString *nvimRuntime = [self bundledNeovimRuntimePath];
  if (nvimRuntime.length > 0 &&
      [[NSFileManager defaultManager] fileExistsAtPath:nvimRuntime]) {
    setenv("VIMRUNTIME", nvimRuntime.UTF8String, 1);
    NSString *nvimConfig = [self activeNeovimConfigPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:nvimConfig
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
    setenv("XDG_CONFIG_HOME", nvimConfig.UTF8String, 1);
    setenv("XDG_DATA_HOME", nvimConfig.UTF8String, 1);
    setenv("XDG_STATE_HOME",
           [[nvimConfig stringByAppendingPathComponent:@"state"] UTF8String], 1);
    NSLog(@"WWNRootfs: in-process nvim; VIMRUNTIME=%@ XDG_CONFIG_HOME=%@",
          nvimRuntime, nvimConfig);
  }

  /* Do not set ZSH= — bundled share init breaks the fake-PTY bootstrap. */
  NSLog(@"WWNRootfs: in-process zsh (libwawona-zsh.a); WAWONA_SHELL=%@ is a virtual path, HOME=%@",
        shell, home);
}

@end

#endif
