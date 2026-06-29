#if os(watchOS)
import SwiftUI
import WawonaModel

struct MachineStatusView: View {
    let profileStore: MachineProfileStore
    let sessions: SessionOrchestrator

    @State var showingAdd = false
    @State var editingProfile: MachineProfile?

    var body: some View {
        Group {
            if profileStore.profiles.isEmpty {
                ContentUnavailableView(
                    "No Machines",
                    systemImage: "server.rack",
                    description: Text("Tap + to add a machine.")
                )
            } else {
                List {
                    ForEach(profileStore.profiles) { profile in
                        NavigationLink {
                            QuickConnectView(profile: profile, profileStore: profileStore, sessions: sessions)
                        } label: {
                            MachineRowLabel(profile: profile, sessions: sessions)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                editingProfile = profile
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                profileStore.delete(id: profile.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Machines")
        .onAppear {
            WatchKitGlobalSettings.registerHost()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    WatchKitGlobalSettings.open()
                } label: {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("Wawona Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            MachineEditorView(profileStore: profileStore)
        }
        .sheet(item: $editingProfile) { profile in
            WatchMachineOverridesSheet(machineID: profile.id, profileStore: profileStore)
        }
    }
}

struct MachineRowLabel: View {
    let profile: MachineProfile
    let sessions: SessionOrchestrator

    private var status: MachineStatus? {
        sessions.sessions.first(where: { $0.machineId == profile.id })?.status
    }

    private var clientLabel: String {
        if profile.type == .native, let launcher = profile.launchers.first {
            return launcher.displayName
        }
        return profile.type.userFacingName
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status == .connected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(clientLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
