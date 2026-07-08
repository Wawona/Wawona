//
//  WWNPopupWindow.m
//  WWN
//

#import "WWNPopupWindow.h"
#import "../../util/WWNLog.h"
#import "WWNWindow.h"

@implementation WWNPopupWindow {
  WWNNativeView *_parentView;
  __weak NSWindow *_parentWindow;
  CGSize _contentSize;
  BOOL _dismissed;
}

@synthesize contentView = _contentView;
@synthesize parentView = _parentView;
@synthesize onDismiss = _onDismiss;
@synthesize windowId = _windowId;

- (instancetype)initWithParentView:(WWNNativeView *)parentView {
  self = [super init];
  if (self) {
    _parentView = parentView;
    _contentSize = CGSizeMake(100, 100);

    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                          styleMask:NSWindowStyleMaskBorderless
                                            backing:NSBackingStoreBuffered
                                              defer:NO];

    _window.backgroundColor = [NSColor clearColor];
    // xdg_popup content (menus, tooltips) already paints its own CSD shadow
    // when the client wants one; AppKit's window shadow additionally boxes
    // the borderless popup in a rectangular drop shadow that doesn't match
    // the client's actual (often non-rectangular / partially transparent)
    // popup shape, showing up as an unwanted halo. Disable it here so it's
    // suppressed uniformly for both native in-process and remote (waypipe)
    // Weston clients.
    _window.hasShadow = NO;
    _window.opaque = NO;
    // Menu-like stacking so popups can extend beyond the parent window frame.
    _window.level = NSPopUpMenuWindowLevel;
    _window.releasedWhenClosed = NO;
    _window.ignoresMouseEvents = NO;

    WWNView *v = [[WWNView alloc] initWithFrame:_window.contentView.bounds];
    v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _window.contentView = v;
    _contentView = v;
  }
  return self;
}

- (void)setWindowId:(uint64_t)windowId {
  _windowId = windowId;
  if ([_contentView isKindOfClass:[WWNView class]]) {
    [(WWNView *)_contentView setOverrideWindowId:windowId];
  }
}

- (void)setContentSize:(CGSize)size {
  _contentSize = size;
  [_window setContentSize:size];
}

- (void)showAtScreenRect:(NSRect)screenFrame {
  [_window setFrame:screenFrame display:YES];
  NSWindow *parentWin = _parentView.window;
  if (parentWin) {
    if (!_parentWindow) {
      _parentWindow = parentWin;
      [parentWin addChildWindow:_window ordered:NSWindowAbove];
      WWNLog("POPUP-WIN",
             @"Added popup %llu as child window of parent %p (screen frame "
             @"%.0f,%.0f %.0fx%.0f)",
             _windowId, parentWin, screenFrame.origin.x, screenFrame.origin.y,
             screenFrame.size.width, screenFrame.size.height);
    }
  }
  [_window orderFront:nil];
}

- (void)showAtScreenPoint:(CGPoint)point {
  [self showAtScreenRect:NSMakeRect(point.x, point.y, _contentSize.width,
                                    _contentSize.height)];
}

- (void)dismiss {
  // wwnRemovePopupHost:windowId: invokes -dismiss and then (via onDismiss)
  // re-enters the bridge's popup-dismissed handler, which looks the popup
  // back up and calls -dismiss again before the first call has returned.
  // Without this guard that round-trip recurses forever (dismiss ->
  // onDismiss -> handlePopupDismissed -> wwnRemovePopupHost -> dismiss ->
  // ...) and crashes with a stack overflow. Make dismiss idempotent so the
  // re-entrant call is a no-op.
  if (_dismissed) {
    return;
  }
  _dismissed = YES;

  if (_parentWindow) {
    [_parentWindow removeChildWindow:_window];
    _parentWindow = nil;
  }
  [_window orderOut:nil];
  if (self.onDismiss) {
    void (^callback)(void) = self.onDismiss;
    self.onDismiss = nil;
    callback();
  }
}

@end
