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

    var body: some View {
        Group {
            if preferences.hasCompletedWelcome || !profileStore.profiles.isEmpty {
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
            } else {
                WelcomeView(preferences: preferences)
            }
        }
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
