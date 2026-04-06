#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

NS_ASSUME_NONNULL_BEGIN

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@interface WWNAboutPanel : UIViewController
#else
@interface WWNAboutPanel : NSWindowController
#endif

+ (instancetype)sharedAboutPanel;
- (void)showAboutPanel:(id)sender;

@end

NS_ASSUME_NONNULL_END

