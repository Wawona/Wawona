#import "WWNRootfsProvider.h"

#if TARGET_OS_IPHONE
#import "../ios/WWNRootfsManager.h"
#endif

#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
#import "WWNRootfsICloudSync.h"
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

#if TARGET_OS_OSX
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
#endif

@implementation WWNRootfsProvider

+ (WWNRootfsCapabilities)capabilities {
  WWNRootfsCapabilities caps = WWNRootfsCapabilityNone;
#if TARGET_OS_TV
  caps = WWNRootfsCapabilitySettings | WWNRootfsCapabilityResetDotfiles |
         WWNRootfsCapabilityReinstallSystemTree;
#elif TARGET_OS_IPHONE
  caps = WWNRootfsCapabilitySettings | WWNRootfsCapabilityResetDotfiles |
         WWNRootfsCapabilityReinstallSystemTree |
         WWNRootfsCapabilityBrowseUserFiles | WWNRootfsCapabilityImportFile;
#elif TARGET_OS_OSX
  caps = WWNRootfsCapabilitySettings | WWNRootfsCapabilityBrowseUserFiles;
#endif
#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
  if ([WWNRootfsICloudSync isSupported]) {
    caps |= WWNRootfsCapabilityICloudSync;
  }
#endif
  return caps;
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
  if ([WWNRootfsICloudSync isEnabled] && [WWNRootfsICloudSync isContainerAvailable]) {
    snap[@"filesHint"] =
        @"iCloud Drive → Wawona → home/ (also in Files on Vision Pro).";
  } else {
    snap[@"filesHint"] =
        @"Files → On My Vision Pro → Wawona → Wawona → home/";
  }
#else
  if ([WWNRootfsICloudSync isEnabled] && [WWNRootfsICloudSync isContainerAvailable]) {
    snap[@"filesHint"] =
        @"iCloud Drive → Wawona → home/ (and On My iPhone → Wawona).";
  } else {
    snap[@"filesHint"] =
        @"Files → On My iPhone/iPad → Wawona → Wawona → home/";
  }
#endif
  return snap;
#elif TARGET_OS_OSX
  NSMutableDictionary *snap = [WWNRootfsHostSnapshot() mutableCopy];
  snap[@"iCloudSync"] = [WWNRootfsICloudSync isEnabled] ? @"On" : @"Off";
  snap[@"iCloudStatus"] = [WWNRootfsICloudSync statusSummary];
  if ([WWNRootfsICloudSync isEnabled]) {
    snap[@"filesHint"] =
        @"iCloud Drive → Wawona → home/ syncs with iPhone, iPad, and Vision Pro.";
  }
  return snap;
#else
  return @{};
#endif
}

+ (void)prepareUserAccess {
#if TARGET_OS_IPHONE
  [WWNRootfsManager prepareFilesAppAccess];
#elif (TARGET_OS_OSX && !TARGET_OS_TV)
  [WWNRootfsICloudSync prepareICloudLayout];
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
  return [[NSWorkspace sharedWorkspace]
      openURL:[NSURL fileURLWithPath:path isDirectory:YES]];
#elif TARGET_OS_IPHONE
  // No public API to deep-link Files.app to a folder; caller shows instructions.
  return NO;
#else
  return NO;
#endif
}

#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV

+ (BOOL)isICloudSyncSupported {
  return [WWNRootfsICloudSync isSupported];
}

+ (BOOL)isICloudSyncEnabled {
  return [WWNRootfsICloudSync isEnabled];
}

+ (BOOL)setICloudSyncEnabled:(BOOL)enabled
                       error:(NSError * _Nullable * _Nullable)error {
  return [WWNRootfsICloudSync setEnabled:enabled error:error];
}

#endif

@end
