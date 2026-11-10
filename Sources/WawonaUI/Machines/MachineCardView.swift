import SwiftUI
import WawonaModel

struct MachineCardView: View {
    let profile: MachineProfile
    let status: MachineStatus
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
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
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if !profile.launchers.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(profile.launchers) { launcher in
                                    Text(launcher.displayName)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                                }
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .wwnA11y(WawonaA11y.machinesCard(profile.id), label: profile.name)
    }

    var subtitle: String {
        switch profile.type {
        case MachineType.native: return "Runs on this host"
        case MachineType.wasm: return "Relay WASI (wasm / wpm)"
        case MachineType.sshWaypipe, MachineType.sshTerminal:
            return profile.sshHost.isEmpty ? "SSH host not configured" : "\(profile.sshUser)@\(profile.sshHost)"
        case MachineType.virtualMachine: return "Virtual machine profile"
        case MachineType.container: return "Container profile"
        }
    }
}
