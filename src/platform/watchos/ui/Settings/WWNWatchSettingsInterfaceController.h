#import <WatchKit/WatchKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNWatchSettingsRootInterfaceController : WKInterfaceController
@end

@interface WWNWatchSettingsDetailInterfaceController : WKInterfaceController
@end

@interface WWNWatchSettingsActionRowController : NSObject
@property (weak, nonatomic) IBOutlet WKInterfaceLabel *titleLabel;
@property (weak, nonatomic) IBOutlet WKInterfaceLabel *valueLabel;
@end

NS_ASSUME_NONNULL_END
