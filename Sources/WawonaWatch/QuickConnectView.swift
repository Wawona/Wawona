import SwiftUI
import WawonaModel

struct QuickConnectView: View {
    let profile: MachineProfile
    let sessions: SessionOrchestrator

    @State var runningSession: MachineSession?

    var activeSession: MachineSession? {
        sessions.sessions.first(where: { $0.machineId == profile.id })
    }
    var isNative: Bool       { profile.type == .native }
    var isSSHWaypipe: Bool   { profile.type == .sshWaypipe }
    var isSSHTerminal: Bool  { profile.type == .sshTerminal }
    var isLaunchable: Bool   { isNative || isSSHWaypipe || isSSHTerminal }
    var isConnected: Bool    { activeSession?.status == .connected }
    var isConnecting: Bool   { activeSession?.status == .connecting }

    var launcherName: String {
        profile.launchers.first?.displayName ?? profile.launchers.first?.name ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Identity header
                VStack(spacing: 4) {
                    Image(systemName: profile.type.watchSystemImage)
                        .font(.title2)
                        .foregroundStyle(isLaunchable && isConnected ? .green : .secondary)
                    Text(profile.name)
                        .font(.headline)
                        .lineLimit(1)
                    if isNative, !profile.launchers.isEmpty {
                        Text(launcherName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if !profile.sshHost.isEmpty {
                        Text("\(profile.sshUser.isEmpty ? "" : profile.sshUser + "@")\(profile.sshHost)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if isNative {
                    nativeContent
                } else if isSSHWaypipe || isSSHTerminal {
                    sshContent
                } else {
                    notSupportedBanner
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .navigationTitle(isLaunchable ? "Launch" : profile.type.watchDisplayName)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            NSLog("[Wawona·Nav] QuickConnectView appeared — machine='%@' type=%@ launcher='%@'",
                  profile.name,
                  profile.type.rawValue,
                  profile.launchers.first?.name ?? "none")
        }
        .onDisappear {
            NSLog("[Wawona·Nav] QuickConnectView disappeared — machine='%@'", profile.name)
        }
        .navigationDestination(item: $runningSession) { session in
            CompositorActiveView(profile: profile, session: session, sessions: sessions)
        }
    }

    // MARK: - Native client content

    @ViewBuilder
    var nativeContent: some View {
        // Status pill
        HStack(spacing: 5) {
            Circle()
                .fill(nativeStatusColor)
                .frame(width: 7, height: 7)
            Text(nativeStatusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(nativeStatusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(nativeStatusColor.opacity(0.15), in: Capsule())

        // Run / Stop button
        if isConnected {
            Button(role: .destructive) {
                NSLog("[Wawona·Nav] Stop tapped — machine '%@'", profile.name)
                if let s = activeSession { sessions.disconnect(sessionId: s.id) }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            Button {
                NSLog("[Wawona·Nav] Run tapped — machine '%@' type=native launcher='%@'",
                      profile.name,
                      profile.launchers.first?.name ?? "none")
                let session = sessions.connect(machineId: profile.id)
                NSLog("[Wawona·Nav] Native session created id=%@ → pushing CompositorActiveView",
                      session.id.uuidString)
                runningSession = session
            } label: {
                Label(
                    isConnecting ? "Starting…" : "Run",
                    systemImage: isConnecting
                        ? "arrow.trianglehead.2.clockwise"
                        : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)
        }
    }

    // MARK: - SSH + Waypipe / SSH Terminal content

    @ViewBuilder
    var sshContent: some View {
        // Connection info
        VStack(alignment: .leading, spacing: 4) {
            Label(profile.sshHost.isEmpty ? "No host" : profile.sshHost, systemImage: "network")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !profile.sshUser.isEmpty {
                Label(profile.sshUser, systemImage: "person")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !profile.remoteCommand.isEmpty {
                Label(profile.remoteCommand, systemImage: "terminal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)

        // Status pill (same style as native)
        HStack(spacing: 5) {
            Circle()
                .fill(nativeStatusColor)
                .frame(width: 7, height: 7)
            Text(sshStatusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(nativeStatusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(nativeStatusColor.opacity(0.15), in: Capsule())

        // Connect / Disconnect button
        if isConnected {
            Button(role: .destructive) {
                NSLog("[Wawona·Nav] Disconnect tapped — machine '%@'", profile.name)
                if let s = activeSession { sessions.disconnect(sessionId: s.id) }
            } label: {
                Label("Disconnect", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            Button {
                NSLog("[Wawona·Nav] Connect tapped — machine '%@' type=%@ remoteCmd='%@'",
                      profile.name,
                      profile.type.rawValue,
                      profile.remoteCommand)
                let session = sessions.connect(machineId: profile.id)
                NSLog("[Wawona·Nav] SSH session created id=%@ → pushing CompositorActiveView",
                      session.id.uuidString)
                runningSession = session
            } label: {
                Label(
                    isConnecting ? "Connecting…" : "Connect",
                    systemImage: isConnecting
                        ? "arrow.trianglehead.2.clockwise"
                        : "cable.connector"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting || profile.sshHost.isEmpty)
        }
    }

    // MARK: - Non-native "not supported" banner

    @ViewBuilder
    var notSupportedBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "apple.logo")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Not available on Apple Watch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(notSupportedDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

        // Connection details (read-only)
        if !profile.sshHost.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label(profile.sshHost, systemImage: "network")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !profile.sshUser.isEmpty {
                    Label(profile.sshUser, systemImage: "person")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    var notSupportedDetail: String {
        switch profile.type {
        case .virtualMachine:
            return "Virtual Machine connections are not supported on Apple Watch."
        case .container:
            return "Container connections are not supported on Apple Watch."
        case .native, .sshWaypipe, .sshTerminal:
            return ""
        }
    }

    // MARK: - Helpers

    var nativeStatusColor: Color {
        switch activeSession?.status {
        case .connected:    return .green
        case .connecting:   return .orange
        case .degraded:     return .yellow
        case .error:        return .red
        default:            return .secondary
        }
    }

    var nativeStatusText: String {
        switch activeSession?.status {
        case .connected:    return "Running"
        case .connecting:   return "Starting"
        case .disconnected: return "Stopped"
        case .degraded:     return "Degraded"
        case .error:        return "Error"
        case nil:           return "Ready"
        }
    }

    var sshStatusText: String {
        switch activeSession?.status {
        case .connected:    return "Connected"
        case .connecting:   return "Connecting"
        case .disconnected: return "Disconnected"
        case .degraded:     return "Degraded"
        case .error:        return "Error"
        case nil:           return "Ready"
        }
    }
}
