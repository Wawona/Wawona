import Foundation
import SwiftUI
import WawonaModel
#if canImport(Darwin)
import Darwin
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

    private var needsWelcome: Bool {
        !preferences.hasCompletedWelcome && profileStore.profiles.isEmpty
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
                }
            }
            .backport.onChange(of: needsWelcome) { _, needed in
                if needed {
                    showWelcomeAlert = true
                } else if preferences.hasCompletedWelcome {
                    showWelcomeAlert = false
                }
            }
            .wawonaWelcomeAlert(preferences: preferences, isPresented: $showWelcomeAlert)
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
        if bridge.start(withSocketName: "wayland-0") {
            setenv("WAYLAND_DISPLAY", bridge.socketName(), 1)
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
