/*
 * WWNStartupLogViewController. Shows a native scrollable log overlay
 * during the Wayland client launch transition.
 *
 * Presented over the compositor container between "Run" and the first
 * Wayland frame being presented.  The user can scroll, select, and copy
 * any text.  Fades out automatically on the first frame or on tap.
 */

#ifndef WWNStartupLogViewController_h
#define WWNStartupLogViewController_h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNStartupLogViewController : UIViewController

/// Machine/client label displayed in the header (e.g. "weston-terminal").
@property (nonatomic, copy, nullable) NSString *clientLabel;

/// Fade out and call the completion block when dismissed.
- (void)dismissWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END

#endif /* WWNStartupLogViewController_h */
