import SwiftUI
import WawonaModel

struct MachineCardView: View {
    let profile: MachineProfile
    let status: MachineStatus
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(profile.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    StatusBadge(status: status)
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

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

                MachineActionBar(items: [
                    MachineActionItem(
                        title: "Connect",
                        systemImage: "play.fill",
                        prominent: true,
                        accessibilityID: WawonaA11y.machinesConnect,
                        accessibilityLabel: "Connect",
                        action: onConnect
                    ),
                    MachineActionItem(
                        title: "Edit",
                        systemImage: "slider.horizontal.3",
                        accessibilityID: WawonaA11y.machinesEdit,
                        accessibilityLabel: "Edit",
                        action: onEdit
                    ),
                    MachineActionItem(
                        title: "Delete",
                        systemImage: "trash",
                        role: .destructive,
                        accessibilityID: WawonaA11y.machinesDelete,
                        accessibilityLabel: "Delete",
                        action: onDelete
                    ),
                ])
            }
        }
        .wwnA11y(WawonaA11y.machinesCard(profile.id), label: profile.name)
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
