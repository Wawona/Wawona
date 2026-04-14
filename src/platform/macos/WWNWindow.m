#import "WWNWindow.h"
#import "../../util/WWNLog.h"
#import "WWNCompositorBridge.h"
#import "WWNSettings.h"

//
// WWNView Implementation (macOS)
//
@implementation WWNView {
  CALayer *contentLayer_;
  // NSTextInputClient state for IME / emoji composition
  NSString *markedText_;
  NSRange markedRange_;
  NSRange selectedRange_;
  // Set to YES during keyDown: if the raw keycode was already injected,
  // so insertText:replacementRange: can skip duplicate key events.
  BOOL handledByKeyEvent_;

  // Text Assist proxy buffer for autocorrect / text replacement context
  NSMutableString *textBuffer_;
  BOOL textAssistEnabled_;
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
    contentLayer_.contentsGravity = kCAGravityResize;
    contentLayer_.masksToBounds =
        NO; // Allow subsurfaces to extend outside (Wayland spec)
    contentLayer_.autoresizingMask =
        kCALayerWidthSizable | kCALayerHeightSizable;
    [self.layer addSublayer:contentLayer_];
    [self updateTrackingAreas];

    textBuffer_ = [NSMutableString string];
    textAssistEnabled_ = WWNSettings_GetEnableTextAssist();

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
  textAssistEnabled_ = WWNSettings_GetEnableTextAssist();
  [self.window invalidateCursorRectsForView:self];
}

- (CALayer *)contentLayer {
  if (!contentLayer_) {
    contentLayer_ = [CALayer layer];
    contentLayer_.geometryFlipped = YES;
    contentLayer_.contentsGravity = kCAGravityResize;
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
}

- (void)updateLayer {
  [super updateLayer];
  contentLayer_.frame = self.bounds;
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
  if ([self.window isKindOfClass:[WWNWindow class]]) {
    ((WWNWindow *)self.window).lastMouseDownEvent = event;
  }
  [[WWNCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wwnWindowId]
                            button:0x110 // BTN_LEFT
                           pressed:YES
                         timestamp:(uint32_t)(event.timestamp * 1000)];
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

  static NSMutableSet *pressedModifiers = nil;
  if (!pressedModifiers) {
    pressedModifiers = [NSMutableSet set];
  }

  uint32_t keycode = MacosToXkbKeycode(event.keyCode);
  if (keycode > 0) {
    // Track physical key state
    BOOL isPressed = NO;
    NSNumber *keyObj = @(keycode);

    if ([pressedModifiers containsObject:keyObj]) {
      [pressedModifiers removeObject:keyObj];
      isPressed = NO;
    } else {
      [pressedModifiers addObject:keyObj];
      isPressed = YES;
    }

    WWNLog("INPUT", @"Determined modifier key state: keycode=%u isPressed=%d",
           keycode, isPressed);

    [[WWNCompositorBridge sharedBridge]
        injectKeyWithKeycode:keycode
                     pressed:isPressed
                   timestamp:(uint32_t)(event.timestamp * 1000)];
  }

  NSUInteger flags = [event modifierFlags];
  uint32_t depressed = 0;
  uint32_t locked = 0;

  if (flags & NSEventModifierFlagShift) {
    depressed |= 1;
  }
  if (flags & NSEventModifierFlagControl) {
    depressed |= 4;
  }
  if (flags & NSEventModifierFlagOption) {
    depressed |= 8;
  }
  if (flags & NSEventModifierFlagCommand) {
    depressed |= 64;
  }
  if (flags & NSEventModifierFlagCapsLock) {
    locked |= 2;
  }

  WWNLog("INPUT", @"Injecting modifiers state: depressed=%u locked=%u",
         depressed, locked);

  [[WWNCompositorBridge sharedBridge] injectModifiersWithDepressed:depressed
                                                           latched:0
                                                            locked:locked
                                                             group:0];
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
  if (textAssistEnabled_) {
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
  }

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
  if (!textAssistEnabled_ || textBuffer_.length == 0) {
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

  BOOL showHostCursor = WWNSettings_GetRenderMacOSPointer();

  if (!showHostCursor &&
      [[WWNCompositorBridge sharedBridge] clientWantsCursorRendered]) {
    showHostCursor = YES;
  }

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

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backingStoreType
                              defer:(BOOL)flag {
  self = [super initWithContentRect:contentRect
                          styleMask:style
                            backing:backingStoreType
                              defer:flag];
  if (self) {
    [self setDelegate:self];
  }
  return self;
}

- (void)windowDidResize:(NSNotification *)notification {
  if (self.processingResize || self.suppressCompositorCallbacks ||
      !self.isVisible) {
    return;
  }

  NSSize size = [self.contentView bounds].size;
  [[WWNCompositorBridge sharedBridge] injectWindowResize:self.wwnWindowId
                                                   width:(uint32_t)size.width
                                                  height:(uint32_t)size.height];
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
  if (self.suppressCompositorCallbacks) {
    return;
  }

  WWNLog("INPUT", @"Window %llu resigned key - removing keyboard focus",
         self.wwnWindowId);

  [[WWNCompositorBridge sharedBridge] setWindowActivated:self.wwnWindowId
                                                  active:NO];

  [[WWNCompositorBridge sharedBridge]
      injectKeyboardLeaveForWindow:self.wwnWindowId];
}

@end
