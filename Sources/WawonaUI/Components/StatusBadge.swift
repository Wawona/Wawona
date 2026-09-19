import SwiftUI
import WawonaModel

struct StatusBadge: View {
    let status: MachineStatus

    var body: some View {
        Label(status.rawValue.capitalized, systemImage: icon)
            .font(.caption.weight(.semibold))
            .backport.foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var icon: String {
        switch status {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .disconnected: return "pause.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .blue
        case .degraded: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }
}
