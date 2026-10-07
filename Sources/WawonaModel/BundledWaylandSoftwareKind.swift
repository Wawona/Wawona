import Foundation

/// Catalog group for native Wayland software in the machine editor picker.
/// Custom commands belong under Native Shell → Terminal, not in this catalog.
public enum BundledWaylandSoftwareKind: Int, CaseIterable, Codable, Sendable, Comparable {
    /// Nested compositors (weston, niri).
    case compositor = 0
    /// Terminal Wayland clients.
    case terminal = 1
    /// GLES / Vulkan / KMS graphics demos.
    case graphics = 2
    /// Weston toytoolkit and similar demos.
    case demo = 3
    /// Everything else (e.g. weston-simple-shm).
    case other = 4

    public static func < (lhs: BundledWaylandSoftwareKind, rhs: BundledWaylandSoftwareKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Section header in the Native Shell → Wayland client picker.
    public var sectionTitle: String {
        switch self {
        case .compositor: return "Compositors"
        case .terminal: return "Terminals"
        case .graphics: return "Graphics"
        case .demo: return "Demos"
        case .other: return "Other"
        }
    }

    /// Classify a bundled client / launcher id (not `custom`).
    public static func kind(forClientId id: String) -> BundledWaylandSoftwareKind {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "weston", "niri":
            return .compositor
        case "weston-terminal", "foot", "wayland-terminal":
            return .terminal
        case "kmscube", "gbm-es2-demo", "opengl-cube", "vkcube", "weston-simple-egl":
            return .graphics
        case "weston-simple-shm", "wawona-shell", "wawona-wasm", "custom":
            return .other
        default:
            if trimmed.hasPrefix("weston-") {
                return .demo
            }
            return .other
        }
    }
}

public extension Array where Element == ClientLauncher {
    /// Wayland picker order: compositors, then client types (terminal →
    /// graphics → demo), then other. Drops shell/wasm session entries.
    func waylandPickerGrouped() -> [(kind: BundledWaylandSoftwareKind, clients: [ClientLauncher])] {
        let visible = filter {
            $0.name != "wawona-shell" && $0.name != "wawona-wasm"
        }
        return BundledWaylandSoftwareKind.allCases.compactMap { kind in
            let group = visible
                .filter { BundledWaylandSoftwareKind.kind(forClientId: $0.name) == kind }
                .sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            return group.isEmpty ? nil : (kind, group)
        }
    }
}
