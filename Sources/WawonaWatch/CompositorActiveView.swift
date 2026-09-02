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
        ZStack {
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
            // immediately (scribble / QuickType / dictation). No on-screen
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
            if !startupLog.isPresented {
                // ToolbarSpacer is unavailable on watchOS (even 26.x); keep
                // the HStack+Spacer layout that works on every watchOS SDK.
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer(minLength: 0)
                        keyboardToolbarButton
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbarColorScheme(.dark, for: .bottomBar)
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

    /// Bottom-trailing Liquid Glass keyboard control. Same toolbar slot as
    /// Whisperer's watch input strip; watchOS 26 uses native `.glass`.
    @ViewBuilder
    private var keyboardToolbarButton: some View {
        if #available(watchOS 26.0, *) {
            Button {
                draftText = ""
                keyboardFocused = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityIdentifier("wwn.watch.keyboard")
            .accessibilityLabel("Keyboard")
        } else {
            Button {
                draftText = ""
                keyboardFocused = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wwn.watch.keyboard")
            .accessibilityLabel("Keyboard")
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

/// Paints the mini compositor's latest SHM commit. Default present is SpriteKit
/// (`WatchSpritePresentView`). `WWN_WATCH_SK_PRESENT=0` keeps the CPU Image path
/// for A/B. Frames arrive on `WWNWatchCompositorFrameReadyNotification`.
struct WatchCompositorSurfaceView: View {
    var onFirstFrame: (() -> Void)? = nil
    @State private var frameID = 0
    @State private var didNotifyFirstFrame = false

    var body: some View {
        if PlatformCapabilities.watchPresentAcceleratorEnabled {
            WatchSpritePresentView(onFirstFrame: onFirstFrame)
        } else {
            cpuImagePresent
        }
    }

    private var cpuImagePresent: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image = WWNWatchCompositorBridge.shared().latestFrame {
                    let iw = CGFloat(image.width)
                    let ih = CGFloat(image.height)
                    let scale = min(
                        1,
                        min(geo.size.width / max(iw, 1), geo.size.height / max(ih, 1))
                    )
                    Image(uiImage: UIImage(cgImage: image))
                        .resizable()
                        .frame(width: iw * scale, height: ih * scale)
                        .id(frameID)
                } else if onFirstFrame == nil {
                    Text("Waiting for surface…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
