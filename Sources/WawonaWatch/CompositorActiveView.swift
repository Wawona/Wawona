#if os(watchOS)
import SwiftUI
import WawonaModel

struct CompositorActiveView: View {
    let profile: MachineProfile
    let session: MachineSession
    let sessions: SessionOrchestrator
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var preferences = WawonaPreferences.shared
    @State private var showStopConfirmation = false
    @State private var inputText = ""

    private var requiresExitConfirmation: Bool {
        let resolved = preferences.resolvedSettings(for: profile)
        return resolved.shakeToCloseEnabled || resolved.swipeBackToCloseEnabled
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(profile.name).font(.headline)
            Text("Session Active").font(.caption)
            SessionGlanceView(session: session)
            keyboardInputRow
            Button(role: .destructive) {
                if requiresExitConfirmation {
                    showStopConfirmation = true
                } else {
                    disconnectActiveSession()
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("wwn.watch.stop")
            .accessibilityLabel("Stop")
        }
        .confirmationDialog(
            "Close current Wayland app?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                disconnectActiveSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop the current session and return to Machines.")
        }
    }

    // WatchKit text entry → PTY. The TextField invokes the system text-input
    // controller (scribble / dictation / QuickType); the committed string is
    // fed to the focused Wayland client (weston-terminal → zsh) as synthetic
    // US-layout key events. "⏎" sends a bare Return so shell commands execute.
    @ViewBuilder private var keyboardInputRow: some View {
        VStack(spacing: 6) {
            TextField("Type…", text: $inputText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.send)
                .onSubmit { submitLine() }
                .accessibilityIdentifier("wwn.watch.terminalInput")
                .accessibilityLabel("Terminal Input")
            HStack(spacing: 8) {
                Button {
                    sendCurrentText()
                } label: {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("wwn.watch.terminalSend")
                .accessibilityLabel("Send Text")
                Button {
                    WWNWatchCompositorBridge.shared().sendText("\n")
                } label: {
                    Label("Return", systemImage: "return")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("wwn.watch.terminalReturn")
                .accessibilityLabel("Return")
            }
            .buttonStyle(.bordered)
        }
    }

    private func sendCurrentText() {
        guard !inputText.isEmpty else { return }
        WWNWatchCompositorBridge.shared().sendText(inputText)
        inputText = ""
    }

    private func submitLine() {
        // Send the typed text followed by Return so the command runs.
        WWNWatchCompositorBridge.shared().sendText(inputText + "\n")
        inputText = ""
    }

    private func disconnectActiveSession() {
        WatchMachineSessionBridge.disconnect(profile: profile)
        sessions.disconnect(sessionId: session.id)
        dismiss()
    }
}
#endif
