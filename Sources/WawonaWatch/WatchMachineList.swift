#if os(watchOS)
import SwiftUI
import WatchKit
import WawonaModel

struct WatchMachineList: View {
    let profiles: [MachineProfile]
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    var searchQuery: String = ""
    var emptyTitle = "No Machines"
    var emptyDescription = "Tap + to add a machine."
    var onEdit: (MachineProfile) -> Void
    var onStarted: (MachineProfile, MachineSession) -> Void

    @ObservedObject private var pinStore = WWNMachinePinStore.shared
    @ObservedObject private var tagStore = WWNMachineTagStore.shared
    @ObservedObject private var preferences = WawonaPreferences.shared
    @State private var openProfile: MachineProfile?
    @State private var menuProfile: MachineProfile?
    @State private var pendingAction: (WatchMachineAction, MachineProfile)?
    /// Set by the long press so the row's tap on release does not also open it.
    @State private var suppressTap = false
    @State private var startFailed = false

    private var pinned: [MachineProfile] { profiles.filter { pinStore.isPinned($0.id) } }
    private var unpinned: [MachineProfile] { profiles.filter { !pinStore.isPinned($0.id) } }

    var body: some View {
        Group {
            if profiles.isEmpty {
                ContentUnavailableView(
                    searchQuery.isEmpty ? emptyTitle : "No Matching Machines",
                    systemImage: searchQuery.isEmpty ? "server.rack" : "magnifyingglass",
                    description: Text(
                        searchQuery.isEmpty
                            ? emptyDescription
                            : "No machine name matches this search."
                    )
                )
            } else {
                List {
                    if pinned.isEmpty {
                        rows(unpinned)
                    } else {
                        Section("Pinned") { rows(pinned) }
                        if !unpinned.isEmpty {
                            Section("Machines") { rows(unpinned) }
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $openProfile) { profile in
            QuickConnectView(
                profile: profile,
                profileStore: profileStore,
                sessions: sessions,
                onStarted: { session in onStarted(profile, session) }
            )
        }
        .sheet(item: $menuProfile, onDismiss: runPendingAction) { profile in
            WatchMachineActionsView(profile: profile, running: isRunning(profile)) { action in
                pendingAction = (action, profile)
            }
        }
        .alert("Could not start", isPresented: $startFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The Wayland compositor did not start. Check Watch logs for WATCH errors.")
        }
        .onChange(of: profileStore.profiles.map(\.id)) { _, ids in
            let kept = Set(ids)
            pinStore.prune(keeping: kept)
            tagStore.pruneAssignments(keeping: kept)
        }
    }

    private func rows(_ list: [MachineProfile]) -> some View {
        ForEach(list) { profile in
            let bleedThumbnail = WatchMachineThumbnailStore.isEnabled(
                profile: profile,
                preferences: preferences
            )
            Button {
                guard !suppressTap else { return }
                openProfile = profile
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    WatchMachineRowPreview(profile: profile)
                    HStack(spacing: 4) {
                        MachineRowLabel(
                            profile: profile,
                            sessions: sessions,
                            searchQuery: searchQuery
                        )
                        Spacer(minLength: 2)
                        WatchTagDots(tags: tagStore.tags(for: profile.id))
                        if pinStore.isPinned(profile.id) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .accessibilityLabel("Pinned")
                        }
                    }
                    .padding(.horizontal, bleedThumbnail ? 10 : 0)
                    .padding(.bottom, bleedThumbnail ? 6 : 0)
                }
            }
            .modifier(WatchMachineCardBleed(active: bleedThumbnail))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    suppressTap = true
                    WKInterfaceDevice.current().play(.click)
                    menuProfile = profile
                }
            )
            .accessibilityAction(named: "Actions") { menuProfile = profile }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(action: { onEdit(profile) }) {
                    Label("Edit", systemImage: "pencil")
                        .lineLimit(1)
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: { profileStore.delete(id: profile.id) }) {
                    Label("Delete", systemImage: "trash")
                        .lineLimit(1)
                }
            }
        }
    }

    private func session(for profile: MachineProfile) -> MachineSession? {
        sessions.sessions.first(where: { $0.machineId == profile.id })
    }

    private func isRunning(_ profile: MachineProfile) -> Bool {
        guard let status = session(for: profile)?.status else { return false }
        return status == .connected || status == .connecting
    }

    private func runPendingAction() {
        suppressTap = false
        guard let (action, profile) = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .start:
            if WatchMachineSessionBridge.connect(profile: profile) {
                onStarted(profile, sessions.connect(machineId: profile.id))
            } else {
                startFailed = true
            }
        case .focus:
            if let active = session(for: profile) {
                onStarted(profile, active)
            }
        case .stop:
            WatchMachineSessionBridge.disconnect(profile: profile)
            if let active = session(for: profile) {
                sessions.disconnect(sessionId: active.id)
            }
        case .edit:
            onEdit(profile)
        case .delete:
            profileStore.delete(id: profile.id)
        }
    }
}

/// Drops the row's top inset so the thumbnail meets the platter.
/// Side insets stay on the title, not on the image.
private struct WatchMachineCardBleed: ViewModifier {
    var active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        } else {
            content
        }
    }
}
#endif
