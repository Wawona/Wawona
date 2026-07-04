//
//  WWNPopupHost.h
//  WWN
//
//  Created by WWN Agent.
//

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
typedef UIView WWNNativeView;
#else
#import <Cocoa/Cocoa.h>
typedef NSView WWNNativeView;
#endif

NS_ASSUME_NONNULL_BEGIN

@protocol WWNPopupHost <NSObject>

@required
@property(nonatomic, readonly) WWNNativeView *contentView;
@property(nonatomic, readonly) WWNNativeView *parentView;
- (instancetype)initWithParentView:(WWNNativeView *)parentView;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)showAtPoint:(CGPoint)point inView:(UIView *)parentView;
#else
- (void)showAtScreenPoint:(CGPoint)point;
- (void)showAtScreenRect:(NSRect)screenFrame;
#endif

- (void)dismiss;

// Update content size (Wayland configure event)
- (void)setContentSize:(CGSize)size;

// Set the window ID for content mapping
@property(nonatomic, assign) uint64_t windowId;

// Callback for when the popup is dismissed by user (e.g. click outside)
@property(nonatomic, copy, nullable) void (^onDismiss)(void);

@end

NS_ASSUME_NONNULL_END
