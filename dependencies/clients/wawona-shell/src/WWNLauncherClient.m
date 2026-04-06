// Wawona Launcher Client - Wayland client implementation
// A GUI Launcher that scans for bundled Wayland applications
// Displays app icons and labels, allows launching apps
// Supports iOS, macOS, and Android

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import "../../../../src/util/WWNLog.h"
#import "WWNLauncherClient.h"
#include "xdg-shell-client-protocol.h"
#include <arpa/inet.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#import <objc/runtime.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client-protocol.h>
#include <wayland-client.h>

// ============================================================================
// Application Discovery
// ============================================================================

@implementation WWNLauncherApp
@end

// Blacklisted app IDs (launcher itself, etc.)
static NSArray<NSString *> *blacklistedAppIds = nil;

// Discovered applications
static NSMutableArray<WWNLauncherApp *> *discoveredApps = nil;

// Initialize blacklist
static void initBlacklist(void) {
  if (!blacklistedAppIds) {
    blacklistedAppIds = @[
      @"com.aspauldingcode.Wawona.Launcher", @"wawona-launcher", @"launcher"
    ];
  }
}

// Check if an app is blacklisted
static BOOL isAppBlacklisted(NSString *appId, NSString *executableName) {
  initBlacklist();
  for (NSString *blacklisted in blacklistedAppIds) {
    if ([appId.lowercaseString containsString:blacklisted.lowercaseString] ||
        [executableName.lowercaseString
            containsString:blacklisted.lowercaseString]) {
      return YES;
    }
  }
  return NO;
}

// Parse app.json metadata file
static WWNLauncherApp *parseAppMetadata(NSString *metadataPath,
                                        NSString *basePath) {
  NSData *data = [NSData dataWithContentsOfFile:metadataPath];
  if (!data)
    return nil;

  NSError *error = nil;
  NSDictionary *json =
      [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || !json) {
    WWNLog("LAUNCHER", @"Warning: Failed to parse app.json at %@: %@",
           metadataPath, error);
    return nil;
  }

  WWNLauncherApp *app = [[WWNLauncherApp alloc] init];
  app.appId = json[@"id"] ?: @"unknown";
  app.name = json[@"name"] ?: @"Unknown App";
  app.description = json[@"description"] ?: @"";
  app.categories = json[@"categories"] ?: @[];

  // Resolve executable path
  NSString *executable = json[@"executable"] ?: @"";
  if (executable.length > 0) {
    if ([executable hasPrefix:@"/"]) {
      app.executablePath = executable;
    } else {
      app.executablePath = [[basePath stringByAppendingPathComponent:@"bin"]
          stringByAppendingPathComponent:executable];
    }
  }

  // Resolve icon path
  NSString *icon = json[@"icon"] ?: @"";
  if (icon.length > 0) {
    if ([icon hasPrefix:@"/"]) {
      app.iconPath = icon;
    } else {
      app.iconPath = [[basePath stringByAppendingPathComponent:@"share/icons"]
          stringByAppendingPathComponent:icon];
    }
  }

  // Check blacklist
  NSString *execName = [app.executablePath lastPathComponent];
  app.isBlacklisted = isAppBlacklisted(app.appId, execName);

  return app;
}

// Scan for bundled applications
void refreshLauncherApplicationList(void) {
  if (!discoveredApps) {
    discoveredApps = [NSMutableArray array];
  }
  [discoveredApps removeAllObjects];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSBundle *mainBundle = [NSBundle mainBundle];

  // Locations to scan for bundled apps
  NSMutableArray<NSString *> *searchPaths = [NSMutableArray array];

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // iOS: Check inside app bundle
  NSString *bundlePath = [mainBundle bundlePath];
  [searchPaths
      addObject:[bundlePath stringByAppendingPathComponent:@"Applications"]];
  [searchPaths addObject:[bundlePath stringByAppendingPathComponent:@"apps"]];

  // Also check Documents for side-loaded apps (jailbreak/TrollStore)
  NSString *docsPath = NSSearchPathForDirectoriesInDomains(
                           NSDocumentDirectory, NSUserDomainMask, YES)
                           .firstObject;
  if (docsPath) {
    [searchPaths
        addObject:[docsPath stringByAppendingPathComponent:@"Applications"]];
  }
#else
  // macOS: Check inside app bundle and standard locations
  NSString *resourcePath = [mainBundle resourcePath];
  [searchPaths
      addObject:[resourcePath stringByAppendingPathComponent:@"Applications"]];

  NSString *execPath =
      [[mainBundle executablePath] stringByDeletingLastPathComponent];
  [searchPaths addObject:[execPath stringByAppendingPathComponent:@"apps"]];
  [searchPaths
      addObject:[execPath stringByAppendingPathComponent:@"Applications"]];

  // Also check ~/.local/share/wawona/applications
  NSString *homeApps = [NSHomeDirectory()
      stringByAppendingPathComponent:@".local/share/wawona/applications"];
  [searchPaths addObject:homeApps];
#endif

  WWNLog("LAUNCHER", @"Scanning for applications in %lu locations",
         (unsigned long)searchPaths.count);

  for (NSString *searchPath in searchPaths) {
    if (![fm fileExistsAtPath:searchPath]) {
      continue;
    }

    WWNLog("LAUNCHER", @"Scanning %@", searchPath);

    NSError *error = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:searchPath error:&error];
    if (error)
      continue;

    for (NSString *item in contents) {
      NSString *itemPath = [searchPath stringByAppendingPathComponent:item];
      BOOL isDir = NO;
      if (![fm fileExistsAtPath:itemPath isDirectory:&isDir] || !isDir) {
        continue;
      }

      // Look for app.json or wawona metadata
      NSString *metadataPath =
          [itemPath stringByAppendingPathComponent:@"share/wawona/app.json"];
      if (![fm fileExistsAtPath:metadataPath]) {
        // Try alternate locations
        metadataPath = [itemPath stringByAppendingPathComponent:@"app.json"];
      }
      if (![fm fileExistsAtPath:metadataPath]) {
        metadataPath =
            [itemPath stringByAppendingPathComponent:@"metadata.json"];
      }

      if ([fm fileExistsAtPath:metadataPath]) {
        WWNLauncherApp *app = parseAppMetadata(metadataPath, itemPath);
        if (app && !app.isBlacklisted) {
          // Verify executable exists
          if (app.executablePath &&
              [fm isExecutableFileAtPath:app.executablePath]) {
            [discoveredApps addObject:app];
            WWNLog("LAUNCHER", @"Found app: %@ (%@)", app.name, app.appId);
          } else {
            WWNLog("LAUNCHER", @"Warning: App %@ has no valid executable at %@",
                   app.name, app.executablePath);
          }
        }
      } else {
        // Try to auto-discover based on directory structure
        NSString *binPath = [itemPath stringByAppendingPathComponent:@"bin"];
        if ([fm fileExistsAtPath:binPath]) {
          NSArray *binContents =
              [fm contentsOfDirectoryAtPath:binPath error:nil];
          for (NSString *binItem in binContents) {
            NSString *execPath =
                [binPath stringByAppendingPathComponent:binItem];
            if ([fm isExecutableFileAtPath:execPath] &&
                !isAppBlacklisted(binItem, binItem)) {
              WWNLauncherApp *app = [[WWNLauncherApp alloc] init];
              app.appId = [NSString stringWithFormat:@"auto.%@", binItem];
              app.name = binItem;
              app.executablePath = execPath;
              app.isBlacklisted = NO;
              [discoveredApps addObject:app];
              WWNLog("LAUNCHER", @"Auto-discovered app: %@", app.name);
            }
          }
        }
      }
    }
  }

  WWNLog("LAUNCHER", @"Found %lu applications",
         (unsigned long)discoveredApps.count);
}

NSArray<WWNLauncherApp *> *getLauncherApplications(void) {
  if (!discoveredApps) {
    refreshLauncherApplicationList();
  }
  return [discoveredApps copy];
}

// ============================================================================
// Application Launching
// ============================================================================

BOOL launchLauncherApplication(NSString *appId) {
  NSArray *apps = getLauncherApplications();
  for (WWNLauncherApp *app in apps) {
    if ([app.appId isEqualToString:appId]) {
      WWNLog("LAUNCHER", @"Launching %@ (%@)", app.name, app.executablePath);

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      // iOS: Use dlopen to load as dynamic library
      void *handle =
          dlopen([app.executablePath UTF8String], RTLD_NOW | RTLD_LOCAL);
      if (!handle) {
        WWNLog("LAUNCHER", @"Error: Failed to load %@: %s", app.name,
               dlerror());
        return NO;
      }

      // Look for entry point (main or custom entry)
      typedef int (*EntryFunc)(int, char **);
      EntryFunc entry = (EntryFunc)dlsym(handle, "main");
      if (!entry) {
        entry = (EntryFunc)dlsym(handle, "app_entry");
      }
      if (!entry) {
        WWNLog("LAUNCHER", @"Error: No entry point found for %@", app.name);
        dlclose(handle);
        return NO;
      }

      // Launch in a new thread
      dispatch_async(
          dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            char *argv[] = {(char *)[app.name UTF8String], NULL};
            entry(1, argv);
          });

      return YES;
#else
      // macOS/Android: Fork and exec
      pid_t pid = fork();
      if (pid == 0) {
        // Child process
        // Set up Wayland environment
        const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
        const char *wayland_display = getenv("WAYLAND_DISPLAY");

        if (!runtime_dir) {
          char buf[256];
          snprintf(buf, sizeof(buf), "/tmp/wawona-%d", getuid());
          setenv("XDG_RUNTIME_DIR", buf, 1);
        }
        if (!wayland_display) {
          setenv("WAYLAND_DISPLAY", "wayland-0", 1);
        }

        execl([app.executablePath UTF8String], [app.name UTF8String], NULL);
        _exit(1); // execl failed
      } else if (pid > 0) {
        WWNLog("LAUNCHER", @"Spawned %@ with PID %d", app.name, pid);
        return YES;
      } else {
        WWNLog("LAUNCHER", @"Error: Failed to fork for %@", app.name);
        return NO;
      }
#endif
    }
  }

  WWNLog("LAUNCHER", @"Warning: App not found: %@", appId);
  return NO;
}

// ============================================================================
// Wayland Client State
// ============================================================================

// Internal: Set client_display on delegate using runtime
static void setClientDisplay(WWNAppDelegate *delegate,
                             struct wl_display *display) {
  objc_setAssociatedObject(delegate, @selector(client_display),
                           [NSValue valueWithPointer:display],
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Internal: Get client_display from delegate using runtime
static struct wl_display *getClientDisplay(WWNAppDelegate *delegate) {
  NSValue *value =
      objc_getAssociatedObject(delegate, @selector(client_display));
  return value ? [value pointerValue] : NULL;
}

// Launcher client state
struct launcher_client_state {
  struct wl_compositor *compositor;
  struct wl_shm *shm;
  struct xdg_wm_base *xdg_wm_base;
  struct wl_seat *seat;
  struct wl_touch *touch;
  struct wl_pointer *pointer;
  struct wl_surface *surface;
  struct xdg_surface *xdg_surface;
  struct xdg_toplevel *xdg_toplevel;
  int width;
  int height;
  int ready;
  int configured;
  bool needs_redraw;

  // App grid state
  int selected_app;
  int scroll_offset;
  int icon_size;
  int grid_cols;
  int grid_padding;
};

// ============================================================================
// UI Constants and Drawing
// ============================================================================

#define LAUNCHER_BG_COLOR 0xFF1E1E2E  // Dark background (Catppuccin Mocha)
#define LAUNCHER_ACCENT 0xFF89B4FA    // Accent color (Blue)
#define LAUNCHER_TEXT 0xFFCDD6F4      // Text color (Light)
#define LAUNCHER_SECONDARY 0xFF6C7086 // Secondary text
#define LAUNCHER_SELECTED 0xFF45475A  // Selected item background
#define LAUNCHER_ICON_BG 0xFF313244   // Icon background

// App icon drawing (placeholder - replace with actual icon loading)
static void draw_app_icon(uint32_t *pixels, int buf_width, int x, int y,
                          int size, uint32_t color, const char *initial) {
  // Draw rounded rectangle background
  int radius = size / 8;
  for (int py = 0; py < size; py++) {
    for (int px = 0; px < size; px++) {
      int ix = x + px;
      int iy = y + py;
      if (ix < 0 || ix >= buf_width || iy < 0)
        continue;

      // Simple rounded corner check
      bool in_corner = false;
      if (px < radius && py < radius) {
        int dx = radius - px, dy = radius - py;
        in_corner = (dx * dx + dy * dy) > radius * radius;
      } else if (px >= size - radius && py < radius) {
        int dx = px - (size - radius - 1), dy = radius - py;
        in_corner = (dx * dx + dy * dy) > radius * radius;
      } else if (px < radius && py >= size - radius) {
        int dx = radius - px, dy = py - (size - radius - 1);
        in_corner = (dx * dx + dy * dy) > radius * radius;
      } else if (px >= size - radius && py >= size - radius) {
        int dx = px - (size - radius - 1), dy = py - (size - radius - 1);
        in_corner = (dx * dx + dy * dy) > radius * radius;
      }

      if (!in_corner) {
        pixels[iy * buf_width + ix] = color;
      }
    }
  }

  // Draw initial letter in center (simplified - no real font rendering)
  if (initial && initial[0]) {
    int cx = x + size / 2;
    int cy = y + size / 2;
    int letter_size = size / 3;

    // Simple block letter (placeholder)
    for (int py = cy - letter_size / 2; py < cy + letter_size / 2; py++) {
      for (int px = cx - letter_size / 4; px < cx + letter_size / 4; px++) {
        if (px >= 0 && px < buf_width && py >= 0) {
          pixels[py * buf_width + px] = LAUNCHER_TEXT;
        }
      }
    }
  }
}

// Draw text label (simplified - placeholder for real text rendering)
static void draw_label(uint32_t *pixels, int buf_width, int buf_height, int x,
                       int y, int max_width, const char *text, uint32_t color) {
  // Placeholder: draw a simple underline to indicate text position
  int text_len = text ? (int)strlen(text) : 0;
  int line_width = text_len * 6; // Approximate
  if (line_width > max_width)
    line_width = max_width;

  int start_x = x + (max_width - line_width) / 2;
  for (int px = start_x; px < start_x + line_width && px < buf_width; px++) {
    if (y >= 0 && y < buf_height) {
      // Draw a thin line to represent text
      pixels[y * buf_width + px] = color;
      if (y + 1 < buf_height) {
        pixels[(y + 1) * buf_width + px] = color;
      }
    }
  }
}

// Main UI drawing function
static void draw_launcher_ui(void *data, int width, int height, int stride,
                             struct launcher_client_state *state) {
  uint32_t *pixels = (uint32_t *)data;

  // Clear background
  for (int i = 0; i < width * height; ++i) {
    pixels[i] = LAUNCHER_BG_COLOR;
  }

  // Get applications
  NSArray<WWNLauncherApp *> *apps = getLauncherApplications();

  if (apps.count == 0) {
    // Draw "No Apps" message
    int msg_y = height / 2;
    int msg_x = width / 2 - 50;
    for (int y = msg_y; y < msg_y + 20 && y < height; y++) {
      for (int x = msg_x; x < msg_x + 100 && x < width; x++) {
        pixels[y * width + x] = LAUNCHER_SECONDARY;
      }
    }
    return;
  }

  // Calculate grid layout
  int icon_size = state->icon_size > 0 ? state->icon_size : 64;
  int padding = state->grid_padding > 0 ? state->grid_padding : 20;
  int label_height = 24;
  int cell_width = icon_size + padding;
  int cell_height = icon_size + label_height + padding;

  int cols = (width - padding) / cell_width;
  if (cols < 1)
    cols = 1;
  state->grid_cols = cols;

  // Draw app grid
  for (NSUInteger i = 0; i < apps.count; i++) {
    WWNLauncherApp *app = apps[i];

    int col = (int)(i % cols);
    int row = (int)(i / cols);

    int cell_x = padding + col * cell_width;
    int cell_y = padding + row * cell_height - state->scroll_offset;

    // Skip if off-screen
    if (cell_y + cell_height < 0 || cell_y > height)
      continue;

    // Draw selection highlight
    if ((int)i == state->selected_app) {
      for (int y = cell_y; y < cell_y + cell_height && y < height; y++) {
        if (y < 0)
          continue;
        for (int x = cell_x; x < cell_x + cell_width && x < width; x++) {
          pixels[y * width + x] = LAUNCHER_SELECTED;
        }
      }
    }

    // Generate icon color from app name (simple hash)
    uint32_t icon_color = LAUNCHER_ICON_BG;
    if (app.name) {
      unsigned hash = 0;
      for (const char *c = [app.name UTF8String]; *c; c++) {
        hash = hash * 31 + *c;
      }
      // Generate a pleasant color
      uint8_t hue = hash % 360;
      uint8_t r = 128 + (hash % 64);
      uint8_t g = 128 + ((hash >> 8) % 64);
      uint8_t b = 128 + ((hash >> 16) % 64);
      icon_color = 0xFF000000 | (r << 16) | (g << 8) | b;
    }

    // Draw icon
    int icon_x = cell_x + (cell_width - icon_size) / 2;
    int icon_y = cell_y + padding / 2;
    char initial[2] = {app.name ? [app.name UTF8String][0] : '?', 0};
    draw_app_icon(pixels, width, icon_x, icon_y, icon_size, icon_color,
                  initial);

    // Draw label
    int label_y = icon_y + icon_size + 4;
    draw_label(pixels, width, height, cell_x, label_y, cell_width,
               [app.name UTF8String], LAUNCHER_TEXT);
  }

  // Draw header bar
  for (int y = 0; y < 40 && y < height; y++) {
    for (int x = 0; x < width; x++) {
      pixels[y * width + x] = LAUNCHER_SELECTED;
    }
  }
}

// ============================================================================
// Wayland Protocol Handlers
// ============================================================================

// Registry listener callbacks
static void launcher_registry_handle_global(void *data,
                                            struct wl_registry *registry,
                                            uint32_t name,
                                            const char *interface,
                                            uint32_t version) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;

  WWNLog("LAUNCHER", @"Found global: %s v%u", interface, version);

  if (strcmp(interface, "wl_compositor") == 0) {
    uint32_t bind_version = version < 4 ? version : 4;
    state->compositor = (struct wl_compositor *)wl_registry_bind(
        registry, name, &wl_compositor_interface, bind_version);
    if (state->compositor) {
      WWNLog("LAUNCHER", @"Bound wl_compositor v%u", bind_version);
    }
  } else if (strcmp(interface, "wl_shm") == 0) {
    state->shm =
        (struct wl_shm *)wl_registry_bind(registry, name, &wl_shm_interface, 1);
    WWNLog("LAUNCHER", @"Bound wl_shm");
  } else if (strcmp(interface, "xdg_wm_base") == 0) {
    state->xdg_wm_base = (struct xdg_wm_base *)wl_registry_bind(
        registry, name, &xdg_wm_base_interface, 1);
    WWNLog("LAUNCHER", @"Bound xdg_wm_base");
  } else if (strcmp(interface, "wl_seat") == 0) {
    state->seat = (struct wl_seat *)wl_registry_bind(registry, name,
                                                     &wl_seat_interface, 7);
    WWNLog("LAUNCHER", @"Bound wl_seat");
  }
}

static void launcher_registry_handle_global_remove(void *data,
                                                   struct wl_registry *registry,
                                                   uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener launcher_registry_listener = {
    launcher_registry_handle_global, launcher_registry_handle_global_remove};

// XDG Shell listeners
static void xdg_wm_base_ping(void *data, struct xdg_wm_base *xdg_wm_base,
                             uint32_t serial) {
  xdg_wm_base_pong(xdg_wm_base, serial);
}

static const struct xdg_wm_base_listener xdg_wm_base_listener = {
    .ping = xdg_wm_base_ping,
};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface,
                                  uint32_t serial) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;
  xdg_surface_ack_configure(xdg_surface, serial);
  state->configured = 1;
  state->needs_redraw = true;
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_configure,
};

static void xdg_toplevel_configure(void *data,
                                   struct xdg_toplevel *xdg_toplevel,
                                   int32_t width, int32_t height,
                                   struct wl_array *states) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;

  if (width > 0 && height > 0) {
    if (state->width != width || state->height != height) {
      state->width = width;
      state->height = height;
      WWNLog("LAUNCHER", @"Resize to %dx%d", width, height);
      state->needs_redraw = true;
    }
  }
}

static void xdg_toplevel_close(void *data, struct xdg_toplevel *xdg_toplevel) {
  WWNLog("LAUNCHER", @"Close requested");
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    .configure = xdg_toplevel_configure,
    .close = xdg_toplevel_close,
};

// ============================================================================
// Input Handling
// ============================================================================

static int get_app_at_position(struct launcher_client_state *state, int x,
                               int y) {
  NSArray<WWNLauncherApp *> *apps = getLauncherApplications();
  if (apps.count == 0)
    return -1;

  int icon_size = state->icon_size > 0 ? state->icon_size : 64;
  int padding = state->grid_padding > 0 ? state->grid_padding : 20;
  int label_height = 24;
  int cell_width = icon_size + padding;
  int cell_height = icon_size + label_height + padding;
  int cols = state->grid_cols > 0 ? state->grid_cols : 1;

  // Adjust for scroll
  y += state->scroll_offset;

  // Skip header
  if (y < 40)
    return -1;

  int col = (x - padding) / cell_width;
  int row = (y - padding) / cell_height;

  if (col < 0 || col >= cols)
    return -1;
  if (row < 0)
    return -1;

  int index = row * cols + col;
  if (index < 0 || index >= (int)apps.count)
    return -1;

  return index;
}

static void touch_down(void *data, struct wl_touch *wl_touch, uint32_t serial,
                       uint32_t timestamp, struct wl_surface *surface,
                       int32_t id, wl_fixed_t x_w, wl_fixed_t y_w) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;
  int x = wl_fixed_to_int(x_w);
  int y = wl_fixed_to_int(y_w);

  int app_idx = get_app_at_position(state, x, y);
  if (app_idx >= 0) {
    state->selected_app = app_idx;
    state->needs_redraw = true;
    WWNLog("LAUNCHER", @"Selected app %d", app_idx);
  }
}

static void touch_up(void *data, struct wl_touch *wl_touch, uint32_t serial,
                     uint32_t timestamp, int32_t id) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;

  if (state->selected_app >= 0) {
    NSArray<WWNLauncherApp *> *apps = getLauncherApplications();
    if (state->selected_app < (int)apps.count) {
      WWNLauncherApp *app = apps[state->selected_app];
      WWNLog("LAUNCHER", @"Launching %@", app.name);
      launchLauncherApplication(app.appId);
    }
    state->selected_app = -1;
    state->needs_redraw = true;
  }
}

static void touch_motion(void *data, struct wl_touch *wl_touch,
                         uint32_t timestamp, int32_t id, wl_fixed_t x_w,
                         wl_fixed_t y_w) {}
static void touch_frame(void *data, struct wl_touch *wl_touch) {}
static void touch_cancel(void *data, struct wl_touch *wl_touch) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;
  state->selected_app = -1;
  state->needs_redraw = true;
}
static void touch_shape(void *data, struct wl_touch *wl_touch, int32_t id,
                        wl_fixed_t major, wl_fixed_t minor) {}
static void touch_orientation(void *data, struct wl_touch *wl_touch, int32_t id,
                              wl_fixed_t orientation) {}

static const struct wl_touch_listener touch_listener = {
    .down = touch_down,
    .up = touch_up,
    .motion = touch_motion,
    .frame = touch_frame,
    .cancel = touch_cancel,
    .shape = touch_shape,
    .orientation = touch_orientation,
};

// Pointer (mouse) handlers for macOS
static void pointer_enter(void *data, struct wl_pointer *wl_pointer,
                          uint32_t serial, struct wl_surface *surface,
                          wl_fixed_t x, wl_fixed_t y) {}
static void pointer_leave(void *data, struct wl_pointer *wl_pointer,
                          uint32_t serial, struct wl_surface *surface) {}
static void pointer_motion(void *data, struct wl_pointer *wl_pointer,
                           uint32_t timestamp, wl_fixed_t x, wl_fixed_t y) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;
  int ix = wl_fixed_to_int(x);
  int iy = wl_fixed_to_int(y);

  int app_idx = get_app_at_position(state, ix, iy);
  if (app_idx != state->selected_app) {
    state->selected_app = app_idx;
    state->needs_redraw = true;
  }
}
static void pointer_button(void *data, struct wl_pointer *wl_pointer,
                           uint32_t serial, uint32_t timestamp, uint32_t button,
                           uint32_t state_val) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;

  if (state_val == WL_POINTER_BUTTON_STATE_RELEASED &&
      state->selected_app >= 0) {
    NSArray<WWNLauncherApp *> *apps = getLauncherApplications();
    if (state->selected_app < (int)apps.count) {
      WWNLauncherApp *app = apps[state->selected_app];
      WWNLog("LAUNCHER", @"Launching %@", app.name);
      launchLauncherApplication(app.appId);
    }
  }
}
static void pointer_axis(void *data, struct wl_pointer *wl_pointer,
                         uint32_t timestamp, uint32_t axis, wl_fixed_t value) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;
  if (axis == WL_POINTER_AXIS_VERTICAL_SCROLL) {
    state->scroll_offset += wl_fixed_to_int(value);
    if (state->scroll_offset < 0)
      state->scroll_offset = 0;
    state->needs_redraw = true;
  }
}

static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter,
    .leave = pointer_leave,
    .motion = pointer_motion,
    .button = pointer_button,
    .axis = pointer_axis,
};

static void seat_capabilities(void *data, struct wl_seat *wl_seat,
                              uint32_t caps) {
  struct launcher_client_state *state = (struct launcher_client_state *)data;

  if ((caps & WL_SEAT_CAPABILITY_TOUCH) && !state->touch) {
    state->touch = wl_seat_get_touch(wl_seat);
    wl_touch_add_listener(state->touch, &touch_listener, state);
    WWNLog("LAUNCHER", @"Got touch device");
  }

  if ((caps & WL_SEAT_CAPABILITY_POINTER) && !state->pointer) {
    state->pointer = wl_seat_get_pointer(wl_seat);
    wl_pointer_add_listener(state->pointer, &pointer_listener, state);
    WWNLog("LAUNCHER", @"Got pointer device");
  }
}

static void seat_name(void *data, struct wl_seat *wl_seat, const char *name) {}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

// ============================================================================
// SHM Buffer Creation
// ============================================================================

static int create_shm_file(off_t size) {
  char template[1024];
  const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
  if (runtime_dir) {
    snprintf(template, sizeof(template), "%s/wawona-shm-XXXXXX", runtime_dir);
  } else {
    snprintf(template, sizeof(template), "/tmp/wawona-shm-XXXXXX");
  }

  int fd = mkstemp(template);
  if (fd < 0)
    return -1;
  unlink(template);

  if (ftruncate(fd, size) < 0) {
    close(fd);
    return -1;
  }

  return fd;
}

static struct wl_buffer *create_shm_buffer(struct launcher_client_state *state,
                                           int width, int height) {
  if (!state->shm)
    return NULL;

  int stride = width * 4;
  int size = stride * height;

  int fd = create_shm_file(size);
  if (fd < 0) {
    WWNLog("LAUNCHER", @"Error: Failed to create SHM file");
    return NULL;
  }

  void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (data == MAP_FAILED) {
    WWNLog("LAUNCHER", @"Error: Failed to mmap SHM");
    close(fd);
    return NULL;
  }

  struct wl_shm_pool *pool = wl_shm_create_pool(state->shm, fd, size);
  struct wl_buffer *buffer = wl_shm_pool_create_buffer(
      pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
  wl_shm_pool_destroy(pool);
  close(fd);

  // Draw UI
  draw_launcher_ui(data, width, height, stride, state);

  munmap(data, size);
  return buffer;
}

// ============================================================================
// Thread Arguments
// ============================================================================

typedef struct {
  __unsafe_unretained WWNAppDelegate *delegate;
  int client_fd;
} LauncherThreadArgs;

// ============================================================================
// Main Launcher Thread
// ============================================================================

static void *launcherClientThread(void *arg) {
  LauncherThreadArgs *args = (LauncherThreadArgs *)arg;
  WWNAppDelegate *delegate = args->delegate;
  int client_fd = args->client_fd;
  free(args);

  // Initialize application list
  refreshLauncherApplicationList();

  // Initialize state
  struct launcher_client_state state = {0};
  state.width = 800;
  state.height = 600;
  state.icon_size = 64;
  state.grid_padding = 20;
  state.selected_app = -1;

  struct wl_display *client_display = NULL;

  // Connect to compositor
  if (client_fd >= 0) {
    WWNLog("LAUNCHER", @"Connecting via fd %d", client_fd);
    client_display = wl_display_connect_to_fd(client_fd);
  } else {
    const char *tcp_port_str = getenv("WAYLAND_TCP_PORT");
    if (tcp_port_str && tcp_port_str[0]) {
      int port = atoi(tcp_port_str);
      int tcp_fd = socket(AF_INET, SOCK_STREAM, 0);
      if (tcp_fd >= 0) {
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = inet_addr("127.0.0.1");
        addr.sin_port = htons(port);

        if (connect(tcp_fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
          client_display = wl_display_connect_to_fd(tcp_fd);
        } else {
          close(tcp_fd);
        }
      }
    } else {
      client_display = wl_display_connect(NULL);
    }
  }

  if (!client_display) {
    WWNLog("LAUNCHER", @"Error: Failed to connect to compositor");
    return NULL;
  }

  setClientDisplay(delegate, client_display);
  WWNLog("LAUNCHER", @"Connected to compositor");

  // Get registry
  struct wl_registry *registry = wl_display_get_registry(client_display);
  wl_registry_add_listener(registry, &launcher_registry_listener, &state);
  wl_display_roundtrip(client_display);

  if (!state.compositor || !state.shm) {
    WWNLog("LAUNCHER", @"Error: Missing required globals");
    wl_registry_destroy(registry);
    wl_display_disconnect(client_display);
    setClientDisplay(delegate, NULL);
    return NULL;
  }

  // Create surface
  state.surface = wl_compositor_create_surface(state.compositor);

  if (state.xdg_wm_base) {
    xdg_wm_base_add_listener(state.xdg_wm_base, &xdg_wm_base_listener, &state);

    state.xdg_surface =
        xdg_wm_base_get_xdg_surface(state.xdg_wm_base, state.surface);
    xdg_surface_add_listener(state.xdg_surface, &xdg_surface_listener, &state);

    state.xdg_toplevel = xdg_surface_get_toplevel(state.xdg_surface);
    xdg_toplevel_add_listener(state.xdg_toplevel, &xdg_toplevel_listener,
                              &state);
    xdg_toplevel_set_title(state.xdg_toplevel, "Wawona Launcher");
    xdg_toplevel_set_app_id(state.xdg_toplevel,
                            "com.aspauldingcode.Wawona.Launcher");

    wl_surface_commit(state.surface);
    wl_display_roundtrip(client_display);
  }

  // Set up input
  if (state.seat) {
    wl_seat_add_listener(state.seat, &seat_listener, &state);
    wl_display_roundtrip(client_display);
  }

  // Initial render
  struct wl_buffer *buffer =
      create_shm_buffer(&state, state.width, state.height);
  if (buffer) {
    wl_surface_attach(state.surface, buffer, 0, 0);
    wl_surface_damage(state.surface, 0, 0, state.width, state.height);
    wl_surface_commit(state.surface);
  }

  WWNLog("LAUNCHER", @"Running with %lu apps",
         (unsigned long)getLauncherApplications().count);

  // Event loop
  while (wl_display_dispatch(client_display) != -1) {
    if (state.needs_redraw) {
      state.needs_redraw = false;
      buffer = create_shm_buffer(&state, state.width, state.height);
      if (buffer) {
        wl_surface_attach(state.surface, buffer, 0, 0);
        wl_surface_damage(state.surface, 0, 0, state.width, state.height);
        wl_surface_commit(state.surface);
      }
      wl_display_flush(client_display);
    }
  }

  // Cleanup
  WWNLog("LAUNCHER", @"Shutting down");
  if (state.xdg_toplevel)
    xdg_toplevel_destroy(state.xdg_toplevel);
  if (state.xdg_surface)
    xdg_surface_destroy(state.xdg_surface);
  if (state.surface)
    wl_surface_destroy(state.surface);
  if (state.touch)
    wl_touch_destroy(state.touch);
  if (state.pointer)
    wl_pointer_destroy(state.pointer);
  wl_registry_destroy(registry);
  wl_display_disconnect(client_display);
  setClientDisplay(delegate, NULL);

  return NULL;
}

// ============================================================================
// Public API
// ============================================================================

pthread_t startLauncherClientThread(WWNAppDelegate *delegate, int client_fd) {
  LauncherThreadArgs *args = malloc(sizeof(LauncherThreadArgs));
  if (!args) {
    if (client_fd >= 0)
      close(client_fd);
    return NULL;
  }

  args->delegate = delegate;
  args->client_fd = client_fd;

  pthread_t thread;
  if (pthread_create(&thread, NULL, launcherClientThread, args) != 0) {
    free(args);
    if (client_fd >= 0)
      close(client_fd);
    return NULL;
  }

  pthread_detach(thread);
  WWNLog("LAUNCHER", @"Thread started");
  return thread;
}

struct wl_display *getLauncherClientDisplay(WWNAppDelegate *delegate) {
  return getClientDisplay(delegate);
}

void disconnectLauncherClient(WWNAppDelegate *delegate) {
  struct wl_display *display = getClientDisplay(delegate);
  if (display) {
    wl_display_disconnect(display);
    setClientDisplay(delegate, NULL);
  }
}
