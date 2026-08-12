#import "WWNWindow.h"
#import "../../util/WWNLog.h"
#import "WWNCompositorBridge.h"
#import "WWNSettings.h"
#import "WWNIlandPresenter.h"
#import "ui/Machines/WWNMachineProfileStore.h"
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

@interface WWNWindow ()
@property(nonatomic, assign) BOOL wwnCloseDeferred;
@property(nonatomic, strong) NSTimer *wwnCloseForceTimer;
@end

//
// WWNView Implementation (macOS)
//
@implementation WWNView {
  CALayer *contentLayer_;
  CAMetalLayer *metalLayer_;
  WWNIlandPresenter *ilandPresenter_;
  // NSTextInputClient state for IME / emoji composition
  NSString *markedText_;
  NSRange markedRange_;
  NSRange selectedRange_;
  // Set to YES during keyDown: if the raw keycode was already injected,
  // so insertText:replacementRange: can skip duplicate key events.
  BOOL handledByKeyEvent_;

  // Text Assist proxy buffer for autocorrect / text replacement context
  NSMutableString *textBuffer_;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;

    // Prevent NSView from scaling or redrawing contents during resize
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
    self.layerContentsPlacement = NSViewLayerContentsPlacementTopLeft;

    contentLayer_ = [CALayer layer];
    contentLayer_.geometryFlipped = YES;
    contentLayer_.contentsGravity = kCAGravityTopLeft;
    contentLayer_.masksToBounds =
        NO; // Allow subsurfaces to extend outside (Wayland spec)
    contentLayer_.autoresizingMask =
        kCALayerWidthSizable | kCALayerHeightSizable;
    [self.layer addSublayer:contentLayer_];
    [self updateTrackingAreas];

    textBuffer_ = [NSMutableString string];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(defaultsChanged:)
               name:NSUserDefaultsDidChangeNotification
             object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)defaultsChanged:(NSNotification *)notification {
  (void)notification;
  [self.window invalidateCursorRectsForView:self];
}

- (CALayer *)contentLayer {
  if (!contentLayer_) {
    contentLayer_ = [CALayer layer];
    contentLayer_.geometryFlipped = YES;
    contentLayer_.contentsGravity = kCAGravityTopLeft;
    contentLayer_.masksToBounds =
        NO; // Allow subsurfaces to extend outside (Wayland spec)
    contentLayer_.autoresizingMask =
        kCALayerWidthSizable | kCALayerHeightSizable;
    if (self.layer) {
      [self.layer addSublayer:contentLayer_];
    }
  }
  return contentLayer_;
}

- (void)setFrame:(NSRect)frame {
  [super setFrame:frame];
  contentLayer_.frame = self.bounds;
}

- (void)setBounds:(NSRect)bounds {
  [super setBounds:bounds];
  contentLayer_.frame = self.bounds;
}

- (void)layout {
  [super layout];
  contentLayer_.frame = self.bounds;
  if (metalLayer_) {
    // -updateLayer only runs when the view is marked for display, so a live
    // resize drag needs the layout pass to republish geometry too.
    metalLayer_.frame = self.bounds;
    [ilandPresenter_ hostGeometryDidChange];
  }
}

- (void)updateLayer {
  [super updateLayer];
  contentLayer_.frame = self.bounds;
  if (metalLayer_) {
    metalLayer_.frame = self.bounds;
    // Republish the mode here rather than from the present callback: the client
    // render thread must not read CALayer geometry, and a per-present refresh
    // was inert anyway (iland applies the preferred mode at enumeration).
    [ilandPresenter_ hostGeometryDidChange];
  }
}

- (BOOL)prepareIlandMetalPresentation {
  self.wantsLayer = YES;
  if (!metalLayer_) {
    metalLayer_ = [CAMetalLayer layer];
    metalLayer_.geometryFlipped = YES;
    metalLayer_.frame = self.bounds;
    metalLayer_.contentsScale = self.window.backingScaleFactor ?: 1.0;
    metalLayer_.autoresizingMask =
        kCALayerWidthSizable | kCALayerHeightSizable;
    [self.layer addSublayer:metalLayer_];
  }
  metalLayer_.hidden = NO;
  metalLayer_.frame = self.bounds;
  // Never tear down a presenter that already owns an in-process DRM client —
  // recreating it left the old kmscube/gbm thread alive and made the next
  // Start look like the previous client (title + frames).
  if (ilandPresenter_) {
    if ([ilandPresenter_ runningClientId].length > 0) {
      contentLayer_.hidden = YES;
      return YES;
    }
    [ilandPresenter_ invalidate];
    ilandPresenter_ = nil;
  }
  ilandPresenter_ =
      [[WWNIlandPresenter alloc] initWithLayer:metalLayer_ device:nil];
  contentLayer_.hidden = YES;
  return ilandPresenter_ != nil;
}

- (BOOL)launchNestedIlandGpuClient:(NSString *)clientId {
  NSString *running = [ilandPresenter_ runningClientId];
  if (running.length > 0) {
    if ([running isEqualToString:clientId]) {
      return YES;
    }
    WWNLog("CLIENT",
           @"refusing %@ — in-process %@ still owns iland DRM (Stop that "
           @"machine first)",
           clientId, running);
    return NO;
  }
  if (![self prepareIlandMetalPresentation]) {
    return NO;
  }
  int w = (int)self.bounds.size.width;
  int h = (int)self.bounds.size.height;
  if (w <= 0 || h <= 0) {
    w = 1280;
    h = 720;
  }
  return [ilandPresenter_ launchNestedIlandGpuClient:clientId
                                               width:w
                                              height:h];
}

- (BOOL)launchNestedKmscube {
  return [self launchNestedIlandGpuClient:@"kmscube"];
}

- (void)updateTrackingAreas {
  for (NSTrackingArea *area_to_remove in self.trackingAreas) {
    [self removeTrackingArea:area_to_remove];
  }

  NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
      initWithRect:self.bounds
           options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                   NSTrackingActiveAlways | NSTrackingInVisibleRect
             owner:self
          userInfo:nil];

  [self addTrackingArea:trackingArea];
  [super updateTrackingAreas];
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

// Route Ctrl+C, Ctrl+Z, etc. to keyDown: instead of the menu bar (terminal emulators).
- (BOOL)performKeyEquivalent:(NSEvent *)event {
  if ((event.modifierFlags & NSEventModifierFlagCommand) &&
      !(event.modifierFlags & NSEventModifierFlagControl) &&
      !(event.modifierFlags & NSEventModifierFlagOption)) {
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars isEqualToString:@"q"] || [chars isEqualToString:@"Q"] ||
        [chars isEqualToString:@"h"] || [chars isEqualToString:@"H"] ||
        [chars isEqualToString:@"m"] || [chars isEqualToString:@"M"]) {
      return NO;
    }
  }

  [self keyDown:event];
  return YES;
}

- (BOOL)isFlipped {
  return YES;
}

// Helper to get window ID
- (uint64_t)wwnWindowId {
  if (self.overrideWindowId != 0) {
    return self.overrideWindowId;
  }
  if ([self.window isKindOfClass:[WWNWindow class]]) {
    return [(WWNWindow *)self.window wwnWindowId];
  }
  return 0;
}

//
// Input Handling
//

- (void)mouseEntered:(NSEvent *)event {
  NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
  double y = loc.y;

  [[WWNCompositorBridge sharedBridge]
      injectPointerEnterForWindow:[self wwnWindowId]
                                x:loc.x
                                y:y
                        timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)mouseExited:(NSEvent *)event {
  [[WWNCompositorBridge sharedBridge]
      injectPointerLeaveForWindow:[self wwnWindowId]
                        timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)mouseMoved:(NSEvent *)event {
  NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
  double y = loc.y;

  [[WWNCompositorBridge sharedBridge]
      injectPointerMotionForWindow:[self wwnWindowId]
                                 x:loc.x
                                 y:y
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)mouseDragged:(NSEvent *)event {
  [self mouseMoved:event];
}

- (void)mouseDown:(NSEvent *)event {
  WWNWindow *wwnWindow = nil;
  if ([self.window isKindOfClass:[WWNWindow class]]) {
    wwnWindow = (WWNWindow *)self.window;
    // Kept for xdg_toplevel.move → handleWindowMoveRequested →
    // performWindowDragWithEvent (serial must match this button press).
    wwnWindow.lastMouseDownEvent = event;
  }
  [[WWNCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wwnWindowId]
                            button:0x110 // BTN_LEFT
                           pressed:YES
                         timestamp:(uint32_t)(event.timestamp * 1000)];
  // Do NOT start an AppKit window drag here. Clients that want content-drag
  // (weston-flower, weston-simple-egl, CSD titlebars) issue xdg_toplevel.move
  // from their button handler; the compositor surfaces that as
  // WindowMoveRequested. Host-initiated whole-surface drag steals text
  // selection and nested-compositor gestures (niri).
}

- (void)mouseUp:(NSEvent *)event {
  if ([self.window isKindOfClass:[WWNWindow class]]) {
    ((WWNWindow *)self.window).lastMouseDownEvent = nil;
  }
  [[WWNCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wwnWindowId]
                            button:0x110 // BTN_LEFT
                           pressed:NO
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)rightMouseDown:(NSEvent *)event {
  [[WWNCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wwnWindowId]
                            button:0x111 // BTN_RIGHT
                           pressed:YES
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)rightMouseUp:(NSEvent *)event {
  [[WWNCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wwnWindowId]
                            button:0x111 // BTN_RIGHT
                           pressed:NO
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

// wl_pointer.axis (scroll). NSEvent already applies the user's natural-
// scrolling preference before we see it, so deltas are forwarded as-is —
// no manual inversion. Trackpads report continuous, already-pixel-scaled
// deltas via scrollingDelta{X,Y} (hasPreciseScrollingDeltas); traditional
// mouse wheels report whole "clicks" via delta{X,Y} (~1.0 per notch), which
// we scale up to roughly match the pixel-ish magnitude wl_pointer.axis
// expects — same 15x convention the Linux GTK UI uses for its scroll
// controller (see wawona-linux-ui.rs) so client-side scroll speed (e.g.
// weston-terminal's AXIS_UNITS_PER_LINE) behaves consistently everywhere.
- (void)scrollWheel:(NSEvent *)event {
  double dx, dy;
  uint32_t source; // matches WWNCoreInjectPointerAxis's AxisSource::Finger today
  if (event.hasPreciseScrollingDeltas) {
    dx = event.scrollingDeltaX;
    dy = event.scrollingDeltaY;
    source = 1; // continuous / trackpad
  } else {
    dx = event.deltaX * 15.0;
    dy = event.deltaY * 15.0;
    source = 0; // wheel
  }
  (void)source; // WWNCoreInjectPointerAxis doesn't take a source yet.

  if (dx == 0.0 && dy == 0.0) {
    return;
  }

  uint64_t windowId = [self wwnWindowId];
  uint32_t timestampMs = (uint32_t)(event.timestamp * 1000);
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  if (dy != 0.0) {
    [bridge injectPointerAxisForWindow:windowId
                                  axis:0 // vertical
                                 value:dy
                              discrete:0
                             timestamp:timestampMs];
  }
  if (dx != 0.0) {
    [bridge injectPointerAxisForWindow:windowId
                                  axis:1 // horizontal
                                 value:dx
                              discrete:0
                             timestamp:timestampMs];
  }
}

// Helper to translate macOS keycodes to XKB/Evdev keycodes (offset by 8)
static uint32_t MacosToXkbKeycode(unsigned short macCode) {
  switch (macCode) {
  case 0:
    return 30; // A -> KEY_A
  case 1:
    return 31; // S -> KEY_S
  case 2:
    return 32; // D -> KEY_D
  case 3:
    return 33; // F -> KEY_F
  case 4:
    return 35; // H -> KEY_H
  case 5:
    return 34; // G -> KEY_G
  case 6:
    return 44; // Z -> KEY_Z
  case 7:
    return 45; // X -> KEY_X
  case 8:
    return 46; // C -> KEY_C
  case 9:
    return 47; // V -> KEY_V
  case 11:
    return 48; // B -> KEY_B
  case 12:
    return 16; // Q -> KEY_Q
  case 13:
    return 17; // W -> KEY_W
  case 14:
    return 18; // E -> KEY_E
  case 15:
    return 19; // R -> KEY_R
  case 16:
    return 21; // Y -> KEY_Y
  case 17:
    return 20; // T -> KEY_T
  case 18:
    return 2; // 1 -> KEY_1
  case 19:
    return 3; // 2 -> KEY_2
  case 20:
    return 4; // 3 -> KEY_3
  case 21:
    return 5; // 4 -> KEY_4
  case 22:
    return 7; // 6 -> KEY_6
  case 23:
    return 6; // 5 -> KEY_5
  case 24:
    return 13; // = -> KEY_EQUAL
  case 25:
    return 10; // 9 -> KEY_9
  case 26:
    return 8; // 7 -> KEY_7
  case 27:
    return 12; // - -> KEY_MINUS
  case 28:
    return 9; // 8 -> KEY_8
  case 29:
    return 11; // 0 -> KEY_0
  case 30:
    return 27; // ] -> KEY_RIGHTBRACE
  case 31:
    return 24; // O -> KEY_O
  case 32:
    return 22; // U -> KEY_U
  case 33:
    return 26; // [ -> KEY_LEFTBRACE
  case 34:
    return 23; // I -> KEY_I
  case 35:
    return 25; // P -> KEY_P
  case 36:
    return 28; // Return -> KEY_ENTER
  case 37:
    return 38; // L -> KEY_L
  case 38:
    return 36; // J -> KEY_J
  case 39:
    return 40; // ' -> KEY_APOSTROPHE
  case 40:
    return 37; // K -> KEY_K
  case 41:
    return 39; // ; -> KEY_SEMICOLON
  case 42:
    return 43; // \ -> KEY_BACKSLASH
  case 43:
    return 51; // , -> KEY_COMMA
  case 44:
    return 53; // / -> KEY_SLASH
  case 45:
    return 49; // N -> KEY_N
  case 46:
    return 50; // M -> KEY_M
  case 47:
    return 52; // . -> KEY_DOT
  case 48:
    return 15; // Tab -> KEY_TAB
  case 49:
    return 57; // Space -> KEY_SPACE
  case 50:
    return 41; // ` -> KEY_GRAVE
  case 51:
    return 14; // Delete (Backspace) -> KEY_BACKSPACE
  case 53:
    return 1; // Esc -> KEY_ESC
  case 55:
    return 125; // Command -> KEY_LEFTMETA (Super)
  case 54:
    return 126; // Right Command -> KEY_RIGHTMETA (Super_R)
  case 63:
    return 464; // Fn -> KEY_FN (0x1d0)
  case 56:
    return 42; // Shift Left -> KEY_LEFTSHIFT
  case 57:
    return 58; // Caps Lock -> KEY_CAPSLOCK
  case 58:
    return 56; // Option Left -> KEY_LEFTALT
  case 59:
    return 29; // Control Left -> KEY_LEFTCTRL
  case 60:
    return 54; // Shift Right -> KEY_RIGHTSHIFT
  case 61:
    return 100; // Option Right -> KEY_RIGHTALT
  case 62:
    return 97; // Control Right -> KEY_RIGHTCTRL
  case 123:
    return 105; // Left -> KEY_LEFT
  case 124:
    return 106; // Right -> KEY_RIGHT
  case 125:
    return 108; // Down -> KEY_DOWN
  case 126:
    return 103; // Up -> KEY_UP
  case 115:
    return 102; // Home -> KEY_HOME
  case 119:
    return 107; // End -> KEY_END
  case 116:
    return 104; // Page Up -> KEY_PAGEUP
  case 121:
    return 109; // Page Down -> KEY_PAGEDOWN
  case 117:
    return 111; // Forward Delete -> KEY_DELETE
  case 96:
    return 63; // F5 -> KEY_F5
  case 97:
    return 64; // F6 -> KEY_F6
  case 98:
    return 65; // F7 -> KEY_F7
  case 99:
    return 61; // F3 -> KEY_F3
  case 100:
    return 66; // F8 -> KEY_F8
  case 101:
    return 67; // F9 -> KEY_F9
  case 109:
    return 68; // F10 -> KEY_F10
  case 103:
    return 87; // F11 -> KEY_F11
  case 111:
    return 88; // F12 -> KEY_F12
  case 105:
    return 183; // F13
  case 107:
    return 184; // F14
  case 113:
    return 185; // F15
  case 122:
    return 59; // F1 -> KEY_F1
  case 120:
    return 60; // F2 -> KEY_F2
  case 118:
    return 62; // F4 -> KEY_F4
  case 65:
    return 83; // Keypad . -> KEY_KPDOT
  case 67:
    return 55; // Keypad * -> KEY_KPASTERISK
  case 69:
    return 78; // Keypad + -> KEY_KPPLUS
  case 71:
    return 69; // Keypad Clear -> KEY_NUMLOCK
  case 75:
    return 98; // Keypad / -> KEY_KPSLASH
  case 76:
    return 96; // Keypad Enter -> KEY_KPENTER
  case 78:
    return 74; // Keypad - -> KEY_KPMINUS
  case 81:
    return 117; // Keypad = -> KEY_KPEQUAL
  case 82:
    return 82; // Keypad 0 -> KEY_KP0
  case 83:
    return 79; // Keypad 1 -> KEY_KP1
  case 84:
    return 80; // Keypad 2 -> KEY_KP2
  case 85:
    return 81; // Keypad 3 -> KEY_KP3
  case 86:
    return 75; // Keypad 4 -> KEY_KP4
  case 87:
    return 76; // Keypad 5 -> KEY_KP5
  case 88:
    return 77; // Keypad 6 -> KEY_KP6
  case 89:
    return 71; // Keypad 7 -> KEY_KP7
  case 91:
    return 72; // Keypad 8 -> KEY_KP8
  case 92:
    return 73; // Keypad 9 -> KEY_KP9
  default:
    return 0;
  }
}

- (void)keyDown:(NSEvent *)event {
  WWNLog("INPUT", @"keyDown: keyCode=%d", event.keyCode);

  // First, try the raw keycode path for maximum compatibility with
  // Wayland clients that only support wl_keyboard (e.g. terminals).
  uint32_t keycode = MacosToXkbKeycode(event.keyCode);
  if (keycode > 0) {
    [[WWNCompositorBridge sharedBridge]
        injectKeyWithKeycode:keycode
                     pressed:YES
                   timestamp:(uint32_t)(event.timestamp * 1000)];
  }

  // Also route through the macOS text input system so that:
  //  - The emoji picker (Ctrl+Cmd+Space / Globe) works
  //  - Dead-key composition works (e.g. Option+E, then E → é)
  //  - IME composition works (e.g. Japanese input)
  // For ordinary characters this will call insertText:replacementRange:
  // which we use ONLY for text that can't be expressed as a keycode.
  handledByKeyEvent_ = (keycode > 0);
  [self interpretKeyEvents:@[ event ]];
  handledByKeyEvent_ = NO;
}

- (void)keyUp:(NSEvent *)event {
  uint32_t keycode = MacosToXkbKeycode(event.keyCode);
  if (keycode > 0) {
    [[WWNCompositorBridge sharedBridge]
        injectKeyWithKeycode:keycode
                     pressed:NO
                   timestamp:(uint32_t)(event.timestamp * 1000)];
  }
}

- (void)flagsChanged:(NSEvent *)event {
  WWNLog("INPUT", @"flagsChanged: keyCode=%hu flags=0x%lx", event.keyCode,
         (unsigned long)event.modifierFlags);

  uint32_t keycode = MacosToXkbKeycode(event.keyCode);
  if (keycode > 0) {
    // Query physical key state directly to avoid sticky/toggled modifiers.
    BOOL isPressed = CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState,
                                           event.keyCode);

    WWNLog("INPUT", @"Determined modifier key state: keycode=%u isPressed=%d",
           keycode, isPressed);

    [[WWNCompositorBridge sharedBridge]
        injectKeyWithKeycode:keycode
                     pressed:isPressed
                   timestamp:(uint32_t)(event.timestamp * 1000)];
  }
  // IMPORTANT: Do not also push hard-coded modifier bitmasks here.
  // Smithay's keyboard path updates modifiers from key transitions; sending
  // both paths can desynchronize modifier state and scramble keybinds.
}

// ---------------------------------------------------------------------------
#pragma mark - NSTextInputClient
// ---------------------------------------------------------------------------

// Called by the text input system with composed text (emoji, IME, dead
// keys) or with ordinary characters via interpretKeyEvents:.
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
  NSString *str = [string isKindOfClass:[NSAttributedString class]]
                      ? [(NSAttributedString *)string string]
                      : (NSString *)string;

  if (str.length == 0)
    return;

  // Clear any in-progress composition
  markedText_ = nil;
  markedRange_ = NSMakeRange(NSNotFound, 0);

  // Update the proxy text buffer for context (used by autocorrect)
  if (replacementRange.location != NSNotFound &&
      replacementRange.location < textBuffer_.length) {
    NSRange safeRange =
        NSMakeRange(replacementRange.location,
                    MIN(replacementRange.length,
                        textBuffer_.length - replacementRange.location));

    // Compute deletion needed before committing replacement text
    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
    if (safeRange.length > 0) {
      // Delete the text being replaced, then commit new text
      [bridge textInputDeleteSurrounding:(uint32_t)safeRange.length
                             afterLength:0];
    }
    [textBuffer_ replaceCharactersInRange:safeRange withString:str];
    selectedRange_ = NSMakeRange(safeRange.location + str.length, 0);
    [bridge textInputCommitString:str];
    return;
  }
  [textBuffer_ appendString:str];
  selectedRange_ = NSMakeRange(textBuffer_.length, 0);

  // If the raw keycode was already injected by keyDown:, we don't need
  // to send it again — the wl_keyboard path already delivered it.
  // We only fall through to text-input-v3 for text that CAN'T be
  // expressed as a keycode (emoji, accented chars from dead keys, CJK).
  if (handledByKeyEvent_) {
    return;
  }

  // Text that arrived without a matching keyDown (e.g. emoji picker,
  // dead-key resolved composition, clipboard, IME, autocorrect,
  // dictation) — commit via text-input-v3.
  WWNLog("INPUT", @"Committing composed text via text-input-v3: \"%@\"", str);
  [[WWNCompositorBridge sharedBridge] textInputCommitString:str];
}

// Called during IME composition (e.g. Japanese input, dead keys)
- (void)setMarkedText:(id)string
        selectedRange:(NSRange)selectedRange
     replacementRange:(NSRange)replacementRange {
  NSString *str = [string isKindOfClass:[NSAttributedString class]]
                      ? [(NSAttributedString *)string string]
                      : (NSString *)string;

  markedText_ = str.length > 0 ? [str copy] : nil;
  markedRange_ = markedText_ ? NSMakeRange(0, markedText_.length)
                             : NSMakeRange(NSNotFound, 0);
  selectedRange_ = selectedRange;

  if (markedText_) {
    [[WWNCompositorBridge sharedBridge]
        textInputPreeditString:markedText_
                   cursorBegin:(int32_t)selectedRange.location
                     cursorEnd:(int32_t)(selectedRange.location +
                                         selectedRange.length)];
  } else {
    // Empty preedit → clear composition
    [[WWNCompositorBridge sharedBridge] textInputPreeditString:@""
                                                   cursorBegin:0
                                                     cursorEnd:0];
  }
}

- (void)unmarkText {
  if (markedText_) {
    // Commit the marked text
    [[WWNCompositorBridge sharedBridge] textInputCommitString:markedText_];
  }
  markedText_ = nil;
  markedRange_ = NSMakeRange(NSNotFound, 0);
}

- (BOOL)hasMarkedText {
  return markedText_ != nil && markedText_.length > 0;
}

- (NSRange)markedRange {
  return markedRange_;
}

- (NSRange)selectedRange {
  return selectedRange_;
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
                                                actualRange:(NSRangePointer)
                                                                actualRange {
  if (textBuffer_.length == 0) {
    return nil;
  }

  NSRange safeRange =
      NSIntersectionRange(range, NSMakeRange(0, textBuffer_.length));
  if (safeRange.length == 0) {
    return nil;
  }

  if (actualRange) {
    *actualRange = safeRange;
  }
  NSString *sub = [textBuffer_ substringWithRange:safeRange];
  return [[NSAttributedString alloc] initWithString:sub];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
  return NSNotFound;
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
  // Query the cursor rectangle reported by the Wayland client.
  CGRect cursorRect = [[WWNCompositorBridge sharedBridge] textInputCursorRect];

  if (cursorRect.size.width > 0 || cursorRect.size.height > 0) {
    // The cursor rect is in surface-local coordinates.  Convert to
    // screen coordinates for the IME panel.
    NSRect viewRect =
        NSMakeRect(cursorRect.origin.x, cursorRect.origin.y,
                   cursorRect.size.width, MAX(cursorRect.size.height, 1));
    NSRect windowRect = [self convertRect:viewRect toView:nil];
    return [self.window convertRectToScreen:windowRect];
  }

  // Fallback: use the view's frame.
  NSRect frame = self.frame;
  NSRect windowRect = [self convertRect:frame toView:nil];
  return [self.window convertRectToScreen:windowRect];
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
  return @[ NSMarkedClauseSegmentAttributeName, NSGlyphInfoAttributeName ];
}

// Override doCommandBySelector: to prevent macOS from beeping when a key
// combination doesn't map to a text system command.
- (void)doCommandBySelector:(SEL)selector {
  // Swallow unhandled commands silently
}

- (void)resetCursorRects {
  [super resetCursorRects];

  BOOL showHostCursor = [WWNMachineProfileStore resolvedShowHostCursorActive];

  if (!showHostCursor) {
    NSImage *emptyImage = [[NSImage alloc] initWithSize:NSMakeSize(1, 1)];
    NSCursor *invisibleCursor =
        [[NSCursor alloc] initWithImage:emptyImage hotSpot:NSZeroPoint];
    [self addCursorRect:self.bounds cursor:invisibleCursor];
  } else {
    [self addCursorRect:self.bounds cursor:[NSCursor arrowCursor]];
  }
}

@end

//
// WWNWindow Implementation
//
@implementation WWNWindow

- (void)wwnCancelCloseForceTimer {
  [self.wwnCloseForceTimer invalidate];
  self.wwnCloseForceTimer = nil;
}

- (void)cancelPendingHostCloseEscalation {
  self.wwnCloseDeferred = NO;
  [self wwnCancelCloseForceTimer];
}

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backingStoreType
                              defer:(BOOL)flag {
  self = [super initWithContentRect:contentRect
                          styleMask:style
                            backing:backingStoreType
                              defer:flag];
  if (self) {
    // ARC owns this window (held in WWNCompositorBridge._windows and by the
    // teardown block). NSWindow defaults releasedWhenClosed to YES, so -close
    // would hand AppKit an extra -autorelease and over-release the object when
    // the run loop's autorelease pool drains — crashing in objc_release after a
    // client (e.g. weston-terminal) tears down. Match WWNPopupWindow/prefs.
    self.releasedWhenClosed = NO;
    [self setDelegate:self];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(wwn_onWillMiniaturize:)
               name:NSWindowWillMiniaturizeNotification
             object:self];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)wwn_onWillMiniaturize:(NSNotification *)notification {
  (void)notification;
  self.wwnMiniaturizeInProgress = YES;
}

- (void)miniaturize:(id)sender {
  self.wwnMiniaturizeInProgress = YES;
  WWNLog("INPUT", @"Window %llu miniaturize: requested", self.wwnWindowId);
  [super miniaturize:sender];
}

- (void)deminiaturize:(id)sender {
  WWNLog("INPUT", @"Window %llu deminiaturize: requested", self.wwnWindowId);
  [super deminiaturize:sender];
}

- (void)applyPresentationPolicyForServerSideDecorations:
    (BOOL)serverSideDecorations {
  if (self.hostLocked) {
    return;
  }

  BOOL csd = !serverSideDecorations;
  self.clientSideDecorated = csd;

  if (csd) {
    self.opaque = NO;
    self.backgroundColor = NSColor.clearColor;
    self.hasShadow = NO;
  } else {
    self.opaque = YES;
    self.backgroundColor = nil;
    self.hasShadow = YES;
  }

  if (![self.contentView isKindOfClass:[WWNView class]]) {
    return;
  }
  WWNView *view = (WWNView *)self.contentView;
  view.wantsLayer = YES;
  view.layer.backgroundColor = NSColor.clearColor.CGColor;

  if (csd) {
    // Transparent host: client buffer alpha (rounded corners, shadows) composites
    // to the desktop instead of showing black from an opaque AppKit backing store.
    view.layer.opaque = NO;
    view.layer.masksToBounds = NO;
    view.contentLayer.opaque = NO;
    view.contentLayer.backgroundColor = NSColor.clearColor.CGColor;
    view.contentLayer.masksToBounds = NO;
  } else {
    view.layer.opaque = YES;
    view.layer.masksToBounds = YES;
    view.contentLayer.opaque = YES;
    view.contentLayer.backgroundColor = NSColor.clearColor.CGColor;
    view.contentLayer.masksToBounds = NO;
  }
}

- (void)windowDidResize:(NSNotification *)notification {
  if (self.processingResize || self.suppressCompositorCallbacks ||
      !self.isVisible || self.isMiniaturized ||
      self.wwnMiniaturizeInProgress || self.wwnFullscreenTransitionInProgress) {
    return;
  }

  // Match Rust/AppKit round-trip sizing to the actual frame<->content mapping.
  NSSize size = [self contentRectForFrameRect:self.frame].size;
  uint32_t width = (uint32_t)MAX(1, lround(size.width));
  uint32_t height = (uint32_t)MAX(1, lround(size.height));
  [[WWNCompositorBridge sharedBridge] injectWindowResize:self.wwnWindowId
                                                   width:width
                                                  height:height];

  if (self.hostLocked) {
    return;
  }
  BOOL zoomed = [self isZoomed];
  if (zoomed != self.wwnLastZoomed) {
    self.wwnLastZoomed = zoomed;
    [[WWNCompositorBridge sharedBridge]
        syncHostMaximized:zoomed
              forWindowId:self.wwnWindowId
                    width:width
                   height:height];
  }
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
  (void)notification;
  self.wwnFullscreenTransitionInProgress = YES;
}

- (void)windowWillExitFullScreen:(NSNotification *)notification {
  (void)notification;
  self.wwnFullscreenTransitionInProgress = YES;
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
  (void)notification;
  self.wwnFullscreenTransitionInProgress = NO;
  if (self.processingResize || self.suppressCompositorCallbacks ||
      self.hostLocked) {
    return;
  }
  NSSize size = [self contentRectForFrameRect:self.frame].size;
  uint32_t width = (uint32_t)MAX(1, lround(size.width));
  uint32_t height = (uint32_t)MAX(1, lround(size.height));
  // syncHostFullscreen sends the fullscreen configure and opens a resize
  // transaction itself; also injecting a plain resize here issued a second,
  // racing configure for the same transition (feedback loop with the
  // client's commits).
  [[WWNCompositorBridge sharedBridge]
      syncHostFullscreen:YES
             forWindowId:self.wwnWindowId
                   width:width
                  height:height];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
  (void)notification;
  self.wwnFullscreenTransitionInProgress = NO;
  if (self.processingResize || self.suppressCompositorCallbacks ||
      self.hostLocked) {
    return;
  }
  NSSize size = [self contentRectForFrameRect:self.frame].size;
  uint32_t width = (uint32_t)MAX(1, lround(size.width));
  uint32_t height = (uint32_t)MAX(1, lround(size.height));
  [[WWNCompositorBridge sharedBridge]
      syncHostFullscreen:NO
             forWindowId:self.wwnWindowId
                   width:width
                  height:height];
}

- (void)windowWillStartLiveResize:(NSNotification *)notification {
  (void)notification;
  if (self.processingResize || self.suppressCompositorCallbacks ||
      !self.isVisible || self.isMiniaturized ||
      self.wwnMiniaturizeInProgress || self.wwnFullscreenTransitionInProgress) {
    return;
  }
  // SSD host edge-drag: set xdg_toplevel.state.resizing before mid-drag
  // configures stream (xdg-shell / niri interactive-resize pattern).
  [[WWNCompositorBridge sharedBridge] beginInteractiveResize:self.wwnWindowId];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
  (void)sender;
  if (self.processingResize || self.suppressCompositorCallbacks ||
      !self.isVisible || self.isMiniaturized ||
      self.wwnMiniaturizeInProgress || self.wwnFullscreenTransitionInProgress) {
    return frameSize;
  }

  // During live edge-drag, forward each intermediate content size so Wayland
  // clients track host window dimensions continuously, not only after mouse up.
  NSRect nextFrame = NSMakeRect(self.frame.origin.x, self.frame.origin.y,
                                frameSize.width, frameSize.height);
  NSSize currentContent = [self contentRectForFrameRect:self.frame].size;
  NSSize contentSize = [self contentRectForFrameRect:nextFrame].size;

  // AppKit's shrink-to-dock animation can emit resizes before -miniaturize: or
  // windowWillMiniaturize: fire; forwarding those sizes kills weston-terminal.
  if (!self.interactiveResizeInProgress &&
      contentSize.width < currentContent.width * 0.75 &&
      contentSize.height < currentContent.height * 0.75) {
    self.wwnMiniaturizeInProgress = YES;
    WWNLog("INPUT",
           @"Window %llu detected minimize shrink %.0fx%.0f -> %.0fx%.0f",
           self.wwnWindowId, currentContent.width, currentContent.height,
           contentSize.width, contentSize.height);
    return frameSize;
  }

  // AppKit can emit willResize before willStartLiveResize; ensure Resizing is
  // set for the first mid-drag configure as well.
  if (self.inLiveResize || self.interactiveResizeInProgress) {
    [[WWNCompositorBridge sharedBridge] beginInteractiveResize:self.wwnWindowId];
  }

  uint32_t width = (uint32_t)MAX(1, lround(contentSize.width));
  uint32_t height = (uint32_t)MAX(1, lround(contentSize.height));
  [[WWNCompositorBridge sharedBridge] injectWindowResize:self.wwnWindowId
                                                   width:width
                                                  height:height];
  return frameSize;
}

- (void)windowDidEndLiveResize:(NSNotification *)notification {
  (void)notification;
  if (self.processingResize || self.suppressCompositorCallbacks ||
      !self.isVisible || self.isMiniaturized ||
      self.wwnMiniaturizeInProgress) {
    return;
  }
  // Final authoritative sync after fast edge-drag: clears Resizing and
  // guarantees host/client dimensions converge.
  [[WWNCompositorBridge sharedBridge]
      reconcileWindowResizeNow:self.wwnWindowId];
}

- (BOOL)canBecomeKeyWindow {
  return YES;
}

- (BOOL)canBecomeMainWindow {
  return YES;
}

- (void)becomeKeyWindow {
  [super becomeKeyWindow];
  if (self.suppressCompositorCallbacks) {
    return;
  }

  WWNLog("INPUT", @"Window %llu became key - setting keyboard focus",
         self.wwnWindowId);

  [self makeFirstResponder:self.contentView];

  [[WWNCompositorBridge sharedBridge] setWindowActivated:self.wwnWindowId
                                                  active:YES];

  [[WWNCompositorBridge sharedBridge]
      injectKeyboardEnterForWindow:self.wwnWindowId
                              keys:@[]];
}

- (void)resignKeyWindow {
  [super resignKeyWindow];
  if (self.suppressCompositorCallbacks || self.isMiniaturized ||
      self.wwnMiniaturizeInProgress) {
    return;
  }

  WWNLog("INPUT", @"Window %llu resigned key - removing keyboard focus",
         self.wwnWindowId);

  [[WWNCompositorBridge sharedBridge] setWindowActivated:self.wwnWindowId
                                                  active:NO];

  [[WWNCompositorBridge sharedBridge]
      injectKeyboardLeaveForWindow:self.wwnWindowId];
}

- (void)windowWillMiniaturize:(NSNotification *)notification {
  (void)notification;
  self.wwnMiniaturizeInProgress = YES;
  WWNLog("INPUT", @"Window %llu will miniaturize", self.wwnWindowId);
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
  (void)notification;
  self.wwnMiniaturizeInProgress = NO;
  WWNLog("INPUT", @"Window %llu miniaturized to dock", self.wwnWindowId);
}

- (void)windowDidDeminiaturize:(NSNotification *)notification {
  (void)notification;
  self.wwnMiniaturizeInProgress = NO;
  if (self.suppressCompositorCallbacks) {
    return;
  }
  WWNLog("INPUT", @"Window %llu deminiaturized from dock", self.wwnWindowId);
  NSSize size = [self contentRectForFrameRect:self.frame].size;
  uint32_t width = (uint32_t)MAX(1, lround(size.width));
  uint32_t height = (uint32_t)MAX(1, lround(size.height));
  [[WWNCompositorBridge sharedBridge] injectWindowResize:self.wwnWindowId
                                                   width:width
                                                  height:height];
  [[WWNCompositorBridge sharedBridge]
      reconcileWindowResizeNow:self.wwnWindowId];
}

/// Defer AppKit teardown until the Wayland client handles `xdg_toplevel.close`.
/// Without this, closing the NSWindow first races nested compositors (e.g. Weston)
/// and can abort the client during Cairo/Pixman teardown.
- (BOOL)windowShouldClose:(NSWindow *)sender {
  (void)sender;
  if (self.suppressCompositorCallbacks) {
    return YES;
  }
  if (self.wwnCloseDeferred) {
    [self wwnCancelCloseForceTimer];
    self.wwnCloseDeferred = NO;
    [[WWNCompositorBridge sharedBridge]
        requestForceDestroyHostWindowForWindowId:self.wwnWindowId];
    WWNLog("INPUT", @"windowShouldClose: second close — force-destroy host for "
                     @"window %llu",
           self.wwnWindowId);
    return NO;
  }
  BOOL sent = [[WWNCompositorBridge sharedBridge]
      requestHostCloseForWindowId:self.wwnWindowId];
  if (sent) {
    // Once close has been requested, stop feeding additional AppKit callbacks
    // for this host window while the Wayland client unwinds.
    self.suppressCompositorCallbacks = YES;
    WWNLog("INPUT", @"windowShouldClose: sent xdg_toplevel.close for window %llu — "
                     @"deferring NSWindow close",
           self.wwnWindowId);
    self.wwnCloseDeferred = YES;
    [self.wwnCloseForceTimer invalidate];
    // Grace timeout (Linux UI parity): if the client never Destroyed, escalate
    // to force-destroy so the host window cannot stick forever (#52).
    __weak typeof(self) weakSelf = self;
    uint64_t wid = self.wwnWindowId;
    self.wwnCloseForceTimer =
        [NSTimer scheduledTimerWithTimeInterval:1.5
                                        repeats:NO
                                          block:^(__unused NSTimer *timer) {
                                            __strong typeof(weakSelf) strongSelf =
                                                weakSelf;
                                            if (!strongSelf ||
                                                !strongSelf.wwnCloseDeferred) {
                                              return;
                                            }
                                            strongSelf.wwnCloseDeferred = NO;
                                            strongSelf.wwnCloseForceTimer = nil;
                                            WWNLog("INPUT",
                                                   @"windowShouldClose: grace "
                                                   @"timeout — force-destroy "
                                                   @"host for window %llu",
                                                   wid);
                                            [[WWNCompositorBridge sharedBridge]
                                                requestForceDestroyHostWindowForWindowId:
                                                    wid];
                                          }];
    return NO;
  }
  return YES;
}

@end
