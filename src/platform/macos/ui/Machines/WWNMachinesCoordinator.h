#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface WWNMachinesCoordinator : NSObject

+ (instancetype)sharedCoordinator;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (nullable UIViewController *)buildMachinesViewControllerWithOnConnect:
    (dispatch_block_t)onConnect;
- (void)presentMachinesFromViewController:(UIViewController *)presenter
                                onConnect:(dispatch_block_t)onConnect;
#else
- (void)showMachinesWindowAndActivate:(BOOL)activate;
- (void)showMachinesWindowFromMenu:(id)sender;
#endif

@end

NS_ASSUME_NONNULL_END
