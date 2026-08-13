#import "WWNRootfsManager.h"
#import "../macos/WWNRootfsICloudSync.h"
#import "../macos/WWNPlatformCallbacks.h"

#if TARGET_OS_IPHONE

#import <unistd.h>

static NSString *const kWWNRootfsReadmeText =
    @"Wawona Local Shell — user files for the in-process zsh terminal.\n"
    "\n"
    "home/          Shell HOME ($HOME). Edit .zshrc, add scripts, configs.\n"
    "               XDG dirs live under home/.config, home/.cache, etc.\n"
    "\n"
    "System files (etc/, usr/) stay in Application Support and are\n"
    "refreshed from the app bundle on template updates. Reset them in\n"
    "Wawona Settings → Local Shell.\n"
    "\n"
    "Tip: Import files with Settings → Local Shell → Import File to Home.\n";

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

+ (NSString *)filesAppRootPath {
  NSURL *docs = [[NSFileManager defaultManager]
      URLsForDirectory:NSDocumentDirectory
             inDomains:NSUserDomainMask]
      .firstObject;
  if (!docs) {
    return [[NSTemporaryDirectory() stringByAppendingPathComponent:@"Wawona"] copy];
  }
  return [[docs URLByAppendingPathComponent:@"Wawona" isDirectory:YES] path];
}

+ (NSString *)localHomePath {
  return [[self filesAppRootPath] stringByAppendingPathComponent:@"home"];
}

+ (NSString *)activeHomePath {
  if ([WWNRootfsICloudSync isEnabled]) {
    NSString *cloud = [WWNRootfsICloudSync icloudHomePath];
    if (cloud.length > 0) {
      return cloud;
    }
  }
  return [self localHomePath];
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

+ (NSString *)appliedTemplateVersion {
  NSString *path = [[self activeRootfsPath]
      stringByAppendingPathComponent:@".template-version-applied"];
  NSString *ver =
      [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  return ver.length ? [ver stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
}

+ (BOOL)ensureShellDotfilesPresent:(NSString *)bundleRoot
                              home:(NSString *)home
                             force:(BOOL)force {
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
    if (!force && [fm fileExistsAtPath:dst]) {
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

+ (BOOL)migrateLegacyHomeIfNeeded:(NSString *)newHome error:(NSError **)error {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *legacyHome =
      [[self activeRootfsPath] stringByAppendingPathComponent:@"home"];
  if ([legacyHome isEqualToString:newHome]) {
    return YES;
  }
  if (![fm fileExistsAtPath:legacyHome]) {
    return YES;
  }

  BOOL newHasContent = NO;
  NSArray *newEntries = [fm contentsOfDirectoryAtPath:newHome error:nil];
  if (newEntries.count > 0) {
    newHasContent = YES;
  }

  if (newHasContent) {
    NSString *backup = [[self activeRootfsPath]
        stringByAppendingPathComponent:@"home.legacy-backup"];
    if (![fm fileExistsAtPath:backup]) {
      [fm moveItemAtPath:legacyHome toPath:backup error:nil];
      NSLog(@"WWNRootfs: legacy home moved to %@", backup);
    }
    return YES;
  }

  if (![fm moveItemAtPath:legacyHome toPath:newHome error:error]) {
    if (![self copyTreeFrom:legacyHome to:newHome error:error]) {
      return NO;
    }
    [fm removeItemAtPath:legacyHome error:nil];
  }
  NSLog(@"WWNRootfs: migrated shell HOME → %@", newHome);
  return YES;
}

+ (void)ensureXDGDirectoriesUnderHome:(NSString *)home {
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *rel in @[
         @".config", @".cache", @".local/share", @".local/state"
       ]) {
    [fm createDirectoryAtPath:[home stringByAppendingPathComponent:rel]
        withIntermediateDirectories:YES
                     attributes:nil
                          error:nil];
  }
}

+ (void)prepareFilesAppAccess {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [self filesAppRootPath];
  NSString *home = [self localHomePath];
  [fm createDirectoryAtPath:root
      withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];
  [fm createDirectoryAtPath:home
      withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];
  [self ensureXDGDirectoriesUnderHome:home];

  NSString *readme = [root stringByAppendingPathComponent:@"README.txt"];
  if (![fm fileExistsAtPath:readme]) {
    [kWWNRootfsReadmeText writeToFile:readme
                           atomically:YES
                             encoding:NSUTF8StringEncoding
                                error:nil];
  }

  [WWNRootfsICloudSync prepareICloudLayout];
  if ([WWNRootfsICloudSync isEnabled]) {
    NSString *cloudHome = [WWNRootfsICloudSync icloudHomePath];
    if (cloudHome.length) {
      [fm createDirectoryAtPath:cloudHome
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
      [self ensureXDGDirectoriesUnderHome:cloudHome];
    }
  }

  NSError *migrateError = nil;
  [self migrateLegacyHomeIfNeeded:home error:&migrateError];
  if (migrateError) {
    NSLog(@"WWNRootfs: legacy home migration failed: %@",
          migrateError.localizedDescription);
  }
}

+ (BOOL)reinstallSystemTree:(NSError **)error {
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

  NSString *bundleTemplateVer = [self bundledTemplateVersion:bundleRoot];
  NSString *appliedVerPath =
      [activeRoot stringByAppendingPathComponent:@".template-version-applied"];
  [bundleTemplateVer writeToFile:appliedVerPath
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];
  [@"installed" writeToFile:[activeRoot stringByAppendingPathComponent:@".installed-v13"]
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
  return YES;
}

+ (BOOL)refreshShellDotfiles:(NSError **)error {
  NSString *bundleRoot = [self bundleRootfsPath];
  if (bundleRoot.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNRootfs"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Bundled wawona-rootfs not found."
                               }];
    }
    return NO;
  }
  [self prepareFilesAppAccess];
  if (![self ensureShellDotfilesPresent:bundleRoot
                                 home:[self activeHomePath]
                                force:YES]) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNRootfs"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to refresh zsh dotfiles from templates."
                               }];
    }
    return NO;
  }
  return YES;
}

+ (NSDictionary<NSString *, NSString *> *)rootfsStatusSnapshot {
  NSString *bundleRoot = [self bundleRootfsPath];
  NSString *filesRoot = [self filesAppRootPath] ?: @"";
  if ([WWNRootfsICloudSync isEnabled] && [WWNRootfsICloudSync icloudHomePath].length) {
    filesRoot = [[WWNRootfsICloudSync icloudHomePath] stringByDeletingLastPathComponent];
  }
  return @{
    @"filesRoot" : filesRoot,
    @"home" : [self activeHomePath] ?: @"",
    @"localHome" : [self localHomePath] ?: @"",
    @"systemRoot" : [self activeRootfsPath] ?: @"",
    @"bundleTemplateVersion" : [self bundledTemplateVersion:bundleRoot],
    @"appliedTemplateVersion" : [self appliedTemplateVersion],
    @"filesHint" : @"Files → On My iPhone/iPad → Wawona",
    @"iCloudSync" : [WWNRootfsICloudSync isEnabled] ? @"On" : @"Off",
    @"iCloudStatus" : [WWNRootfsICloudSync statusSummary] ?: @"",
  };
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

  [self prepareFilesAppAccess];

  [fm createDirectoryAtPath:activeRoot
      withIntermediateDirectories:YES
                       attributes:nil
                            error:error];
  if (error && *error) {
    return NO;
  }

  NSString *home = [self activeHomePath];
  if (![self ensureShellDotfilesPresent:bundleRoot home:home force:NO]) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNRootfs"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to install zsh dotfiles."
                               }];
    }
    return NO;
  }

  NSString *bundleTemplateVer = [self bundledTemplateVersion:bundleRoot];
  NSString *appliedVer = [self appliedTemplateVersion];

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
    [self ensureShellDotfilesPresent:bundleRoot home:home force:YES];
  }

  if (![self reinstallSystemTree:error]) {
    return NO;
  }

  for (NSString *old in @[
         @".installed-v5", @".installed-v6", @".installed-v7", @".installed-v8",
         @".installed-v9", @".installed-v10", @".installed-v11", @".installed-v12"
       ]) {
    NSString *p = [activeRoot stringByAppendingPathComponent:old];
    if ([fm fileExistsAtPath:p]) {
      [fm removeItemAtPath:p error:nil];
    }
  }

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

+ (void)migrateFastfetchConfigFromBundle:(NSString *)bundleRoot
                             configHome:(NSString *)configHome {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bundleVerPath =
      [bundleRoot stringByAppendingPathComponent:@"etc/fastfetch/.template-version"];
  if (![fm fileExistsAtPath:bundleVerPath]) {
    return;
  }
  NSString *bundleVer =
      [NSString stringWithContentsOfFile:bundleVerPath
                                encoding:NSUTF8StringEncoding
                                   error:nil];
  bundleVer = bundleVer.length
      ? [bundleVer stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]]
      : @"0";

  NSString *destDir = [configHome stringByAppendingPathComponent:@"fastfetch"];
  [fm createDirectoryAtPath:destDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
  NSString *appliedVerPath =
      [destDir stringByAppendingPathComponent:@".template-version-applied"];
  NSString *appliedVer =
      [NSString stringWithContentsOfFile:appliedVerPath
                                encoding:NSUTF8StringEncoding
                                   error:nil];
  appliedVer = appliedVer.length
      ? [appliedVer stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]]
      : @"";

  if ([appliedVer isEqualToString:bundleVer]) {
    return;
  }

  NSString *configPath = [destDir stringByAppendingPathComponent:@"config.jsonc"];
  if ([fm fileExistsAtPath:configPath]) {
    [fm removeItemAtPath:configPath error:nil];
    NSLog(@"WWNRootfs: removed fastfetch config.jsonc (template v%@ → v%@)",
          appliedVer.length ? appliedVer : @"0", bundleVer);
  }

  [bundleVer writeToFile:appliedVerPath
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
}

+ (void)applyShellEnvironment {
  NSError *error = nil;
  BOOL rootfsReady = [self ensureRootfsInstalled:&error];
  if (!rootfsReady) {
    NSLog(@"WWNRootfs: install failed: %@", error.localizedDescription);
    /* Still mark in-process zsh so weston-terminal does not reject /usr/bin/zsh
     * and call exit() (which would tear down the whole host process). */
    setenv("WAWONA_ZSH_IN_PROCESS", "1", 1);
    setenv("WAWONA_SHELL", "/usr/bin/zsh", 1);
    setenv("SHELL", "/usr/bin/zsh", 1);
    setenv("TERM", "xterm-256color", 1);
    setenv("USER", "mobile", 1);
    setenv("LOGNAME", "mobile", 1);
    const char *homeEnv = getenv("HOME");
    if (homeEnv == NULL || homeEnv[0] == '\0') {
      NSString *fallbackHome = NSHomeDirectory() ?: @"/tmp";
      setenv("HOME", fallbackHome.UTF8String, 1);
      setenv("ZDOTDIR", fallbackHome.UTF8String, 1);
    }
    return;
  }

  NSString *bundleRoot = [self bundleRootfsPath];
  NSString *activeRoot = [self activeRootfsPath];
  NSString *home = [self activeHomePath];
  NSString *shell = [self bundledShellPath];

  setenv("WAWONA_BUNDLE_ROOTFS", bundleRoot.UTF8String, 1);
  setenv("WAWONA_ROOTFS", activeRoot.UTF8String, 1);
  setenv("WAWONA_ZSH_IN_PROCESS", "1", 1);
  setenv("WAWONA_SHELL", shell.UTF8String, 1);
  setenv("HOME", home.UTF8String, 1);
  setenv("ZDOTDIR", home.UTF8String, 1);
  setenv("PATH", "/usr/bin:/bin", 1);
  setenv("SHELL", shell.UTF8String, 1);
  setenv("TERM", "xterm-256color", 1);
  setenv("USER", "mobile", 1);
  setenv("LOGNAME", "mobile", 1);

  NSFileManager *fm = [NSFileManager defaultManager];
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

  [self migrateFastfetchConfigFromBundle:bundleRoot configHome:xdgConfig];

  NSString *nvimRuntime = [self bundledNeovimRuntimePath];
  if (nvimRuntime.length > 0 && [fm fileExistsAtPath:nvimRuntime]) {
    setenv("VIMRUNTIME", nvimRuntime.UTF8String, 1);
    NSLog(@"WWNRootfs: in-process nvim; VIMRUNTIME=%@ XDG_CONFIG_HOME=%@",
          nvimRuntime, xdgConfig);
  }

  NSLog(@"WWNRootfs: in-process zsh; HOME=%@ (Files: %@) WAWONA_ROOTFS=%@",
        home, [self filesAppRootPath], activeRoot);
}

@end

#endif
