#import "WWNRootfsProvider.h"

#if TARGET_OS_IPHONE
#import "../ios/WWNRootfsManager.h"
#endif

#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

static NSString *WWNRootfsPlatformLabel(void) {
#if defined(TARGET_OS_VISION) && TARGET_OS_VISION
  return @"visionOS";
#elif TARGET_OS_TV
  return @"tvOS";
#elif TARGET_OS_IPHONE
  return @"iOS";
#elif TARGET_OS_OSX
  return @"macOS";
#else
  return @"Apple";
#endif
}

static NSDictionary<NSString *, NSString *> *WWNRootfsHostSnapshot(void) {
  NSString *home = NSHomeDirectory() ?: @"";
  NSString *shell = NSProcessInfo.processInfo.environment[@"SHELL"] ?: @"/bin/zsh";
  NSString *xdgRuntime = NSProcessInfo.processInfo.environment[@"XDG_RUNTIME_DIR"] ?: @"";
  return @{
    @"mode" : @"host",
    @"filesRoot" : home,
    @"home" : home,
    @"systemRoot" : xdgRuntime.length ? xdgRuntime : @"(host system — no bundled rootfs)",
    @"bundleTemplateVersion" : @"—",
    @"appliedTemplateVersion" : @"—",
    @"filesHint" : @"Finder → Go → Home, or open Terminal with your login shell.",
    @"platformLabel" : WWNRootfsPlatformLabel(),
    @"shellPath" : shell,
  };
}

@implementation WWNRootfsProvider

+ (WWNRootfsCapabilities)capabilities {
#if TARGET_OS_TV
  return WWNRootfsCapabilitySettings | WWNRootfsCapabilityResetDotfiles |
         WWNRootfsCapabilityReinstallSystemTree;
#elif TARGET_OS_IPHONE
  return WWNRootfsCapabilitySettings | WWNRootfsCapabilityResetDotfiles |
         WWNRootfsCapabilityReinstallSystemTree |
         WWNRootfsCapabilityBrowseUserFiles | WWNRootfsCapabilityImportFile;
#elif TARGET_OS_OSX
  return WWNRootfsCapabilitySettings | WWNRootfsCapabilityBrowseUserFiles;
#else
  return WWNRootfsCapabilityNone;
#endif
}

+ (NSDictionary<NSString *, NSString *> *)snapshot {
#if TARGET_OS_IPHONE
  [WWNRootfsManager prepareFilesAppAccess];
  NSMutableDictionary *snap =
      [[WWNRootfsManager rootfsStatusSnapshot] mutableCopy];
  snap[@"mode"] = @"bundled";
  snap[@"platformLabel"] = WWNRootfsPlatformLabel();
#if TARGET_OS_TV
  snap[@"filesHint"] =
      @"tvOS has no Files app; use Reset/Reinstall below.";
#elif defined(TARGET_OS_VISION) && TARGET_OS_VISION
  snap[@"filesHint"] =
      @"Files → On My Vision Pro → Wawona → Wawona → home/";
#else
  snap[@"filesHint"] =
      @"Files → On My iPhone/iPad → Wawona → Wawona → home/";
#endif
  return snap;
#elif TARGET_OS_OSX
  return WWNRootfsHostSnapshot();
#else
  return @{};
#endif
}

+ (void)prepareUserAccess {
#if TARGET_OS_IPHONE
  [WWNRootfsManager prepareFilesAppAccess];
#endif
}

+ (BOOL)refreshShellDotfiles:(NSError **)error {
#if TARGET_OS_IPHONE
  return [WWNRootfsManager refreshShellDotfiles:error];
#else
  if (error) {
    *error = [NSError errorWithDomain:@"WWNRootfs"
                                 code:100
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Reset dotfiles is only available with a bundled shell rootfs."
                             }];
  }
  return NO;
#endif
}

+ (BOOL)reinstallSystemTree:(NSError **)error {
#if TARGET_OS_IPHONE
  return [WWNRootfsManager reinstallSystemTree:error];
#else
  if (error) {
    *error = [NSError errorWithDomain:@"WWNRootfs"
                                 code:101
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Reinstall system tree is only available with a bundled shell rootfs."
                             }];
  }
  return NO;
#endif
}

+ (void)applyShellEnvironment {
#if TARGET_OS_IPHONE
  [WWNRootfsManager applyShellEnvironment];
#endif
}

+ (BOOL)openUserFilesLocation {
  NSDictionary *snap = [self snapshot];
  NSString *path = snap[@"filesRoot"];
  if (path.length == 0) {
    return NO;
  }
#if TARGET_OS_OSX
  return [[NSWorkspace sharedWorkspace] openFile:path];
#elif TARGET_OS_IPHONE
  // No public API to deep-link Files.app to a folder; caller shows instructions.
  return NO;
#else
  return NO;
#endif
}

@end
