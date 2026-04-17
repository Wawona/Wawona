import SwiftUI
import WawonaModel

private final class WatchCompositorRuntime {
    /// Must match `WWNWatchCompositorFrameReadyNotification` in WWNWatchCompositorBridge.m.
    static let frameReadyNotification = Notification.Name("WWNWatchCompositorFrameReadyNotification")

    private let bridge: WWNWatchCompositorBridge

    init() {
        self.bridge = WWNWatchCompositorBridge.shared()
    }

    func start() -> Bool {
        bridge.start(withSocketName: nil)
    }

    func stop() {
        bridge.stop()
    }

    func launchNativeClient(named launcherName: String) {
        let normalized = launcherName.lowercased()
        switch normalized {
        case "weston":
            bridge.launchWeston()
        case "weston-terminal":
            bridge.launchWestonTerminal()
        case "foot":
            bridge.launchFoot()
        default:
            bridge.launchWestonSimpleSHM()
        }
    }

    var latestFrame: CGImage? {
        bridge.latestFrame
    }

    var isRunning: Bool {
        bridge.isRunning
    }
}

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
    @State private var frameObserver: NSObjectProtocol?
    @State private var compositorRuntime: WatchCompositorRuntime?

    private var clientName: String {
        if profile.type == .sshWaypipe || profile.type == .sshTerminal {
            return profile.remoteCommand.isEmpty ? profile.name : profile.remoteCommand
        }
        return profile.launchers.first?.displayName
            ?? profile.launchers.first?.name
            ?? profile.name
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, _ in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(rect), with: .color(.black))
                if let frame = compositorFrame {
                    let img = Image(decorative: frame, scale: 1.0, orientation: .up)
                    ctx.draw(img, in: rect)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .navigationTitle(profile.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Stop") {
                    stopAndDismiss()
                }
            }
        }
        #endif
        .onAppear {
            NSLog("[Wawona·Nav] CompositorActiveView appeared — machine='%@' client='%@'",
                  profile.name, clientName)
            startCompositor()
        }
        .onDisappear {
            NSLog("[Wawona·Nav] CompositorActiveView disappeared — stopping compositor")
            sessions.disconnect(sessionId: session.id)
            stopCompositor()
        }
    }

    // MARK: - Compositor management

    private func startCompositor() {
        guard !compositorStarted else {
            NSLog("[Wawona·Compositor] startCompositor called but already started — skipping")
            return
        }
        let runtime = WatchCompositorRuntime()

        frameObserver = NotificationCenter.default.addObserver(
            forName: WatchCompositorRuntime.frameReadyNotification,
            object: WWNWatchCompositorBridge.shared(),
            queue: .main
        ) { _ in
            compositorFrame = runtime.latestFrame
            Task { @MainActor in
                sessions.notifyFramePresented(sessionId: session.id)
            }
        }

        guard runtime.start() else {
            NSLog("[Wawona·Compositor] ERROR: Failed to start watch compositor backend.")
            if let observer = frameObserver {
                NotificationCenter.default.removeObserver(observer)
                frameObserver = nil
            }
            return
        }

        compositorRuntime = runtime
        compositorStarted = true

        switch profile.type {
        case .native:
            let launcherName = profile.launchers.first?.name ?? "weston-simple-shm"
            NSLog("[Wawona·Compositor] Launching native client '%@'", launcherName)
            runtime.launchNativeClient(named: launcherName)
            sessions.notifyClientConnected(sessionId: session.id)
        case .sshWaypipe, .sshTerminal:
            NSLog("[Wawona·Compositor] SSH session opened in watch view (native compositor launch not applicable).")
        case .virtualMachine, .container:
            NSLog("[Wawona·Compositor] Unsupported machine type on watchOS: %@", profile.type.rawValue)
        }
    }

    private func stopCompositor() {
        NSLog("[Wawona·Compositor] Stopping compositor")
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
        compositorRuntime?.stop()
        compositorRuntime = nil
        compositorFrame = nil
        compositorStarted = false
    }

    private func stopAndDismiss() {
        NSLog("[Wawona·Nav] Stop button tapped — disconnecting session and dismissing")
        sessions.disconnect(sessionId: session.id)
        stopCompositor()
        dismiss()
    }
}

