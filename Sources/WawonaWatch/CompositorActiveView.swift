import SwiftUI
import WawonaModel

/// Full-screen view shown while a native Wayland client session is running.
/// Starts the in-process compositor + client and renders compositor frames
/// via a SwiftUI Canvas backed by CGImage snapshots from WWNWatchCompositorBridge.
struct CompositorActiveView: View {
    let profile: MachineProfile
    let session: MachineSession
    let sessions: SessionOrchestrator

    @Environment(\.dismiss) var dismiss
    @State var compositorFrame: CGImage?
    @State var compositorStarted = false

    private var clientName: String {
        if profile.type == .sshWaypipe || profile.type == .sshTerminal {
            return profile.remoteCommand.isEmpty ? profile.name : profile.remoteCommand
        }
        return profile.launchers.first?.displayName
            ?? profile.launchers.first?.name
            ?? profile.name
    }

    var body: some View {
        ZStack {
            // Compositor output — fills the watch face when a frame is ready
            if let frame = compositorFrame {
                GeometryReader { _ in
                    Canvas { ctx, size in
                        let img = Image(frame, scale: 1.0, orientation: .up, label: Text("frame"))
                        ctx.draw(img, in: CGRect(origin: .zero, size: size))
                    }
                    .ignoresSafeArea()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers,
                                      isActive: true)
                    Text("Running")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(clientName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Stop button — always accessible at the bottom
            VStack {
                Spacer()
                Button(role: .destructive) {
                    stopAndDismiss()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(profile.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .onAppear {
            NSLog("[Wawona·Nav] CompositorActiveView appeared — machine='%@' client='%@'",
                  profile.name, clientName)
            startCompositor()
        }
        .onDisappear {
            NSLog("[Wawona·Nav] CompositorActiveView disappeared — stopping compositor")
            stopCompositor()
        }
    }

    // MARK: - Compositor management

    private func startCompositor() {
        guard !compositorStarted else {
            NSLog("[Wawona·Compositor] startCompositor called but already started — skipping")
            return
        }
        compositorStarted = true

        NSLog("[Wawona·Compositor] Shared module compositor bridge unavailable in this build context")
    }

    private func stopCompositor() {
        NSLog("[Wawona·Compositor] Stopping compositor")
        // No-op when running from the shared Swift package context.
        compositorStarted = false
    }

    private func stopAndDismiss() {
        NSLog("[Wawona·Nav] Stop button tapped — disconnecting session and dismissing")
        sessions.disconnect(sessionId: session.id)
        stopCompositor()
        dismiss()
    }
}

