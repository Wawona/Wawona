#if os(macOS)
import AppKit
import Foundation

@objc(WWNCLIMachineRecipes)
public final class WWNCLIMachineRecipes: NSObject {

    @objc public static func allRecipeIds() -> [String] {
        [
            "flower", "weston-flower", "weston-terminal", "foot", "weston", "weston-container",
            "niri", "sway", "labwc", "plasma", "kwin", "gnome", "hyprland",
        ]
    }

    @objc public static func printRecipeHelp() {
        let image = CLIMachineRecipeSpecs.desktopImageRef
        print(
            """
            Usage: Wawona run <recipe>

            Creates a Machines card if none exists for this recipe, then starts it.
            CLI and GUI share the same profiles (wawona.machineProfiles.v1).

            Recipes:
              flower            weston-flower in a container (200x200)
              weston-terminal   Weston Terminal (native bundled)
              foot              foot terminal (native bundled)
              weston            nested Weston compositor (native)
              weston-container  Weston in a container (waypipe)
              niri              nested niri (native)
              sway              nested sway + wallpaper + Alt+Enter terminal (container)
              labwc             labwc (container)
              plasma / kwin     KWin nested (container; needs guest dbus)
              gnome             GNOME Shell (container; needs guest dbus)
              hyprland          Hyprland (container)

            Container recipes use image \(image) (no nix shell at Start).
            Also: Wawona machines list | show <id|name>
            """
        )
    }

    @objc(profileMatchingIdOrName:)
    public static func profileMatching(idOrName query: String) -> WWNMachineProfile? {
        guard !query.isEmpty else { return nil }
        let profiles = WWNMachineProfileStore.loadProfiles()
        if let direct = profiles.first(where: { $0.machineId == query }) { return direct }
        let lower = query.lowercased()
        if let byName = profiles.first(where: { $0.name.lowercased() == lower }) { return byName }
        for profile in profiles {
            guard let key = profile.runtimeOverrides[kWWNCLIRecipeKey] as? String else { continue }
            if key.lowercased() == lower { return profile }
            let shortId = key.split(separator: ":").last.map { String($0).lowercased() } ?? ""
            if shortId == lower { return profile }
        }
        let asNative = "cli-native-\(lower)"
        let asContainer = "cli-container-\(lower)"
        return profiles.first { $0.machineId == asNative || $0.machineId == asContainer }
    }

    @objc(profileForRecipeKey:)
    public static func profile(forRecipeKey recipeKey: String) -> WWNMachineProfile? {
        for profile in WWNMachineProfileStore.loadProfiles() {
            if let key = profile.runtimeOverrides[kWWNCLIRecipeKey] as? String, key == recipeKey {
                return profile
            }
            if profile.machineId == CLIMachineRecipeSpecs.stableMachineId(recipeKey: recipeKey) {
                return profile
            }
        }
        return nil
    }

    @objc public static func notifyProfilesChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            .WWNMachineProfilesChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        NotificationCenter.default.post(name: .WWNMachineProfilesChanged, object: nil)
    }

    @objc(ensureProfileForRecipe:error:)
    public static func ensureProfile(forRecipe rawRecipe: String, error: NSErrorPointer) -> WWNMachineProfile? {
        let recipe = rawRecipe.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !recipe.isEmpty else {
            error?.pointee = NSError(
                domain: "WawonaCLI",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing recipe. Try: Wawona run --help"]
            )
            return nil
        }
        let native = CLIMachineRecipeSpecs.nativeRecipeSpec(recipe)
        let container = CLIMachineRecipeSpecs.containerRecipeSpec(recipe)
        guard native != nil || container != nil else {
            error?.pointee = NSError(
                domain: "WawonaCLI",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown recipe '\(rawRecipe)'. Try: Wawona run --help"]
            )
            return nil
        }
        let useContainer = container != nil && native == nil
        let recipeKey = useContainer ? "cli:container:\(recipe)" : "cli:native:\(recipe)"

        if let existing = profile(forRecipeKey: recipeKey) {
            if useContainer, let container {
                existing.containerSettings = CLIMachineRecipeSpecs.containerSettings(for: container)
                var ro = existing.runtimeOverrides
                ro[kWWNCLIRecipeKey] = recipeKey
                ro[kWWNMachineOrigin] = kWWNMachineOriginCLI
                ro["useBundledApp"] = false
                ro["bundledAppID"] = ""
                existing.runtimeOverrides = ro
            } else if let native {
                var so = existing.settingsOverrides
                so["NativeClientId"] = native["id"]
                existing.settingsOverrides = so
                var ro = existing.runtimeOverrides
                ro["bundledAppID"] = native["id"]
                ro["useBundledApp"] = true
                ro[kWWNCLIRecipeKey] = recipeKey
                ro[kWWNMachineOrigin] = kWWNMachineOriginCLI
                existing.runtimeOverrides = ro
            }
            WWNMachineProfileStore.upsertProfile(existing)
            notifyProfilesChanged()
            return existing
        }

        let profile = WWNMachineProfile.defaultProfile()
        profile.machineId = CLIMachineRecipeSpecs.stableMachineId(recipeKey: recipeKey)
        profile.sshEnabled = false

        if useContainer, let container {
            profile.name = container["name"] ?? recipe
            profile.type = kWWNMachineTypeContainer
            profile.containerSettings = CLIMachineRecipeSpecs.containerSettings(for: container)
            profile.settingsOverrides = [:]
            profile.runtimeOverrides = [
                kWWNCLIRecipeKey: recipeKey,
                kWWNMachineOrigin: kWWNMachineOriginCLI,
                "useBundledApp": false,
                "bundledAppID": "",
            ]
        } else if let native {
            profile.name = native["name"] ?? recipe
            profile.type = kWWNMachineTypeNative
            profile.settingsOverrides = ["NativeClientId": native["id"] ?? "", "EnableLauncher": true]
            profile.runtimeOverrides = [
                kWWNCLIRecipeKey: recipeKey,
                kWWNMachineOrigin: kWWNMachineOriginCLI,
                "bundledAppID": native["id"] ?? "",
                "useBundledApp": true,
            ]
            profile.containerSettings = [:]
        }

        WWNMachineProfileStore.upsertProfile(profile)
        notifyProfilesChanged()
        return profile
    }
}
#endif
