import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Why a capability is unavailable on this target.
///
/// The distinction is load-bearing, and a plain `Bool` erases it. "tvOS and
/// watchOS have no GPU stack" was one flag covering three different situations,
/// so unfinished work read like policy and an SDK limitation read like a
/// decision. Each case has a different correct response:
///
/// - `planned`. Our work is unfinished. Finish it; never harden into removal.
/// - `blocked`. We want it, the platform offers no public API. Re-check on
///                 SDK updates. Never route around it with private API.
/// - `forbidden`. Product or store rule. Never "fix" it by turning it on.
public enum CapabilityGate: Sendable, Equatable {
    case available
    /// Intended, not shipped yet. Opt in with `flag` once the slices are bundled.
    case planned(flag: String)
    /// Wanted, but the platform SDK exposes nothing to build on.
    case blocked(reason: String)
    case forbidden(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// True when the capability is off only because our work is unfinished.
    public var isPlanned: Bool {
        if case .planned = self { return true }
        return false
    }

    /// True when no amount of Wawona-side work can enable this today.
    public var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}

/// Single source of truth for per-platform product gates.
/// Aligns with `.cursor/rules/wawona-platform-targets.mdc`.
public enum PlatformCapabilities: Sendable {
    private static func isFlagEnabled(_ name: String) -> Bool {
        guard let value = ProcessInfo.processInfo.environment[name] else { return false }
        return value == "1" || value.lowercased() == "true"
    }

    /// Policy: VM machine kinds. Planned on macOS / iOS / iPadOS; forbidden on
    /// tvOS / watchOS / visionOS. Android is gated in Compose the same way.
    public static var virtualMachineGate: CapabilityGate {
        #if os(tvOS) || os(watchOS) || os(visionOS)
        return .forbidden(reason: "VM machine kinds are not offered on tvOS/watchOS/visionOS")
        #else
        return .planned(flag: "WWN_VMS")
        #endif
    }

    public static var allowsVirtualMachine: Bool { virtualMachineGate.isAvailable }

    /// Same platform set as VMs. Planned, not shipping yet.
    ///
    /// iOS / iPadOS Mode A: OCI pull is userspace (`wwn-oci`); execution is
    /// container-in-VM via jitless UTM-SE-class interpreter (`wwn-vms`).
    /// Mode B (Sileo Mode B IPA only. Never App Store): same OCI + JIT UTM.
    /// Not Wasm Runtime packages. See docs/mode-a-b.md.
    public static var containerGate: CapabilityGate {
        #if os(tvOS) || os(watchOS) || os(visionOS)
        return .forbidden(reason: "Container machine kinds are not offered on tvOS/watchOS/visionOS")
        #else
        return .planned(flag: "WWN_CONTAINERS")
        #endif
    }

    public static var allowsContainer: Bool { containerGate.isAvailable }

    /// Apple Containerization.framework and the Apple `container` CLI.
    ///
    /// This is the macOS execution engine only (Virtualization.framework,
    /// Apple silicon, macOS 15+ / 26 recommended). Other targets that allow
    /// container *machine kinds* use container-in-VM (`wwn-vms`), never this
    /// engine. Distinct from `containerGate`.
    public static var appleContainerizationGate: CapabilityGate {
        #if os(macOS)
        return .planned(flag: "WWN_APPLE_CONTAINERIZATION")
        #else
        return .forbidden(reason: "Apple Containerization.framework and the Apple container CLI are macOS-only")
        #endif
    }

    public static var allowsAppleContainerization: Bool { appleContainerizationGate.isAvailable }

    /// ANGLE / Vulkan / iland GL stack may be bundled and linked.
    ///
    /// tvOS and watchOS are not the same case, verified against the 26.5 SDKs:
    ///
    /// - **tvOS ships `Metal.framework` *and* `OpenGLES.framework`**, and
    ///   `CAMetalLayer` is available since tvOS 9. Both a Vulkan (MoltenVK) and
    ///   a GLES path are legal public API, so this is a porting job. The final
    ///   phase of the graphics plan, not a prohibition.
    /// - **watchOS ships no `Metal.framework` at all** (device or simulator),
    ///   no `OpenGLES.framework`, and `CAMetalLayer` is `API_UNAVAILABLE(watchos)`.
    ///   ANGLE and MoltenVK both terminate in Metal, so neither has a floor.
    ///   SceneKit/SpriteKit are present but are not a shader backdoor, and
    ///   private Metal would forfeit store compliance.
    ///
    /// Until slices are actually bundled the tvOS gate stays `planned` whatever
    /// the environment says. A runtime flag cannot conjure a framework into the
    /// bundle.
    public static var gpuStackGate: CapabilityGate {
        #if os(tvOS)
        #if WWN_TVOS_GPU_BUNDLED
        return isFlagEnabled("WWN_TVOS_GPU") ? .available : .planned(flag: "WWN_TVOS_GPU")
        #else
        return .planned(flag: "WWN_TVOS_GPU")
        #endif
        #elseif os(watchOS)
        return .blocked(reason: "watchOS SDK exposes no Metal.framework and CAMetalLayer is API_UNAVAILABLE(watchos)")
        #else
        return .available
        #endif
    }

    public static var allowsGpuStack: Bool { gpuStackGate.isAvailable }

    /// Desktop + LockScreen host replacement. Coming soon on macOS (Android is
    /// gated in Compose). App Store Apple-mobile builds keep this forbidden and
    /// must never mention alternate distribution paths in UI or strings.
    public static var desktopReplacementGate: CapabilityGate {
        #if os(macOS)
        return .planned(flag: "WWN_DESKTOP_REPLACEMENT")
        #else
        return .forbidden(reason: "Desktop/LockScreen replacement is not offered in App Store Apple-mobile builds")
        #endif
    }

    public static var allowsDesktopReplacement: Bool { desktopReplacementGate.isAvailable }

    /// Wawona Swinging Bridge (formerly anowaW): host apps → Wayland over
    /// waypipe / nested compositor. Not Desktop/LockScreen.
    /// macOS + Android: Mode A+B planned. iOS/iPadOS: Mode B only (forbidden
    /// in store IPA). See docs/swinging-bridge.md.
    public static var swingingBridgeGate: CapabilityGate {
        #if os(macOS)
        return .planned(flag: "WWN_SWINGING_BRIDGE")
        #elseif os(iOS)
        // Store IPA: no Swinging Bridge. Mode B is jailbreak / Sileo only.
        return .forbidden(reason: "Wawona Swinging Bridge on iOS/iPadOS is Mode B (jailbreak) only")
        #else
        return .forbidden(reason: "Wawona Swinging Bridge is macOS and Android (Mode A); iOS Mode B only outside store")
        #endif
    }

    public static var allowsSwingingBridge: Bool { swingingBridgeGate.isAvailable }

    /// - Warning: Deprecated name for ``allowsSwingingBridge``.
    public static var allowsAnowaW: Bool { allowsSwingingBridge }

    /// - Warning: Deprecated name for ``swingingBridgeGate``.
    public static var anowaWGate: CapabilityGate { swingingBridgeGate }

    /// Client-side decorations (CSD) only render correctly on macOS Wawona,
    /// which draws host chrome around a client-decorated surface. Every other
    /// target draws server-side decorations unconditionally because a Wayland
    /// client cannot present standalone CSD in the fill-primary / desktop
    /// shell. Gates the Force SSD setting UI to macOS only and forces effective
    /// SSD elsewhere. See Force SSD per-machine (#120) and
    /// `.cursor/rules/wawona-platform-targets.mdc`.
    public static var supportsClientSideDecorations: Bool {
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
    /// Used on phone iOS + tvOS where multi-window scenes are off. watchOS is
    /// single-client (stub WM) and Android has its own Compose tab strip.
    public static var allowsClientTabs: Bool {
        #if os(tvOS)
        return true
        #elseif os(watchOS)
        // watchOS runs a single client at a time (stub host WM, no tab surface);
        // native + remote only per wawona-platform-targets. No tab consumer.
        return false
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
