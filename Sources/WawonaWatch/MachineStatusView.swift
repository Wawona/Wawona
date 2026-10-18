#if os(watchOS)
import SwiftUI
import WawonaModel
import WawonaUIContracts

struct MachineStatusView: View {
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    @ObservedObject private var tagStore = WWNMachineTagStore.shared

    @State var showingAdd = false
    @State var editingProfile: MachineProfile?
    @Binding var settingsRoute: WatchSettingsRoute?
    @State private var showingSections = false
    @State private var page: WatchHomePage = .machines
    @State private var searchQuery = ""
    @State private var searching = false
    @State private var showsTopItems = true
    @State private var topFaded = false
    @State private var contentWidth: CGFloat = 184
    @State private var runningCover: WatchMachineCover?

    var body: some View {
        Group {
            switch page {
            case .machines, .tag:
                WatchMachineList(
                    profiles: filteredProfiles,
                    profileStore: profileStore,
                    sessions: sessions,
                    searchQuery: searchQuery,
                    emptyTitle: activeTag == nil ? "No Machines" : "No Tagged Machines",
                    emptyDescription: activeTag == nil
                        ? "Tap + to add a machine."
                        : "Press and hold a machine, then choose Tags.",
                    onEdit: { editingProfile = $0 },
                    onStarted: { profile, session in
                        runningCover = WatchMachineCover(profile: profile, session: session)
                    }
                )
            case .tabOverview:
                WatchTabOverviewList(
                    profiles: profileStore.profiles,
                    sessions: sessions,
                    searchQuery: searchQuery,
                    onOpen: openTab,
                    onClose: closeTab
                )
            }
        }
        .modifier(WatchSearchLift(active: searching))
        // System title: full size, and long titles scroll on their own.
        // It leaves with the top buttons so the bar shrinks to the clock row.
        .navigationTitle(navigationTitleText)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if showsTopItems {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: showingSections ? closeSections : openSections) {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Sections")
                    .accessibilityIdentifier("wwn.watch.sections")
                    .modifier(WatchSearchHiddenWhileSearching(searching: topFaded))
                }
                if !showingSections {
                    ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Wawona Settings")
                    .accessibilityIdentifier("wwn.watch.settings")
                    .modifier(WatchSearchHiddenWhileSearching(searching: topFaded))
                    }
                }
            }
            ToolbarItem(id: "wwn.watch.bottom", placement: .bottomBar) {
                WatchSearchBottomBar(
                    query: $searchQuery,
                    searching: searching,
                    rowWidth: max(120, contentWidth - 30),
                    addLabel: "Add Machine",
                    addIdentifier: "wwn.watch.add",
                    onSearch: searchTapped,
                    onAdd: { showingAdd = true },
                    onCancel: cancelSearch
                )
            }
        }
        // watchOS keeps the presenter's bottom bar live under a sheet or
        // cover, so its search pill would take taps meant for the sheet.
        .toolbar(presentsModal ? .hidden : .automatic, for: .bottomBar)
        .task(id: searching) {
            // Icons fade first; the bar items (and their glass) leave after.
            // Closing re-adds them faded, then fades them in.
            if searching {
                topFaded = true
                try? await Task.sleep(for: .seconds(WatchSearchInput.expandDuration))
                guard !Task.isCancelled else { return }
                showsTopItems = false
            } else {
                // Re-added items need a moment to mount in the bar before
                // the fade-in, or they appear at full opacity.
                showsTopItems = true
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                withAnimation(WatchSearchInput.animation) { topFaded = false }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: WatchContentWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(WatchContentWidthKey.self) { width in
            guard width > 1, abs(width - contentWidth) > 0.5 else { return }
            contentWidth = width
        }
        .onReceive(NotificationCenter.default.publisher(
            for: WatchKitGlobalSettings.fallbackPresentationNeeded
        )) { _ in
            openSettings()
        }
        .onChange(of: tagStore.tags) { _, tags in
            if case .tag(let tagId) = page, !tags.contains(where: { $0.id == tagId }) {
                page = .machines
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wawonaPreferencesDidSave)) { _ in
            WawonaPreferences.shared.load()
        }
        // A stack push always arrives from the trailing edge. The sections
        // page is the sidebar, so it slides in from the leading edge instead.
        .overlay {
            if showingSections {
                WatchSectionListView(page: $page, onClose: closeSections)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .transition(.move(edge: .leading))
            }
        }
        .sheet(isPresented: $showingAdd) {
            MachineEditorView(profileStore: profileStore)
        }
        .sheet(item: $editingProfile) { profile in
            MachineEditorView(profileStore: profileStore, profile: profile)
        }
        .fullScreenCover(item: $runningCover) { cover in
            NavigationStack {
                CompositorActiveView(
                    profile: cover.profile,
                    session: cover.session,
                    sessions: sessions,
                    onPark: { runningCover = nil }
                )
            }
        }
    }

    private var presentsModal: Bool {
        showingSections || showingAdd || editingProfile != nil || runningCover != nil
    }

    private var activeTag: WWNMachineTag? {
        guard case .tag(let tagId) = page else { return nil }
        return tagStore.tags.first { $0.id == tagId }
    }

    /// Sidebar open: its own title. Otherwise the page title, which leaves
    /// with the top buttons while search is open.
    private var navigationTitleText: String {
        if showingSections { return "Wawona" }
        return showsTopItems ? pageTitle : ""
    }

    /// Sidebar row stays "Machines"; the page itself is Machine Configuration,
    /// as on iOS.
    private var pageTitle: String {
        switch page {
        case .machines: return "Machine Configuration"
        case .tabOverview: return "Tab Overview"
        case .tag: return activeTag?.name ?? "Machine Configuration"
        }
    }

    private var filteredProfiles: [MachineProfile] {
        var base = profileStore.profiles
        if let activeTag {
            base = base.filter { tagStore.isAssigned(activeTag.id, to: $0.id) }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { profile in
            profile.name.localizedCaseInsensitiveContains(query)
                || profile.type.userFacingName.localizedCaseInsensitiveContains(query)
        }
    }

    private func openSettings() {
        settingsRoute = .global
    }

    private func openSections() {
        withAnimation(.smooth(duration: 0.35)) { showingSections = true }
    }

    private func closeSections() {
        withAnimation(.smooth(duration: 0.35)) { showingSections = false }
    }

    /// Grows the search control into the pill. A tap on the pill edits the query.
    private func searchTapped() {
        withAnimation(WatchSearchInput.animation) {
            searching = true
        }
    }

    private func cancelSearch() {
        withAnimation(.smooth(duration: WatchSearchInput.expandDuration)) {
            searchQuery = ""
            searching = false
        }
    }

    private func openTab(_ profile: MachineProfile, _ session: MachineSession) {
        runningCover = WatchMachineCover(profile: profile, session: session)
    }

    private func closeTab(_ profile: MachineProfile, _ session: MachineSession) {
        let wasActive = sessions.activeSessionId == session.id
        WatchNativeShellRegistry.shared.stop(sessionId: session.id)
        sessions.disconnect(sessionId: session.id)
        if wasActive {
            WatchMachineSessionBridge.disconnect(profile: profile)
            runningCover = nil
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
    var searchQuery: String = ""
    @Environment(\.colorScheme) private var colorScheme

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
        HStack(spacing: 6) {
            Circle()
                .fill(status == .connected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(WatchSearchHighlight.name(
                    profile.name.isEmpty ? "Unnamed Machine" : profile.name,
                    query: searchQuery,
                    scheme: colorScheme
                ))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                Text(clientLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#endif
