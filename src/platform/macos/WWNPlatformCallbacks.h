//  WWNPlatformCallbacks.h
//  Platform callbacks that Rust compositor calls for native operations

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// Canonical bundle / resource path resolution (all Apple platforms).
FOUNDATION_EXPORT NSString *WWNWawonaAppBundleRoot(void);
FOUNDATION_EXPORT NSString *WWNWawonaAppBundleRootForUI(void);
FOUNDATION_EXPORT NSString *WWNWawonaExecutableDirectory(void);
FOUNDATION_EXPORT NSString *WWNWawonaResourcesRoot(void);
FOUNDATION_EXPORT NSString *WWNWawonaShareRoot(void);
FOUNDATION_EXPORT NSString *WWNWawonaLibRoot(void);
FOUNDATION_EXPORT NSString *WWNWawonaBundledSharePath(NSString *relativePath);
FOUNDATION_EXPORT NSString *_Nullable WWNWawonaBundledResourcePath(NSString *filename);
FOUNDATION_EXPORT NSString *_Nullable WWNWawonaFindBundledExecutable(NSString *name);
FOUNDATION_EXPORT void WWNConfigureBundledRuntimeEnvIfNeeded(void);
FOUNDATION_EXPORT void wwn_ios_refresh_bundle_env(void);

/// Platform callbacks interface for Rust → macOS/iOS communication
@protocol WWNPlatformCallbacksProtocol <NSObject>

// Window management
- (void)createNativeWindowWithId:(uint64_t)windowId
                           width:(int32_t)width
                          height:(int32_t)height
                           title:(NSString *_Nullable)title
                          useSSD:(BOOL)useSSD;

- (void)destroyNativeWindowWithId:(uint64_t)windowId;
- (void)setWindowTitle:(NSString *)title forWindowId:(uint64_t)windowId;
- (void)setWindowSize:(CGSize)size forWindowId:(uint64_t)windowId;

// Rendering
- (void)requestRenderForWindowId:(uint64_t)windowId;

@end

/// Implementation of platform callbacks
@interface WWNPlatformCallbacks : NSObject <WWNPlatformCallbacksProtocol>

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, NSWindow *> *windowRegistry;
#else
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, UIWindow *> *windowRegistry;
#endif

+ (instancetype)sharedCallbacks;

@end

NS_ASSUME_NONNULL_END
