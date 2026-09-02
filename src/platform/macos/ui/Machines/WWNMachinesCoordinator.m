#import "WWNMachinesCoordinator.h"
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import "../Settings/WWNPreferences.h"
#endif
#import <objc/message.h>
#import <objc/runtime.h>

static Class WWNFindMachinesHostingBridgeClass(void) {
  NSMutableOrderedSet<NSString *> *candidateNames = [NSMutableOrderedSet orderedSetWithArray:@[
    @"WWNMachinesHostingBridge",
    @"Wawona.WWNMachinesHostingBridge",
    @"Wawona_iOS.WWNMachinesHostingBridge",
    @"Wawona_macOS.WWNMachinesHostingBridge",
  ]];

  NSBundle *mainBundle = [NSBundle mainBundle];
  NSString *bundleName = [mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
  NSString *execName = [mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
  if (bundleName.length > 0) {
    [candidateNames addObject:[NSString stringWithFormat:@"%@.WWNMachinesHostingBridge", bundleName]];
    [candidateNames addObject:[NSString stringWithFormat:@"%@.WWNMachinesHostingBridge",
                                                         [bundleName stringByReplacingOccurrencesOfString:@"-" withString:@"_"]]];
  }
  if (execName.length > 0) {
    [candidateNames addObject:[NSString stringWithFormat:@"%@.WWNMachinesHostingBridge", execName]];
    [candidateNames addObject:[NSString stringWithFormat:@"%@.WWNMachinesHostingBridge",
                                                         [execName stringByReplacingOccurrencesOfString:@"-" withString:@"_"]]];
  }

  for (NSString *name in candidateNames) {
    Class bridgeClass = NSClassFromString(name);
    if (bridgeClass) {
      return bridgeClass;
    }
  }

  int classCount = objc_getClassList(NULL, 0);
  if (classCount <= 0) {
    return Nil;
  }
  Class *classes = (__unsafe_unretained Class *)malloc((size_t)classCount * sizeof(Class));
  if (classes == NULL) {
    return Nil;
  }
  classCount = objc_getClassList(classes, classCount);
  Class foundClass = Nil;
  for (int i = 0; i < classCount; i++) {
    NSString *className = NSStringFromClass(classes[i]);
    if ([className isEqualToString:@"WWNMachinesHostingBridge"] ||
        [className hasSuffix:@".WWNMachinesHostingBridge"]) {
      foundClass = classes[i];
      break;
    }
  }
  free(classes);
  return foundClass;
}

@interface WWNMachinesCoordinator ()
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
@property(nonatomic, strong) NSWindowController *macMachinesController;
#endif
@end

@implementation WWNMachinesCoordinator

+ (instancetype)sharedCoordinator {
  static WWNMachinesCoordinator *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (UIViewController *)buildMachinesViewControllerWithOnConnect:
    (dispatch_block_t)onConnect {
  return [self buildSwiftUIMachinesController:onConnect];
}

- (UIViewController *)buildSwiftUIMachinesController:(dispatch_block_t)onConnect {
  Class bridgeClass = WWNFindMachinesHostingBridgeClass();
  SEL selector = NSSelectorFromString(@"buildIOSMachinesControllerWithOnConnect:");
  if (!bridgeClass || ![bridgeClass respondsToSelector:selector]) {
    return nil;
  }
  UIViewController *(*buildFn)(id, SEL, dispatch_block_t) =
      (UIViewController *(*)(id, SEL, dispatch_block_t))objc_msgSend;
  return buildFn(bridgeClass, selector, onConnect);
}
#else
- (NSWindowController *)buildSwiftUIMachinesWindowController:(dispatch_block_t)onConnect {
  Class bridgeClass = WWNFindMachinesHostingBridgeClass();
  SEL selector = NSSelectorFromString(@"buildMacMachinesWindowControllerWithOnConnect:");
  if (!bridgeClass || ![bridgeClass respondsToSelector:selector]) {
    return nil;
  }
  NSWindowController *(*buildFn)(id, SEL, dispatch_block_t) =
      (NSWindowController *(*)(id, SEL, dispatch_block_t))objc_msgSend;
  return buildFn(bridgeClass, selector, onConnect);
}
#endif

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)presentMachinesFromViewController:(UIViewController *)presenter
                                onConnect:(dispatch_block_t)onConnect {
  UIViewController *top = presenter;
  while (top.presentedViewController != nil) {
    top = top.presentedViewController;
  }
  UIViewController *machinesVC = [self buildMachinesViewControllerWithOnConnect:onConnect];
  if (!machinesVC) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Machines UI Unavailable"
                         message:@"SwiftUI machines view failed to load. Regenerate the Xcode project and rebuild."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
    return;
  }
  [top presentViewController:machinesVC animated:YES completion:nil];
}
#else
- (void)showMachinesWindowAndActivate:(BOOL)activate {
  // One Machines window forever. Never rebuild just because the existing
  // window is ordered out / not yet visible: that orphaned the previous
  // NSWindow (still retained by NSApp) and produced two "Machine Control
  // Panel" windows in one process. Only build when we have no controller
  // or its window was destroyed.
  NSWindow *existing = self.macMachinesController.window;
  if (!self.macMachinesController || existing == nil) {
    NSWindowController *controller =
        [self buildSwiftUIMachinesWindowController:nil];
    if (controller) {
      if (self.macMachinesController.window != nil &&
          self.macMachinesController.window != controller.window) {
        [self.macMachinesController.window close];
      }
      self.macMachinesController = controller;
    }
  }
  if (!self.macMachinesController) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Machines UI Unavailable";
    alert.informativeText =
        @"SwiftUI machines view failed to load. Regenerate the Xcode project and rebuild.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    return;
  }
  // Collapse any orphaned duplicates from older builds / races.
  NSWindow *keep = self.macMachinesController.window;
  for (NSWindow *window in [NSApp.windows copy]) {
    if (window == keep) {
      continue;
    }
    NSString *title = window.title ?: @"";
    NSString *ident = window.identifier ?: @"";
    if ([ident isEqualToString:@"wwn.machines.control-panel"] ||
        [title isEqualToString:@"Wawona Machine Control Panel"] ||
        [title isEqualToString:@"Machines"]) {
      [window close];
    }
  }
  if (activate) {
    [NSApp activateIgnoringOtherApps:YES];
  }
  [self.macMachinesController showWindow:nil];
  [keep makeKeyAndOrderFront:nil];
}

- (void)showMachinesWindowFromMenu:(id)sender {
  (void)sender;
  [self showMachinesWindowAndActivate:YES];
}
#endif

@end
