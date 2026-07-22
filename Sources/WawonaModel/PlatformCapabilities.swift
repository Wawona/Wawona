import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Single source of truth for per-platform product gates.
/// Aligns with `.cursor/rules/wawona-platform-targets.mdc`.
public enum PlatformCapabilities: Sendable {
    public static var allowsVirtualMachine: Bool {
        #if os(tvOS) || os(watchOS)
        return false
        #else
        return true
        #endif
    }

    public static var allowsContainer: Bool {
        #if os(tvOS) || os(watchOS)
        return false
        #else
        return true
        #endif
    }

    /// ANGLE / Vulkan / iland GL stack may be bundled and linked.
    public static var allowsGpuStack: Bool {
        #if os(tvOS) || os(watchOS)
        return false
        #else
        return true
        #endif
    }

    public static var allowsDesktopReplacement: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    public static var allowsAnowaW: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// One host window/scene per Wayland client (macOS NSWindow parity).
    /// Required on iPadOS + visionOS; optional elsewhere.
    public static var allowsMultiWindowScenes: Bool {
        #if os(visionOS)
        return true
        #elseif os(iOS)
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
        #elseif os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// In-window tab strip: one tab per Wayland client toplevel (never Shell).
    /// Used on phone iOS / tvOS / watchOS where multi-window scenes are off.
    public static var allowsClientTabs: Bool {
        #if os(tvOS) || os(watchOS)
        return true
        #elseif os(iOS)
        return !allowsMultiWindowScenes
        #else
        return false
        #endif
    }

    /// How xdg maximize / fullscreen / minimize map onto the host.
    /// - `nativeAppKit`: macOS NSWindow zoom / toggleFullScreen / miniaturize
    /// - `fillPrimary`: host owns geometry; max/fs = fill compositor surface +
    ///   sync xdg state; minimize = hide host chrome → Machines (session lives);
    ///   Focus reverses minimize. Used on iOS phone, tvOS, Android.
    /// - `multiSceneFillPrimary`: same fill-primary semantics, one host
    ///   window/scene per Wayland client (iPadOS / visionOS).
    /// - `stub`: watchOS mini server ignores WM requests.
    public enum HostWindowManagerPolicy: String, Sendable {
        case nativeAppKit
        case fillPrimary
        case multiSceneFillPrimary
        case stub
    }

    public static var hostWindowManagerPolicy: HostWindowManagerPolicy {
        #if os(macOS)
        return .nativeAppKit
        #elseif os(watchOS)
        return .stub
        #elseif os(visionOS)
        return .multiSceneFillPrimary
        #elseif os(iOS)
        return allowsMultiWindowScenes ? .multiSceneFillPrimary : .fillPrimary
        #elseif os(tvOS)
        return .fillPrimary
        #else
        return .fillPrimary
        #endif
    }

    /// Host cannot resize floating Wayland frames (UIKit / Android fill-primary).
    public static var hostOwnsWindowGeometry: Bool {
        switch hostWindowManagerPolicy {
        case .nativeAppKit: return false
        case .fillPrimary, .multiSceneFillPrimary, .stub: return true
        }
    }

    public static var availableMachineTypes: [MachineType] {
        MachineType.allCases.filter { type in
            switch type {
            case .virtualMachine: return allowsVirtualMachine
            case .container: return allowsContainer
            case .native, .sshWaypipe, .sshTerminal: return true
            }
        }
    }

    public static func allowsMachineType(_ type: MachineType) -> Bool {
        availableMachineTypes.contains(type)
    }
}
