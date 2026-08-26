#pragma once

#import <Cocoa/Cocoa.h>
#import <TargetConditionals.h>

@interface WWNWindow : NSWindow <NSWindowDelegate>
@property(nonatomic, assign) uint64_t wwnWindowId;
@property(nonatomic, assign) BOOL hostLocked;
@property(nonatomic, assign) BOOL processingResize;
@property(nonatomic, assign) BOOL interactiveResizeInProgress;
@property(nonatomic, assign) BOOL suppressCompositorCallbacks;
/// YES when the Wayland client draws its own window chrome (CSD).
@property(nonatomic, assign) BOOL clientSideDecorated;
/// Tracks zoom state for host → Wayland maximize sync.
@property(nonatomic, assign) BOOL wwnLastZoomed;
/// YES while AppKit is miniaturizing (before isMiniaturized flips).
@property(nonatomic, assign) BOOL wwnMiniaturizeInProgress;
/// YES during the AppKit fullscreen enter/exit animation. Intermediate
/// windowWillResize/windowDidResize callbacks are suppressed so only the
/// settled fullscreen size reaches the Wayland client.
@property(nonatomic, assign) BOOL wwnFullscreenTransitionInProgress;
/// Last left-mouse-down in this window; used when `xdg_toplevel.move` arrives
/// after button inject (WindowMoveRequested → performWindowDragWithEvent).
@property(nonatomic, strong) NSEvent *lastMouseDownEvent;
/// Flower/smoke/simple-egl/simple-shm: client owns a preferred square. Host
/// must not inject live resize or leave the NSWindow resizable.
@property(nonatomic, assign) BOOL prefersFixedSquare;
/// Toggle AppKit chrome vs transparent host for SSD/CSD presentation.
- (void)applyPresentationPolicyForServerSideDecorations:(BOOL)serverSideDecorations;
/// Called when bridge tears host down (client path) so delayed force-close cancels.
- (void)cancelPendingHostCloseEscalation;
@end

@interface WWNView : NSView <NSTextInputClient
#if TARGET_OS_OSX
    ,
    NSDraggingDestination
#endif
>
@property(nonatomic, assign) uint64_t overrideWindowId;
@property(nonatomic, strong, readonly) CALayer *contentLayer;
- (BOOL)prepareIlandMetalPresentation;
- (void)stopIlandMetalPresentation;
- (BOOL)launchNestedIlandGpuClient:(NSString *)clientId;
- (BOOL)launchNestedKmscube;
@end
