#if os(watchOS)
import SwiftUI
import WawonaModel
import WatchConnectivity

public struct WawonaWatchRootView: View {
    @StateObject private var profileStore = MachineProfileStore()
    @StateObject private var sessions = SessionOrchestrator()
    @ObservedObject private var preferences = WawonaPreferences.shared
    @State private var didAutoConnect = false
    @State private var autoProfile: MachineProfile?
    @State private var autoSession: MachineSession?
    @State private var phoneFrame: UIImage?
    @State private var phoneTouchDown = false
    /// Native SwiftUI alert (not a full-screen Welcome page). Same first-launch
    /// gate as phone/macOS/Android (`hasCompletedWelcome`).
    @State private var showWelcomeAlert = false

    public init() {}

    private var needsWelcome: Bool {
        !preferences.hasCompletedWelcome && profileStore.profiles.isEmpty
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 4) {
                if let phoneFrame {
                    GeometryReader { geo in
                        Image(uiImage: phoneFrame)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(phoneTouch(in: geo.size))
                    }
                    .frame(height: 80)
                }
                MachineStatusView(profileStore: profileStore, sessions: sessions)
            }
        }
        .fullScreenCover(item: $autoSession) { session in
            if let autoProfile {
                NavigationStack {
                    CompositorActiveView(
                        profile: autoProfile,
                        session: session,
                        sessions: sessions
                    )
                }
            }
        }
        .alert("Welcome to Wawona", isPresented: $showWelcomeAlert) {
            Button("Continue") {
                preferences.hasCompletedWelcome = true
                preferences.save()
                showWelcomeAlert = false
            }
            .accessibilityIdentifier("wwn.welcome.continue")
        } message: {
            Text("Machines on your wrist. Add one when you are ready.")
        }
        .onAppear {
            if needsWelcome {
                showWelcomeAlert = true
            }
            WatchCompanionController.shared.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                maybeAutoConnectNestedClient()
            }
        }
        .onChange(of: needsWelcome) { _, needed in
            if needed {
                showWelcomeAlert = true
            } else if preferences.hasCompletedWelcome {
                showWelcomeAlert = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("WWNWatchDisplayFrameNotification")
        )) { note in
            if let data = note.userInfo?["jpeg"] as? Data {
                phoneFrame = UIImage(data: data)
            }
        }
    }

    /// One finger on the phone frame. The phone seat is single-touch for this contact.
    private func phoneTouch(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let phase = phoneTouchDown ? "move" : "down"
                phoneTouchDown = true
                sendPhoneTouch(phase: phase, at: value.location, in: size)
            }
            .onEnded { value in
                phoneTouchDown = false
                sendPhoneTouch(phase: "up", at: value.location, in: size)
            }
    }

    private func sendPhoneTouch(phase: String, at location: CGPoint, in size: CGSize) {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        let x = min(1, max(0, location.x / max(size.width, 1)))
        let y = min(1, max(0, location.y / max(size.height, 1)))
        let message: [String: Any] = [
            "kind": "display-touch",
            "phase": phase,
            "x": x,
            "y": y,
        ]
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    /// Automation: `SIMCTL_CHILD_WAWONA_WATCH_AUTO_CLIENT=weston-simple-shm`
    /// or `simctl launch … --auto-client=weston-simple-shm`.
    private func maybeAutoConnectNestedClient() {
        guard !didAutoConnect else { return }
        let client = watchAutoClientId()
        guard !client.isEmpty else { return }
        didAutoConnect = true
        var overrides = MachineRuntimeOverrides()
        overrides.bundledAppID = client
        let profile = MachineProfile(
            id: "auto-\(client)",
            name: "Auto \(client)",
            type: .native,
            runtimeOverrides: overrides
        )
        guard WatchMachineSessionBridge.connect(profile: profile) else { return }
        autoProfile = profile
        autoSession = sessions.connect(machineId: profile.id)
    }

    private func watchAutoClientId() -> String {
        if let env = ProcessInfo.processInfo.environment["WAWONA_WATCH_AUTO_CLIENT"],
           !env.isEmpty {
            return env
        }
        for arg in ProcessInfo.processInfo.arguments {
            if arg.hasPrefix("--auto-client="), arg.count > 14 {
                return String(arg.dropFirst(14))
            }
        }
        return ""
    }
}
#endif
