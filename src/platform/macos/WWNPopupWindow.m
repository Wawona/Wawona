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
    _window.hasShadow = YES;
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
  if (_parentWindow) {
    [_parentWindow removeChildWindow:_window];
    _parentWindow = nil;
  }
  [_window orderOut:nil];
  if (self.onDismiss) {
    self.onDismiss();
  }
}

@end
