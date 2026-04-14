import Foundation
import SwiftUI
import WawonaModel

// SKIP @bridge
public struct WawonaRootView: View {
    @StateObject private var preferences: WawonaPreferences
    @StateObject private var profileStore: MachineProfileStore
    @StateObject private var sessions: SessionOrchestrator

    public init() {
        _preferences = StateObject(wrappedValue: WawonaPreferences.shared)
        _profileStore = StateObject(wrappedValue: MachineProfileStore())
        _sessions = StateObject(wrappedValue: SessionOrchestrator())
    }

    public var body: some View {
        Group {
            if preferences.hasCompletedWelcome || !profileStore.profiles.isEmpty {
                #if SKIP && os(Android)
                rootWithAndroidCompositorOverlay
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

    #if SKIP && os(Android)
    @State private var androidCompositorSession: MachineSession?

    private var rootWithAndroidCompositorOverlay: some View {
        ZStack(alignment: .topLeading) {
            ContentView(
                preferences: preferences,
                profileStore: profileStore,
                sessions: sessions,
                onPresentNativeCompositor: { session in
                    androidCompositorSession = session
                }
            )
            if let overlay = androidCompositorSession {
                AndroidMachineCompositorChrome(
                    session: overlay,
                    sessions: sessions,
                    onDismiss: { androidCompositorSession = nil }
                )
            }
        }
    }
    #endif
}

// SKIP @bridge
public final class WawonaAppDelegate: Sendable {
    // SKIP @bridge
    public static let shared = WawonaAppDelegate()

    public init() {}

    // SKIP @bridge
    public func onInit() {}
    // SKIP @bridge
    public func onLaunch() {}
    // SKIP @bridge
    public func onResume() {}
    // SKIP @bridge
    public func onPause() {}
    // SKIP @bridge
    public func onStop() {}
    // SKIP @bridge
    public func onDestroy() {}
    // SKIP @bridge
    public func onLowMemory() {}
}
