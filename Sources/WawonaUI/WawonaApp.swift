import Foundation
import SwiftUI
import WawonaModel

public struct WawonaRootView: View {
    @StateObject var preferences: WawonaPreferences
    @StateObject var profileStore: MachineProfileStore
    @StateObject var sessions: SessionOrchestrator
    var onConnect: (() -> Void)?

    public init(onConnect: (() -> Void)? = nil) {
        self.onConnect = onConnect
        _preferences = StateObject(wrappedValue: WawonaPreferences.shared)
        _profileStore = StateObject(wrappedValue: MachineProfileStore())
        _sessions = StateObject(wrappedValue: SessionOrchestrator())
    }

    public var body: some View {
        Group {
            if preferences.hasCompletedWelcome || !profileStore.profiles.isEmpty {
                #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
                WawonaMainWindowView(
                    model: WWNSettingsValueModel.shared,
                    router: WWNMainWindowRouter.shared,
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
    public func onLaunch() {}
    public func onResume() {}
    public func onPause() {}
    public func onStop() {}
    public func onDestroy() {}
    public func onLowMemory() {}
}
