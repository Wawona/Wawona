#if os(watchOS)
import SwiftUI
import WawonaModel

struct QuickConnectView: View {
    let profile: MachineProfile
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    var onStarted: (MachineSession) -> Void

    @ObservedObject private var preferences = WawonaPreferences.shared
    @ObservedObject private var tagStore = WWNMachineTagStore.shared
    @ObservedObject private var pinStore = WWNMachinePinStore.shared
    @State private var showDisconnectConfirmation = false
    @State private var startFailed = false
    @State private var showingEditor = false
    @State private var confirmDelete = false

    private var requiresExitConfirmation: Bool {
        let resolved = preferences.resolvedSettings(for: profile)
        return resolved.shakeToCloseEnabled || resolved.swipeBackToCloseEnabled
    }

    private var runningSession: MachineSession? {
        sessions.sessions.first {
            $0.machineId == profile.id && ($0.status == .connected || $0.status == .connecting)
        }
    }

    private var pinned: Bool { pinStore.isPinned(profile.id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(profile.name).font(.headline)
                if let runningSession {
                    Button {
                        onStarted(runningSession)
                    } label: {
                        Label("Focus", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("wwn.watch.focus")
                    .accessibilityLabel("Focus")
                    Button(role: .destructive) {
                        if requiresExitConfirmation {
                            showDisconnectConfirmation = true
                        } else {
                            stopSession(runningSession)
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("wwn.watch.stop")
                    .accessibilityLabel("Stop")
                } else {
                    Button {
                        // Do not write profileStore here. `activeMachineId` + save()
                        // republishes Machines and destroys this destination
                        // before the compositor cover can present.
                        if WatchMachineSessionBridge.connect(profile: profile) {
                            onStarted(sessions.connect(machineId: profile.id))
                        } else {
                            startFailed = true
                        }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("wwn.watch.start")
                    .accessibilityLabel("Start")
                }
                Button(action: { showingEditor = true }) {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("wwn.watch.machineSettings")
                .accessibilityLabel("Edit")

                NavigationLink {
                    WatchMachineTagsView(machineId: profile.id)
                } label: {
                    HStack {
                        Label("Tags", systemImage: "tag")
                        Spacer(minLength: 4)
                        WatchTagDots(tags: tagStore.tags(for: profile.id))
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("wwn.watch.detail.tags")
                .accessibilityLabel("Tags")

                Button {
                    pinStore.toggle(profile.id)
                } label: {
                    Label(
                        pinned ? "Unpin" : "Pin",
                        systemImage: pinned ? "pin.slash" : "pin"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(!pinned && pinStore.limitReached)
                .accessibilityIdentifier("wwn.watch.detail.pin")
                .accessibilityLabel(pinned ? "Unpin" : "Pin")

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(runningSession != nil)
                .accessibilityIdentifier("wwn.watch.detail.delete")
                .accessibilityLabel("Delete")
            }
        }
        .sheet(isPresented: $showingEditor) {
            MachineEditorView(profileStore: profileStore, profile: profile)
        }
        .alert("Could not start", isPresented: $startFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The Wayland compositor did not start. Check Watch logs for WATCH errors.")
        }
        .confirmationDialog(
            "Close current Wayland app?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                if let runningSession {
                    stopSession(runningSession)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop the current session and return to Machines.")
        }
        .confirmationDialog(
            "Delete \(profile.name.isEmpty ? "this machine" : profile.name)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                profileStore.delete(id: profile.id)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func stopSession(_ activeSession: MachineSession) {
        WatchMachineSessionBridge.disconnect(profile: profile)
        sessions.disconnect(sessionId: activeSession.id)
    }
}
#endif
