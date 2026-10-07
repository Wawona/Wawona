import Foundation

private let envStorageKey = "wawona.pref.environment.v1"

@objc(WWNEnvironmentOverrides)
public final class WWNEnvironmentOverrides: NSObject {
    private override init() {}

    @objc(apply:)
    public static func apply(_ machineEnvironment: NSDictionary?) {
        #if os(iOS) || targetEnvironment(simulator)
        let stripBanned = true
        #else
        let stripBanned = false
        #endif
        let merged = mergedOverrides(machineEnvironment: machineEnvironment)
        for case let name as String in merged.keys {
            applyOne(name: name, entry: merged[name], stripBanned: stripBanned)
        }
    }

    @objc(applyForActiveMachine)
    public static func applyForActiveMachine() {
        var machineEnv: NSDictionary?
        if let activeId = WWNMachineProfileStore.activeMachineId(), !activeId.isEmpty,
           let profile = WWNMachineProfileStore.profile(byId: activeId),
           let runtime = profile.runtimeOverrides as? [String: Any],
           let env = runtime["environment"] as? NSDictionary {
            machineEnv = env
        }
        apply(machineEnv)
    }

    @objc(mergeIntoTaskEnvironment:machineEnvironment:)
    public static func merge(
        intoTaskEnvironment env: NSMutableDictionary,
        machineEnvironment: NSDictionary?
    ) {
        let merged = mergedOverrides(machineEnvironment: machineEnvironment)
        for case let name as String in merged.keys {
            guard let entry = merged[name] as? [String: Any],
                  let action = entry["action"] as? String else { continue }
            if action == "unset" {
                env.removeObject(forKey: name)
            } else if action == "set" {
                env[name] = entry["value"] as? String ?? ""
            }
        }
    }

    private static func mergedOverrides(machineEnvironment: NSDictionary?) -> [String: Any] {
        var merged = loadGlobalOverrides()
        if let machineEnvironment {
            for case let key as String in machineEnvironment.allKeys {
                merged[key] = machineEnvironment[key]
            }
        }
        return merged
    }

    private static func loadGlobalOverrides() -> [String: Any] {
        guard let data = UserDefaults.standard.data(forKey: envStorageKey),
              !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func envKeyBanned(_ name: String) -> Bool {
        name.hasPrefix("DYLD_") || name.hasPrefix("LD_")
    }

    private static func applyOne(name: String, entry: Any?, stripBanned: Bool) {
        guard !name.isEmpty else { return }
        if stripBanned, envKeyBanned(name) {
            unsetenv(name)
            return
        }
        guard let entry = entry as? [String: Any],
              let action = entry["action"] as? String else { return }
        if action == "unset" {
            unsetenv(name)
        } else if action == "set" {
            let value = entry["value"] as? String ?? ""
            setenv(name, value, 1)
        }
    }
}

@_cdecl("WWNEnvironmentOverridesApply")
public func WWNEnvironmentOverridesApply(_ machineEnvironment: NSDictionary?) {
    WWNEnvironmentOverrides.apply(machineEnvironment)
}

@_cdecl("WWNEnvironmentOverridesApplyForActiveMachine")
public func WWNEnvironmentOverridesApplyForActiveMachine() {
    WWNEnvironmentOverrides.applyForActiveMachine()
}

@_cdecl("WWNEnvironmentOverridesMergeIntoTaskEnvironment")
public func WWNEnvironmentOverridesMergeIntoTaskEnvironment(
    _ env: NSMutableDictionary,
    _ machineEnvironment: NSDictionary?
) {
    WWNEnvironmentOverrides.merge(intoTaskEnvironment: env, machineEnvironment: machineEnvironment)
}
