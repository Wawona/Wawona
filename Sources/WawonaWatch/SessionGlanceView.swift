import SwiftUI
import WawonaModel

struct SessionGlanceView: View {
    let session: MachineSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statRow("Sent", bytes: session.bytesSent)
            statRow("Received", bytes: session.bytesReceived)
        }
        .font(.caption2)
        .padding(8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statRow(_ label: String, bytes: Int64) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(formatted(bytes)).fontWeight(.medium)
        }
    }

    private func formatted(_ bytes: Int64) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1_024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
