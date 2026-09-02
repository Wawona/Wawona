#import "WWNCLIMachineRecipes.h"

NSNotificationName const WWNMachineProfilesChangedNotification =
    @"WWNMachineProfilesChangedNotification";

NSString *const kWWNCLIRecipeKey = @"cliRecipeKey";
NSString *const kWWNMachineOrigin = @"origin";
NSString *const kWWNMachineOriginCLI = @"cli";
NSString *const kWWNMachineOriginManual = @"manual";

/// Prebaked desktop OCI (wwn-containers `wawona-container-desktop`). No
/// `nix shell` at Start. Fall back to pulling the tag if the archive is not
/// bundled under Resources/oci/.
static NSString *const kWWNCLIDesktopImageRef = @"wawona-container-desktop:latest";

static NSString *WWNCLIStableMachineId(NSString *recipeKey) {
  // recipeKey is already cli:native:… / cli:container:… → cli-native-…
  return [[recipeKey stringByReplacingOccurrencesOfString:@":" withString:@"-"]
      lowercaseString];
}

static NSString *WWNCLISwayConfig(void) {
  // Nested sway over waypipe: pixman + Alt+Enter terminal (ghostty, else foot).
  return @"# Wawona nested sway (container / waypipe)\n"
         @"output * bg #1a1b26 solid_color\n"
         @"exec swaybg -c '#1a1b26'\n"
         @"\n"
         @"set $mod Mod1\n"
         @"set $term sh -c 'command -v ghostty >/dev/null && exec ghostty || "
         @"exec foot'\n"
         @"\n"
         @"bindsym $mod+Return exec $term\n"
         @"bindsym $mod+Shift+q kill\n"
         @"bindsym $mod+Shift+e exit\n"
         @"bindsym $mod+Left focus left\n"
         @"bindsym $mod+Right focus right\n"
         @"bindsym $mod+Up focus up\n"
         @"bindsym $mod+Down focus down\n"
         @"\n"
         @"default_border pixel 2\n"
         @"font pango:monospace 11\n"
         @"bar {\n"
         @"    position top\n"
         @"    status_command while date +'%Y-%m-%d %H:%M:%S'; do sleep 1; "
         @"done\n"
         @"}\n";
}

/// Bundled OCI layout from product-build (optional). When present, Start uses
/// `--image-archive` and never pulls or runs `nix shell`.
static NSString *WWNCLIBundledDesktopArchive(void) {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *path =
      [bundle pathForResource:@"wawona-container-desktop" ofType:nil
                  inDirectory:@"oci"];
  if (path.length == 0) {
    path = [bundle pathForResource:@"wawona-container-desktop" ofType:nil];
  }
  if (path.length > 0) {
    NSString *index = [path stringByAppendingPathComponent:@"index.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:index]) {
      return path;
    }
  }
  return nil;
}

/// Local `container import` layout under ~/.local/share/wwn-oci (or $WWN_OCI_ROOT).
/// Prefers a catalog entry whose reference contains wawona-container-desktop.
static NSString *WWNCLIImportedDesktopArchive(void) {
  NSString *root = NSProcessInfo.processInfo.environment[@"WWN_OCI_ROOT"];
  if (root.length == 0) {
    root = [NSHomeDirectory()
        stringByAppendingPathComponent:@".local/share/wwn-oci"];
  }
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *imagesDir = [root stringByAppendingPathComponent:@"images"];
  NSArray<NSString *> *catalogFiles =
      [fm contentsOfDirectoryAtPath:imagesDir error:nil];
  for (NSString *name in catalogFiles) {
    if (![name.pathExtension isEqualToString:@"json"]) {
      continue;
    }
    NSData *data =
        [NSData dataWithContentsOfFile:[imagesDir stringByAppendingPathComponent:name]];
    if (data.length == 0) {
      continue;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *ref = json[@"reference"] ?: json[@"canonical"];
    if (![ref isKindOfClass:[NSString class]] ||
        [ref rangeOfString:@"wawona-container-desktop"].location == NSNotFound) {
      continue;
    }
    NSString *digest = json[@"manifest_digest"];
    if (![digest isKindOfClass:[NSString class]] ||
        ![digest hasPrefix:@"sha256:"] || digest.length <= 7) {
      continue;
    }
    NSString *hex = [digest substringFromIndex:7];
    NSString *layoutDir = [[root stringByAppendingPathComponent:@"oci-layout"]
        stringByAppendingPathComponent:hex];
    NSString *index = [layoutDir stringByAppendingPathComponent:@"index.json"];
    if ([fm fileExistsAtPath:index]) {
      return layoutDir;
    }
  }
  // Fallback: single layout dir under oci-layout/ (common after one import).
  NSString *layouts = [root stringByAppendingPathComponent:@"oci-layout"];
  NSArray<NSString *> *kids =
      [fm contentsOfDirectoryAtPath:layouts error:nil];
  if (kids.count == 1) {
    NSString *layoutDir =
        [layouts stringByAppendingPathComponent:kids.firstObject];
    NSString *index = [layoutDir stringByAppendingPathComponent:@"index.json"];
    if ([fm fileExistsAtPath:index]) {
      return layoutDir;
    }
  }
  return nil;
}

static NSString *WWNCLIDesktopArchive(void) {
  NSString *bundled = WWNCLIBundledDesktopArchive();
  if (bundled.length > 0) {
    return bundled;
  }
  return WWNCLIImportedDesktopArchive();
}

@implementation WWNCLIMachineRecipes

+ (NSArray<NSString *> *)allRecipeIds {
  return @[
    @"flower",
    @"weston-flower",
    @"weston-terminal",
    @"foot",
    @"ghostty",
    @"weston",
    @"weston-container",
    @"niri",
    @"sway",
    @"labwc",
    @"plasma",
    @"kwin",
    @"gnome",
    @"hyprland",
  ];
}

+ (void)printRecipeHelp {
  printf("Usage: Wawona run <recipe>\n"
         "\n"
         "Creates a Machines card if none exists for this recipe, then starts "
         "it.\n"
         "CLI and GUI share the same profiles (wawona.machineProfiles.v1).\n"
         "\n"
         "Recipes:\n"
         "  flower            weston-flower in a container (200x200)\n"
         "  weston-terminal   Weston Terminal (native bundled)\n"
         "  foot              foot terminal (native bundled)\n"
         "  ghostty           Ghostty in prebaked desktop container\n"
         "  weston            nested Weston compositor (native)\n"
         "  weston-container  Weston in a container (waypipe)\n"
         "  niri              nested niri (native)\n"
         "  sway              nested sway + wallpaper + Alt+Enter terminal "
         "(container)\n"
         "  labwc             labwc (container)\n"
         "  plasma / kwin     KWin nested (container; needs guest dbus)\n"
         "  gnome             GNOME Shell (container; needs guest dbus)\n"
         "  hyprland          Hyprland (container)\n"
         "\n"
         "Container recipes use image %s (no nix shell at Start).\n"
         "Also: Wawona machines list | show <id|name>\n",
         [kWWNCLIDesktopImageRef UTF8String]);
}

+ (nullable WWNMachineProfile *)profileMatchingIdOrName:(NSString *)query {
  if (query.length == 0) {
    return nil;
  }
  NSArray<WWNMachineProfile *> *profiles = [WWNMachineProfileStore loadProfiles];
  for (WWNMachineProfile *p in profiles) {
    if ([p.machineId isEqualToString:query]) {
      return p;
    }
  }
  NSString *lower = query.lowercaseString;
  for (WWNMachineProfile *p in profiles) {
    if ([p.name.lowercaseString isEqualToString:lower]) {
      return p;
    }
  }
  // Recipe short name (flower, sway, weston, …) or full cli:… key.
  for (WWNMachineProfile *p in profiles) {
    NSString *key = p.runtimeOverrides[kWWNCLIRecipeKey];
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    if ([key.lowercaseString isEqualToString:lower]) {
      return p;
    }
    NSArray<NSString *> *parts = [key componentsSeparatedByString:@":"];
    NSString *shortId = parts.lastObject.lowercaseString;
    if ([shortId isEqualToString:lower]) {
      return p;
    }
  }
  // Stable id forms: cli-native-weston / cli-container-flower
  NSString *asIdNative =
      [NSString stringWithFormat:@"cli-native-%@", lower];
  NSString *asIdContainer =
      [NSString stringWithFormat:@"cli-container-%@", lower];
  for (WWNMachineProfile *p in profiles) {
    if ([p.machineId isEqualToString:asIdNative] ||
        [p.machineId isEqualToString:asIdContainer]) {
      return p;
    }
  }
  return nil;
}

+ (nullable WWNMachineProfile *)profileForRecipeKey:(NSString *)recipeKey {
  for (WWNMachineProfile *p in [WWNMachineProfileStore loadProfiles]) {
    NSString *key = p.runtimeOverrides[kWWNCLIRecipeKey];
    if ([key isKindOfClass:[NSString class]] && [key isEqualToString:recipeKey]) {
      return p;
    }
    if ([p.machineId isEqualToString:WWNCLIStableMachineId(recipeKey)]) {
      return p;
    }
  }
  return nil;
}

+ (void)notifyProfilesChanged {
#if TARGET_OS_OSX
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:WWNMachineProfilesChangedNotification
                    object:nil
                  userInfo:nil
        deliverImmediately:YES];
#endif
  [[NSNotificationCenter defaultCenter]
      postNotificationName:WWNMachineProfilesChangedNotification
                    object:nil];
}

+ (NSDictionary *)nativeRecipeSpec:(NSString *)recipe {
  // bundledAppID / NativeClientId for native Machines Start.
  NSDictionary *map = @{
    @"weston" : @{@"id" : @"weston", @"name" : @"Weston"},
    @"niri" : @{@"id" : @"niri", @"name" : @"Niri"},
    @"weston-terminal" : @{
      @"id" : @"weston-terminal",
      @"name" : @"Weston Terminal"
    },
    @"foot" : @{@"id" : @"foot", @"name" : @"Foot"},
    @"weston-simple-egl" : @{
      @"id" : @"weston-simple-egl",
      @"name" : @"Weston Simple EGL"
    },
    @"weston-simple-shm" : @{
      @"id" : @"weston-simple-shm",
      @"name" : @"Weston Simple SHM"
    },
    @"opengl-cube" : @{@"id" : @"opengl-cube", @"name" : @"OpenGL Cube"},
    @"vkcube" : @{@"id" : @"vkcube", @"name" : @"Vulkan Cube"},
    @"kmscube" : @{@"id" : @"kmscube", @"name" : @"kmscube"},
  };
  return map[recipe];
}

+ (nullable NSDictionary *)containerRecipeSpec:(NSString *)recipe {
  // Direct binaries from wawona-container-desktop. Never nix shell at Start.
  if ([recipe isEqualToString:@"flower"] ||
      [recipe isEqualToString:@"weston-flower"]) {
    return @{
      @"name" : @"Flower (container)",
      @"entry" : @"weston-flower",
      @"mem" : @"2048",
    };
  }
  if ([recipe isEqualToString:@"ghostty"]) {
    // Prebaked desktop image may omit ghostty (layer collisions). Prefer
    // ghostty when present; otherwise foot from the same image.
    return @{
      @"name" : @"Ghostty (container)",
      @"entry" : @"sh -c 'command -v ghostty >/dev/null && exec ghostty || "
                 @"exec foot'",
      @"mem" : @"2048",
    };
  }
  if ([recipe isEqualToString:@"sway"]) {
    NSString *cfg = WWNCLISwayConfig();
    NSString *b64 = [[cfg dataUsingEncoding:NSUTF8StringEncoding]
        base64EncodedStringWithOptions:0];
    NSString *entry = [NSString
        stringWithFormat:
            @"sh -c 'export WLR_BACKENDS=wayland WLR_RENDERER=pixman "
            @"WLR_LIBINPUT_NO_DEVICES=1 XDG_CONFIG_HOME=/tmp/wawona-xdg; "
            @"mkdir -p \"$XDG_CONFIG_HOME/sway\"; "
            @"echo %@ | base64 -d > \"$XDG_CONFIG_HOME/sway/config\"; "
            @"exec sway -c \"$XDG_CONFIG_HOME/sway/config\"'",
            b64];
    return @{
      @"name" : @"Sway (container)",
      @"entry" : entry,
      @"mem" : @"2048",
    };
  }
  if ([recipe isEqualToString:@"labwc"]) {
    return @{
      @"name" : @"labwc (container)",
      @"entry" : @"labwc",
      @"mem" : @"2048",
    };
  }
  if ([recipe isEqualToString:@"plasma"] || [recipe isEqualToString:@"kwin"]) {
    return @{
      @"name" : @"Plasma / KWin (container)",
      @"entry" : @"sh -c 'export QT_QPA_PLATFORM=wayland; "
                 @"exec kwin_wayland --platform wayland'",
      @"mem" : @"4096",
    };
  }
  if ([recipe isEqualToString:@"gnome"]) {
    return @{
      @"name" : @"GNOME (container)",
      @"entry" : @"sh -c 'mkdir -p /run/user/0; "
                 @"exec dbus-run-session -- gnome-shell --wayland'",
      @"mem" : @"4096",
    };
  }
  if ([recipe isEqualToString:@"hyprland"]) {
    return @{
      @"name" : @"Hyprland (container)",
      @"entry" : @"sh -c 'export WLR_BACKENDS=wayland WLR_RENDERER=pixman "
                 @"WLR_LIBINPUT_NO_DEVICES=1; exec Hyprland'",
      @"mem" : @"4096",
    };
  }
  // Optional: container weston when user wants container path explicitly.
  if ([recipe isEqualToString:@"weston-container"]) {
    return @{
      @"name" : @"Weston (container)",
      @"entry" : @"weston --backend=wayland",
      @"mem" : @"2048",
    };
  }
  return nil;
}

+ (NSMutableDictionary *)containerSettingsForSpec:(NSDictionary *)container {
  NSMutableDictionary *cs = [NSMutableDictionary dictionary];
  cs[@"entryCommand"] = container[@"entry"];
  cs[@"containerRef"] = kWWNCLIDesktopImageRef;
  cs[@"desktopSession"] = @YES;
  cs[@"memory"] = container[@"mem"] ?: @"2048";
  cs[@"remove"] = @YES;
  NSString *archive = WWNCLIDesktopArchive();
  if (archive.length > 0) {
    cs[@"imageArchivePath"] = archive;
  }
  return cs;
}

+ (nullable WWNMachineProfile *)ensureProfileForRecipe:(NSString *)rawRecipe
                                                 error:(NSError *_Nullable *_Nullable)error {
  NSString *recipe =
      [[rawRecipe stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]]
          lowercaseString];
  if (recipe.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WawonaCLI"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Missing recipe. Try: Wawona run --help"
                 }];
    }
    return nil;
  }

  NSDictionary *native = [self nativeRecipeSpec:recipe];
  NSDictionary *container = [self containerRecipeSpec:recipe];

  if (!native && !container) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WawonaCLI"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"Unknown recipe '%@'. Try: Wawona run --help",
                                        rawRecipe]
                 }];
    }
    return nil;
  }

  // Prefer native when both exist (weston/niri). Container-only recipes use container.
  BOOL useContainer = (container != nil) && (native == nil);
  NSString *recipeKey =
      useContainer ? [NSString stringWithFormat:@"cli:container:%@", recipe]
                   : [NSString stringWithFormat:@"cli:native:%@", recipe];

  WWNMachineProfile *existing = [self profileForRecipeKey:recipeKey];
  if (existing) {
    // Refresh launch settings from current recipe (CLI improvements apply).
    if (useContainer) {
      existing.containerSettings = [self containerSettingsForSpec:container];
      NSMutableDictionary *ro =
          [existing.runtimeOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
      ro[kWWNCLIRecipeKey] = recipeKey;
      ro[kWWNMachineOrigin] = kWWNMachineOriginCLI;
      ro[@"useBundledApp"] = @NO;
      ro[@"bundledAppID"] = @"";
      existing.runtimeOverrides = ro;
    } else {
      NSMutableDictionary *so =
          [existing.settingsOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
      so[@"NativeClientId"] = native[@"id"];
      existing.settingsOverrides = so;
      NSMutableDictionary *ro =
          [existing.runtimeOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
      ro[@"bundledAppID"] = native[@"id"];
      ro[@"useBundledApp"] = @YES;
      ro[kWWNCLIRecipeKey] = recipeKey;
      ro[kWWNMachineOrigin] = kWWNMachineOriginCLI;
      existing.runtimeOverrides = ro;
    }
    [WWNMachineProfileStore upsertProfile:existing];
    [self notifyProfilesChanged];
    return existing;
  }

  WWNMachineProfile *profile = [WWNMachineProfile defaultProfile];
  profile.machineId = WWNCLIStableMachineId(recipeKey);
  profile.sshEnabled = NO;

  if (useContainer) {
    profile.name = container[@"name"];
    profile.type = kWWNMachineTypeContainer;
    profile.containerSettings = [self containerSettingsForSpec:container];
    profile.settingsOverrides = @{};
    profile.runtimeOverrides = @{
      kWWNCLIRecipeKey : recipeKey,
      kWWNMachineOrigin : kWWNMachineOriginCLI,
      @"useBundledApp" : @NO,
      @"bundledAppID" : @"",
    };
  } else {
    profile.name = native[@"name"];
    profile.type = kWWNMachineTypeNative;
    profile.settingsOverrides = @{
      @"NativeClientId" : native[@"id"],
      @"EnableLauncher" : @YES,
    };
    profile.runtimeOverrides = @{
      kWWNCLIRecipeKey : recipeKey,
      kWWNMachineOrigin : kWWNMachineOriginCLI,
      @"bundledAppID" : native[@"id"],
      @"useBundledApp" : @YES,
    };
    profile.containerSettings = @{};
  }

  [WWNMachineProfileStore upsertProfile:profile];
  [self notifyProfilesChanged];
  return profile;
}

@end
