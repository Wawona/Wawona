#if os(watchOS)
import SwiftUI
import WawonaModel

struct MachineStatusView: View {
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    @Binding var runningCover: WatchMachineCover?

    @State var showingAdd = false
    @State var editingProfile: MachineProfile?
    @State var showingGlobalSettings = false

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
                            QuickConnectView(
                                profile: profile,
                                profileStore: profileStore,
                                sessions: sessions,
                                onStarted: { session in
                                    runningCover = WatchMachineCover(
                                        profile: profile,
                                        session: session
                                    )
                                }
                            )
                        } label: {
                            MachineRowLabel(profile: profile, sessions: sessions)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                editingProfile = profile
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                .lineLimit(1)
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                profileStore.delete(id: profile.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                                .lineLimit(1)
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
        .onReceive(NotificationCenter.default.publisher(
            for: WatchKitGlobalSettings.fallbackPresentationNeeded
        )) { _ in
            showingGlobalSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .wawonaPreferencesDidSave)) { _ in
            WawonaPreferences.shared.load()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // Always show settings in-process. WatchKit storyboard present
                    // from SwiftUI `@main` is unreliable (host may claim success
                    // while nothing appears). Sheet uses the same `wawona.pref.*`
                    // keys as `WWNWatchSettingsBridge` / WatchKit controllers.
                    WatchKitGlobalSettings.registerHost()
                    showingGlobalSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .accessibilityIdentifier("wwn.watch.settings")
                .accessibilityLabel("Wawona Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("wwn.watch.add")
                .accessibilityLabel("Add Machine")
            }
        }
        .sheet(isPresented: $showingAdd) {
            MachineEditorView(profileStore: profileStore)
        }
        .sheet(item: $editingProfile) { profile in
            WatchMachineOverridesSheet(machineID: profile.id, profileStore: profileStore)
        }
        .sheet(isPresented: $showingGlobalSettings) {
            WatchGlobalSettingsView()
        }
        .fullScreenCover(item: $runningCover) { cover in
            NavigationStack {
                CompositorActiveView(
                    profile: cover.profile,
                    session: cover.session,
                    sessions: sessions
                )
            }
        }
    }
}

/// Stable cover item. Start must not live on QuickConnect's NavigationLink
/// destination: saving `activeMachineId` republishes the list and tears that
/// view down before `navigationDestination` can push.
struct WatchMachineCover: Identifiable {
    var id: UUID { session.id }
    let profile: MachineProfile
    let session: MachineSession
}

struct MachineRowLabel: View {
    let profile: MachineProfile
    let sessions: SessionOrchestrator

    private var status: MachineStatus? {
        sessions.sessions.first(where: { $0.machineId == profile.id })?.status
    }

    private var clientLabel: String {
        if profile.type == .native {
            let id = profile.runtimeOverrides.bundledAppID?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !id.isEmpty {
                return ClientLauncher.displayName(for: id)
            }
            if let launcher = profile.launchers.first {
                return launcher.displayName
            }
        }
        return profile.type.userFacingName
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status == .connected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name.isEmpty ? "Unnamed Machine" : profile.name)
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
