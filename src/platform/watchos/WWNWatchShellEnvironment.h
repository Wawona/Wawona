#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs bundled wawona-rootfs templates (when present) and sets
/// WAWONA_ZSH_IN_PROCESS / HOME / SHELL for the App Store–compliant
/// in-process zsh path. Call before launching weston-terminal / foot.
@interface WWNWatchShellEnvironment : NSObject
+ (void)apply;
@end

NS_ASSUME_NONNULL_END
