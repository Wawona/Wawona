#pragma once

#import <Cocoa/Cocoa.h>

@interface WWNWindow : NSWindow <NSWindowDelegate>
@property(nonatomic, assign) uint64_t wwnWindowId;
@property(nonatomic, assign) BOOL hostLocked;
@property(nonatomic, assign) BOOL processingResize;
@property(nonatomic, assign) BOOL interactiveResizeInProgress;
@property(nonatomic, assign) BOOL suppressCompositorCallbacks;
@property(nonatomic, strong) NSEvent *lastMouseDownEvent;
/// Called when bridge tears host down (client path) so delayed force-close cancels.
- (void)cancelPendingHostCloseEscalation;
@end

@interface WWNView : NSView <NSTextInputClient>
@property(nonatomic, assign) uint64_t overrideWindowId;
@property(nonatomic, strong, readonly) CALayer *contentLayer;
@end
