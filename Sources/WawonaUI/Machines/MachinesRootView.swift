import SwiftUI
import WawonaModel

struct MachinesRootView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    var onPresentNativeCompositor: ((MachineSession) -> Void)?
    @State var search = ""
    @State var selectedMachineId: String?
    @State var showingEditor = false

    init(
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore,
        sessions: SessionOrchestrator,
        onPresentNativeCompositor: ((MachineSession) -> Void)? = nil
    ) {
        self.preferences = preferences
        self.profileStore = profileStore
        self.sessions = sessions
        self.onPresentNativeCompositor = onPresentNativeCompositor
    }

    var body: some View {
        machinesNavigation
    }

    private var machinesNavigation: some View {
        #if SKIP
        // Skip maps `NavigationSplitView` to stubs; `AdaptiveNavigationView` only renders `detail`,
        // so the sidebar list never appeared. Use a single column with a bar title like iOS phone.
        NavigationStack {
            ScrollView {
                MachinesGridView(
                    profiles: filteredProfiles,
                    sessions: sessions,
                    onAdd: { showingEditor = true },
                    onConnect: connect,
                    onDelete: delete
                )
                .padding()
            }
            .navigationTitle("Machines")
            .searchable(text: $search)
            .sheet(isPresented: $showingEditor) {
                MachineEditorView { profile in
                    profileStore.upsert(profile)
                }
            }
        }
        #else
        AdaptiveNavigationView {
            List(selection: $selectedMachineId) {
                ForEach(filteredProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .navigationTitle("Machines")
        } detail: {
            ScrollView {
                MachinesGridView(
                    profiles: filteredProfiles,
                    sessions: sessions,
                    onAdd: { showingEditor = true },
                    onConnect: connect,
                    onDelete: delete
                )
                .padding()
            }
            .searchable(text: $search)
            .sheet(isPresented: $showingEditor) {
                MachineEditorView { profile in
                    profileStore.upsert(profile)
                }
            }
        }
        #endif
    }

    private var filteredProfiles: [MachineProfile] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return profileStore.profiles }
        return profileStore.profiles.filter {
            $0.name.lowercased().contains(q) || $0.sshHost.lowercased().contains(q)
        }
    }

    private func connect(_ profile: MachineProfile) {
        let session = sessions.connect(machineId: profile.id)
        profileStore.activeMachineId = profile.id
        profileStore.save()
        #if SKIP && os(Android)
        if profile.type == .native {
            NativeCompositorPrefs.apply(for: profile)
            onPresentNativeCompositor?(session)
        }
        #endif
    }

    private func delete(_ profile: MachineProfile) {
        profileStore.delete(id: profile.id)
    }
}
