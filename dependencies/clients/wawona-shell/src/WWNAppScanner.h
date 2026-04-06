#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

// Wayland Client App Launcher
// Handles discovery and launching of bundled Wayland client applications

// App metadata for discovered applications
@interface WaylandApp : NSObject
@property(nonatomic, strong) NSString *appId;
@property(nonatomic, strong) NSString *name;
@property(nonatomic, strong) NSString *appDescription;
@property(nonatomic, strong) NSString *iconPath;
@property(nonatomic, strong) NSString *executablePath;
@property(nonatomic, strong) NSArray<NSString *> *categories;
@property(nonatomic, assign) BOOL isRunning;
@property(nonatomic, assign) BOOL isBlacklisted;
@end

@interface WWNAppScanner : NSObject

@property(nonatomic, assign, readonly) void *display;
@property(nonatomic, strong, readonly)
    NSArray<WaylandApp *> *availableApplications;
@property(nonatomic, strong, readonly)
    NSArray<NSDictionary *> *runningApplications;

- (instancetype)initWithDisplay:(void *)display;

// Application discovery
- (void)scanForApplications;
- (void)refreshApplicationList;

// Application launching
- (BOOL)launchApplication:(NSString *)appId;
- (BOOL)launchApplicationAtPath:(NSString *)executablePath;
- (void)terminateApplication:(NSString *)appId;
- (BOOL)isApplicationRunning:(NSString *)appId;

// Environment setup
- (void)setupWaylandEnvironment;
- (NSString *)waylandSocketPath;

// Bundled application directories
+ (NSArray<NSString *> *)bundledApplicationSearchPaths;

@end
