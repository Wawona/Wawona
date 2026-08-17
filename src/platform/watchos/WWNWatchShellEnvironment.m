#import "WWNWatchShellEnvironment.h"
#import "WWNLog.h"

#import <stdlib.h>
#import <unistd.h>

@interface WWNWatchShellEnvironment (BundleFonts)
+ (NSString *)firstExistingFont:(NSArray<NSString *> *)relPaths
                          under:(NSString *)fontDir;
@end

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

+ (NSString *)canonicalFilesystemPath:(NSString *)path {
  if (path.length == 0) {
    return path;
  }
  NSString *resolved = [path stringByResolvingSymlinksInPath];
  return resolved.length > 0 ? resolved : path;
}

+ (NSString *)activeHomePath {
  NSURL *docs = [[NSFileManager defaultManager]
      URLsForDirectory:NSDocumentDirectory
             inDomains:NSUserDomainMask]
                     .firstObject;
  NSString *home;
  if (!docs) {
    home = [NSHomeDirectory() stringByAppendingPathComponent:@"Wawona/home"];
  } else {
    home = [[docs URLByAppendingPathComponent:@"Wawona/home" isDirectory:YES]
        path];
  }
  return [self canonicalFilesystemPath:home];
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
  WWNLog("SHELL", @"installed rootfs template v%@", bundleVer);
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
  NSString *active = [self canonicalFilesystemPath:[self activeRootfsPath]];

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

  [self applyBundleShareEnv];

  WWNLog("SHELL", @"in-process zsh; HOME=%@ WAWONA_ROOTFS=%@", home,
        active);
}

/// Resolve a subdirectory of the bundled `share/` tree embedded by the
/// xkb/font/weston postBuild phases (xcodegen.nix). Checks the app bundle
/// root first, then Resources, matching the layout the embed scripts write.
+ (NSString *)bundledSharePath:(NSString *)sub {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bundle = [NSBundle mainBundle].bundlePath;
  NSString *candidate =
      [[bundle stringByAppendingPathComponent:@"share"]
          stringByAppendingPathComponent:sub];
  if ([fm fileExistsAtPath:candidate]) {
    return candidate;
  }
  NSString *resource = [NSBundle mainBundle].resourcePath;
  if (resource.length > 0) {
    candidate = [[resource stringByAppendingPathComponent:@"share"]
        stringByAppendingPathComponent:sub];
    if ([fm fileExistsAtPath:candidate]) {
      return candidate;
    }
  }
  return @"";
}

/// Point weston-terminal/foot at the bundled fonts (fontconfig), xkb keymap,
/// weston data, and the share root (XDG_DATA_DIRS) so they render text and
/// resolve resources instead of coming up blank. Mirrors the iOS
/// WWNConfigureBundledRuntimeEnvIfNeeded path (WWNPlatformCallbacks.m), which
/// is not compiled into the watch target.
+ (void)applyBundleShareEnv {
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *shareRoot = [NSBundle mainBundle].bundlePath;
  shareRoot = [shareRoot stringByAppendingPathComponent:@"share"];
  if (![fm fileExistsAtPath:shareRoot]) {
    NSString *res = [NSBundle mainBundle].resourcePath;
    if (res.length > 0) {
      NSString *alt = [res stringByAppendingPathComponent:@"share"];
      if ([fm fileExistsAtPath:alt]) {
        shareRoot = alt;
      }
    }
  }
  if ([fm fileExistsAtPath:shareRoot] && !getenv("XDG_DATA_DIRS")) {
    setenv("XDG_DATA_DIRS", shareRoot.UTF8String, 1);
  }

  // xkb keymap tree (rules/evdev lives two levels under share/X11/xkb).
  NSString *xkbRules =
      [[self bundledSharePath:@"X11/xkb"] stringByAppendingPathComponent:
                                             @"rules/evdev"];
  if (xkbRules.length > 0 && [fm fileExistsAtPath:xkbRules] &&
      !getenv("XKB_CONFIG_ROOT")) {
    NSString *root =
        [[xkbRules stringByDeletingLastPathComponent]
            stringByDeletingLastPathComponent];
    setenv("XKB_CONFIG_ROOT", root.UTF8String, 1);
  }

  // weston data (terminal.png, cursors, panel, etc.).
  NSString *westonData = [self bundledSharePath:@"weston"];
  if (westonData.length > 0 && [fm fileExistsAtPath:westonData]) {
    setenv("WESTON_DATA_DIR", westonData.UTF8String, 1);
  }
  NSString *cursors = [self bundledSharePath:@"icons/Adwaita/cursors"];
  if (cursors.length > 0 && [fm fileExistsAtPath:cursors]) {
    setenv("XCURSOR_PATH",
           [self bundledSharePath:@"icons"].UTF8String, 1);
    setenv("XCURSOR_THEME", "Adwaita", 1);
  }

  // fontconfig: always rewrite fonts.conf for the live bundle UUID (same as
  // iOS WWNPlatformCallbacks). A stale FONTCONFIG_FILE from a previous install
  // makes Pango title glyphs tofu while WAWONA_MONO_FONT still paints the grid.
  NSString *fontDir = [self bundledSharePath:@"fonts"];
  if (fontDir.length > 0 && [fm fileExistsAtPath:fontDir]) {
    const char *xdg = getenv("XDG_RUNTIME_DIR");
    NSString *base = (xdg && xdg[0]) ? @(xdg) : NSTemporaryDirectory();
    NSString *cacheDir =
        [base stringByAppendingPathComponent:@"fontconfig-cache"];
    [fm createDirectoryAtPath:cacheDir
        withIntermediateDirectories:YES
                         attributes:nil
                              error:NULL];
    NSString *confPath = [base stringByAppendingPathComponent:@"fonts.conf"];
    NSString *conf = [NSString
        stringWithFormat:@"<?xml version=\"1.0\"?>\n"
                         @"<!DOCTYPE fontconfig SYSTEM "
                         @"\"urn:fontconfig:fonts.dtd\">\n"
                         @"<fontconfig>\n"
                         @"  <dir>%@</dir>\n"
                         @"  <cachedir>%@</cachedir>\n"
                         @"  <alias><family>monospace</family>"
                         @"<prefer><family>DejaVuSansM Nerd Font Mono</family></prefer>"
                         @"<prefer><family>DejaVu Sans Mono</family></prefer>"
                         @"</alias>\n"
                         @"  <alias><family>sans-serif</family>"
                         @"<prefer><family>DejaVu Sans</family></prefer>"
                         @"</alias>\n"
                         @"  <alias><family>sans</family>"
                         @"<prefer><family>DejaVu Sans</family></prefer>"
                         @"</alias>\n"
                         @"  <alias><family>Sans</family>"
                         @"<prefer><family>DejaVu Sans</family></prefer>"
                         @"</alias>\n"
                         @"  <match target=\"pattern\">\n"
                         @"    <test name=\"family\"><string>sans-serif</string></test>\n"
                         @"    <edit name=\"family\" mode=\"prepend\" binding=\"strong\">\n"
                         @"      <string>DejaVu Sans</string>\n"
                         @"    </edit>\n"
                         @"  </match>\n"
                         @"  <config><rescan><int>30</int></rescan></config>\n"
                         @"</fontconfig>\n",
                         fontDir, cacheDir];
    if ([conf writeToFile:confPath
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:NULL]) {
      setenv("FONTCONFIG_FILE", confPath.UTF8String, 1);
      setenv("FONTCONFIG_PATH", base.UTF8String, 1);
      NSString *monoFont =
          [self firstExistingFont:@[
            @"truetype/DejaVuSansMNerdFontMono-Regular.ttf",
            @"truetype/DejaVuSansMono.ttf",
            @"truetype/dejavu/DejaVuSansMono.ttf"
          ]
                          under:fontDir];
      if (monoFont.length > 0) {
        setenv("WAWONA_MONO_FONT", monoFont.UTF8String, 1);
      }
      NSString *sansFont =
          [self firstExistingFont:@[ @"truetype/DejaVuSans.ttf",
                                     @"truetype/dejavu/DejaVuSans.ttf" ]
                          under:fontDir];
      if (sansFont.length > 0) {
        setenv("WAWONA_SANS_FONT", sansFont.UTF8String, 1);
      }
    }
  }
  WWNLog("SHELL", @"bundle share env; XDG_DATA_DIRS=%s FONTCONFIG_FILE=%s "
        @"WAWONA_MONO_FONT=%s WAWONA_SANS_FONT=%s",
        getenv("XDG_DATA_DIRS") ?: "(unset)",
        getenv("FONTCONFIG_FILE") ?: "(unset)",
        getenv("WAWONA_MONO_FONT") ?: "(unset)",
        getenv("WAWONA_SANS_FONT") ?: "(unset)");
}

+ (NSString *)firstExistingFont:(NSArray<NSString *> *)relPaths
                          under:(NSString *)fontDir {
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *rel in relPaths) {
    NSString *path = [fontDir stringByAppendingPathComponent:rel];
    if ([fm fileExistsAtPath:path]) {
      return path;
    }
  }
  NSString *leaf = relPaths.firstObject.lastPathComponent;
  if (leaf.length == 0) {
    return @"";
  }
  NSDirectoryEnumerator *en = [fm enumeratorAtPath:fontDir];
  NSString *rel;
  while ((rel = [en nextObject])) {
    if ([rel.lastPathComponent isEqualToString:leaf]) {
      return [fontDir stringByAppendingPathComponent:rel];
    }
  }
  return @"";
}

@end

// Strong definition: overrides the weak empty stub in WWNWatchStubs.c so
// callers of wwn_ios_refresh_bundle_env (shared Apple-mobile launch paths)
// get the same WESTON/FONTCONFIG/XKB/XDG share-tree env as +apply.
void wwn_ios_refresh_bundle_env(void) {
  [WWNWatchShellEnvironment apply];
}
