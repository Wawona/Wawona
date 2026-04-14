import SwiftUI
import WawonaModel

struct MachineCardView: View {
    let profile: MachineProfile
    let status: MachineStatus
    let onConnect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(profile.name)
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: status)
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !profile.launchers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(profile.launchers) { launcher in
                                Text(launcher.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                }

                HStack {
                    Button("Connect", action: onConnect)
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
        }
    }

    var subtitle: String {
        switch profile.type {
        case MachineType.native: return "Runs on this host"
        case MachineType.sshWaypipe, MachineType.sshTerminal:
            return profile.sshHost.isEmpty ? "SSH host not configured" : "\(profile.sshUser)@\(profile.sshHost)"
        case MachineType.virtualMachine: return "Virtual machine profile"
        case MachineType.container: return "Container profile"
        }
    }
}
