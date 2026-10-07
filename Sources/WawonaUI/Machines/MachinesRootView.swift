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
    @State var editorSheet: MachineEditorSheet?
    @State var showingContainerImages = false

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
        WawonaBackport<Any>.navigation {
            ScrollView {
                MachinesGridView(
                    profiles: filteredProfiles,
                    sessions: sessions,
                    onEdit: { editorSheet = .edit($0) },
                    onConnect: connect,
                    onDelete: delete
                )
                .padding()
            }
            .backport.navigationTitle("Machines")
            .wwnA11y(WawonaA11y.machinesRoot, label: "Machines")
            #if os(macOS)
            .searchable(text: $search, placement: .toolbar, prompt: "Search machines")
            #endif
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    WawonaButton {
                        editorSheet = .add
                    } label: {
                        WawonaLabel("Add Machine", systemImage: "plus")
                    }
                    .backport.glassToolbarButton()
                    .wwnA11y(WawonaA11y.machinesAdd, label: "Add Machine")
                }
                ToolbarItem(placement: .navigation) {
                    WawonaButton {
                        showingContainerImages = true
                    } label: {
                        WawonaLabel("Images", systemImage: "shippingbox")
                    }
                    .backport.glassToolbarButton()
                    .wwnA11y(WawonaA11y.machinesImages, label: "Container Images")
                }
            }
            #else
            .backport.navigationActions(trailingIsPrimary: true, leading: { EmptyView() }, trailing: {
                    WawonaButton {
                        editorSheet = .add
                    } label: {
                        WawonaLabel("Add Machine", systemImage: "plus")
                    }
                    .backport.glassToolbarButton()
                    .wwnA11y(WawonaA11y.machinesAdd, label: "Add Machine")
            })
            #endif
            .sheet(item: $editorSheet) { sheet in
                Group {
                    switch sheet {
                    case .add:
                        MachineEditorView { profile in
                            profileStore.upsert(profile)
                        }
                    case .edit(let profile):
                        MachineEditorView(profile: profile) { updated in
                            profileStore.upsert(updated)
                        }
                    }
                }
                .backport.editorSheet()
            }
            .sheet(isPresented: $showingContainerImages) {
                ContainerImagesView(onSelect: nil)
            }
        }
    }

    private var filteredProfiles: [MachineProfile] {
        MachineFuzzySearch.filter(
            profiles: profileStore.profiles,
            query: search,
            searchableText: { profile in
                [
                    profile.name,
                    profile.sshHost,
                    profile.sshUser,
                    profile.type.rawValue,
                ]
                .joined(separator: " ")
                .lowercased()
            }
        )
    }

    private func connect(_ profile: MachineProfile) {
        let preferences = preferences
        let profileStore = profileStore
        let sessions = sessions
        // relay_start opens the disk and builds the CPU on the caller. Leave
        // the SwiftUI thread before that work.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try MachineSessionBridge.connect(
                    profile: profile,
                    preferences: preferences,
                    profileStore: profileStore
                )
                DispatchQueue.main.async {
                    _ = sessions.connect(machineId: profile.id)
                }
            } catch {
                let reason = error.localizedDescription
                DispatchQueue.main.async {
                    _ = sessions.markFailed(machineId: profile.id, reason: reason)
                }
            }
        }
    }

    private func delete(_ profile: MachineProfile) {
        profileStore.delete(id: profile.id)
    }

}

enum MachineEditorSheet: Identifiable {
    case add
    case edit(MachineProfile)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let profile):
            return profile.id
        }
    }
}
