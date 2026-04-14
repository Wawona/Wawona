import SwiftUI
import WawonaModel

struct MachineStatusView: View {
    let profileStore: MachineProfileStore
    let sessions: SessionOrchestrator

    @State var showingAdd = false
    @State var editingProfile: MachineProfile?
    @State var showingSettings = false

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
                            QuickConnectView(profile: profile, sessions: sessions)
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
            NSLog("[Wawona·Nav] MachineStatusView appeared — %d machine(s)", profileStore.profiles.count)
        }
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gear")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
            #else
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gear")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
            #endif
        }
        .sheet(isPresented: $showingAdd) {
            MachineEditorView(profileStore: profileStore)
        }
        .sheet(item: $editingProfile) { profile in
            MachineEditorView(profileStore: profileStore, profile: profile)
        }
        .sheet(isPresented: $showingSettings) {
            WawonaSettingsView()
        }
    }
}

// MARK: - Row label

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
        return profile.type.watchDisplayName
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

// MARK: - MachineType watch helpers

extension MachineType {
    var watchDisplayName: String {
        switch self {
        case .native:          return "Native"
        case .sshWaypipe:      return "SSH + Waypipe"
        case .sshTerminal:     return "SSH Terminal"
        case .virtualMachine:  return "Virtual Machine"
        case .container:       return "Container"
        }
    }

    var watchSystemImage: String {
        switch self {
        case .native:          return "desktopcomputer"
        case .sshWaypipe:      return "network"
        case .sshTerminal:     return "terminal"
        case .virtualMachine:  return "cube"
        case .container:       return "shippingbox"
        }
    }
}
