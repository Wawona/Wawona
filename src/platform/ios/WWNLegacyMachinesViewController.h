#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// UIKit-only Machines host for iOS 11 and 12.  It deliberately contains no
/// compositor policy: profiles and session startup stay behind the existing
/// Rust-backed bridge.
@interface WWNLegacyMachinesViewController : UITableViewController

- (instancetype)initWithOnConnect:(nullable dispatch_block_t)onConnect;

@end

NS_ASSUME_NONNULL_END
