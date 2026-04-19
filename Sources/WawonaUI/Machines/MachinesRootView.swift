import SwiftUI
import WawonaModel

struct MachinesRootView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    @State var search = ""
    @State var showingEditor = false
    @State var editingProfile: MachineProfile?
    @State var showingSettings = false
    #if os(iOS)
    @State private var isGlassSearchPresented = false
    @FocusState private var isGlassSearchFocused: Bool
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
            #if os(macOS)
            .searchable(text: $search, prompt: "Search machines")
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .navigation) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                #else
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                #endif
                #if os(iOS)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            isGlassSearchPresented = true
                        }
                        DispatchQueue.main.async {
                            isGlassSearchFocused = true
                        }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
                #else
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Add Machine", systemImage: "plus")
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Add Machine", systemImage: "plus")
                    }
                }
                #endif
                #endif
            }
            #if os(iOS)
            .overlay(alignment: .top) {
                if isGlassSearchPresented {
                    glassSearchOverlay
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isGlassSearchPresented)
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Wawona Settings", systemImage: "gearshape")
                    }
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Add Machine", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
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
            .sheet(isPresented: $showingSettings) {
                SettingsRootView(
                    preferences: preferences,
                    profileStore: profileStore
                )
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
    }

    private func delete(_ profile: MachineProfile) {
        profileStore.delete(id: profile.id)
    }

    #if os(iOS)
    /// GitHub-mobile style: glass pill under the nav bar; toolbar magnifying glass opens this.
    @ViewBuilder
    private var glassSearchOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissGlassSearchBar(preserveQuery: true)
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("Search machines", text: $search)
                        .textFieldStyle(.plain)
                        .focused($isGlassSearchFocused)
                        .submitLabel(.search)

                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Cancel") {
                        dismissGlassSearchBar(preserveQuery: false)
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    if #available(iOS 26, *) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
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
        isGlassSearchFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isGlassSearchPresented = false
        }
    }
    #endif
}
