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
    #if os(iOS)
    @State private var isGlassSearchPresented = false
    #endif

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
        Backport<Any>.NavigationContainer {
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
            .backport.navigationTitle("Machines")
            .wwnA11y(WawonaA11y.machinesRoot, label: "Machines")
            #if os(macOS)
            .searchable(text: $search, placement: .toolbar, prompt: "Search machines")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        openPlatformSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .wwnA11y(WawonaA11y.machinesSettings, label: "Settings")
                }
            }
            #else
            .navigationBarItems(
                trailing: HStack {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Add Machine", systemImage: "plus")
                    }
                    .wwnA11y(WawonaA11y.machinesAdd, label: "Add Machine")
                    Button {
                        openPlatformSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .wwnA11y(WawonaA11y.machinesSettings, label: "Settings")
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            isGlassSearchPresented = true
                        }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
            )
            #endif
            #if os(iOS)
            .overlay(
                Group {
                if isGlassSearchPresented {
                    glassSearchOverlay
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
                },
                alignment: .top
            )
            .backport.animation(
                .spring(response: 0.32, dampingFraction: 0.86),
                value: isGlassSearchPresented
            )
            #endif
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
        do {
            try MachineSessionBridge.connect(
                profile: profile,
                preferences: preferences,
                profileStore: profileStore
            )
            _ = sessions.connect(machineId: profile.id)
        } catch {
            _ = sessions.markFailed(machineId: profile.id, reason: error.localizedDescription)
        }
    }

    private func delete(_ profile: MachineProfile) {
        profileStore.delete(id: profile.id)
    }

    private func openPlatformSettings() {
        PlatformGlobalSettings.open()
    }

    #if os(iOS)
    /// GitHub-mobile style: glass pill under the nav bar; toolbar magnifying glass opens this.
    @ViewBuilder
    private var glassSearchOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    dismissGlassSearchBar(preserveQuery: true)
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .backport.foregroundStyle(.secondary)

                    TextField("Search machines", text: $search)
                        .textFieldStyle(.plain)

                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .backport.foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Cancel") {
                        dismissGlassSearchBar(preserveQuery: false)
                    }
                    .font(.body.weight(.medium))
                    .backport.foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Backport<Any>.glassRoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func dismissGlassSearchBar(preserveQuery: Bool) {
        if !preserveQuery {
            search = ""
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isGlassSearchPresented = false
        }
    }
    #endif
}
