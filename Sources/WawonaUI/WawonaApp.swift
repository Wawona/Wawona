import Foundation
import SwiftUI
import WawonaModel
#if canImport(Darwin)
import Darwin
#endif
#if os(macOS)
import AppKit
#endif

@MainActor
private final class WawonaRootState {
    let preferences = WawonaPreferences.shared
    let profileStore = MachineProfileStore()
    let sessions = SessionOrchestrator()
}

@MainActor
public struct WawonaRootView: View {
    @State private var state: WawonaRootState
    private let onConnect: (() -> Void)?

    public init(onConnect: (() -> Void)? = nil) {
        self.onConnect = onConnect
        _state = State(initialValue: WawonaRootState())
    }

    public var body: some View {
        WawonaRootContent(preferences: state.preferences, profileStore: state.profileStore,
                          sessions: state.sessions, onConnect: onConnect)
    }
}

private struct WawonaRootContent: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    let onConnect: (() -> Void)?
    /// Native alert over Machines. Never a full-screen Welcome page.
    @State private var showWelcomeAlert = false
    /// macOS: Login Item + Launch Agents offer after welcome Continue.
    @State private var showAgentsOffer = false

    private var needsWelcome: Bool {
        !preferences.hasCompletedWelcome && profileStore.profiles.isEmpty
    }

    private var shouldOfferLaunchAgents: Bool {
        #if os(macOS)
        preferences.hasCompletedWelcome
            && !UserDefaults.standard.bool(forKey: "HasOfferedLaunchAgents")
        #else
        false
        #endif
    }

    @ViewBuilder
    private var mainShell: some View {
        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
        WawonaMainWindowView(
            model: WWNSettingsValueModel.shared,
            router: WWNMainWindowRouter.shared,
            preferences: preferences,
            profileStore: profileStore,
            sessions: sessions,
            onConnect: onConnect
        )
        #else
        ContentView(
            preferences: preferences,
            profileStore: profileStore,
            sessions: sessions
        )
        #endif
    }

    var body: some View {
        mainShell
            .onAppear {
                if needsWelcome {
                    showWelcomeAlert = true
                } else if shouldOfferLaunchAgents {
                    // Welcome already done earlier; still offer agents once.
                    showAgentsOffer = true
                }
            }
            .backport.onChange(of: needsWelcome) { _, needed in
                if needed {
                    showWelcomeAlert = true
                } else if preferences.hasCompletedWelcome {
                    showWelcomeAlert = false
                }
            }
            .wawonaWelcomeAlert(
                preferences: preferences,
                isPresented: $showWelcomeAlert,
                onContinue: {
                    #if os(macOS)
                    if shouldOfferLaunchAgents {
                        DispatchQueue.main.async {
                            showAgentsOffer = true
                        }
                    }
                    #endif
                }
            )
            .wawonaWelcomeAgentsOffer(
                preferences: preferences,
                isPresented: $showAgentsOffer
            )
    }
}

public final class WawonaAppDelegate: Sendable {
    public static let shared = WawonaAppDelegate()

    public init() {}

    public func onInit() {}

    public func onLaunch() {
        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
        // Host compositor must be up before Machines Start can attach clients.
        // SwiftUI WindowGroup already owns the Machines UI; do not open a second window.
        #if os(macOS)
        // Client tabs live under Tab Overview only. Never let AppKit merge
        // Machines / session windows into a global "Wawona" window tab bar.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
        #if os(iOS) || os(tvOS) || os(visionOS)
        // iOS sandbox cannot bind /tmp/wawona-<uid>. Use the app runtime dir.
        let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
        try? FileManager.default.createDirectory(
            atPath: runtime,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        setenv("XDG_RUNTIME_DIR", runtime, 1)
        #endif
        let bridge = WWNCompositorBridge.sharedBridge
        // #223: compositor-host LaunchAgent may already own wayland-0.
        // start() adopts that socket without unlinking it.
        if bridge.start(withSocketName: "wayland-0") {
            setenv("WAYLAND_DISPLAY", bridge.socketName(), 1)
        }
        Task { @MainActor in
            WWNCloudSync.shared.start(homePath: { WWNRootfsManager.activeHomePath() })
        }
        #endif
    }

    public func onResume() {
        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
        WWNCompositorBridge.sharedBridge.pollAndHandleWindowEvents()
        #endif
    }

    public func onPause() {}
    public func onStop() {}

    public func onDestroy() {
        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
        WWNCompositorBridge.sharedBridge.stop()
        #endif
    }

    public func onLowMemory() {}
}
