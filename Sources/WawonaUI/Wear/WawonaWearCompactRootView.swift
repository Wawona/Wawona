import SwiftUI
import WawonaModel

public struct WawonaWearCompactRootView: View {
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator

    @MainActor
    public init(
        profileStore: MachineProfileStore,
        sessions: SessionOrchestrator
    ) {
        _profileStore = ObservedObject(wrappedValue: profileStore)
        _sessions = ObservedObject(wrappedValue: sessions)
    }

    @MainActor
    public init() {
        _profileStore = ObservedObject(wrappedValue: MachineProfileStore())
        _sessions = ObservedObject(wrappedValue: SessionOrchestrator())
    }

    public var body: some View {
        Backport<Any>.NavigationContainer {
            if profileStore.profiles.isEmpty {
                Backport<Any>.ContentUnavailable(
                    "No Machines",
                    systemImage: "server.rack",
                    description: "Add machine on phone to continue."
                )
            } else {
                List(profileStore.profiles) { profile in
                    NavigationLink(profile.name) {
                        WawonaWearMachineQuickView(profile: profile, sessions: sessions)
                    }
                }
            }
        }
    }
}

struct WawonaWearMachineQuickView: View {
    let profile: MachineProfile
    @ObservedObject var sessions: SessionOrchestrator

    private var activeSession: MachineSession? {
        sessions.sessions.first(where: { $0.machineId == profile.id })
    }

    private var isConnected: Bool {
        activeSession?.status == .connected
    }

    private var isConnecting: Bool {
        activeSession?.status == .connecting
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "display.2")
                .font(.title3)
                .backport.foregroundStyle(isConnected ? .green : .secondary)
            Text(profile.name)
                .font(.headline)
                .lineLimit(1)

            Text(statusLabel)
                .font(.caption)
                .backport.foregroundStyle(.secondary)

            Button {
                if let session = activeSession {
                    sessions.disconnect(sessionId: session.id)
                } else {
                    _ = sessions.connect(machineId: profile.id)
                }
            } label: {
                Text(buttonLabel)
                    .frame(maxWidth: .infinity)
            }
            .backport.glassProminentButtonStyle()
            .disabled(isConnecting)
        }
        .padding()
        .backport.navigationTitle("Machine")
    }

    private var buttonLabel: String {
        if isConnecting { return "Connecting..." }
        return isConnected ? "Disconnect" : "Quick Connect"
    }

    private var statusLabel: String {
        switch activeSession?.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .degraded: return "Degraded"
        case .error: return "Error"
        default: return "Ready"
        }
    }
}
