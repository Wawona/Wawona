#import "WWNCompositorView_ios.h"
#import "WWNIlandPresenter.h"
#import "../macos/ui/Settings/WWNPreferencesManager.h"
#import "../../util/WWNLog.h"
#import "WWNCompositorBridge.h"
#import <QuartzCore/QuartzCore.h>
#import <TargetConditionals.h>
#import <math.h>
#import <string.h>

extern int wwn_ios_terminal_is_active(void);
extern ssize_t wwn_ios_terminal_inject(const void *buf, size_t len);

// ===========================================================================
// UITextPosition / UITextRange subclasses for UITextInput
// ===========================================================================

@interface WWNTextPosition : UITextPosition
@property(nonatomic, assign) NSInteger index;
+ (instancetype)positionWithIndex:(NSInteger)index;
@end

@implementation WWNTextPosition
+ (instancetype)positionWithIndex:(NSInteger)index {
  WWNTextPosition *p = [[WWNTextPosition alloc] init];
  p.index = index;
  return p;
}
@end

@interface WWNTextRange : UITextRange
@property(nonatomic, strong) WWNTextPosition *start;
@property(nonatomic, strong) WWNTextPosition *end;
+ (instancetype)rangeWithStart:(NSInteger)start end:(NSInteger)end;
@end

@implementation WWNTextRange
@synthesize start = _start;
@synthesize end = _end;
+ (instancetype)rangeWithStart:(NSInteger)s end:(NSInteger)e {
  WWNTextRange *r = [[WWNTextRange alloc] init];
  r.start = [WWNTextPosition positionWithIndex:s];
  r.end = [WWNTextPosition positionWithIndex:e];
  return r;
}
- (BOOL)isEmpty {
  return self.start.index == self.end.index;
}
@end

// ---------------------------------------------------------------------------
// Linux input-event-codes.h key definitions
// ---------------------------------------------------------------------------
enum {
  KEY_RESERVED = 0,
  KEY_ESC = 1,
  KEY_1 = 2,
  KEY_2 = 3,
  KEY_3 = 4,
  KEY_4 = 5,
  KEY_5 = 6,
  KEY_6 = 7,
  KEY_7 = 8,
  KEY_8 = 9,
  KEY_9 = 10,
  KEY_0 = 11,
  KEY_MINUS = 12,
  KEY_EQUAL = 13,
  KEY_BACKSPACE = 14,
  KEY_TAB = 15,
  KEY_Q = 16,
  KEY_W = 17,
  KEY_E = 18,
  KEY_R = 19,
  KEY_T = 20,
  KEY_Y = 21,
  KEY_U = 22,
  KEY_I = 23,
  KEY_O = 24,
  KEY_P = 25,
  KEY_LEFTBRACE = 26,
  KEY_RIGHTBRACE = 27,
  KEY_ENTER = 28,
  KEY_LEFTCTRL = 29,
  KEY_A = 30,
  KEY_S = 31,
  KEY_D = 32,
  KEY_F = 33,
  KEY_G = 34,
  KEY_H = 35,
  KEY_J = 36,
  KEY_K = 37,
  KEY_L = 38,
  KEY_SEMICOLON = 39,
  KEY_APOSTROPHE = 40,
  KEY_GRAVE = 41,
  KEY_LEFTSHIFT = 42,
  KEY_BACKSLASH = 43,
  KEY_Z = 44,
  KEY_X = 45,
  KEY_C = 46,
  KEY_V = 47,
  KEY_B = 48,
  KEY_N = 49,
  KEY_M = 50,
  KEY_COMMA = 51,
  KEY_DOT = 52,
  KEY_SLASH = 53,
  KEY_RIGHTSHIFT = 54,
  KEY_LEFTALT = 56,
  KEY_SPACE = 57,
  KEY_CAPSLOCK = 58,
  KEY_F1 = 59,
  KEY_F2 = 60,
  KEY_F3 = 61,
  KEY_F4 = 62,
  KEY_F5 = 63,
  KEY_F6 = 64,
  KEY_F7 = 65,
  KEY_F8 = 66,
  KEY_F9 = 67,
  KEY_F10 = 68,
  KEY_F11 = 87,
  KEY_F12 = 88,
  KEY_RIGHTCTRL = 97,
  KEY_RIGHTALT = 100,
  KEY_HOME = 102,
  KEY_UP = 103,
  KEY_PAGEUP = 104,
  KEY_LEFT = 105,
  KEY_RIGHT = 106,
  KEY_END = 107,
  KEY_DOWN = 108,
  KEY_PAGEDOWN = 109,
  KEY_DELETE = 111,
  KEY_LEFTMETA = 125,
  KEY_RIGHTMETA = 126,
};

// Linux button codes (input-event-codes.h)
static const uint32_t BTN_LEFT = 0x110;
static const uint32_t BTN_RIGHT = 0x111;

/// Map a single Unicode character to a Linux keycode and whether Shift is
/// needed
static BOOL charToLinuxKeycode(unichar ch, uint32_t *outKeycode,
                               BOOL *outNeedsShift) {
  *outNeedsShift = NO;

  if (ch >= 'a' && ch <= 'z') {
    static const uint32_t letterKeys[] = {
        KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I,
        KEY_J, KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R,
        KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
    };
    *outKeycode = letterKeys[ch - 'a'];
    return YES;
  }

  if (ch >= 'A' && ch <= 'Z') {
    static const uint32_t letterKeys[] = {
        KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I,
        KEY_J, KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R,
        KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
    };
    *outKeycode = letterKeys[ch - 'A'];
    *outNeedsShift = YES;
    return YES;
  }

  if (ch >= '1' && ch <= '9') {
    *outKeycode = KEY_1 + (ch - '1');
    return YES;
  }
  if (ch == '0') {
    *outKeycode = KEY_0;
    return YES;
  }

  switch (ch) {
  case ' ':
    *outKeycode = KEY_SPACE;
    return YES;
  case '\n':
  case '\r':
    *outKeycode = KEY_ENTER;
    return YES;
  case '\t':
    *outKeycode = KEY_TAB;
    return YES;
  case '-':
    *outKeycode = KEY_MINUS;
    return YES;
  case '=':
    *outKeycode = KEY_EQUAL;
    return YES;
  case '[':
    *outKeycode = KEY_LEFTBRACE;
    return YES;
  case ']':
    *outKeycode = KEY_RIGHTBRACE;
    return YES;
  case '\\':
    *outKeycode = KEY_BACKSLASH;
    return YES;
  case ';':
    *outKeycode = KEY_SEMICOLON;
    return YES;
  case '\'':
    *outKeycode = KEY_APOSTROPHE;
    return YES;
  case '`':
    *outKeycode = KEY_GRAVE;
    return YES;
  case ',':
    *outKeycode = KEY_COMMA;
    return YES;
  case '.':
    *outKeycode = KEY_DOT;
    return YES;
  case '/':
    *outKeycode = KEY_SLASH;
    return YES;
  case '!':
    *outKeycode = KEY_1;
    *outNeedsShift = YES;
    return YES;
  case '@':
    *outKeycode = KEY_2;
    *outNeedsShift = YES;
    return YES;
  case '#':
    *outKeycode = KEY_3;
    *outNeedsShift = YES;
    return YES;
  case '$':
    *outKeycode = KEY_4;
    *outNeedsShift = YES;
    return YES;
  case '%':
    *outKeycode = KEY_5;
    *outNeedsShift = YES;
    return YES;
  case '^':
    *outKeycode = KEY_6;
    *outNeedsShift = YES;
    return YES;
  case '&':
    *outKeycode = KEY_7;
    *outNeedsShift = YES;
    return YES;
  case '*':
    *outKeycode = KEY_8;
    *outNeedsShift = YES;
    return YES;
  case '(':
    *outKeycode = KEY_9;
    *outNeedsShift = YES;
    return YES;
  case ')':
    *outKeycode = KEY_0;
    *outNeedsShift = YES;
    return YES;
  case '_':
    *outKeycode = KEY_MINUS;
    *outNeedsShift = YES;
    return YES;
  case '+':
    *outKeycode = KEY_EQUAL;
    *outNeedsShift = YES;
    return YES;
  case '{':
    *outKeycode = KEY_LEFTBRACE;
    *outNeedsShift = YES;
    return YES;
  case '}':
    *outKeycode = KEY_RIGHTBRACE;
    *outNeedsShift = YES;
    return YES;
  case '|':
    *outKeycode = KEY_BACKSLASH;
    *outNeedsShift = YES;
    return YES;
  case ':':
    *outKeycode = KEY_SEMICOLON;
    *outNeedsShift = YES;
    return YES;
  case '"':
    *outKeycode = KEY_APOSTROPHE;
    *outNeedsShift = YES;
    return YES;
  case '~':
    *outKeycode = KEY_GRAVE;
    *outNeedsShift = YES;
    return YES;
  case '<':
    *outKeycode = KEY_COMMA;
    *outNeedsShift = YES;
    return YES;
  case '>':
    *outKeycode = KEY_DOT;
    *outNeedsShift = YES;
    return YES;
  case '?':
    *outKeycode = KEY_SLASH;
    *outNeedsShift = YES;
    return YES;
  }

  return NO;
}

// ---------------------------------------------------------------------------
// HID Usage Page 0x07 (Keyboard) → Linux input-event-codes keycode mapping.
// Used by pressesBegan/pressesEnded to translate physical keyboard events.
// ---------------------------------------------------------------------------
static uint32_t hidUsageToLinuxKeycode(long hidUsage) {
  // Letters: HID 0x04 (A) .. 0x1D (Z)
  if (hidUsage >= 0x04 && hidUsage <= 0x1D) {
    static const uint32_t map[26] = {
        KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I,
        KEY_J, KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R,
        KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
    };
    return map[hidUsage - 0x04];
  }
  // Digits: HID 0x1E (1) .. 0x26 (9), 0x27 (0)
  if (hidUsage >= 0x1E && hidUsage <= 0x26)
    return KEY_1 + (uint32_t)(hidUsage - 0x1E);
  if (hidUsage == 0x27)
    return KEY_0;

  switch (hidUsage) {
  case 0x28:
    return KEY_ENTER;
  case 0x29:
    return KEY_ESC;
  case 0x2A:
    return KEY_BACKSPACE;
  case 0x2B:
    return KEY_TAB;
  case 0x2C:
    return KEY_SPACE;
  case 0x2D:
    return KEY_MINUS;
  case 0x2E:
    return KEY_EQUAL;
  case 0x2F:
    return KEY_LEFTBRACE;
  case 0x30:
    return KEY_RIGHTBRACE;
  case 0x31:
    return KEY_BACKSLASH;
  case 0x33:
    return KEY_SEMICOLON;
  case 0x34:
    return KEY_APOSTROPHE;
  case 0x35:
    return KEY_GRAVE;
  case 0x36:
    return KEY_COMMA;
  case 0x37:
    return KEY_DOT;
  case 0x38:
    return KEY_SLASH;
  case 0x39:
    return KEY_CAPSLOCK;
  case 0x3A:
    return KEY_F1;
  case 0x3B:
    return KEY_F2;
  case 0x3C:
    return KEY_F3;
  case 0x3D:
    return KEY_F4;
  case 0x3E:
    return KEY_F5;
  case 0x3F:
    return KEY_F6;
  case 0x40:
    return KEY_F7;
  case 0x41:
    return KEY_F8;
  case 0x42:
    return KEY_F9;
  case 0x43:
    return KEY_F10;
  case 0x44:
    return KEY_F11;
  case 0x45:
    return KEY_F12;
  case 0x4A:
    return KEY_HOME;
  case 0x4B:
    return KEY_PAGEUP;
  case 0x4C:
    return KEY_DELETE;
  case 0x4D:
    return KEY_END;
  case 0x4E:
    return KEY_PAGEDOWN;
  case 0x4F:
    return KEY_RIGHT;
  case 0x50:
    return KEY_LEFT;
  case 0x51:
    return KEY_DOWN;
  case 0x52:
    return KEY_UP;
  case 0xE0:
    return KEY_LEFTCTRL;
  case 0xE1:
    return KEY_LEFTSHIFT;
  case 0xE2:
    return KEY_LEFTALT;
  case 0xE3:
    return KEY_LEFTMETA;
  case 0xE4:
    return KEY_RIGHTCTRL;
  case 0xE5:
    return KEY_RIGHTSHIFT;
  case 0xE6:
    return KEY_RIGHTALT;
  case 0xE7:
    return KEY_RIGHTMETA;
  default:
    return KEY_RESERVED;
  }
}

/// Returns YES if the given Linux keycode is a modifier key.
static BOOL isModifierKeycode(uint32_t keycode) {
  return keycode == KEY_LEFTSHIFT || keycode == KEY_RIGHTSHIFT ||
         keycode == KEY_LEFTCTRL || keycode == KEY_RIGHTCTRL ||
         keycode == KEY_LEFTALT || keycode == KEY_RIGHTALT ||
         keycode == KEY_LEFTMETA || keycode == KEY_RIGHTMETA;
}

/// Returns the XKB modifier bit for a Linux modifier keycode, or 0.
static uint32_t modifierBitForKeycode(uint32_t keycode) {
  switch (keycode) {
  case KEY_LEFTSHIFT:
  case KEY_RIGHTSHIFT:
    return (1 << 0); // XKB_MOD_SHIFT
  case KEY_LEFTCTRL:
  case KEY_RIGHTCTRL:
    return (1 << 2); // XKB_MOD_CTRL
  case KEY_LEFTALT:
  case KEY_RIGHTALT:
    return (1 << 3); // XKB_MOD_ALT
  case KEY_LEFTMETA:
  case KEY_RIGHTMETA:
    return (1 << 6); // XKB_MOD_SUPER
  default:
    return 0;
  }
}

// ---------------------------------------------------------------------------
// XKB modifier bit masks (must match the minimal keymap modifier_map order)
// ---------------------------------------------------------------------------
static const uint32_t XKB_MOD_SHIFT = (1 << 0);
static const uint32_t XKB_MOD_CTRL = (1 << 2);
static const uint32_t XKB_MOD_ALT = (1 << 3);
static const uint32_t XKB_MOD_SUPER = (1 << 6);

// Tag constants for modifier buttons in the accessory bar
static const NSInteger kTagModShift = 1000;
static const NSInteger kTagModCtrl = 1001;
static const NSInteger kTagModAlt = 1002;
static const NSInteger kTagModSuper = 1003;

// ---------------------------------------------------------------------------
// Touchpad mode constants
// ---------------------------------------------------------------------------
// Movement less than this many points within the tap duration → tap (click)
static const CGFloat kTapMovementThreshold = 12.0;
// Duration less than this many seconds → short tap (left click at cursor)
static const NSTimeInterval kTapDurationThreshold = 0.35;
// Tap+hold drag: a radial indicator appears at this delay and fills until the
// engage delay, at which point a sustained LMB-down (drag) engages.
static const NSTimeInterval kDragArmShowDelay = 0.5;
static const NSTimeInterval kDragEngageDelay = 1.0;
// Sensitivity multiplier for touchpad pointer movement
static const CGFloat kTouchpadSensitivity = 1.5;
// Scroll multiplier for two-finger drag (wl_fixed-ish units; weston-terminal
// accumulates ~256 per line).
static const CGFloat kScrollSensitivity = 12.0;
// macOS arrow cursor (NSCursor arrowCursor / Tahoe theme) — hotspot at the tip.
static const CGSize kTouchpadCursorSize = {28.0, 40.0};
static const CGFloat kTouchpadCursorHotspotX = 5.0;
static const CGFloat kTouchpadCursorHotspotY = 5.0;
static const CGFloat kTouchpadRadialRadius = 26.0;

// ---------------------------------------------------------------------------
// Input mode enum
// ---------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, WWNTouchInputMode) {
  WWNTouchInputModeMultiTouch = 0,
  WWNTouchInputModeTouchpad = 1,
};

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------
@implementation WWNCompositorView_ios {
  CAMetalLayer *_contentLayer;
  CALayer *_waylandLayer;
  UIView *_waylandFrameView;
  BOOL _keyboardActive;
  BOOL _keyboardEnterSent;

  // Sticky modifier state (active = one-shot, locked = persistent toggle)
  BOOL _modShiftActive;
  BOOL _modCtrlActive;
  BOOL _modAltActive;
  BOOL _modSuperActive;
  BOOL _modShiftLocked;
  BOOL _modCtrlLocked;
  BOOL _modAltLocked;
  BOOL _modSuperLocked;

  // Double-tap detection timestamps for modifier lock
  NSTimeInterval _lastModShiftTap;
  NSTimeInterval _lastModCtrlTap;
  NSTimeInterval _lastModAltTap;
  NSTimeInterval _lastModSuperTap;

  // Accessory bar (lazily created)
  UIView *_accessoryBar;

  // Touchpad mode state
  CGPoint _pointerPos;     // Virtual cursor position (view coords)
  CGPoint _prevTouchPoint; // Previous single-finger position
  NSTimeInterval _touchStartTime;
  CGFloat _touchTotalMovement;
  NSInteger _activeTouchCount; // Current simultaneous finger count
  CGPoint _prevScrollCenter;   // Previous two-finger centroid
  BOOL _scrollActive;          // Whether a two-finger scroll gesture is active
  NSInteger _maxTouchCount;    // Peak finger count seen during this gesture

  // Tap-and-hold drag state machine (touchpad mode)
  BOOL _dragging;              // Sustained LMB-down (drag) is engaged
  NSInteger _dragGeneration;   // Bumped to invalidate stale arm callbacks
  CAShapeLayer *_radialLayer;  // Tap-hold progress indicator (sibling of cursor)

  // Cached input mode for the duration of a gesture
  WWNTouchInputMode _currentInputMode;

  // Multi-Touch: mirror primary finger to wl_pointer for nested desktop-shell
  int32_t _primaryTouchId;
  BOOL _multitouchPointerEntered;
  BOOL _touchpadPointerEntered;

  BOOL _sessionActive;

  // Wayland cursor rendering (touchpad mode)
  CALayer *_cursorLayer;
  float _cursorHotspotX;
  float _cursorHotspotY;

  WWNIlandPresenter *_ilandPresenter;
  uint64_t _lastPresentToken;
  CGImageRef _lastPresentedWaylandImage;
  CGFloat _lastContentsScale;
  CGSize _lastWaylandLayoutSize;

  // Physical (hardware) keyboard state — suppresses insertText: when active
  NSInteger _pressedPhysicalKeyCount;
  uint32_t _physicalModifiers; // XKB depressed mask from physical keys

  // UITextInput proxy state (for Text Assist / autocorrect mode)
  NSMutableString *_textBuffer;
  NSInteger _cursorIndex;
  NSRange _markedRange;   // NSNotFound location = no marked text
  NSRange _selectedRange; // single cursor when length == 0
  NSDictionary *_markedTextStyle;
  UITextInputStringTokenizer *_tokenizer;
  BOOL _textAssistEnabled;
}

@synthesize keyboardActive = _keyboardActive;

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.userInteractionEnabled = YES;
#if !TARGET_OS_TV
    self.multipleTouchEnabled = YES;
#endif
    self.backgroundColor = [UIColor blackColor];

    // CAMetalLayer is created lazily for iland/kmscube only. An idle Metal
    // layer in the hierarchy composites above Wayland content on iOS and shows
    // as a solid magenta/purple screen even when hidden=YES.
    _contentLayer = nil;

    // Legacy subsurface host; primary presentation uses _waylandFrameView.
    _waylandLayer = [CALayer layer];
    _waylandLayer.geometryFlipped = YES;
    _waylandLayer.contentsGravity = kCAGravityTopLeft;
    _waylandLayer.masksToBounds = YES;
    _waylandLayer.hidden = YES;
    [self.layer addSublayer:_waylandLayer];

    _waylandFrameView = [[UIView alloc] initWithFrame:self.bounds];
    _waylandFrameView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _waylandFrameView.userInteractionEnabled = NO;
    _waylandFrameView.backgroundColor = UIColor.clearColor;
    _waylandFrameView.opaque = YES;
    _waylandFrameView.layer.contentsGravity = kCAGravityResize;
    _waylandFrameView.layer.minificationFilter = kCAFilterNearest;
    _waylandFrameView.layer.magnificationFilter = kCAFilterNearest;
    [self insertSubview:_waylandFrameView atIndex:0];

    // Initialise virtual pointer at center
    _pointerPos = CGPointMake(frame.size.width / 2, frame.size.height / 2);
    _currentInputMode = WWNTouchInputModeMultiTouch;

    // UITextInput proxy state
    _textBuffer = [NSMutableString string];
    _cursorIndex = 0;
    _markedRange = NSMakeRange(NSNotFound, 0);
    _selectedRange = NSMakeRange(0, 0);
    _textAssistEnabled = [self _readTextAssistEnabled];

    // Cursor layer for touchpad mode — hidden by default.
    // It renders the Wayland client's cursor image.
    _cursorLayer = [CALayer layer];
    _cursorLayer.bounds =
        CGRectMake(0, 0, kTouchpadCursorSize.width, kTouchpadCursorSize.height);
    _cursorLayer.contentsScale = self.traitCollection.displayScale > 0
                                     ? self.traitCollection.displayScale
                                     : 2.0;
    _cursorLayer.contentsGravity = kCAGravityResize;
    _cursorLayer.zPosition = 10000; // always on top
    _cursorLayer.hidden = YES;
    [self.layer addSublayer:_cursorLayer];

    _ilandPresenter = nil;
    _lastPresentToken = 0;
    _lastPresentedWaylandImage = NULL;
    _lastContentsScale = 0;
    _lastWaylandLayoutSize = CGSizeZero;
    _sessionActive = YES;

    WWNLog("IOS_VIEW", @"Created view for window %llu", self.wwnWindowId);
  }
  return self;
}

- (void)dealloc {
  [_ilandPresenter invalidate];
}

- (void)_ensureMetalPresentationLayer {
  if (_contentLayer) {
    return;
  }
  _contentLayer = [CAMetalLayer layer];
  _contentLayer.device = MTLCreateSystemDefaultDevice();
  _contentLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  _contentLayer.framebufferOnly = NO;
  _contentLayer.contentsGravity = kCAGravityResize;
  _contentLayer.masksToBounds = YES;
  _contentLayer.frame = self.bounds;
  [self.layer insertSublayer:_contentLayer atIndex:0];
  _ilandPresenter = [[WWNIlandPresenter alloc] initWithLayer:_contentLayer
                                                      device:_contentLayer.device];
}

- (void)_teardownMetalPresentationLayer {
  [_ilandPresenter invalidate];
  _ilandPresenter = nil;
  [_contentLayer removeFromSuperlayer];
  _contentLayer = nil;
}

- (void)prepareForSessionTeardown {
  _sessionActive = NO;
  _keyboardActive = NO;
  _keyboardEnterSent = NO;
  _activeTouchCount = 0;
  [self resignFirstResponder];
  [self presentWaylandFrame:NULL
                      frame:CGRectZero
                contentRect:CGRectMake(0, 0, 1, 1)
               presentToken:0];
  [self _teardownMetalPresentationLayer];
  _waylandLayer.hidden = YES;
  [_cursorLayer removeFromSuperlayer];
  _cursorLayer.hidden = YES;
  _cursorLayer.contents = nil;
  [_ilandPresenter invalidate];
  _ilandPresenter = nil;
}

- (void)setWaylandPresentationActive:(BOOL)active {
  _waylandFrameView.hidden = !active;
  if (active) {
    [self _teardownMetalPresentationLayer];
  }
}

- (void)prepareWaylandLayerSubpresentation {
  [self _teardownMetalPresentationLayer];
  _waylandFrameView.hidden = YES;
  _waylandFrameView.layer.contents = nil;
  _waylandLayer.hidden = NO;
  _lastPresentToken = 0;
  _lastPresentedWaylandImage = NULL;
  _lastContentsScale = 0;
  _lastWaylandLayoutSize = CGSizeZero;
}

- (void)presentWaylandFrame:(CGImageRef)image
                      frame:(CGRect)frame
                contentRect:(CGRect)normalizedContentRect
               presentToken:(uint64_t)presentToken {
  if (!_sessionActive) {
    return;
  }
  [self _teardownMetalPresentationLayer];
  _waylandLayer.hidden = YES;
  if (!image) {
    _waylandFrameView.layer.contents = nil;
    _waylandFrameView.hidden = YES;
    _lastPresentToken = 0;
    _lastPresentedWaylandImage = NULL;
    _lastContentsScale = 0;
    return;
  }

  _waylandFrameView.hidden = NO;
  if (!CGRectIsEmpty(frame)) {
    CGSize bounds = self.bounds.size;
    BOOL hasCsdCrop =
        (normalizedContentRect.size.width > 0.0 &&
         normalizedContentRect.size.height > 0.0 &&
         (normalizedContentRect.origin.x > 0.001 ||
          normalizedContentRect.origin.y > 0.001 ||
          normalizedContentRect.size.width < 0.999 ||
          normalizedContentRect.size.height < 0.999));
    if (!hasCsdCrop && bounds.width > 0.0 && bounds.height > 0.0 &&
        frame.size.width >= bounds.width * 0.94 &&
        frame.size.height >= bounds.height * 0.94 &&
        (frame.size.width < bounds.width || frame.size.height < bounds.height)) {
      // Nested Weston fullscreen: minor configure/scale drift leaves gutters;
      // snap the presentation view to the host compositor edges.
      frame = CGRectMake(0, 0, bounds.width, bounds.height);
    }
    _waylandFrameView.frame = frame;
    _waylandFrameView.autoresizingMask = UIViewAutoresizingNone;
  } else {
    _waylandFrameView.frame = self.bounds;
    _waylandFrameView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  }

  CGFloat viewW = _waylandFrameView.bounds.size.width;
  CGFloat viewH = _waylandFrameView.bounds.size.height;
  if (viewW <= 0.0 || viewH <= 0.0) {
    viewW = self.bounds.size.width;
    viewH = self.bounds.size.height;
  }
  size_t imgW = CGImageGetWidth(image);
  size_t imgH = CGImageGetHeight(image);
  CGFloat scaleX = viewW > 0.0 ? (CGFloat)imgW / viewW : 1.0;
  CGFloat scaleY = viewH > 0.0 ? (CGFloat)imgH / viewH : 1.0;
  CGFloat contentsScale = MAX(scaleX, scaleY);
  if (contentsScale < 1.0) {
    contentsScale = 1.0;
  }

  BOOL unchanged =
      (presentToken != 0 && presentToken == _lastPresentToken &&
       image == _lastPresentedWaylandImage &&
       fabs(_lastContentsScale - contentsScale) < 0.001);
  if (unchanged) {
    return;
  }

  _lastPresentToken = presentToken;
  _lastPresentedWaylandImage = image;
  _lastContentsScale = contentsScale;

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _waylandFrameView.layer.opaque = YES;
  _waylandFrameView.layer.contentsGravity = kCAGravityResize;
  _waylandFrameView.layer.contentsScale = contentsScale;
  _waylandFrameView.layer.contents = nil;
  _waylandFrameView.layer.contents = (__bridge id)image;
  _waylandFrameView.layer.contentsRect = normalizedContentRect;
  [CATransaction commit];
}

- (BOOL)launchNestedKmscube {
  if (![self prepareIlandMetalPresentation]) {
    return NO;
  }
  int w = (int)self.bounds.size.width;
  int h = (int)self.bounds.size.height;
  if (w <= 0 || h <= 0) {
    w = 640;
    h = 480;
  }
  return [_ilandPresenter launchNestedKmscubeWithWidth:w height:h];
}

- (BOOL)prepareIlandMetalPresentation {
  [self _ensureMetalPresentationLayer];
  _waylandFrameView.hidden = YES;
  _waylandFrameView.layer.contents = nil;
  _waylandLayer.hidden = YES;
  _contentLayer.hidden = NO;
  _contentLayer.frame = self.bounds;
  return _ilandPresenter != nil;
}

- (CAMetalLayer *)contentLayer {
  [self _ensureMetalPresentationLayer];
  return _contentLayer;
}

- (CALayer *)waylandLayer {
  return _waylandLayer;
}

- (void)safeAreaInsetsDidChange {
  [super safeAreaInsetsDidChange];
  UIEdgeInsets insets = self.safeAreaInsets;
  WWNLog("IOS_VIEW",
         @"Safe Area Insets changed: top=%.1f bottom=%.1f left=%.1f "
         @"right=%.1f",
         insets.top, insets.bottom, insets.left, insets.right);

  [[WWNCompositorBridge sharedBridge]
      setSafeAreaInsetsTop:(int32_t)insets.top
                     right:(int32_t)insets.right
                    bottom:(int32_t)insets.bottom
                      left:(int32_t)insets.left];
}

- (void)layoutSubviews {
  [super layoutSubviews];

  // Snap the content layer to the new bounds immediately.  Without this,
  // UIKit's rotation animation context captures the frame change and
  // animates it, stretching the old buffer for the animation duration and
  // preventing new content from appearing until the animation completes.
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (_contentLayer) {
    _contentLayer.frame = self.bounds;
  }
  _waylandLayer.frame = self.bounds;
  if (_waylandFrameView.autoresizingMask != UIViewAutoresizingNone) {
    _waylandFrameView.frame = self.bounds;
  }
  if (!CGSizeEqualToSize(_lastWaylandLayoutSize, self.bounds.size)) {
    _lastWaylandLayoutSize = self.bounds.size;
    _lastPresentToken = 0;
  }
  [CATransaction commit];

  if (self.bounds.size.width > 0 && self.bounds.size.height > 0) {
    [[WWNCompositorBridge sharedBridge]
        injectWindowResize:self.wwnWindowId
                     width:(uint32_t)self.bounds.size.width
                    height:(uint32_t)self.bounds.size.height];
  }
}

// ---------------------------------------------------------------------------
#pragma mark - Input Mode Helper
// ---------------------------------------------------------------------------

- (WWNTouchInputMode)_readInputMode {
  NSString *type = [[WWNPreferencesManager sharedManager] touchInputType];
  if ([type isEqualToString:@"Touchpad"]) {
    return WWNTouchInputModeTouchpad;
  }
  return WWNTouchInputModeMultiTouch;
}

// ---------------------------------------------------------------------------
#pragma mark - Input Accessory View (Special Keys Toolbar)
// ---------------------------------------------------------------------------

#if !TARGET_OS_VISION
- (UIView *)inputAccessoryView {
  if (!_accessoryBar) {
    _accessoryBar = [self _buildAccessoryBar];
  }
  return _accessoryBar;
}

/// Build the two-row special key toolbar that sits above the iOS keyboard.
///
/// Row 1: ESC  `  TAB  /  —  HOME  ↑  END  PGUP
/// Row 2: ⇧  CTRL  ALT  ⌘  ←  ↓  →  PGDN  ⌨↓
- (UIView *)_buildAccessoryBar {
  CGFloat barHeight = 80;
  CGFloat rowHeight = 38;
  CGFloat vPad = 2;

  UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, barHeight)];
  bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

  // Background: Liquid Glass on iOS 26+, dark chrome blur on older versions.
  // The effect view is edge-to-edge (no corner radius) so it blends
  // seamlessly with the native iOS virtual keyboard beneath.
  if (@available(iOS 26, *)) {
#if !TARGET_OS_TV
    UIGlassEffect *glass = [[UIGlassEffect alloc] init];
    UIVisualEffectView *glassView =
        [[UIVisualEffectView alloc] initWithEffect:glass];
    glassView.frame = bar.bounds;
    glassView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [bar addSubview:glassView];
#else
    UIBlurEffect *blur =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView =
        [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = bar.bounds;
    blurView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [bar addSubview:blurView];
#endif
  } else {
#if TARGET_OS_TV
    UIBlurEffect *blur =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
#else
    UIBlurEffect *blur = [UIBlurEffect
        effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
#endif
    UIVisualEffectView *blurView =
        [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = bar.bounds;
    blurView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [bar addSubview:blurView];
  }

  UIStackView *row1 = [self _makeRowStack];
  UIStackView *row2 = [self _makeRowStack];

  row1.translatesAutoresizingMaskIntoConstraints = NO;
  row2.translatesAutoresizingMaskIntoConstraints = NO;
  [bar addSubview:row1];
  [bar addSubview:row2];

  UILayoutGuide *safe = bar.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [row1.topAnchor constraintEqualToAnchor:bar.topAnchor constant:vPad],
    [row1.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:4],
    [row1.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                        constant:-4],
    [row1.heightAnchor constraintEqualToConstant:rowHeight],

    [row2.topAnchor constraintEqualToAnchor:row1.bottomAnchor constant:vPad],
    [row2.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:4],
    [row2.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                        constant:-4],
    [row2.heightAnchor constraintEqualToConstant:rowHeight],
  ]];

  // Row 1
  [row1 addArrangedSubview:[self _keyButton:@"ESC" action:@selector(_tapESC)]];
  [row1 addArrangedSubview:[self _keyButton:@"`" action:@selector(_tapGrave)]];
  [row1 addArrangedSubview:[self _keyButton:@"TAB" action:@selector(_tapTab)]];
  [row1 addArrangedSubview:[self _keyButton:@"/" action:@selector(_tapSlash)]];
  [row1 addArrangedSubview:[self _keyButton:@"—" action:@selector(_tapMinus)]];
  [row1
      addArrangedSubview:[self _keyButton:@"HOME" action:@selector(_tapHome)]];
  [row1
      addArrangedSubview:[self _keyButton:@"↑" action:@selector(_tapArrowUp)]];
  [row1 addArrangedSubview:[self _keyButton:@"END" action:@selector(_tapEnd)]];
  [row1 addArrangedSubview:[self _keyButton:@"PGUP"
                                     action:@selector(_tapPageUp)]];

  // Row 2
  UIButton *shiftBtn = [self _keyButton:@"⇧" action:@selector(_tapModShift:)];
  shiftBtn.tag = kTagModShift;
  [row2 addArrangedSubview:shiftBtn];

  UIButton *ctrlBtn = [self _keyButton:@"CTRL" action:@selector(_tapModCtrl:)];
  ctrlBtn.tag = kTagModCtrl;
  [row2 addArrangedSubview:ctrlBtn];

  UIButton *altBtn = [self _keyButton:@"ALT" action:@selector(_tapModAlt:)];
  altBtn.tag = kTagModAlt;
  [row2 addArrangedSubview:altBtn];

  UIButton *superBtn = [self _keyButton:@"⌘" action:@selector(_tapModSuper:)];
  superBtn.tag = kTagModSuper;
  [row2 addArrangedSubview:superBtn];

  [row2 addArrangedSubview:[self _keyButton:@"←"
                                     action:@selector(_tapArrowLeft)]];
  [row2 addArrangedSubview:[self _keyButton:@"↓"
                                     action:@selector(_tapArrowDown)]];
  [row2 addArrangedSubview:[self _keyButton:@"→"
                                     action:@selector(_tapArrowRight)]];
  [row2 addArrangedSubview:[self _keyButton:@"PGDN"
                                     action:@selector(_tapPageDown)]];

  UIButton *dismissBtn =
      [self _keyButton:@"⌨↓" action:@selector(_tapDismissKeyboard)];
  [row2 addArrangedSubview:dismissBtn];

  return bar;
}
#endif // !TARGET_OS_VISION

- (UIStackView *)_makeRowStack {
  UIStackView *stack = [[UIStackView alloc] init];
  stack.axis = UILayoutConstraintAxisHorizontal;
  stack.distribution = UIStackViewDistributionFillEqually;
  stack.spacing = 3;
  return stack;
}

- (UIButton *)_keyButton:(NSString *)title action:(SEL)action {
  UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
  [btn setTitle:title forState:UIControlStateNormal];
  btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  btn.titleLabel.adjustsFontSizeToFitWidth = YES;
  btn.titleLabel.minimumScaleFactor = 0.6;
  btn.clipsToBounds = YES;
  [btn addTarget:self
                action:action
      forControlEvents:UIControlEventTouchUpInside];

  if (@available(iOS 26, *)) {
#if !TARGET_OS_TV
    // Liquid Glass style: translucent key caps that sit on the glass
    // bar background, matching the native iOS 26 keyboard aesthetic.
    btn.backgroundColor = [UIColor tertiarySystemFillColor];
    [btn setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    btn.layer.cornerRadius = 6;
#else
    btn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.layer.cornerRadius = 5;
#endif
  } else {
    btn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.layer.cornerRadius = 5;
  }

  return btn;
}

// ---------------------------------------------------------------------------
#pragma mark - Accessory Key Actions (non-modifier)
// ---------------------------------------------------------------------------

- (void)_tapESC {
  [self _sendAccessoryKey:KEY_ESC];
}
- (void)_tapGrave {
  [self _sendAccessoryKey:KEY_GRAVE];
}
- (void)_tapTab {
  [self _sendAccessoryKey:KEY_TAB];
}
- (void)_tapSlash {
  [self _sendAccessoryKey:KEY_SLASH];
}
- (void)_tapMinus {
  [self _sendAccessoryKey:KEY_MINUS];
}
- (void)_tapHome {
  [self _sendAccessoryKey:KEY_HOME];
}
- (void)_tapEnd {
  [self _sendAccessoryKey:KEY_END];
}
- (void)_tapArrowUp {
  [self _sendAccessoryKey:KEY_UP];
}
- (void)_tapArrowDown {
  [self _sendAccessoryKey:KEY_DOWN];
}
- (void)_tapArrowLeft {
  [self _sendAccessoryKey:KEY_LEFT];
}
- (void)_tapArrowRight {
  [self _sendAccessoryKey:KEY_RIGHT];
}
- (void)_tapPageUp {
  [self _sendAccessoryKey:KEY_PAGEUP];
}
- (void)_tapPageDown {
  [self _sendAccessoryKey:KEY_PAGEDOWN];
}

- (void)_tapDismissKeyboard {
  [self resignFirstResponder];
}

/// Route accessory-bar keys to the iOS PTY when weston-terminal is active.
/// Soft keyboard already uses wwn_ios_terminal_inject; wl_keyboard does not
/// reach the fake PTY shell stdin path.
- (BOOL)_injectTerminalAccessoryKeycode:(uint32_t)keycode {
  if (_modCtrlActive || _modAltActive || _modSuperActive)
    return NO;

  const char *bytes = NULL;
  char buf[8];
  size_t len = 0;

  switch (keycode) {
  case KEY_MINUS:
    buf[0] = _modShiftActive ? '_' : '-';
    bytes = buf;
    len = 1;
    break;
  case KEY_SLASH:
    buf[0] = _modShiftActive ? '?' : '/';
    bytes = buf;
    len = 1;
    break;
  case KEY_GRAVE:
    buf[0] = _modShiftActive ? '~' : '`';
    bytes = buf;
    len = 1;
    break;
  case KEY_TAB:
    buf[0] = '\t';
    bytes = buf;
    len = 1;
    break;
  case KEY_ESC:
    buf[0] = 0x1b;
    bytes = buf;
    len = 1;
    break;
  case KEY_UP:
    bytes = "\033[A";
    len = 3;
    break;
  case KEY_DOWN:
    bytes = "\033[B";
    len = 3;
    break;
  case KEY_LEFT:
    bytes = "\033[D";
    len = 3;
    break;
  case KEY_RIGHT:
    bytes = "\033[C";
    len = 3;
    break;
  case KEY_HOME:
    bytes = "\033[H";
    len = 3;
    break;
  case KEY_END:
    bytes = "\033[F";
    len = 3;
    break;
  case KEY_PAGEUP:
    bytes = "\033[5~";
    len = 4;
    break;
  case KEY_PAGEDOWN:
    bytes = "\033[6~";
    len = 4;
    break;
  default:
    return NO;
  }

  ssize_t n = wwn_ios_terminal_inject(bytes, len);
  if (n <= 0) {
    WWNLog("IOS_VIEW", @"PTY accessory inject failed (%zd) keycode=%u", n,
           keycode);
  }
  return YES;
}

/// Send a key press with any active sticky modifiers, then clear them.
- (void)_sendAccessoryKey:(uint32_t)keycode {
  [self _sendKeyboardEnterIfNeeded];

  if (wwn_ios_terminal_is_active() &&
      [self _injectTerminalAccessoryKeycode:keycode]) {
    [self _clearStickyModifiers];
    return;
  }

  uint32_t ts = [self _timestampMs];
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  uint32_t mods = 0;
  if (_modShiftActive) {
    mods |= XKB_MOD_SHIFT;
    [bridge injectKeyWithKeycode:KEY_LEFTSHIFT pressed:YES timestamp:ts];
  }
  if (_modCtrlActive) {
    mods |= XKB_MOD_CTRL;
    [bridge injectKeyWithKeycode:KEY_LEFTCTRL pressed:YES timestamp:ts];
  }
  if (_modAltActive) {
    mods |= XKB_MOD_ALT;
    [bridge injectKeyWithKeycode:KEY_LEFTALT pressed:YES timestamp:ts];
  }
  if (_modSuperActive) {
    mods |= XKB_MOD_SUPER;
    [bridge injectKeyWithKeycode:KEY_LEFTMETA pressed:YES timestamp:ts];
  }

  if (mods) {
    [bridge injectModifiersWithDepressed:mods latched:0 locked:0 group:0];
  }

  [bridge injectKeyWithKeycode:keycode pressed:YES timestamp:ts];
  [bridge injectKeyWithKeycode:keycode pressed:NO timestamp:ts + 1];

  if (_modShiftActive)
    [bridge injectKeyWithKeycode:KEY_LEFTSHIFT pressed:NO timestamp:ts + 2];
  if (_modCtrlActive)
    [bridge injectKeyWithKeycode:KEY_LEFTCTRL pressed:NO timestamp:ts + 2];
  if (_modAltActive)
    [bridge injectKeyWithKeycode:KEY_LEFTALT pressed:NO timestamp:ts + 2];
  if (_modSuperActive)
    [bridge injectKeyWithKeycode:KEY_LEFTMETA pressed:NO timestamp:ts + 2];

  if (mods) {
    [bridge injectModifiersWithDepressed:0 latched:0 locked:0 group:0];
  }

  [self _clearStickyModifiers];
}

// ---------------------------------------------------------------------------
#pragma mark - Modifier Toggle Actions
// ---------------------------------------------------------------------------
//
// Modifier keys follow iOS-style three-state cycling:
//   Inactive → (tap) → Sticky → (tap within 0.4s) → Locked
//   Locked → (tap) → Inactive
//
// Sticky: modifier applies to the next keypress then auto-clears.
// Locked:  modifier stays active until the user taps it again.

static const NSTimeInterval kDoubleTapThreshold = 0.4;

- (void)_tapModShift:(UIButton *)sender {
  [self _handleModifierTap:sender
                    active:&_modShiftActive
                    locked:&_modShiftLocked
                   lastTap:&_lastModShiftTap];
}

- (void)_tapModCtrl:(UIButton *)sender {
  [self _handleModifierTap:sender
                    active:&_modCtrlActive
                    locked:&_modCtrlLocked
                   lastTap:&_lastModCtrlTap];
}

- (void)_tapModAlt:(UIButton *)sender {
  [self _handleModifierTap:sender
                    active:&_modAltActive
                    locked:&_modAltLocked
                   lastTap:&_lastModAltTap];
}

- (void)_tapModSuper:(UIButton *)sender {
  [self _handleModifierTap:sender
                    active:&_modSuperActive
                    locked:&_modSuperLocked
                   lastTap:&_lastModSuperTap];
}

/// Shared handler implementing the Inactive → Sticky → Locked → Inactive cycle.
- (void)_handleModifierTap:(UIButton *)btn
                    active:(BOOL *)active
                    locked:(BOOL *)locked
                   lastTap:(NSTimeInterval *)lastTap {
  NSTimeInterval now = CACurrentMediaTime();
  NSTimeInterval elapsed = now - *lastTap;
  *lastTap = now;

  if (*locked) {
    // Locked → Inactive
    *active = NO;
    *locked = NO;
  } else if (*active && elapsed < kDoubleTapThreshold) {
    // Sticky + quick second tap → Locked
    *locked = YES;
    // *active stays YES
  } else if (*active) {
    // Sticky, but slow second tap → Inactive
    *active = NO;
    *locked = NO;
  } else {
    // Inactive → Sticky
    *active = YES;
    *locked = NO;
  }

  [self _updateModifierButtonAppearance:btn active:*active locked:*locked];
}

- (void)_updateModifierButtonAppearance:(UIButton *)btn
                                 active:(BOOL)active
                                 locked:(BOOL)locked {
  if (@available(iOS 26, *)) {
#if !TARGET_OS_TV
    // Liquid Glass modifier states — translucent tints on glass
    if (locked) {
      btn.backgroundColor =
          [[UIColor systemBlueColor] colorWithAlphaComponent:0.35];
      btn.layer.borderWidth = 2.0;
      btn.layer.borderColor = [UIColor systemBlueColor].CGColor;
    } else if (active) {
      btn.backgroundColor =
          [[UIColor systemBlueColor] colorWithAlphaComponent:0.25];
      btn.layer.borderWidth = 0;
      btn.layer.borderColor = nil;
    } else {
      btn.backgroundColor = [UIColor tertiarySystemFillColor];
      btn.layer.borderWidth = 0;
      btn.layer.borderColor = nil;
    }
#else
    if (locked) {
      btn.backgroundColor = [UIColor systemBlueColor];
      btn.layer.borderWidth = 2.0;
      btn.layer.borderColor = [UIColor whiteColor].CGColor;
    } else if (active) {
      btn.backgroundColor = [UIColor systemBlueColor];
      btn.layer.borderWidth = 0;
      btn.layer.borderColor = nil;
    } else {
      btn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
      btn.layer.borderWidth = 0;
      btn.layer.borderColor = nil;
    }
#endif
  } else {
    if (locked) {
      btn.backgroundColor = [UIColor systemBlueColor];
      btn.layer.borderWidth = 2.0;
      btn.layer.borderColor = [UIColor whiteColor].CGColor;
    } else if (active) {
      btn.backgroundColor = [UIColor systemBlueColor];
      btn.layer.borderWidth = 0;
      btn.layer.borderColor = nil;
    } else {
      btn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
      btn.layer.borderWidth = 0;
      btn.layer.borderColor = nil;
    }
  }
}

/// Clear one-shot (sticky) modifiers after a key press.
/// Locked modifiers are preserved until the user explicitly taps them off.
- (void)_clearStickyModifiers {
  UIView *bar = _accessoryBar;

  if (_modShiftActive && !_modShiftLocked) {
    _modShiftActive = NO;
    if (bar) {
      UIButton *b = [bar viewWithTag:kTagModShift];
      if (b)
        [self _updateModifierButtonAppearance:b active:NO locked:NO];
    }
  }
  if (_modCtrlActive && !_modCtrlLocked) {
    _modCtrlActive = NO;
    if (bar) {
      UIButton *b = [bar viewWithTag:kTagModCtrl];
      if (b)
        [self _updateModifierButtonAppearance:b active:NO locked:NO];
    }
  }
  if (_modAltActive && !_modAltLocked) {
    _modAltActive = NO;
    if (bar) {
      UIButton *b = [bar viewWithTag:kTagModAlt];
      if (b)
        [self _updateModifierButtonAppearance:b active:NO locked:NO];
    }
  }
  if (_modSuperActive && !_modSuperLocked) {
    _modSuperActive = NO;
    if (bar) {
      UIButton *b = [bar viewWithTag:kTagModSuper];
      if (b)
        [self _updateModifierButtonAppearance:b active:NO locked:NO];
    }
  }
}

/// Force-clear all modifiers (both sticky and locked). Used when the
/// keyboard is dismissed entirely.
- (void)_clearAllModifiers {
  _modShiftActive = NO;
  _modCtrlActive = NO;
  _modAltActive = NO;
  _modSuperActive = NO;
  _modShiftLocked = NO;
  _modCtrlLocked = NO;
  _modAltLocked = NO;
  _modSuperLocked = NO;

  UIView *bar = _accessoryBar;
  if (!bar)
    return;
  for (NSInteger tag = kTagModShift; tag <= kTagModSuper; tag++) {
    UIButton *b = [bar viewWithTag:tag];
    if (b)
      [self _updateModifierButtonAppearance:b active:NO locked:NO];
  }
}

// ---------------------------------------------------------------------------
#pragma mark - First Responder
// ---------------------------------------------------------------------------

- (BOOL)canBecomeFirstResponder {
  return YES;
}

- (BOOL)_readTextAssistEnabled {
  // Match Android default (off): nested Weston and terminals expect wl_keyboard.
  return [[NSUserDefaults standardUserDefaults] boolForKey:@"enableTextAssist"];
}

- (void)_applyDefaultTouchpadCursorAppearance {
  UIImage *image = [UIImage imageNamed:@"TouchpadCursor"];
  if (image) {
    _cursorLayer.contents = (__bridge id)image.CGImage;
    _cursorLayer.bounds =
        CGRectMake(0, 0, image.size.width, image.size.height);
  } else {
    _cursorLayer.contents = (__bridge id)[self _defaultTouchpadCursorImage];
    _cursorLayer.bounds =
        CGRectMake(0, 0, kTouchpadCursorSize.width, kTouchpadCursorSize.height);
  }
  _cursorHotspotX = kTouchpadCursorHotspotX;
  _cursorHotspotY = kTouchpadCursorHotspotY;
}

- (void)_ensureTouchpadCursorVisible {
  if (_currentInputMode != WWNTouchInputModeTouchpad) {
    return;
  }
  if (![[WWNPreferencesManager sharedManager] renderMacOSPointer]) {
    _cursorLayer.hidden = YES;
    return;
  }
  if (!_cursorLayer.contents) {
    [self _applyDefaultTouchpadCursorAppearance];
  }
  _cursorLayer.hidden = NO;
  [self _repositionCursorLayer];
}

- (CGImageRef)_defaultTouchpadCursorImage {
  static CGImageRef sImage = NULL;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    UIImage *image = [UIImage imageNamed:@"TouchpadCursor"];
    if (image.CGImage) {
      sImage = CGImageRetain(image.CGImage);
      return;
    }
    // Fallback if the asset catalog entry is missing from the bundle.
    CGSize size = kTouchpadCursorSize;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetStrokeColorWithColor(ctx, [UIColor blackColor].CGColor);
    CGContextSetLineWidth(ctx, 1.5);
    CGContextMoveToPoint(ctx, 1.0, 1.0);
    CGContextAddLineToPoint(ctx, 1.0, 22.0);
    CGContextAddLineToPoint(ctx, 7.0, 17.0);
    CGContextAddLineToPoint(ctx, 12.0, 28.0);
    CGContextAddLineToPoint(ctx, 15.0, 27.0);
    CGContextAddLineToPoint(ctx, 10.0, 16.0);
    CGContextAddLineToPoint(ctx, 18.0, 16.0);
    CGContextClosePath(ctx);
    CGContextDrawPath(ctx, kCGPathFillStroke);
    UIImage *fallback = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (fallback.CGImage) {
      sImage = CGImageRetain(fallback.CGImage);
    }
  });
  return sImage;
}

- (BOOL)becomeFirstResponder {
  _textAssistEnabled = [self _readTextAssistEnabled];

  BOOL result = [super becomeFirstResponder];
  if (result) {
    WWNLog("IOS_VIEW", @"Became first responder for window %llu",
           self.wwnWindowId);
    _keyboardActive = YES;

    [[WWNCompositorBridge sharedBridge] setWindowActivated:self.wwnWindowId
                                                    active:YES];
    [self _sendKeyboardEnterIfNeeded];
  }
  return result;
}

- (BOOL)resignFirstResponder {
  BOOL result = [super resignFirstResponder];
  if (result) {
    WWNLog("IOS_VIEW", @"Resigned first responder for window %llu",
           self.wwnWindowId);
    _keyboardActive = NO;
    [self _sendKeyboardLeave];
    [self _clearAllModifiers];

    [[WWNCompositorBridge sharedBridge] setWindowActivated:self.wwnWindowId
                                                    active:NO];
  }
  return result;
}

// ---------------------------------------------------------------------------
#pragma mark - UIKeyInput Protocol
// ---------------------------------------------------------------------------

- (BOOL)hasText {
  return YES;
}

- (void)insertText:(NSString *)text {
  if (text.length == 0)
    return;

  // Physical keyboard events are handled in pressesBegan:/pressesEnded:
  // which send raw keycodes. Suppress the duplicate insertText: that iOS's
  // text input system fires as a side-effect of the same key press.
  if (_pressedPhysicalKeyCount > 0) {
    return;
  }

  WWNLog("IOS_VIEW", @"insertText: \"%@\" (len=%lu) for window %llu", text,
         (unsigned long)text.length, self.wwnWindowId);

  [self _sendKeyboardEnterIfNeeded];

  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  // Notify the input delegate so iOS keeps the text input session valid.
  // Without these calls, emoji search and other system input operations
  // fail with "requires a valid sessionID".
  [self.inputDelegate textWillChange:self];
  [self.inputDelegate selectionWillChange:self];

  /*
   * weston-terminal only reads wl_keyboard / PTY — not text-input-v3.  Route
   * soft keyboard here before Text Assist or wl_keyboard fallbacks.
   *
   * Modifier combos (Ctrl+C, etc.) must not take the plain-text fast path:
   * synthesize the control byte locally or fall through to wl_keyboard.
   */
  if (wwn_ios_terminal_is_active()) {
    BOOL hasCtrlOrAltOrSuper =
        _modCtrlActive || _modAltActive || _modSuperActive;

    if (_modCtrlActive && text.length == 1) {
      unichar ch = [[text uppercaseString] characterAtIndex:0];
      if (ch >= 'A' && ch <= 'Z') {
        unsigned char ctrl = (unsigned char)(ch - 'A' + 1);
        ssize_t n = wwn_ios_terminal_inject(&ctrl, 1);
        if (n <= 0) {
          WWNLog("IOS_VIEW", @"PTY ctrl inject failed (%zd) for window %llu", n,
                 self.wwnWindowId);
        }
        [self.inputDelegate selectionDidChange:self];
        [self.inputDelegate textDidChange:self];
        [self _clearStickyModifiers];
        return;
      }
    }

    if (!hasCtrlOrAltOrSuper) {
      const char *utf8 = text.UTF8String;
      if (utf8 && utf8[0]) {
        ssize_t n = wwn_ios_terminal_inject(utf8, strlen(utf8));
        if (n <= 0) {
          WWNLog("IOS_VIEW", @"PTY inject failed (%zd) for window %llu", n,
                 self.wwnWindowId);
        } else {
          WWNLog("IOS_VIEW", @"PTY inject %zd bytes for window %llu", n,
                 self.wwnWindowId);
        }
      }
      [self.inputDelegate selectionDidChange:self];
      [self.inputDelegate textDidChange:self];
      return;
    }
  }

  // --- Text Assist mode: commit via text-input-v3 ---
  if (_textAssistEnabled) {
    if (_markedRange.location != NSNotFound) {
      [_textBuffer replaceCharactersInRange:_markedRange withString:text];
      _selectedRange = NSMakeRange(_markedRange.location + text.length, 0);
      _markedRange = NSMakeRange(NSNotFound, 0);
    } else {
      [_textBuffer insertString:text atIndex:_selectedRange.location];
      _selectedRange = NSMakeRange(_selectedRange.location + text.length, 0);
    }
    [bridge textInputPreeditString:@"" cursorBegin:0 cursorEnd:0];
    [bridge textInputCommitString:text];
    [self.inputDelegate selectionDidChange:self];
    [self.inputDelegate textDidChange:self];
    [self _clearStickyModifiers];
    return;
  }

  // --- Legacy key-event mode (Text Assist OFF) ---

  if (_markedRange.location != NSNotFound) {
    [bridge textInputPreeditString:@"" cursorBegin:0 cursorEnd:0];
    _markedRange = NSMakeRange(NSNotFound, 0);
  }

  // Check if every character in the string has a Linux keycode mapping.
  // If not (e.g. emoji, CJK, accented characters from IME), commit the
  // whole string via text-input-v3 so it reaches clients as composed text.
  BOOL allMappable = YES;
  for (NSUInteger i = 0; i < text.length; i++) {
    unichar ch = [text characterAtIndex:i];
    if (CFStringIsSurrogateHighCharacter(ch) ||
        CFStringIsSurrogateLowCharacter(ch)) {
      allMappable = NO;
      break;
    }
    uint32_t keycode;
    BOOL needsShift;
    if (!charToLinuxKeycode(ch, &keycode, &needsShift)) {
      allMappable = NO;
      break;
    }
  }

  if (!allMappable) {
    WWNLog("IOS_VIEW", @"Committing via text-input-v3: \"%@\"", text);
    [bridge textInputCommitString:text];
    [self.inputDelegate selectionDidChange:self];
    [self.inputDelegate textDidChange:self];
    [self _clearStickyModifiers];
    return;
  }

  // All characters map to keycodes — send as key events (more compatible
  // with clients that only support wl_keyboard, e.g. terminal emulators).
  uint32_t ts = [self _timestampMs];

  uint32_t mods = 0;
  if (_modShiftActive)
    mods |= XKB_MOD_SHIFT;
  if (_modCtrlActive)
    mods |= XKB_MOD_CTRL;
  if (_modAltActive)
    mods |= XKB_MOD_ALT;
  if (_modSuperActive)
    mods |= XKB_MOD_SUPER;

  if (mods) {
    if (_modShiftActive)
      [bridge injectKeyWithKeycode:KEY_LEFTSHIFT pressed:YES timestamp:ts];
    if (_modCtrlActive)
      [bridge injectKeyWithKeycode:KEY_LEFTCTRL pressed:YES timestamp:ts];
    if (_modAltActive)
      [bridge injectKeyWithKeycode:KEY_LEFTALT pressed:YES timestamp:ts];
    if (_modSuperActive)
      [bridge injectKeyWithKeycode:KEY_LEFTMETA pressed:YES timestamp:ts];
    [bridge injectModifiersWithDepressed:mods latched:0 locked:0 group:0];
  }

  for (NSUInteger i = 0; i < text.length; i++) {
    unichar ch = [text characterAtIndex:i];
    uint32_t keycode;
    BOOL needsShift;

    if (charToLinuxKeycode(ch, &keycode, &needsShift)) {
      if (mods) {
        BOOL extraShift = needsShift && !_modShiftActive;
        if (extraShift) {
          [bridge injectKeyWithKeycode:KEY_LEFTSHIFT pressed:YES timestamp:ts];
          [bridge injectModifiersWithDepressed:(mods | XKB_MOD_SHIFT)
                                       latched:0
                                        locked:0
                                         group:0];
        }
        [bridge injectKeyWithKeycode:keycode pressed:YES timestamp:ts];
        [bridge injectKeyWithKeycode:keycode pressed:NO timestamp:ts + 1];
        if (extraShift) {
          [bridge injectKeyWithKeycode:KEY_LEFTSHIFT
                               pressed:NO
                             timestamp:ts + 2];
          [bridge injectModifiersWithDepressed:mods latched:0 locked:0 group:0];
        }
      } else {
        [self _sendKeyPress:keycode withShift:needsShift timestamp:ts];
      }
    }
  }

  if (mods) {
    if (_modShiftActive)
      [bridge injectKeyWithKeycode:KEY_LEFTSHIFT pressed:NO timestamp:ts + 2];
    if (_modCtrlActive)
      [bridge injectKeyWithKeycode:KEY_LEFTCTRL pressed:NO timestamp:ts + 2];
    if (_modAltActive)
      [bridge injectKeyWithKeycode:KEY_LEFTALT pressed:NO timestamp:ts + 2];
    if (_modSuperActive)
      [bridge injectKeyWithKeycode:KEY_LEFTMETA pressed:NO timestamp:ts + 2];
    [bridge injectModifiersWithDepressed:0 latched:0 locked:0 group:0];
    [self _clearStickyModifiers];
  }

  [self.inputDelegate selectionDidChange:self];
  [self.inputDelegate textDidChange:self];
}

- (void)deleteBackward {
  // Physical backspace is already handled in pressesBegan:
  if (_pressedPhysicalKeyCount > 0) {
    return;
  }

  WWNLog("IOS_VIEW", @"deleteBackward for window %llu", self.wwnWindowId);

  [self.inputDelegate textWillChange:self];
  [self.inputDelegate selectionWillChange:self];

  if (wwn_ios_terminal_is_active()) {
    static const char del = 0x7f;
    wwn_ios_terminal_inject(&del, 1);
    [self.inputDelegate selectionDidChange:self];
    [self.inputDelegate textDidChange:self];
    return;
  }

  if (_textAssistEnabled && _textBuffer.length > 0) {
    NSRange deleteRange;
    if (_selectedRange.length > 0) {
      deleteRange = _selectedRange;
    } else if (_selectedRange.location > 0) {
      deleteRange = NSMakeRange(_selectedRange.location - 1, 1);
    } else {
      [self.inputDelegate selectionDidChange:self];
      [self.inputDelegate textDidChange:self];
      return;
    }
    [_textBuffer deleteCharactersInRange:deleteRange];
    _selectedRange = NSMakeRange(deleteRange.location, 0);

    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
    [bridge textInputDeleteSurrounding:(uint32_t)deleteRange.length
                           afterLength:0];
    [self.inputDelegate selectionDidChange:self];
    [self.inputDelegate textDidChange:self];
    return;
  }

  [self _sendAccessoryKey:KEY_BACKSPACE];
  [self.inputDelegate selectionDidChange:self];
  [self.inputDelegate textDidChange:self];
}

// ---------------------------------------------------------------------------
#pragma mark - UITextInputTraits
// ---------------------------------------------------------------------------

- (UITextAutocapitalizationType)autocapitalizationType {
  return UITextAutocapitalizationTypeNone;
}

- (UITextAutocorrectionType)autocorrectionType {
  return _textAssistEnabled ? UITextAutocorrectionTypeYes
                            : UITextAutocorrectionTypeNo;
}

- (UITextSpellCheckingType)spellCheckingType {
  return _textAssistEnabled ? UITextSpellCheckingTypeYes
                            : UITextSpellCheckingTypeNo;
}

- (UITextSmartQuotesType)smartQuotesType {
  return _textAssistEnabled ? UITextSmartQuotesTypeYes
                            : UITextSmartQuotesTypeNo;
}

- (UITextSmartDashesType)smartDashesType {
  return _textAssistEnabled ? UITextSmartDashesTypeYes
                            : UITextSmartDashesTypeNo;
}

- (UITextSmartInsertDeleteType)smartInsertDeleteType {
  return _textAssistEnabled ? UITextSmartInsertDeleteTypeYes
                            : UITextSmartInsertDeleteTypeNo;
}

- (UIKeyboardType)keyboardType {
  return UIKeyboardTypeDefault;
}

- (UIReturnKeyType)returnKeyType {
  return UIReturnKeyDefault;
}

// ---------------------------------------------------------------------------
#pragma mark - UITextInput Protocol
// ---------------------------------------------------------------------------

// --- Text storage ---

- (nullable NSString *)textInRange:(UITextRange *)range {
  WWNTextRange *r = (WWNTextRange *)range;
  NSInteger start = r.start.index;
  NSInteger end = r.end.index;
  if (start < 0)
    start = 0;
  if (end > (NSInteger)_textBuffer.length)
    end = _textBuffer.length;
  if (start >= end)
    return @"";
  return [_textBuffer substringWithRange:NSMakeRange(start, end - start)];
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
  WWNTextRange *r = (WWNTextRange *)range;
  NSInteger start = r.start.index;
  NSInteger end = r.end.index;
  if (start < 0)
    start = 0;
  if (end > (NSInteger)_textBuffer.length)
    end = _textBuffer.length;
  NSInteger rangeLen = (end - start > 0) ? (end - start) : 0;
  NSRange replaceRange = NSMakeRange(start, (NSUInteger)rangeLen);

  WWNLog("IOS_VIEW", @"replaceRange: [%ld,%ld) with \"%@\"", (long)start,
         (long)end, text);

  [self.inputDelegate textWillChange:self];
  [self.inputDelegate selectionWillChange:self];

  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  uint32_t deleteBefore = 0;
  uint32_t deleteAfter = 0;
  if (replaceRange.location < (NSUInteger)_selectedRange.location) {
    NSUInteger diff = _selectedRange.location - replaceRange.location;
    deleteBefore = (uint32_t)((diff < replaceRange.length) ? diff : replaceRange.length);
  }
  if (NSMaxRange(replaceRange) > NSMaxRange(_selectedRange)) {
    deleteAfter =
        (uint32_t)(NSMaxRange(replaceRange) - NSMaxRange(_selectedRange));
  }

  if (deleteBefore > 0 || deleteAfter > 0) {
    [bridge textInputDeleteSurrounding:deleteBefore afterLength:deleteAfter];
  }

  [_textBuffer replaceCharactersInRange:replaceRange withString:text];
  _selectedRange = NSMakeRange(replaceRange.location + text.length, 0);

  if (text.length > 0) {
    [bridge textInputCommitString:text];
  }

  [self.inputDelegate selectionDidChange:self];
  [self.inputDelegate textDidChange:self];
}

// --- Selection ---

- (UITextRange *)selectedTextRange {
  return [WWNTextRange rangeWithStart:(NSInteger)_selectedRange.location
                                  end:(NSInteger)NSMaxRange(_selectedRange)];
}

- (void)setSelectedTextRange:(UITextRange *)range {
  WWNTextRange *r = (WWNTextRange *)range;
  if (r) {
    NSInteger len = r.end.index - r.start.index;
    _selectedRange =
        NSMakeRange(r.start.index, (NSUInteger)(len > 0 ? len : 0));
  }
}

// --- Marked text (IME composition / preedit) ---

@synthesize markedTextStyle = _markedTextStyle;

- (UITextRange *)markedTextRange {
  if (_markedRange.location == NSNotFound)
    return nil;
  return [WWNTextRange rangeWithStart:(NSInteger)_markedRange.location
                                  end:(NSInteger)NSMaxRange(_markedRange)];
}

- (void)setMarkedText:(nullable NSString *)markedText
        selectedRange:(NSRange)selectedRange {
  NSString *text = markedText ?: @"";
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  [self.inputDelegate textWillChange:self];
  [self.inputDelegate selectionWillChange:self];

  if (_textAssistEnabled) {
    if (_markedRange.location != NSNotFound) {
      [_textBuffer replaceCharactersInRange:_markedRange withString:text];
    } else {
      NSUInteger insertAt = _selectedRange.location;
      [_textBuffer insertString:text atIndex:insertAt];
      _markedRange = NSMakeRange(insertAt, 0);
    }
    _markedRange = NSMakeRange(_markedRange.location, text.length);
    _selectedRange = NSMakeRange(_markedRange.location + selectedRange.location,
                                 selectedRange.length);
  } else {
    if (_markedRange.location == NSNotFound) {
      _markedRange = NSMakeRange(0, 0);
    }
    _markedRange = NSMakeRange(_markedRange.location, text.length);
    _selectedRange = NSMakeRange(_markedRange.location + selectedRange.location,
                                 selectedRange.length);
  }

  [bridge textInputPreeditString:text
                     cursorBegin:(int32_t)selectedRange.location
                       cursorEnd:(int32_t)(selectedRange.location +
                                           selectedRange.length)];

  [self.inputDelegate selectionDidChange:self];
  [self.inputDelegate textDidChange:self];
}

- (void)unmarkText {
  if (_markedRange.location == NSNotFound)
    return;

  [self.inputDelegate textWillChange:self];
  [self.inputDelegate selectionWillChange:self];

  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  NSString *committed = nil;

  if (_textAssistEnabled) {
    committed = [_textBuffer substringWithRange:_markedRange];
    _selectedRange = NSMakeRange(NSMaxRange(_markedRange), 0);
  }

  _markedRange = NSMakeRange(NSNotFound, 0);

  [bridge textInputPreeditString:@"" cursorBegin:0 cursorEnd:0];
  if (committed.length > 0) {
    [bridge textInputCommitString:committed];
  }

  [self.inputDelegate selectionDidChange:self];
  [self.inputDelegate textDidChange:self];
}

// --- Position / range arithmetic ---

- (UITextPosition *)beginningOfDocument {
  return [WWNTextPosition positionWithIndex:0];
}

- (UITextPosition *)endOfDocument {
  return [WWNTextPosition positionWithIndex:_textBuffer.length];
}

- (nullable UITextPosition *)positionFromPosition:(UITextPosition *)position
                                           offset:(NSInteger)offset {
  NSInteger idx = ((WWNTextPosition *)position).index + offset;
  if (idx < 0 || idx > (NSInteger)_textBuffer.length)
    return nil;
  return [WWNTextPosition positionWithIndex:idx];
}

- (nullable UITextPosition *)positionFromPosition:(UITextPosition *)position
                                      inDirection:
                                          (UITextLayoutDirection)direction
                                           offset:(NSInteger)offset {
  NSInteger idx = ((WWNTextPosition *)position).index;
  switch (direction) {
  case UITextLayoutDirectionRight:
  case UITextLayoutDirectionDown:
    idx += offset;
    break;
  case UITextLayoutDirectionLeft:
  case UITextLayoutDirectionUp:
    idx -= offset;
    break;
  }
  if (idx < 0)
    idx = 0;
  if (idx > (NSInteger)_textBuffer.length)
    idx = _textBuffer.length;
  return [WWNTextPosition positionWithIndex:idx];
}

- (nullable UITextRange *)textRangeFromPosition:(UITextPosition *)fromPosition
                                     toPosition:(UITextPosition *)toPosition {
  NSInteger s = ((WWNTextPosition *)fromPosition).index;
  NSInteger e = ((WWNTextPosition *)toPosition).index;
  if (s > e) {
    NSInteger tmp = s;
    s = e;
    e = tmp;
  }
  return [WWNTextRange rangeWithStart:s end:e];
}

- (NSComparisonResult)comparePosition:(UITextPosition *)position
                           toPosition:(UITextPosition *)other {
  NSInteger a = ((WWNTextPosition *)position).index;
  NSInteger b = ((WWNTextPosition *)other).index;
  if (a < b)
    return NSOrderedAscending;
  if (a > b)
    return NSOrderedDescending;
  return NSOrderedSame;
}

- (NSInteger)offsetFromPosition:(UITextPosition *)from
                     toPosition:(UITextPosition *)toPosition {
  return ((WWNTextPosition *)toPosition).index -
         ((WWNTextPosition *)from).index;
}

// --- Geometry (cursor position from Wayland client) ---

- (CGRect)_cursorRectFromCompositor {
  CGRect r = [[WWNCompositorBridge sharedBridge] textInputCursorRect];
  if (r.size.width > 0 || r.size.height > 0) {
    return r;
  }
  return CGRectMake(0, 0, 1, 20);
}

- (CGRect)firstRectForRange:(UITextRange *)range {
  return [self _cursorRectFromCompositor];
}

- (CGRect)caretRectForPosition:(UITextPosition *)position {
  CGRect r = [self _cursorRectFromCompositor];
  CGFloat h = (r.size.height > 20) ? r.size.height : 20;
  return CGRectMake(r.origin.x, r.origin.y, 2, h);
}

- (NSArray<UITextSelectionRect *> *)selectionRectsForRange:
    (UITextRange *)range {
  return @[];
}

- (nullable UITextPosition *)closestPositionToPoint:(CGPoint)point {
  return [WWNTextPosition positionWithIndex:_textBuffer.length];
}

- (nullable UITextPosition *)closestPositionToPoint:(CGPoint)point
                                        withinRange:(UITextRange *)range {
  return ((WWNTextRange *)range).end;
}

- (nullable UITextRange *)characterRangeAtPoint:(CGPoint)point {
  return nil;
}

- (nullable UITextPosition *)positionWithinRange:(UITextRange *)range
                           farthestInDirection:(UITextLayoutDirection)direction {
  WWNTextRange *r = (WWNTextRange *)range;
  if (!r) return nil;
  // Simplistic stub: return start or end based on direction
  if (direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionUp) {
    return r.start;
  }
  return r.end;
}

- (nullable UITextRange *)characterRangeByExtendingPosition:(UITextPosition *)position
                                                inDirection:(UITextLayoutDirection)direction {
  // Stub
  return nil;
}

// --- Writing direction ---

- (NSWritingDirection)
    baseWritingDirectionForPosition:(nonnull UITextPosition *)position
                        inDirection:(UITextStorageDirection)direction {
  return NSWritingDirectionLeftToRight;
}

- (void)setBaseWritingDirection:(NSWritingDirection)writingDirection
                       forRange:(UITextRange *)range {
  // No-op — Wayland clients manage their own writing direction.
}

// --- Tokenizer ---

@synthesize inputDelegate;

- (id<UITextInputTokenizer>)tokenizer {
  if (!_tokenizer) {
    _tokenizer = [[UITextInputStringTokenizer alloc] initWithTextInput:self];
  }
  return _tokenizer;
}

// ---------------------------------------------------------------------------
#pragma mark - Public API
// ---------------------------------------------------------------------------

- (void)activateKeyboard {
  if (!self.isFirstResponder) {
    [self becomeFirstResponder];
  }
}

- (void)deactivateKeyboard {
  if (self.isFirstResponder) {
    [self resignFirstResponder];
  }
}

// ===========================================================================
#pragma mark - Touch Handling (Multi-Touch + Touchpad)
// ===========================================================================

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  // Snapshot the input mode at gesture start (don't switch mid-gesture)
  if (_activeTouchCount == 0) {
    _currentInputMode = [self _readInputMode];
    _maxTouchCount = 0;
    [self _ensureTouchpadCursorVisible];
  }
  _activeTouchCount = (NSInteger)[[event touchesForView:self] count];

  if (_currentInputMode == WWNTouchInputModeTouchpad) {
    [self _touchpad_touchesBegan:touches withEvent:event];
  } else {
    [self _multitouch_touchesBegan:touches withEvent:event];
  }

  if (!self.isFirstResponder) {
    [self becomeFirstResponder];
  }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  _activeTouchCount = (NSInteger)[[event touchesForView:self] count];

  if (_currentInputMode == WWNTouchInputModeTouchpad) {
    [self _touchpad_touchesMoved:touches withEvent:event];
  } else {
    [self _multitouch_touchesMoved:touches withEvent:event];
  }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (_currentInputMode == WWNTouchInputModeTouchpad) {
    [self _touchpad_touchesEnded:touches withEvent:event];
  } else {
    [self _multitouch_touchesEnded:touches withEvent:event];
  }

  // Update count *after* processing (so handlers see the ending count)
  _activeTouchCount =
      (NSInteger)[[event touchesForView:self] count] - (NSInteger)touches.count;
  if (_activeTouchCount < 0)
    _activeTouchCount = 0;
  if (_activeTouchCount == 0 && _currentInputMode == WWNTouchInputModeTouchpad) {
    _touchpadPointerEntered = NO;
  }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event {
  if (_currentInputMode == WWNTouchInputModeTouchpad) {
    [self _touchpad_touchesCancelled];
  } else {
    [[WWNCompositorBridge sharedBridge] injectTouchCancel];
  }
  _activeTouchCount = 0;
}

// ===========================================================================
#pragma mark - Multi-Touch Mode
// ===========================================================================
//
// Direct 1:1 touch-to-surface mapping via Wayland wl_touch events.
// Each finger is a separate touch point identified by its hash.
//
// Nested Weston desktop-shell only tracks wl_pointer for its cursor and
// launcher; the primary finger is also mirrored to pointer at touch location.

- (void)_multitouch_mirrorPointerAt:(CGPoint)loc
                          timestamp:(uint32_t)timestampMs
                       enterIfNeeded:(BOOL)enterIfNeeded {
  if (self.wwnWindowId == 0) {
    return;
  }
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  if (enterIfNeeded && !_multitouchPointerEntered) {
    CGPoint surfaceLoc = [self _surfacePointForViewPoint:loc];
    [bridge injectPointerEnterForWindow:self.wwnWindowId
                                      x:surfaceLoc.x
                                      y:surfaceLoc.y
                              timestamp:timestampMs];
    _multitouchPointerEntered = YES;
  }
  CGPoint surfaceLoc = [self _surfacePointForViewPoint:loc];
  [bridge injectPointerMotionForWindow:self.wwnWindowId
                                     x:surfaceLoc.x
                                     y:surfaceLoc.y
                             timestamp:timestampMs];
}

- (void)_multitouch_touchesBegan:(NSSet<UITouch *> *)touches
                       withEvent:(UIEvent *)event {
  uint32_t ts = (uint32_t)(event.timestamp * 1000);
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  if (_activeTouchCount == 1) {
    UITouch *firstTouch = [touches anyObject];
    _primaryTouchId = (int32_t)firstTouch.hash;
    _prevTouchPoint = [firstTouch locationInView:self];
    _touchStartTime = event.timestamp;
    _touchTotalMovement = 0;
    _multitouchPointerEntered = NO;
  }

  for (UITouch *touch in touches) {
    CGPoint loc = [touch locationInView:self];
    // Route wl_touch through the same letterbox-aware surface mapping the
    // pointer path uses, so touch points and the rendered cursor coincide.
    CGPoint sloc = [self _surfacePointForViewPoint:loc];
    int32_t touchId = (int32_t)touch.hash;
    [bridge injectTouchDown:touchId x:sloc.x y:sloc.y timestamp:ts];
    if (touchId == _primaryTouchId) {
      [self _multitouch_mirrorPointerAt:loc
                              timestamp:ts
                           enterIfNeeded:YES];
    }
  }
  [bridge injectTouchFrame];
}

- (void)_multitouch_touchesMoved:(NSSet<UITouch *> *)touches
                       withEvent:(UIEvent *)event {
  uint32_t ts = (uint32_t)(event.timestamp * 1000);
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  for (UITouch *touch in touches) {
    CGPoint loc = [touch locationInView:self];
    CGPoint sloc = [self _surfacePointForViewPoint:loc];
    int32_t touchId = (int32_t)touch.hash;
    [bridge injectTouchMotion:touchId x:sloc.x y:sloc.y timestamp:ts];
    if (touchId == _primaryTouchId) {
      // Movement tracking stays in view space (tap threshold is a screen-space
      // distance); only the injected coordinates are surface-mapped.
      _touchTotalMovement += fabs(loc.x - _prevTouchPoint.x) +
                             fabs(loc.y - _prevTouchPoint.y);
      _prevTouchPoint = loc;
      [self _multitouch_mirrorPointerAt:loc timestamp:ts enterIfNeeded:NO];
    }
  }
  [bridge injectTouchFrame];
}

- (void)_multitouch_touchesEnded:(NSSet<UITouch *> *)touches
                       withEvent:(UIEvent *)event {
  uint32_t ts = (uint32_t)(event.timestamp * 1000);
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  NSTimeInterval duration = event.timestamp - _touchStartTime;
  BOOL isShortTap = (_touchTotalMovement < kTapMovementThreshold &&
                     duration < kTapDurationThreshold);

  for (UITouch *touch in touches) {
    int32_t touchId = (int32_t)touch.hash;
    if (touchId == _primaryTouchId) {
      CGPoint loc = [touch locationInView:self];
      [self _multitouch_mirrorPointerAt:loc timestamp:ts enterIfNeeded:NO];
      if (isShortTap && (NSInteger)touches.count <= 1 && _activeTouchCount <= 1) {
        [bridge injectPointerButtonForWindow:self.wwnWindowId
                                      button:BTN_LEFT
                                     pressed:YES
                                   timestamp:ts];
        [bridge injectPointerButtonForWindow:self.wwnWindowId
                                      button:BTN_LEFT
                                     pressed:NO
                                   timestamp:ts + 1];
      }
    }
    [bridge injectTouchUp:touchId timestamp:ts];
  }
  [bridge injectTouchFrame];
}

// ===========================================================================
#pragma mark - Touchpad Mode
// ===========================================================================
//
// Simulates a laptop trackpad:
//   1 finger drag       → move pointer (relative)
//   1 finger tap        → left click at virtual cursor (touch location ignored)
//   1 finger tap+hold   → at 0.5s a radial indicator appears and fills; at 1.0s
//                         a sustained LMB-down engages so the finger drags, and
//                         lifting releases LMB
//   2 finger tap        → right click at virtual cursor
//   2 finger drag       → scroll (vertical + horizontal)
//
// The virtual pointer position persists across gestures.

// Show the radial indicator at the current cursor and animate it filling over
// the (engage - show) window.
- (void)_touchpad_showRadial {
  if (!_radialLayer) {
    const CGFloat r = kTouchpadRadialRadius;
    _radialLayer = [CAShapeLayer layer];
    UIBezierPath *path =
        [UIBezierPath bezierPathWithArcCenter:CGPointMake(r, r)
                                       radius:r - 4.0
                                   startAngle:-M_PI_2
                                     endAngle:(3.0 * M_PI_2)
                                    clockwise:YES];
    _radialLayer.path = path.CGPath;
    _radialLayer.bounds = CGRectMake(0, 0, 2 * r, 2 * r);
    _radialLayer.fillColor = [UIColor clearColor].CGColor;
    _radialLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    _radialLayer.lineWidth = 3.0;
    _radialLayer.lineCap = kCALineCapRound;
    _radialLayer.zPosition = 10001; // above the cursor layer
  }
  [self _repositionRadialLayer];
  if (_radialLayer.superlayer != self.layer) {
    [self.layer addSublayer:_radialLayer];
  }
  _radialLayer.hidden = NO;
  _radialLayer.strokeEnd = 0.0;

  CABasicAnimation *fill =
      [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
  fill.fromValue = @0.0;
  fill.toValue = @1.0;
  fill.duration = (kDragEngageDelay - kDragArmShowDelay);
  fill.removedOnCompletion = NO;
  fill.fillMode = kCAFillModeForwards;
  [_radialLayer addAnimation:fill forKey:@"fill"];
}

- (void)_touchpad_hideRadial {
  [_radialLayer removeAllAnimations];
  _radialLayer.hidden = YES;
}

// Invalidate any pending arm callbacks and hide the radial. Does NOT release an
// already-engaged drag.
- (void)_touchpad_cancelDragArm {
  _dragGeneration++;
  [self _touchpad_hideRadial];
}

// Engage the sustained LMB-down drag at the virtual cursor.
- (void)_touchpad_engageDrag {
  if (_dragging) {
    return;
  }
  _dragging = YES;
  uint32_t ts = [self _timestampMs];
  [self _touchpad_ensurePointerEntered];
  [self _touchpad_syncPointerPosition:ts];
  [[WWNCompositorBridge sharedBridge]
      injectPointerButtonForWindow:self.wwnWindowId
                            button:BTN_LEFT
                           pressed:YES
                         timestamp:ts];
  if (@available(iOS 10.0, *)) {
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium];
    [fb impactOccurred];
  }
  [self _touchpad_hideRadial];
}

- (void)_touchpad_touchesBegan:(NSSet<UITouch *> *)touches
                     withEvent:(UIEvent *)event {
  UITouch *firstTouch = [touches anyObject];
  CGPoint loc = [firstTouch locationInView:self];

  _touchStartTime = event.timestamp;
  _touchTotalMovement = 0;
  _scrollActive = NO;
  if (_activeTouchCount > _maxTouchCount) {
    _maxTouchCount = _activeTouchCount;
  }

  if (_activeTouchCount >= 2) {
    // A second finger landed: cancel any pending single-finger drag arm.
    [self _touchpad_cancelDragArm];
    _prevScrollCenter = [self _centroidOfTouches:event];
  } else if (_activeTouchCount == 1) {
    _prevTouchPoint = loc;
    _dragging = NO;
    // Arm the tap-and-hold drag: show the radial at 0.5s, engage at 1.0s.
    NSInteger gen = ++_dragGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(kDragArmShowDelay * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          typeof(self) s = weakSelf;
          if (!s || s->_dragGeneration != gen || s->_activeTouchCount != 1 ||
              s->_scrollActive || s->_dragging ||
              s->_touchTotalMovement >= kTapMovementThreshold) {
            return;
          }
          [s _touchpad_showRadial];
        });
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(kDragEngageDelay * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          typeof(self) s = weakSelf;
          if (!s || s->_dragGeneration != gen || s->_activeTouchCount != 1 ||
              s->_scrollActive ||
              s->_touchTotalMovement >= kTapMovementThreshold) {
            return;
          }
          [s _touchpad_engageDrag];
        });
  }

  // Ensure the pointer has entered the window and Weston knows cursor position
  [self _touchpad_ensurePointerEntered];
  [self _touchpad_syncPointerPosition:(uint32_t)(event.timestamp * 1000)];
}

- (void)_touchpad_touchesMoved:(NSSet<UITouch *> *)touches
                     withEvent:(UIEvent *)event {
  uint32_t ts = (uint32_t)(event.timestamp * 1000);
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  if (_activeTouchCount >= 2) {
    // --- Two (or more) finger drag → scroll ---
    _scrollActive = YES;
    [self _touchpad_ensurePointerEntered];
    [self _touchpad_syncPointerPosition:ts];

    CGPoint center = [self _centroidOfTouches:event];
    CGFloat dx = (center.x - _prevScrollCenter.x) * kScrollSensitivity;
    CGFloat dy = (center.y - _prevScrollCenter.y) * kScrollSensitivity;
    _prevScrollCenter = center;

    _touchTotalMovement += fabs(dx) + fabs(dy);

    if (fabs(dy) > 0.5) {
      [bridge injectPointerAxisForWindow:self.wwnWindowId
                                    axis:0 // vertical
                                   value:-dy
                                discrete:0
                               timestamp:ts];
    }
    if (fabs(dx) > 0.5) {
      [bridge injectPointerAxisForWindow:self.wwnWindowId
                                    axis:1 // horizontal
                                   value:-dx
                                discrete:0
                               timestamp:ts];
    }
  } else if (_activeTouchCount == 1) {
    // --- Single finger drag → move pointer (or drag if engaged) ---
    UITouch *touch = [touches anyObject];
    CGPoint loc = [touch locationInView:self];
    CGFloat dx = (loc.x - _prevTouchPoint.x) * kTouchpadSensitivity;
    CGFloat dy = (loc.y - _prevTouchPoint.y) * kTouchpadSensitivity;
    _prevTouchPoint = loc;

    _touchTotalMovement += fabs(dx) + fabs(dy);

    // Movement before engage cancels the tap-and-hold arm so it becomes a plain
    // pointer move rather than an accidental drag.
    if (!_dragging && _touchTotalMovement >= kTapMovementThreshold) {
      [self _touchpad_cancelDragArm];
    }

    // Update virtual pointer, clamped to view bounds
    CGFloat clampedX = _pointerPos.x + dx;
    if (clampedX < 0) clampedX = 0;
    if (clampedX > self.bounds.size.width) clampedX = self.bounds.size.width;
    _pointerPos.x = clampedX;

    CGFloat clampedY = _pointerPos.y + dy;
    if (clampedY < 0) clampedY = 0;
    if (clampedY > self.bounds.size.height) clampedY = self.bounds.size.height;
    _pointerPos.y = clampedY;

    CGPoint surfacePos = [self _surfacePointerPosition];
    // With a drag engaged the LMB stays down, so this motion drags.
    [bridge injectPointerMotionForWindow:self.wwnWindowId
                                       x:surfacePos.x
                                       y:surfacePos.y
                               timestamp:ts];

    [self _ensureTouchpadCursorVisible];
    [self _repositionCursorLayer];
  }
}

- (void)_touchpad_touchesEnded:(NSSet<UITouch *> *)touches
                     withEvent:(UIEvent *)event {
  uint32_t ts = (uint32_t)(event.timestamp * 1000);
  NSTimeInterval duration = event.timestamp - _touchStartTime;
  BOOL lowMovement = _touchTotalMovement < kTapMovementThreshold;
  BOOL isShortTap = lowMovement && duration < kTapDurationThreshold;

  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  // The wrapper decrements _activeTouchCount after we return; compute whether
  // this end-event finishes the whole gesture (all fingers up).
  NSInteger remaining = _activeTouchCount - (NSInteger)touches.count;
  BOOL gestureEnding = (remaining <= 0);

  if (_dragging) {
    // Release the sustained LMB-down that the tap-and-hold drag engaged.
    [self _touchpad_syncPointerPosition:ts];
    [bridge injectPointerButtonForWindow:self.wwnWindowId
                                  button:BTN_LEFT
                                 pressed:NO
                               timestamp:ts];
    _dragging = NO;
  } else if (gestureEnding && !_scrollActive && lowMovement &&
             duration < kTapDurationThreshold && _maxTouchCount >= 2) {
    // Two-finger tap → right click at virtual cursor.
    [self _touchpad_ensurePointerEntered];
    [self _touchpad_syncPointerPosition:ts];
    [bridge injectPointerButtonForWindow:self.wwnWindowId
                                  button:BTN_RIGHT
                                 pressed:YES
                               timestamp:ts];
    [bridge injectPointerButtonForWindow:self.wwnWindowId
                                  button:BTN_RIGHT
                                 pressed:NO
                               timestamp:ts + 1];
  } else if (isShortTap && !_scrollActive && gestureEnding &&
             _maxTouchCount <= 1) {
    // Single-finger tap → left click at virtual cursor.
    [self _touchpad_ensurePointerEntered];
    [self _touchpad_syncPointerPosition:ts];
    [bridge injectPointerButtonForWindow:self.wwnWindowId
                                  button:BTN_LEFT
                                 pressed:YES
                               timestamp:ts];
    [bridge injectPointerButtonForWindow:self.wwnWindowId
                                  button:BTN_LEFT
                                 pressed:NO
                               timestamp:ts + 1];
  }

  [self _touchpad_cancelDragArm];
  if (gestureEnding) {
    _scrollActive = NO;
  }
}

- (void)_touchpad_touchesCancelled {
  if (_dragging) {
    [[WWNCompositorBridge sharedBridge]
        injectPointerButtonForWindow:self.wwnWindowId
                              button:BTN_LEFT
                             pressed:NO
                           timestamp:[self _timestampMs]];
    _dragging = NO;
  }
  [self _touchpad_cancelDragArm];
  _scrollActive = NO;
  _activeTouchCount = 0;
  _maxTouchCount = 0;
  _touchpadPointerEntered = NO;
}

/// Map the virtual cursor position into Wayland surface coordinates when
/// the presented frame is letterboxed inside the compositor view.
- (CGPoint)_surfacePointerPosition {
  CGPoint pos = _pointerPos;
  if (_waylandFrameView.hidden || _waylandFrameView.layer.contents == nil) {
    return pos;
  }
  CGRect frame = _waylandFrameView.frame;
  if (frame.size.width <= 0.0 || frame.size.height <= 0.0 ||
      CGRectEqualToRect(frame, self.bounds)) {
    return pos;
  }
  pos.x -= frame.origin.x;
  pos.y -= frame.origin.y;
  if (pos.x < 0.0)
    pos.x = 0.0;
  if (pos.y < 0.0)
    pos.y = 0.0;
  if (pos.x > frame.size.width)
    pos.x = frame.size.width;
  if (pos.y > frame.size.height)
    pos.y = frame.size.height;
  return pos;
}

- (CGPoint)_surfacePointForViewPoint:(CGPoint)viewPoint {
  if (_waylandFrameView.hidden || _waylandFrameView.layer.contents == nil) {
    return viewPoint;
  }
  CGRect frame = _waylandFrameView.frame;
  if (frame.size.width <= 0.0 || frame.size.height <= 0.0 ||
      CGRectEqualToRect(frame, self.bounds)) {
    return viewPoint;
  }
  CGPoint pos =
      CGPointMake(viewPoint.x - frame.origin.x, viewPoint.y - frame.origin.y);
  if (pos.x < 0.0)
    pos.x = 0.0;
  if (pos.y < 0.0)
    pos.y = 0.0;
  if (pos.x > frame.size.width)
    pos.x = frame.size.width;
  if (pos.y > frame.size.height)
    pos.y = frame.size.height;
  return pos;
}

/// Sends pointer enter once, then motion to sync the virtual cursor position.
- (void)_touchpad_ensurePointerEntered {
  if (self.wwnWindowId == 0) {
    return;
  }
  if (_touchpadPointerEntered) {
    return;
  }
  CGPoint pos = [self _surfacePointerPosition];
  uint32_t ts = [self _timestampMs];
  [[WWNCompositorBridge sharedBridge]
      injectPointerEnterForWindow:self.wwnWindowId
                                x:pos.x
                                y:pos.y
                        timestamp:ts];
  [[WWNCompositorBridge sharedBridge]
      injectPointerMotionForWindow:self.wwnWindowId
                                 x:pos.x
                                 y:pos.y
                         timestamp:ts];
  _touchpadPointerEntered = YES;
}

- (void)_touchpad_syncPointerPosition:(uint32_t)timestampMs {
  if (self.wwnWindowId == 0) {
    return;
  }
  CGPoint pos = [self _surfacePointerPosition];
  [[WWNCompositorBridge sharedBridge]
      injectPointerMotionForWindow:self.wwnWindowId
                                 x:pos.x
                                 y:pos.y
                         timestamp:timestampMs];
}

/// Compute the centroid (average position) of all touches currently on
/// this view.
- (CGPoint)_centroidOfTouches:(UIEvent *)event {
  NSSet<UITouch *> *allTouches = [event touchesForView:self];
  CGFloat sumX = 0, sumY = 0;
  NSUInteger count = 0;
  for (UITouch *t in allTouches) {
    if (t.phase == UITouchPhaseCancelled || t.phase == UITouchPhaseEnded)
      continue;
    CGPoint loc = [t locationInView:self];
    sumX += loc.x;
    sumY += loc.y;
    count++;
  }
  if (count == 0)
    return CGPointZero;
  return CGPointMake(sumX / count, sumY / count);
}

// ---------------------------------------------------------------------------
#pragma mark - Physical Keyboard Support (iPad, Bluetooth, Simulator passthrough)
// ---------------------------------------------------------------------------

- (NSArray<UIKeyCommand *> *)keyCommands {
  // UIKeyCommand is still needed for keys that iOS intercepts before
  // pressesBegan fires (Escape is one such key on some iOS versions).
  NSMutableArray *commands = [NSMutableArray array];
  [commands
      addObject:[UIKeyCommand keyCommandWithInput:UIKeyInputEscape
                                    modifierFlags:0
                                           action:@selector(handleEscape:)]];
  return commands;
}

- (void)handleEscape:(UIKeyCommand *)command {
  uint32_t ts = [self _timestampMs];
  [self _sendKeyPress:KEY_ESC withShift:NO timestamp:ts];
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses
           withEvent:(UIPressesEvent *)event {
  if (@available(iOS 13.4, *)) {
    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
    uint32_t ts = [self _timestampMs];
    BOOL handled = NO;

    for (UIPress *press in presses) {
      UIKey *key = press.key;
      if (!key)
        continue;

      uint32_t kc = hidUsageToLinuxKeycode(key.keyCode);
      if (kc == KEY_RESERVED)
        continue;

      if (wwn_ios_terminal_is_active() && kc == KEY_BACKSPACE) {
        static const char del = 0x7f;
        wwn_ios_terminal_inject(&del, 1);
        handled = YES;
        continue;
      }

      handled = YES;
      _pressedPhysicalKeyCount++;

      [self _sendKeyboardEnterIfNeeded];

      [bridge injectKeyWithKeycode:kc pressed:YES timestamp:ts];

      if (isModifierKeycode(kc)) {
        _physicalModifiers |= modifierBitForKeycode(kc);
        [bridge injectModifiersWithDepressed:_physicalModifiers
                                     latched:0
                                      locked:0
                                       group:0];
      }
    }

    if (!handled) {
      [super pressesBegan:presses withEvent:event];
    }
  } else {
    [super pressesBegan:presses withEvent:event];
  }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses
           withEvent:(UIPressesEvent *)event {
  if (@available(iOS 13.4, *)) {
    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
    uint32_t ts = [self _timestampMs];
    BOOL handled = NO;

    for (UIPress *press in presses) {
      UIKey *key = press.key;
      if (!key)
        continue;

      uint32_t kc = hidUsageToLinuxKeycode(key.keyCode);
      if (kc == KEY_RESERVED)
        continue;

      if (wwn_ios_terminal_is_active() && kc == KEY_BACKSPACE) {
        handled = YES;
        continue;
      }

      handled = YES;
      if (_pressedPhysicalKeyCount > 0)
        _pressedPhysicalKeyCount--;

      [bridge injectKeyWithKeycode:kc pressed:NO timestamp:ts];

      if (isModifierKeycode(kc)) {
        _physicalModifiers &= ~modifierBitForKeycode(kc);
        [bridge injectModifiersWithDepressed:_physicalModifiers
                                     latched:0
                                      locked:0
                                       group:0];
      }
    }

    if (!handled) {
      [super pressesEnded:presses withEvent:event];
    }
  } else {
    [super pressesEnded:presses withEvent:event];
  }
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses
               withEvent:(UIPressesEvent *)event {
  if (@available(iOS 13.4, *)) {
    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
    uint32_t ts = [self _timestampMs];

    for (UIPress *press in presses) {
      UIKey *key = press.key;
      if (!key)
        continue;

      uint32_t kc = hidUsageToLinuxKeycode(key.keyCode);
      if (kc == KEY_RESERVED)
        continue;

      if (_pressedPhysicalKeyCount > 0)
        _pressedPhysicalKeyCount--;

      [bridge injectKeyWithKeycode:kc pressed:NO timestamp:ts];

      if (isModifierKeycode(kc)) {
        _physicalModifiers &= ~modifierBitForKeycode(kc);
        [bridge injectModifiersWithDepressed:_physicalModifiers
                                     latched:0
                                      locked:0
                                       group:0];
      }
    }
  }
  [super pressesCancelled:presses withEvent:event];
}

// ---------------------------------------------------------------------------
#pragma mark - Wayland Cursor Rendering (Touchpad Mode)
// ---------------------------------------------------------------------------

- (void)updateCursorImage:(id)image
                    width:(uint32_t)width
                   height:(uint32_t)height
                 hotspotX:(float)hotspotX
                 hotspotY:(float)hotspotY {
  if (![[WWNPreferencesManager sharedManager] renderMacOSPointer]) {
    _cursorLayer.contents = nil;
    _cursorLayer.hidden = YES;
    return;
  }

  if (image) {
    _cursorLayer.contents = image;
    _cursorLayer.bounds = CGRectMake(0, 0, width, height);
    _cursorHotspotX = hotspotX;
    _cursorHotspotY = hotspotY;
    _cursorLayer.hidden = (_currentInputMode != WWNTouchInputModeTouchpad);
    [self _repositionCursorLayer];
    return;
  }

  if (_currentInputMode == WWNTouchInputModeTouchpad) {
    [self _applyDefaultTouchpadCursorAppearance];
    _cursorLayer.hidden = NO;
    [self _repositionCursorLayer];
    return;
  }

  _cursorLayer.contents = nil;
  _cursorLayer.hidden = YES;
}

/// Position the radial drag indicator centered on the pointer hotspot (arrow tip).
- (void)_repositionRadialLayer {
  if (!_radialLayer) {
    return;
  }
  _radialLayer.position = _pointerPos;
}

/// Position the cursor layer at the virtual pointer location, offset by the
/// hotspot so the "active point" of the cursor sits exactly at _pointerPos.
- (void)_repositionCursorLayer {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _cursorLayer.position = CGPointMake(
      _pointerPos.x - _cursorHotspotX + _cursorLayer.bounds.size.width / 2.0,
      _pointerPos.y - _cursorHotspotY + _cursorLayer.bounds.size.height / 2.0);
  [self _repositionRadialLayer];
  [CATransaction commit];
}

// ---------------------------------------------------------------------------
#pragma mark - Private Helpers
// ---------------------------------------------------------------------------

- (void)_sendKeyboardEnterIfNeeded {
  if (!_keyboardEnterSent && self.wwnWindowId > 0) {
    WWNLog("IOS_VIEW", @"Sending keyboard enter for window %llu",
           self.wwnWindowId);
    [[WWNCompositorBridge sharedBridge]
        injectKeyboardEnterForWindow:self.wwnWindowId
                                keys:@[]];
    _keyboardEnterSent = YES;
  }
}

- (void)_sendKeyboardLeave {
  if (_keyboardEnterSent && self.wwnWindowId > 0) {
    WWNLog("IOS_VIEW", @"Sending keyboard leave for window %llu",
           self.wwnWindowId);
    [[WWNCompositorBridge sharedBridge]
        injectKeyboardLeaveForWindow:self.wwnWindowId];
    _keyboardEnterSent = NO;
  }
}

- (void)_sendKeyPress:(uint32_t)keycode
            withShift:(BOOL)needsShift
            timestamp:(uint32_t)ts {
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  if (needsShift) {
    [bridge injectKeyWithKeycode:KEY_LEFTSHIFT pressed:YES timestamp:ts];
    [bridge injectModifiersWithDepressed:XKB_MOD_SHIFT
                                 latched:0
                                  locked:0
                                   group:0];
  }

  [bridge injectKeyWithKeycode:keycode pressed:YES timestamp:ts];
  [bridge injectKeyWithKeycode:keycode pressed:NO timestamp:ts + 1];

  if (needsShift) {
    [bridge injectKeyWithKeycode:KEY_LEFTSHIFT pressed:NO timestamp:ts + 2];
    [bridge injectModifiersWithDepressed:0 latched:0 locked:0 group:0];
  }
}

- (uint32_t)_timestampMs {
  return (uint32_t)([[NSProcessInfo processInfo] systemUptime] * 1000);
}

@end
