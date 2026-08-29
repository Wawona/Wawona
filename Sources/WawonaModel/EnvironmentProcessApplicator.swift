import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Apply resolved environment rows to the current process (`setenv` / `unsetenv`).
public enum EnvironmentProcessApplicator {
    /// Apply rows. Secrets are skipped unless `includeSecrets` is true.
    /// When `stripBannedLocalShellKeys` is true, `DYLD_*` / `LD_*` are never set.
    public static func applyToProcess(
        _ rows: [ResolvedEnvironmentEntry],
        includeSecrets: Bool = false,
        stripBannedLocalShellKeys: Bool = false
    ) {
        for row in rows {
            if row.isSecret && !includeSecrets { continue }
            if stripBannedLocalShellKeys && EnvironmentResolver.isBannedLocalShellKey(row.name) {
                unsetenv(row.name)
                continue
            }
            if row.isUnset {
                unsetenv(row.name)
                continue
            }
            if let value = row.value {
                setenv(row.name, value, 1)
            }
        }
    }

    /// Apply only override maps (machine > global) onto the current process.
    /// Use after platform setenv so user overrides win without rebuilding catalog defaults.
    public static func applyOverridesToProcess(
        global: EnvironmentOverrideMap,
        machine: EnvironmentOverrideMap,
        stripBannedLocalShellKeys: Bool = false
    ) {
        var merged = global
        for (k, v) in machine {
            merged[k] = v
        }
        for (name, override) in merged {
            if stripBannedLocalShellKeys && EnvironmentResolver.isBannedLocalShellKey(name) {
                unsetenv(name)
                continue
            }
            switch override.action {
            case .unset:
                unsetenv(name)
            case .set:
                setenv(name, override.value ?? "", 1)
            }
        }
    }
}
