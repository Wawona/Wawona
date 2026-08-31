#import "WWNCLIMachineRecipes.h"

NSNotificationName const WWNMachineProfilesChangedNotification =
    @"WWNMachineProfilesChangedNotification";

NSString *const kWWNCLIRecipeKey = @"cliRecipeKey";
NSString *const kWWNMachineOrigin = @"origin";
NSString *const kWWNMachineOriginCLI = @"cli";
NSString *const kWWNMachineOriginManual = @"manual";

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

static NSString *WWNCLINixShellPrefix(void) {
  return @"nix --extra-experimental-features nix-command shell -f "
         @"'<nixpkgs>'";
}

@implementation WWNCLIMachineRecipes

+ (NSArray<NSString *> *)allRecipeIds {
  return @[
    @"flower",
    @"weston-flower",
    @"weston-terminal",
    @"foot",
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
         "Also: Wawona machines list | show <id|name>\n");
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
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:WWNMachineProfilesChangedNotification
                    object:nil
                  userInfo:nil
        deliverImmediately:YES];
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
  NSString *nix = WWNCLINixShellPrefix();
  if ([recipe isEqualToString:@"flower"] ||
      [recipe isEqualToString:@"weston-flower"]) {
    return @{
      @"name" : @"Flower (container)",
      @"entry" : [NSString stringWithFormat:@"%@ weston -c weston-flower", nix],
      @"mem" : @"2048",
    };
  }
  if ([recipe isEqualToString:@"sway"]) {
    NSString *cfg = WWNCLISwayConfig();
    NSString *b64 = [[cfg dataUsingEncoding:NSUTF8StringEncoding]
        base64EncodedStringWithOptions:0];
    NSString *entry = [NSString
        stringWithFormat:
            @"%@ sway-unwrapped swaybg ghostty foot -c sh -c "
            @"'export WLR_BACKENDS=wayland WLR_RENDERER=pixman "
            @"WLR_LIBINPUT_NO_DEVICES=1 XDG_CONFIG_HOME=/tmp/wawona-xdg; "
            @"mkdir -p \"$XDG_CONFIG_HOME/sway\"; "
            @"echo %@ | base64 -d > \"$XDG_CONFIG_HOME/sway/config\"; "
            @"exec sway -c \"$XDG_CONFIG_HOME/sway/config\"'",
            nix, b64];
    return @{
      @"name" : @"Sway (container)",
      @"entry" : entry,
      @"mem" : @"2048",
    };
  }
  if ([recipe isEqualToString:@"labwc"]) {
    return @{
      @"name" : @"labwc (container)",
      @"entry" : [NSString stringWithFormat:@"%@ labwc -c labwc", nix],
      @"mem" : @"2048",
    };
  }
  if ([recipe isEqualToString:@"plasma"] || [recipe isEqualToString:@"kwin"]) {
    return @{
      @"name" : @"Plasma / KWin (container)",
      @"entry" : [NSString
          stringWithFormat:@"%@ kwin qtwayland -c sh -c "
                           @"'export QT_QPA_PLATFORM=wayland; "
                           @"exec kwin_wayland --platform wayland'",
                           nix],
      @"mem" : @"4096",
    };
  }
  if ([recipe isEqualToString:@"gnome"]) {
    return @{
      @"name" : @"GNOME (container)",
      @"entry" : [NSString
          stringWithFormat:
              @"%@ gnome-shell mutter dbus -c sh -c "
              @"'mkdir -p /run/user/0; exec dbus-run-session -- gnome-shell "
              @"--wayland'",
              nix],
      @"mem" : @"4096",
    };
  }
  if ([recipe isEqualToString:@"hyprland"]) {
    return @{
      @"name" : @"Hyprland (container)",
      @"entry" : [NSString
          stringWithFormat:
              @"%@ hyprland -c sh -c "
              @"'export WLR_BACKENDS=wayland WLR_RENDERER=pixman "
              @"WLR_LIBINPUT_NO_DEVICES=1; exec Hyprland'",
              nix],
      @"mem" : @"4096",
    };
  }
  // Optional: container weston when user wants container path explicitly.
  if ([recipe isEqualToString:@"weston-container"]) {
    return @{
      @"name" : @"Weston (container)",
      @"entry" : [NSString
          stringWithFormat:@"%@ weston -c weston --backend=wayland", nix],
      @"mem" : @"2048",
    };
  }
  return nil;
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
      NSMutableDictionary *cs =
          [existing.containerSettings mutableCopy] ?: [NSMutableDictionary dictionary];
      cs[@"entryCommand"] = container[@"entry"];
      cs[@"containerRef"] = cs[@"containerRef"] ?: @"nixos/nix";
      cs[@"desktopSession"] = @YES;
      cs[@"memory"] = container[@"mem"] ?: @"2048";
      existing.containerSettings = cs;
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
    profile.containerSettings = @{
      @"containerRef" : @"nixos/nix",
      @"entryCommand" : container[@"entry"],
      @"desktopSession" : @YES,
      @"memory" : container[@"mem"] ?: @"2048",
      @"remove" : @YES,
    };
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
