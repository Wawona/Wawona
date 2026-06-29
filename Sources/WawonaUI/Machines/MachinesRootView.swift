import SwiftUI
import WawonaModel
#if os(macOS)
import AppKit
#endif

struct MachinesRootView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    @State var search = ""
    @State var showingEditor = false
    @State var editingProfile: MachineProfile?

    init(
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore,
        sessions: SessionOrchestrator
    ) {
        self.preferences = preferences
        self.profileStore = profileStore
        self.sessions = sessions
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                MachinesGridView(
                    profiles: filteredProfiles,
                    sessions: sessions,
                    onEdit: { editingProfile = $0 },
                    onConnect: connect,
                    onDelete: delete
                )
                .padding()
            }
            .navigationTitle("Machines")
            .searchable(text: $search, placement: .toolbar, prompt: "Search machines")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .navigation) {
                    Button {
                        openPlatformSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                #else
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Add Machine", systemImage: "plus")
                    }
                    Button {
                        openPlatformSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingEditor) {
                MachineEditorView { profile in
                    profileStore.upsert(profile)
                }
            }
            .sheet(item: $editingProfile) { profile in
                MachineEditorView(profile: profile) { updated in
                    profileStore.upsert(updated)
                }
            }
        }
    }

    private var filteredProfiles: [MachineProfile] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return profileStore.profiles }
        return profileStore.profiles.filter {
            $0.name.lowercased().contains(q) || $0.sshHost.lowercased().contains(q)
        }
    }

    private func connect(_ profile: MachineProfile) {
        _ = sessions.connect(machineId: profile.id)
        profileStore.activeMachineId = profile.id
        profileStore.save()
        MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
    }

    private func delete(_ profile: MachineProfile) {
        profileStore.delete(id: profile.id)
    }

    private func openPlatformSettings() {
        PlatformGlobalSettings.open()
    }
}
