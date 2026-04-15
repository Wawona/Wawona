import SwiftUI
import WawonaModel

public struct WawonaWatchRootView: View {
    @StateObject private var profileStore = MachineProfileStore()
    @StateObject private var sessions = SessionOrchestrator()

    public init() {}

    public var body: some View {
        NavigationStack {
            MachineStatusView(profileStore: profileStore, sessions: sessions)
        }
    }
}
