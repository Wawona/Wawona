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
    @State private var detailMachineId: String?

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
            rootContent
                .backport.navigationTitle(navigationTitle)
                .wwnA11y(navigationA11yId, label: navigationTitle)
                .modifier(MachinesRootChromeModifier(
                    detailMachineId: $detailMachineId,
                    search: $search,
                    editorSheet: $editorSheet,
                    showingContainerImages: $showingContainerImages,
                    profileStore: profileStore
                ))
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if let detailMachineId,
           let profile = profileStore.profiles.first(where: { $0.id == detailMachineId }) {
            machineDetail(profile)
        } else {
            machinesGrid
        }
    }

    private var machinesGrid: some View {
        ScrollView {
            MachinesGridView(
                profiles: filteredProfiles,
                sessions: sessions,
                onSelect: { detailMachineId = $0.id }
            )
            .padding()
        }
    }

    private var navigationTitle: String {
        if detailMachineId == nil {
            return "Machines"
        }
        return detailProfileName ?? "Machine"
    }

    private var navigationA11yId: String {
        detailMachineId == nil ? WawonaA11y.machinesRoot : WawonaA11y.machinesDetail
    }

    private var detailProfileName: String? {
        guard let detailMachineId else { return nil }
        return profileStore.profiles.first(where: { $0.id == detailMachineId })?.name
    }

    @ViewBuilder
    private func machineDetail(_ profile: MachineProfile) -> some View {
        let status = sessions.sessions.first(where: { $0.machineId == profile.id })?.status
            ?? .disconnected
        let running = status == .connected || status == .connecting
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(profile.name)
                    .font(.title2.weight(.semibold))
                StatusBadge(status: status)
                MachineActionBar(items: detailActions(
                    profile: profile,
                    running: running
                ))
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func detailActions(
        profile: MachineProfile,
        running: Bool
    ) -> [MachineActionItem] {
        [
            MachineActionItem(
                title: running ? "Focus" : "Start",
                systemImage: running ? "scope" : "play.fill",
                prominent: true,
                accessibilityID: running
                    ? WawonaA11y.machinesFocus
                    : WawonaA11y.machinesConnect,
                accessibilityLabel: running ? "Focus" : "Start",
                action: { connect(profile) }
            ),
            MachineActionItem(
                title: "Edit",
                systemImage: "slider.horizontal.3",
                accessibilityID: WawonaA11y.machinesEdit,
                accessibilityLabel: "Edit",
                action: { editorSheet = .edit(profile) }
            ),
            MachineActionItem(
                title: "Delete",
                systemImage: "trash",
                role: .destructive,
                accessibilityID: WawonaA11y.machinesDelete,
                accessibilityLabel: "Delete",
                action: {
                    delete(profile)
                    detailMachineId = nil
                }
            ),
        ]
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
        // the SwiftUI thread before that work; hop back for @MainActor connect.
        DispatchQueue.global(qos: .userInitiated).async {
            Task { @MainActor in
                do {
                    try MachineSessionBridge.connect(
                        profile: profile,
                        preferences: preferences,
                        profileStore: profileStore
                    )
                    _ = sessions.connect(machineId: profile.id)
                } catch {
                    _ = sessions.markFailed(
                        machineId: profile.id,
                        reason: error.localizedDescription
                    )
                }
            }
        }
    }

    private func delete(_ profile: MachineProfile) {
        profileStore.delete(id: profile.id)
    }
}

/// Toolbar / sheet / search chrome split out so `body` type-checks on tvOS.
private struct MachinesRootChromeModifier: ViewModifier {
    @Binding var detailMachineId: String?
    @Binding var search: String
    @Binding var editorSheet: MachineEditorSheet?
    @Binding var showingContainerImages: Bool
    @ObservedObject var profileStore: MachineProfileStore

    func body(content: Content) -> some View {
        content
            .modifier(MachinesRootSearchModifier(search: $search, detailMachineId: detailMachineId))
            .toolbar { toolbarContent }
            .modifier(MachinesRootTrailingAddModifier(
                detailMachineId: detailMachineId,
                editorSheet: $editorSheet
            ))
            .backport.machineEditorSheet(item: $editorSheet) { sheet in
                editorContent(sheet)
            }
            .sheet(isPresented: $showingContainerImages) {
                ContainerImagesView(onSelect: nil)
            }
            .backport.onChange(of: profileStore.profiles.map(\.id)) { _, ids in
                if let detailMachineId, !ids.contains(detailMachineId) {
                    self.detailMachineId = nil
                }
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if detailMachineId != nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { detailMachineId = nil }
                    .accessibilityIdentifier(WawonaA11y.machinesDetailBack)
                    .accessibilityLabel("Back to Machines")
            }
        }
        #if os(macOS)
        if detailMachineId == nil {
            ToolbarItem(placement: .primaryAction) {
                WawonaButton {
                    editorSheet = .add
                } label: {
                    WawonaLabel("Add Machine", systemImage: "plus")
                }
                .backport.glassProminentToolbarButton()
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
        #endif
    }

    @ViewBuilder
    private func editorContent(_ sheet: MachineEditorSheet) -> some View {
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
}

private struct MachinesRootSearchModifier: ViewModifier {
    @Binding var search: String
    let detailMachineId: String?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.searchable(
            text: $search,
            placement: .toolbar,
            prompt: "Search machines"
        )
        #else
        content
        #endif
    }
}

private struct MachinesRootTrailingAddModifier: ViewModifier {
    let detailMachineId: String?
    @Binding var editorSheet: MachineEditorSheet?

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.backport.navigationActions(
            trailingIsPrimary: true,
            leading: { EmptyView() },
            trailing: {
                if detailMachineId == nil {
                    WawonaButton {
                        editorSheet = .add
                    } label: {
                        WawonaLabel("Add Machine", systemImage: "plus")
                    }
                    .backport.glassProminentToolbarButton()
                    .wwnA11y(WawonaA11y.machinesAdd, label: "Add Machine")
                }
            }
        )
        #endif
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
