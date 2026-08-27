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
                // Same trailing bottom-bar slot as Whisperer's mic
                // (`bottomRightControls` after `Spacer()` in AppView).
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer(minLength: 0)
                    keyboardButton
                        .fixedSize()
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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

    /// Whisperer watch `keyboardButton`: `TextFieldLink` + `keyboard` SF Symbol
    /// with circular liquid glass. Placed in Whisperer's mic slot (bottom-bar
    /// trailing), not Whisperer's leading keyboard slot.
    private var keyboardButton: some View {
        TextFieldLink(prompt: Text("Type message")) {
            keyboardGlyph
        } onSubmit: { value in
            commitDraftToWayland(value)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.send)
        .buttonStyle(.plain)
        .accessibilityIdentifier("wwn.watch.keyboard")
        .accessibilityLabel("Keyboard")
    }

    @ViewBuilder
    private var keyboardGlyph: some View {
        if #available(watchOS 26.0, *) {
            GlassEffectContainer {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        } else {
            Image(systemName: "keyboard")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func requestClose() {
        if requiresExitConfirmation {
            showStopConfirmation = true
        } else {
            disconnectActiveSession()
        }
    }

    /// Native text-entry Send → inject into the focused Wayland surface
    /// (same contract as iOS/Android soft keyboard commit).
    private func commitDraftToWayland(_ raw: String) {
        guard !raw.isEmpty else { return }
        // Append Return so shell commands execute (weston-terminal → zsh).
        WWNWatchCompositorBridge.shared().sendText(raw.hasSuffix("\n") ? raw : raw + "\n")
    }

    private func disconnectActiveSession() {
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
