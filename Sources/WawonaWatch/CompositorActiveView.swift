#if os(watchOS)
import SwiftUI
import UIKit
import WawonaModel

struct CompositorActiveView: View {
    let profile: MachineProfile
    let session: MachineSession
    let sessions: SessionOrchestrator
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var preferences = WawonaPreferences.shared
    @StateObject private var startupLog = WatchStartupLogModel()
    @State private var showStopConfirmation = false
    @State private var draftText = ""
    @FocusState private var keyboardFocused: Bool

    private var requiresExitConfirmation: Bool {
        let resolved = preferences.resolvedSettings(for: profile)
        return resolved.shakeToCloseEnabled || resolved.swipeBackToCloseEnabled
    }

    private var startupClientLabel: String {
        let override = profile.runtimeOverrides.bundledAppID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty { return override }
        if let launcher = profile.launchers.first?.name, !launcher.isEmpty {
            return launcher
        }
        return profile.name
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WatchCompositorSurfaceView(onFirstFrame: {
                startupLog.scheduleDismissAfterFirstFrame()
            })
                .ignoresSafeArea()

            if startupLog.isPresented {
                WatchStartupLogOverlay(
                    model: startupLog,
                    clientLabel: startupClientLabel
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }

            // Hidden field: focusing it opens the native watch text-entry UI
            // immediately (scribble / QuickType / dictation) — no on-screen
            // "Type…" chrome. Submit/Send injects into the Wayland client.
            TextField("", text: $draftText)
                .focused($keyboardFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.send)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
                .onSubmit { commitDraftToWayland() }
                .onChange(of: keyboardFocused) { _, focused in
                    if !focused {
                        commitDraftToWayland()
                    }
                }

            if !startupLog.isPresented {
                Button {
                    draftText = ""
                    keyboardFocused = true
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .padding(.bottom, 6)
                .accessibilityIdentifier("wwn.watch.keyboard")
                .accessibilityLabel("Keyboard")
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityIdentifier(
                    profile.type == .native ? "wwn.watch.stop" : "wwn.watch.disconnect"
                )
                .accessibilityLabel(profile.type == .native ? "Stop" : "Disconnect")
            }
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
        .onAppear {
            startupLog.attach()
        }
        .onDisappear {
            startupLog.dismiss()
        }
    }

    private func requestClose() {
        if requiresExitConfirmation {
            showStopConfirmation = true
        } else {
            disconnectActiveSession()
        }
    }

    /// Native text-entry Send / dismiss → inject into the focused Wayland
    /// surface (same contract as iOS/Android soft keyboard commit).
    private func commitDraftToWayland() {
        let text = draftText
        guard !text.isEmpty else { return }
        draftText = ""
        // Append Return so shell commands execute (weston-terminal → zsh).
        WWNWatchCompositorBridge.shared().sendText(text.hasSuffix("\n") ? text : text + "\n")
    }

    private func disconnectActiveSession() {
        keyboardFocused = false
        WatchMachineSessionBridge.disconnect(profile: profile)
        sessions.disconnect(sessionId: session.id)
        dismiss()
    }
}

/// Paints the mini compositor's latest SHM commit. Frames arrive on
/// `WWNWatchCompositorFrameReadyNotification`; without this view the client
/// runs (PTY, configure, redraw) and nothing appears on the watch.
struct WatchCompositorSurfaceView: View {
    var onFirstFrame: (() -> Void)? = nil
    @State private var frameID = 0
    @State private var didNotifyFirstFrame = false

    var body: some View {
        Group {
            if let image = WWNWatchCompositorBridge.shared().latestFrame {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .scaledToFit()
                    .id(frameID)
            } else if onFirstFrame == nil {
                // Standalone use: keep the old placeholder. When a startup
                // log overlay is active, skip this so logs aren't covered.
                Text("Waiting for surface…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier("wwn.watch.compositorSurface")
        .accessibilityLabel("Wayland Surface")
        .onAppear {
            if WWNWatchCompositorBridge.shared().latestFrame != nil {
                notifyFirstFrameIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("WWNWatchCompositorFrameReadyNotification")
        )) { _ in
            frameID &+= 1
            notifyFirstFrameIfNeeded()
        }
    }

    private func notifyFirstFrameIfNeeded() {
        guard !didNotifyFirstFrame else { return }
        didNotifyFirstFrame = true
        onFirstFrame?()
    }
}
#endif
