#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
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

/// Plain CALayer host for nested Wayland SHM/IOSurface clients (not Metal).
@property(nonatomic, strong, readonly) CALayer *waylandLayer;

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

/// Prepare Metal + iland present callback for nested Weston (DRM/GL overlay).
- (BOOL)prepareIlandMetalPresentation;

/// When YES, Wayland SHM/IOSurface clients are visible and the Metal layer is
/// hidden so CAMetalLayer compositing cannot cover nested client surfaces.
- (void)setWaylandPresentationActive:(BOOL)active;

/// Present a Wayland SHM frame. Uses a plain UIView layer (not nested CALayers
/// under CAMetalLayer) because iOS does not reliably composite the latter.
- (void)presentWaylandFrame:(nullable CGImageRef)image
                      frame:(CGRect)frame
                contentRect:(CGRect)normalizedContentRect
               presentToken:(uint64_t)presentToken;

/// Tear down presentation state before the view is removed (session close).
- (void)prepareForSessionTeardown;

/// Switch from Metal to legacy CALayer subpresentation (IOSurface fallback).
- (void)prepareWaylandLayerSubpresentation;

/// Configure whether the SHM frame host should be treated as opaque.
/// Popups with client-drawn shadows should disable opacity.
- (void)setWaylandFrameOpaque:(BOOL)opaque;

// Virtual pointer control (game controllers, GCMouse, external drivers).
// Moves/clicks the same virtual cursor used by touchpad mode.
- (void)moveVirtualPointerByDx:(CGFloat)dx dy:(CGFloat)dy;
- (void)clickVirtualPointerButton:(uint32_t)linuxButtonCode
                          pressed:(BOOL)pressed;
- (void)scrollVirtualPointerByDx:(CGFloat)dx dy:(CGFloat)dy;

@end

NS_ASSUME_NONNULL_END
