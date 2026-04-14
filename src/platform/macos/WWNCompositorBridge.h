//  WWNCompositorBridge.h
//  Objective-C bridge to Rust WWNCore via UniFFI Swift bindings
//
//  This bridge wraps the UniFFI-generated Swift API to make it accessible
//  from Objective-C code in the compositor.

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// Window event types from Rust compositor
typedef NS_ENUM(NSInteger, WWNWindowEventType) {
  WWNWindowEventTypeCreated,
  WWNWindowEventTypeDestroyed,
  WWNWindowEventTypeTitleChanged,
  WWNWindowEventTypeSizeChanged,
  WWNWindowEventTypeActivated,
  WWNWindowEventTypeCloseRequested,
};

/// C-compatible buffer data structure (mirrors Rust struct)
typedef struct {
  uint64_t window_id;
  uint32_t surface_id;
  uint64_t buffer_id;
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  uint32_t format;
  uint8_t *_Nullable pixels;
  size_t size;
  size_t capacity;
  uint32_t iosurface_id;
} CBufferData;

/// Bridge between Objective-C and Rust compositor
@interface WWNCompositorBridge : NSObject

/// Shared singleton instance
+ (instancetype)sharedBridge;

// MARK: - Lifecycle

/// Initialize and start the Rust compositor
/// @param socketName Wayland socket name (defaults to "wayland-0" if nil)
/// @return YES if successful, NO otherwise
- (BOOL)startWithSocketName:(NSString *_Nullable)socketName;

/// Stop the compositor
- (void)stop;

/// Check if compositor is running
- (BOOL)isRunning;

/// Get the Wayland socket path
- (NSString *)socketPath;

/// Get the Wayland socket name
- (NSString *)socketName;

// MARK: - Event Processing

/// Flush client event queues
- (void)flushClients;

/// Poll and handle window events, calling platform callbacks
- (void)pollAndHandleWindowEvents;

// MARK: - Input Injection

- (void)injectPointerMotionForWindow:(uint64_t)windowId
                                   x:(double)x
                                   y:(double)y
                           timestamp:(uint32_t)timestampMs;

- (void)injectPointerEnterForWindow:(uint64_t)windowId
                                  x:(double)x
                                  y:(double)y
                          timestamp:(uint32_t)timestampMs;

- (void)injectPointerLeaveForWindow:(uint64_t)windowId
                          timestamp:(uint32_t)timestampMs;

/// Inject pointer button
- (void)injectPointerButtonForWindow:(uint64_t)windowId
                              button:(uint32_t)button
                             pressed:(BOOL)pressed
                           timestamp:(uint32_t)timestampMs;

/// Inject pointer axis (scroll)
- (void)injectPointerAxisForWindow:(uint64_t)windowId
                              axis:(uint32_t)axis
                             value:(double)value
                          discrete:(int32_t)discrete
                         timestamp:(uint32_t)timestampMs;

/// Inject key event
- (void)injectKeyWithKeycode:(uint32_t)keycode
                     pressed:(BOOL)pressed
                   timestamp:(uint32_t)timestampMs;

- (void)injectKeyboardEnterForWindow:(uint64_t)windowId
                                keys:(NSArray<NSNumber *> *)keys;

- (void)injectKeyboardLeaveForWindow:(uint64_t)windowId;

- (void)injectWindowResize:(uint64_t)windowId
                     width:(uint32_t)width
                    height:(uint32_t)height;

- (void)setWindowActivated:(uint64_t)windowId active:(BOOL)active;

/// Inject keyboard modifiers
- (void)injectModifiersWithDepressed:(uint32_t)depressed
                             latched:(uint32_t)latched
                              locked:(uint32_t)locked
                               group:(uint32_t)group;

// MARK: - Touch Injection

- (void)injectTouchDown:(NSInteger)touchId
                      x:(double)x
                      y:(double)y
              timestamp:(uint32_t)timestampMs;

- (void)injectTouchUp:(NSInteger)touchId timestamp:(uint32_t)timestampMs;

- (void)injectTouchMotion:(NSInteger)touchId
                        x:(double)x
                        y:(double)y
                timestamp:(uint32_t)timestampMs;

- (void)injectTouchCancel;

- (void)injectTouchFrame;

// MARK: - Text Input (IME / Emoji)

/// Commit a composed string (emoji, IME output, etc.) to the focused
/// Wayland client via text-input-v3.
- (void)textInputCommitString:(NSString *)text;

/// Send a preedit (composition preview) string via text-input-v3.
- (void)textInputPreeditString:(NSString *)text
                   cursorBegin:(int32_t)cursorBegin
                     cursorEnd:(int32_t)cursorEnd;

/// Delete surrounding text relative to the cursor.
- (void)textInputDeleteSurrounding:(uint32_t)beforeLength
                       afterLength:(uint32_t)afterLength;

/// Get the cursor rectangle reported by the focused Wayland client.
/// Returns CGRectZero if no text input is active.
- (CGRect)textInputCursorRect;

// MARK: - Configuration

/// Set output size and scale
- (void)setOutputWidth:(uint32_t)width
                height:(uint32_t)height
                 scale:(float)scale;

/// Set platform safe area insets (iOS notch, home indicator, rounded corners)
- (void)setSafeAreaInsetsTop:(int32_t)top
                       right:(int32_t)right
                      bottom:(int32_t)bottom
                        left:(int32_t)left;

/// Set force server-side decorations
- (void)setForceSSD:(BOOL)enabled;

/// Set keyboard repeat rate
- (void)setKeyboardRepeatRate:(int32_t)rate delay:(int32_t)delay;

// MARK: - Rendering

/// Notify that frame rendering is complete
- (void)notifyFrameComplete;

/// Notify frame presented for surface
- (void)notifyFramePresentedForSurface:(uint32_t)surfaceId
                                buffer:(uint64_t)bufferId
                             timestamp:(uint32_t)timestamp;

/// Flush frame callbacks
- (void)flushFrameCallbacks;

/// Get windows needing redraw
/// @return Array of window IDs (NSNumber wrapping uint64_t)
- (NSArray<NSNumber *> *)pollRedrawRequests;

// MARK: - Window Event Polling

/// Get count of pending window creation events
- (NSUInteger)pendingWindowCount;

/// Pop next pending window creation info
/// @return Dictionary with windowId, width, height, title keys, or nil if none
- (nullable NSDictionary *)popPendingWindow;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@property(nonatomic, weak) UIView *containerView;
#else
/// YES when any connected client has requested cursor management through
/// either wp_cursor_shape (named shapes) or wl_pointer.set_cursor (bitmaps).
@property(nonatomic, readonly) BOOL clientWantsCursorRendered;
#endif

@end

@interface WWNCompositorBridge (Buffer)

/// Pop next pending buffer update
/// Returns pointer to CBufferData or NULL if none
/// Caller must free with freeBufferData:
- (nullable CBufferData *)popPendingBuffer;

/// Free buffer data structure
- (void)freeBufferData:(CBufferData *)data;

@end

NS_ASSUME_NONNULL_END
