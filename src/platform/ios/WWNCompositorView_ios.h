#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * WWNCompositorView_ios
 *
 * An iOS view that represents a Wayland surface.
 * It uses a CAMetalLayer for content rendering (iland GL present + IOSurface)
 * and translates UIKit touches to Wayland pointer events.
 *
 * Conforms to UITextInput for full IME/autocorrect/dictation support and
 * UIKeyInput as fallback.
 */
@interface WWNCompositorView_ios : UIView <UITextInput>

/// The Wayland window ID associated with this view
@property(nonatomic, assign) uint64_t wwnWindowId;

/// Access to the Metal content layer for rendering (WWNIlandPresenter target)
@property(nonatomic, strong, readonly) CAMetalLayer *contentLayer;

/// Whether the keyboard is currently active for this view
@property(nonatomic, assign, readonly) BOOL keyboardActive;

/// Show the iOS virtual keyboard for this view
- (void)activateKeyboard;

/// Hide the iOS virtual keyboard for this view
- (void)deactivateKeyboard;

/// Update the Wayland cursor image displayed in touchpad mode.
/// Pass nil to hide the cursor.
- (void)updateCursorImage:(nullable id)image
                    width:(uint32_t)width
                   height:(uint32_t)height
                 hotspotX:(float)hotspotX
                 hotspotY:(float)hotspotY;

/// Launch in-process kmscube (iland + ANGLE) into this view's Metal layer.
- (BOOL)launchNestedKmscube;

@end

NS_ASSUME_NONNULL_END
