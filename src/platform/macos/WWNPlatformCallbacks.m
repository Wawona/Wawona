//  WWNPlatformCallbacks.m
//  Implementation of platform callbacks for Rust compositor

#import "WWNPlatformCallbacks.h"
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import "WWNWindow.h"
#endif
#import "../../util/WWNLog.h"

@implementation WWNPlatformCallbacks

+ (instancetype)sharedCallbacks {
  static WWNPlatformCallbacks *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[WWNPlatformCallbacks alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    _windowRegistry = [NSMutableDictionary dictionary];
#else
    _windowRegistry = [NSMutableDictionary dictionary];
#endif
  }
  return self;
}

#pragma mark - Window Management

- (void)createNativeWindowWithId:(uint64_t)windowId
                           width:(int32_t)width
                          height:(int32_t)height
                           title:(NSString *)title
                          useSSD:(BOOL)useSSD {
  dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    // macOS window creation
    NSWindowStyleMask styleMask =
        useSSD ? (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
               : (NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable);

    NSRect contentRect = NSMakeRect(100, 100, width, height);
    NSWindow *window =
        [[WWNWindow alloc] initWithContentRect:contentRect
                                     styleMask:styleMask
                                       backing:NSBackingStoreBuffered
                                         defer:NO];

    // Create and set WWNView as content view to handle input
    WWNView *contentView =
        [[WWNView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    [window setContentView:contentView];

    window.title = title ?: @"WWN Client";
    window.delegate = (id<NSWindowDelegate>)self; // For window lifecycle events

    [self.windowRegistry setObject:window forKey:@(windowId)];
    [window makeKeyAndOrderFront:nil];

    WWNLog("PLATFORM", @"Created native window %llu: %@", windowId, title);
#else
        // iOS window creation (simplified for now).
        // Use the first connected UIWindowScene if available.
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                break;
            }
        }
        if (!window) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            window = [[UIWindow alloc] init];
#pragma clang diagnostic pop
        }
        window.backgroundColor = [UIColor blackColor];
        [self.windowRegistry setObject:window forKey:@(windowId)];
        [window makeKeyAndVisible];
        
        WWNLog("PLATFORM", @"Created native window %llu", windowId);
#endif
  });
}

- (void)destroyNativeWindowWithId:(uint64_t)windowId {
  dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    NSWindow *window = [self.windowRegistry objectForKey:@(windowId)];
    if (window) {
      [window close];
      [self.windowRegistry removeObjectForKey:@(windowId)];
      WWNLog("PLATFORM", @"Destroyed native window %llu", windowId);
    }
#else
        UIWindow *window = [self.windowRegistry objectForKey:@(windowId)];
        if (window) {
            window.hidden = YES;
            [self.windowRegistry removeObjectForKey:@(windowId)];
            WWNLog("PLATFORM", @"Destroyed native window %llu", windowId);
        }
#endif
  });
}

- (void)setWindowTitle:(NSString *)title forWindowId:(uint64_t)windowId {
  dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    NSWindow *window = [self.windowRegistry objectForKey:@(windowId)];
    if (window) {
      window.title = title;
    }
#endif
  });
}

- (void)setWindowSize:(CGSize)size forWindowId:(uint64_t)windowId {
  dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    NSWindow *window = [self.windowRegistry objectForKey:@(windowId)];
    if (window) {
      NSRect frame = window.frame;
      NSRect contentRect =
          NSMakeRect(frame.origin.x, frame.origin.y, size.width, size.height);
      NSRect newFrame = [window frameRectForContentRect:contentRect];
      [window setFrame:newFrame display:YES animate:YES];
    }
#else
        UIWindow *window = [self.windowRegistry objectForKey:@(windowId)];
        if (window) {
            CGRect frame = window.frame;
            frame.size = size;
            window.frame = frame;
        }
#endif
  });
}

- (void)requestRenderForWindowId:(uint64_t)windowId {
  // TODO: Trigger Metal rendering for this window
  // For now, this is a stub
}

@end

// MARK: - Bundle path resolution (shared by macOS, iOS, tvOS, visionOS, watchOS)

static NSString *gWWNCachedBundleRoot = nil;
static NSString *gWWNCachedShareRoot = nil;
static NSString *gWWNCachedLibRoot = nil;
static NSString *gWWNCachedResourcesRoot = nil;

static NSString *WWNFirstExistingPath(NSArray<NSString *> *candidates) {
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *path in candidates) {
    if (path.length > 0 && [fm fileExistsAtPath:path]) {
      return path;
    }
  }
  return nil;
}

static void WWNSetEnvIfUnset(NSString *key, NSString *value) {
  if (!key.length || !value.length) {
    return;
  }
  const char *k = key.UTF8String;
  if (getenv(k) != NULL) {
    return;
  }
  setenv(k, value.UTF8String, 1);
}

/// Prepend bundle share to XDG_DATA_DIRS so fuzzel finds share/applications
/// and share/icons/hicolor (issue #78).
static void WWNPrependBundledXdgDataDirs(NSString *shareRoot) {
  if (!shareRoot.length) {
    return;
  }
  NSString *appsDir =
      [shareRoot stringByAppendingPathComponent:@"applications"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:appsDir]) {
    WWNLog("BUNDLE",
           @"No applications catalog at %@ — fuzzel Mod+D list will be empty",
           appsDir);
    return;
  }
  const char *existing = getenv("XDG_DATA_DIRS");
  NSString *combined;
  if (existing && existing[0]) {
    NSString *ex = @(existing);
    NSArray<NSString *> *parts = [ex componentsSeparatedByString:@":"];
    if ([parts containsObject:shareRoot]) {
      return;
    }
    combined = [NSString stringWithFormat:@"%@:%@", shareRoot, ex];
  } else {
    combined = [NSString
        stringWithFormat:@"%@:/usr/local/share:/usr/share", shareRoot];
  }
  setenv("XDG_DATA_DIRS", combined.UTF8String, 1);
  WWNLog("BUNDLE", @"XDG_DATA_DIRS prepended with share root: %s",
         shareRoot.UTF8String);
}

NSString *WWNWawonaAppBundleRoot(void) {
  if (gWWNCachedBundleRoot.length > 0) {
    return gWWNCachedBundleRoot;
  }

  NSBundle *bundle = [NSBundle mainBundle];
  NSString *exec =
      [[bundle.executablePath ?: @"" stringByResolvingSymlinksInPath] copy];

  if (exec.length > 0) {
    NSRange marker = [exec rangeOfString:@".app/Contents/MacOS/"];
    if (marker.location != NSNotFound) {
      gWWNCachedBundleRoot = [exec substringToIndex:marker.location + 4];
      return gWWNCachedBundleRoot;
    }
    NSRange appMarker = [exec rangeOfString:@".app/"];
    if (appMarker.location != NSNotFound) {
      gWWNCachedBundleRoot = [exec substringToIndex:appMarker.location + 4];
      return gWWNCachedBundleRoot;
    }
  }

  NSString *bundlePath =
      [[bundle.bundlePath ?: @"" stringByResolvingSymlinksInPath] copy];
  if ([bundlePath hasSuffix:@".app"]) {
    gWWNCachedBundleRoot = bundlePath;
    return gWWNCachedBundleRoot;
  }

  if (bundlePath.length > 0) {
    NSString *nixApp =
        [[bundlePath stringByAppendingPathComponent:@"../Applications/Wawona.app"]
            stringByStandardizingPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:nixApp]) {
      gWWNCachedBundleRoot = nixApp;
      return gWWNCachedBundleRoot;
    }
    NSString *storeShare =
        [[bundlePath stringByAppendingPathComponent:@"../share"]
            stringByStandardizingPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:storeShare]) {
      NSString *storeApp =
          [[storeShare stringByDeletingLastPathComponent]
              stringByAppendingPathComponent:@"Applications/Wawona.app"];
      storeApp = [storeApp stringByStandardizingPath];
      if ([[NSFileManager defaultManager] fileExistsAtPath:storeApp]) {
        gWWNCachedBundleRoot = storeApp;
        return gWWNCachedBundleRoot;
      }
    }
    if (exec.length > 0) {
      NSString *contents =
          [[exec stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
      NSString *appCandidate = [contents stringByAppendingPathExtension:@"app"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:appCandidate]) {
        gWWNCachedBundleRoot = appCandidate;
        return gWWNCachedBundleRoot;
      }
    }
  }

  gWWNCachedBundleRoot =
      bundlePath.length > 0 ? bundlePath : @"/Applications/Wawona.app";
  return gWWNCachedBundleRoot;
}

NSString *WWNWawonaAppBundleRootForUI(void) {
  return WWNWawonaAppBundleRoot();
}

NSString *WWNWawonaExecutableDirectory(void) {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *exec =
      [[bundle.executablePath ?: @"" stringByResolvingSymlinksInPath] copy];
  if (exec.length > 0) {
    return [exec stringByDeletingLastPathComponent];
  }
  return [[WWNWawonaAppBundleRoot()
      stringByAppendingPathComponent:@"Contents/MacOS"]
      stringByStandardizingPath];
}

NSString *WWNWawonaResourcesRoot(void) {
  if (gWWNCachedResourcesRoot.length > 0) {
    return gWWNCachedResourcesRoot;
  }
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *resource = bundle.resourcePath;
  if (resource.length > 0 &&
      [[NSFileManager defaultManager] fileExistsAtPath:resource]) {
    gWWNCachedResourcesRoot = resource;
    return gWWNCachedResourcesRoot;
  }
  gWWNCachedResourcesRoot =
      [[WWNWawonaAppBundleRoot() stringByAppendingPathComponent:@"Contents/Resources"]
          stringByStandardizingPath];
  return gWWNCachedResourcesRoot;
}

NSString *WWNWawonaShareRoot(void) {
  if (gWWNCachedShareRoot.length > 0) {
    return gWWNCachedShareRoot;
  }
  NSString *appRoot = WWNWawonaAppBundleRoot();
  NSArray<NSString *> *candidates = @[
    [appRoot stringByAppendingPathComponent:@"share"],
    [[WWNWawonaResourcesRoot() stringByAppendingPathComponent:@"share"]
        stringByStandardizingPath],
  ];
  // Prefer a share root that actually has the fuzzel applications catalog.
  // macos.nix historically installs at App/share; Xcode Bundle Executables
  // installs at Contents/Resources/share. Picking the first existing directory
  // (often App/share with only fonts/weston) left XDG_DATA_DIRS pointing at a
  // tree without applications/ → empty Mod+D list on macOS.
  for (NSString *cand in candidates) {
    if (cand.length == 0) {
      continue;
    }
    NSString *apps =
        [cand stringByAppendingPathComponent:@"applications"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:apps]) {
      gWWNCachedShareRoot = cand;
      return gWWNCachedShareRoot;
    }
  }
  NSString *found = WWNFirstExistingPath(candidates);
  gWWNCachedShareRoot =
      found ?: [appRoot stringByAppendingPathComponent:@"share"];
  return gWWNCachedShareRoot;
}

NSString *WWNWawonaLibRoot(void) {
  if (gWWNCachedLibRoot.length > 0) {
    return gWWNCachedLibRoot;
  }
  NSString *appRoot = WWNWawonaAppBundleRoot();
  NSString *found = WWNFirstExistingPath(@[
    [appRoot stringByAppendingPathComponent:@"lib"],
    [[WWNWawonaResourcesRoot() stringByAppendingPathComponent:@"lib"]
        stringByStandardizingPath],
  ]);
  gWWNCachedLibRoot = found ?: [appRoot stringByAppendingPathComponent:@"lib"];
  return gWWNCachedLibRoot;
}

NSString *WWNWawonaBundledSharePath(NSString *relativePath) {
  if (!relativePath.length) {
    return WWNWawonaShareRoot();
  }
  if ([relativePath hasPrefix:@"/"]) {
    return relativePath;
  }
  if ([relativePath hasPrefix:@"share/"]) {
    return [[WWNWawonaAppBundleRoot() stringByAppendingPathComponent:relativePath]
        stringByStandardizingPath];
  }
  return [[WWNWawonaShareRoot() stringByAppendingPathComponent:relativePath]
      stringByStandardizingPath];
}

NSString *_Nullable WWNWawonaBundledResourcePath(NSString *filename) {
  if (!filename.length) {
    return nil;
  }
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *direct =
      [WWNWawonaAppBundleRoot() stringByAppendingPathComponent:filename];
  if ([fm fileExistsAtPath:direct]) {
    return direct;
  }
  NSString *inResources =
      [WWNWawonaResourcesRoot() stringByAppendingPathComponent:filename];
  if ([fm fileExistsAtPath:inResources]) {
    return inResources;
  }
  NSString *base = [filename stringByDeletingPathExtension];
  NSString *ext = [filename pathExtension];
  return [[NSBundle mainBundle] pathForResource:base ofType:ext.length ? ext : nil];
}

NSString *_Nullable WWNWawonaFindBundledExecutable(NSString *name) {
  if (!name.length) {
    return nil;
  }
  NSBundle *bundle = [NSBundle mainBundle];
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL (^isExecutable)(NSString *) = ^BOOL(NSString *candidate) {
    return (candidate.length > 0 && [fm isExecutableFileAtPath:candidate]);
  };

  NSString *realExecPath =
      [[bundle.executablePath ?: @"" stringByResolvingSymlinksInPath] copy];
  if (realExecPath.length > 0) {
    NSString *execSibling =
        [[realExecPath stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:name];
    if (isExecutable(execSibling)) {
      return execSibling;
    }
  }

  NSString *auxPath = [bundle pathForAuxiliaryExecutable:name];
  if (isExecutable(auxPath)) {
    return auxPath;
  }

  NSString *binPath = [bundle pathForResource:name ofType:nil inDirectory:@"bin"];
  if (isExecutable(binPath)) {
    return binPath;
  }

  if (realExecPath.length > 0) {
    NSString *contentsDir =
        [[realExecPath stringByDeletingLastPathComponent]
            stringByDeletingLastPathComponent];
    NSString *manualBinPath =
        [[[contentsDir stringByAppendingPathComponent:@"Resources/bin"]
            stringByAppendingPathComponent:name] stringByStandardizingPath];
    if (isExecutable(manualBinPath)) {
      return manualBinPath;
    }
  }

  NSString *appRoot = WWNWawonaAppBundleRoot();
  NSString *bundleBinPath =
      [[[appRoot stringByAppendingPathComponent:@"Contents/Resources/bin"]
          stringByAppendingPathComponent:name] stringByStandardizingPath];
  if (isExecutable(bundleBinPath)) {
    return bundleBinPath;
  }

  NSString *wrappedName = [NSString stringWithFormat:@".%@-wrapped", name];
  NSString *wrappedBinPath =
      [[[appRoot stringByAppendingPathComponent:@"Contents/Resources/bin"]
          stringByAppendingPathComponent:wrappedName] stringByStandardizingPath];
  if (isExecutable(wrappedBinPath)) {
    return wrappedBinPath;
  }

  NSString *resourcePath = [bundle pathForResource:name ofType:nil];
  if (isExecutable(resourcePath)) {
    return resourcePath;
  }

  NSString *pathEnv = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
  for (NSString *entry in [pathEnv componentsSeparatedByString:@":"]) {
    if (entry.length == 0) {
      continue;
    }
    NSString *candidate = [entry stringByAppendingPathComponent:name];
    if (isExecutable(candidate)) {
      return candidate;
    }
    NSString *wrappedCandidate =
        [entry stringByAppendingPathComponent:
                    [NSString stringWithFormat:@".%@-wrapped", name]];
    if (isExecutable(wrappedCandidate)) {
      return wrappedCandidate;
    }
  }

  NSMutableArray<NSString *> *nixPrefixes = [NSMutableArray array];
  NSString *homeDir = NSHomeDirectory();
  NSString *userName = NSUserName();
  if (homeDir.length > 0) {
    [nixPrefixes addObject:[homeDir stringByAppendingPathComponent:@".nix-profile/bin"]];
  }
  if (userName.length > 0) {
    [nixPrefixes
        addObject:[NSString stringWithFormat:
                                @"/nix/var/nix/profiles/per-user/%@/profile/bin",
                                userName]];
  }
  [nixPrefixes addObject:@"/nix/var/nix/profiles/default/bin"];
  [nixPrefixes addObject:@"/run/current-system/sw/bin"];

  for (NSString *prefix in nixPrefixes) {
    if (prefix.length == 0) {
      continue;
    }
    NSString *candidate = [prefix stringByAppendingPathComponent:name];
    if (isExecutable(candidate)) {
      return candidate;
    }
    NSString *wrappedCandidate =
        [prefix stringByAppendingPathComponent:
                    [NSString stringWithFormat:@".%@-wrapped", name]];
    if (isExecutable(wrappedCandidate)) {
      return wrappedCandidate;
    }
  }

  return nil;
}

static void WWNConfigureBundledXkbIfNeeded(void) {
  if (getenv("XKB_CONFIG_ROOT") != NULL) {
    return;
  }
  NSString *rules = WWNFirstExistingPath(@[
    [WWNWawonaBundledSharePath(@"X11/xkb") stringByAppendingPathComponent:
                                       @"rules/evdev"],
    [[WWNWawonaResourcesRoot() stringByAppendingPathComponent:@"xkb"]
        stringByAppendingPathComponent:@"rules/evdev"],
    [WWNWawonaAppBundleRoot() stringByAppendingPathComponent:
                                @"Contents/Resources/xkb/rules/evdev"],
  ]);
  if (!rules.length) {
    return;
  }
  NSString *root = [rules stringByDeletingLastPathComponent];
  root = [root stringByDeletingLastPathComponent];
  setenv("XKB_CONFIG_ROOT", root.UTF8String, 1);
  WWNLog("BUNDLE", @"Configured XKB_CONFIG_ROOT: %s", root.UTF8String);
}

static void WWNConfigureBundledFontsIfNeeded(void) {
  NSString *fontDir = WWNWawonaBundledSharePath(@"fonts");
  if (![[NSFileManager defaultManager] fileExistsAtPath:fontDir]) {
    WWNLog("BUNDLE", @"No bundled fonts at %s; skipping fontconfig setup",
           fontDir.UTF8String);
    return;
  }

  const char *xdg = getenv("XDG_RUNTIME_DIR");
  NSString *base = (xdg && xdg[0]) ? @(xdg) : NSTemporaryDirectory();
  NSString *cacheDir = [base stringByAppendingPathComponent:@"fontconfig-cache"];
  [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];

  NSString *confPath = [base stringByAppendingPathComponent:@"fonts.conf"];
  /*
   * Always rewrite fonts.conf for the current bundle UUID. A stale
   * FONTCONFIG_FILE from a previous install path makes FcInit fail and
   * weston-terminal draws with zero font metrics.
   */
  NSString *conf = [NSString
      stringWithFormat:@"<?xml version=\"1.0\"?>\n"
                       @"<!DOCTYPE fontconfig SYSTEM "
                       @"\"urn:fontconfig:fonts.dtd\">\n"
                       @"<fontconfig>\n"
                       @"  <dir>%@</dir>\n"
                       @"  <cachedir>%@</cachedir>\n"
                       @"  <alias>\n"
                       @"    <family>monospace</family>\n"
                       @"    <prefer><family>DejaVu Sans Mono</family></prefer>\n"
                       @"  </alias>\n"
                       @"  <alias>\n"
                       @"    <family>sans-serif</family>\n"
                       @"    <prefer><family>DejaVu Sans</family></prefer>\n"
                       @"  </alias>\n"
                       @"  <config></config>\n"
                       @"</fontconfig>\n",
                       fontDir, cacheDir];
  NSError *err = nil;
  if (![conf writeToFile:confPath
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:&err]) {
    WWNLog("BUNDLE", @"Failed to write fonts.conf (%s): %@",
           confPath.UTF8String, err.localizedDescription);
    return;
  }
  setenv("FONTCONFIG_FILE", confPath.UTF8String, 1);
  setenv("FONTCONFIG_PATH", base.UTF8String, 1);
  WWNLog("BUNDLE", @"Configured FONTCONFIG_FILE: %s (fonts: %s)",
         confPath.UTF8String, fontDir.UTF8String);

  NSString *monoFont =
      [fontDir stringByAppendingPathComponent:@"truetype/DejaVuSansMono.ttf"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:monoFont]) {
    setenv("WAWONA_MONO_FONT", monoFont.UTF8String, 1);
  }
}

static void WWNConfigureBundledWestonDataIfNeeded(void) {
  NSString *westonData = WWNWawonaBundledSharePath(@"weston");
  if ([[NSFileManager defaultManager] fileExistsAtPath:westonData]) {
    setenv("WESTON_DATA_DIR", westonData.UTF8String, 1);
  } else {
    WWNLog("BUNDLE", @"No bundled weston data at %s", westonData.UTF8String);
  }

  NSString *westonModules =
      [WWNWawonaLibRoot() stringByAppendingPathComponent:@"weston"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:westonModules]) {
    setenv("WESTON_MODULE_DIR", westonModules.UTF8String, 1);
  }

  NSString *westonBackends =
      [WWNWawonaLibRoot() stringByAppendingPathComponent:@"libweston-13"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:westonBackends]) {
    setenv("WESTON_BACKEND_DIR", westonBackends.UTF8String, 1);
  }

  NSString *cursorTheme =
      WWNWawonaBundledSharePath(@"icons/Adwaita/cursors");
  if ([[NSFileManager defaultManager] fileExistsAtPath:cursorTheme]) {
    NSString *iconsRoot = WWNWawonaBundledSharePath(@"icons");
    setenv("XCURSOR_PATH", iconsRoot.UTF8String, 1);
    setenv("XCURSOR_THEME", "Adwaita", 1);
    WWNLog("BUNDLE", @"Configured XCURSOR_PATH: %s (theme=Adwaita)",
           iconsRoot.UTF8String);
  }
}

void WWNEnsureFuzzelXdgEnv(void) {
  // Drop a stale share-root cache so catalog preference can re-run (App/share
  // vs Contents/Resources/share).
  gWWNCachedShareRoot = nil;
  NSString *shareRoot = WWNWawonaShareRoot();
  setenv("WAWONA_SHARE_ROOT", shareRoot.UTF8String, 1);

  NSString *home = NSHomeDirectory();
  if (home.length > 0) {
    NSString *dataHome =
        [home stringByAppendingPathComponent:@".local/share"];
    NSString *cache = [home stringByAppendingPathComponent:@".cache"];
    NSString *config = [home stringByAppendingPathComponent:@".config"];
    NSString *state =
        [home stringByAppendingPathComponent:@".local/state"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in @[ dataHome, cache, config, state ]) {
      [fm createDirectoryAtPath:dir
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
    }
    // Writable XDG_DATA_HOME for fuzzel locks/cache; catalog stays in the
    // bundle via XDG_DATA_DIRS (do not seed desktops into DATA_HOME).
    setenv("XDG_DATA_HOME", dataHome.UTF8String, 1);
    const char *existingCache = getenv("XDG_CACHE_HOME");
    if (!existingCache || !existingCache[0]) {
      setenv("XDG_CACHE_HOME", cache.UTF8String, 1);
    }
    const char *existingConfig = getenv("XDG_CONFIG_HOME");
    if (!existingConfig || !existingConfig[0]) {
      setenv("XDG_CONFIG_HOME", config.UTF8String, 1);
    }
    const char *existingState = getenv("XDG_STATE_HOME");
    if (!existingState || !existingState[0]) {
      setenv("XDG_STATE_HOME", state.UTF8String, 1);
    }
  }

  WWNPrependBundledXdgDataDirs(shareRoot);
}

void WWNConfigureBundledRuntimeEnvIfNeeded(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *appRoot = WWNWawonaAppBundleRoot();
    NSString *libRoot = WWNWawonaLibRoot();
    WWNSetEnvIfUnset(@"WAWONA_APP_BUNDLE_ROOT", appRoot);
    WWNSetEnvIfUnset(@"WAWONA_LIB_ROOT", libRoot);
    WWNConfigureBundledXkbIfNeeded();
    WWNConfigureBundledWestonDataIfNeeded();
    // Sets WAWONA_SHARE_ROOT + XDG_DATA_DIRS / XDG_DATA_HOME for fuzzel.
    WWNEnsureFuzzelXdgEnv();
    WWNLog("BUNDLE", @"App root: %s", appRoot.UTF8String);
    WWNLog("BUNDLE", @"Share root: %s", getenv("WAWONA_SHARE_ROOT") ?: "(nil)");
    WWNLog("BUNDLE", @"Lib root: %s", libRoot.UTF8String);
  });
  /* Fonts: rewrite every refresh so FONTCONFIG_FILE tracks the live bundle. */
  WWNConfigureBundledFontsIfNeeded();
}

void wwn_ios_refresh_bundle_env(void) {
  WWNConfigureBundledRuntimeEnvIfNeeded();
}
