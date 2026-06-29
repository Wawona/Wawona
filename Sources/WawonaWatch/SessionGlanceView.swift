#if os(watchOS)
import SwiftUI
import WawonaModel

struct SessionGlanceView: View {
    let session: MachineSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sent").foregroundStyle(.secondary)
                Spacer()
                Text("\(session.bytesSent) B")
            }
            HStack {
                Text("Received").foregroundStyle(.secondary)
                Spacer()
                Text("\(session.bytesReceived) B")
            }
        }
        .font(.caption2)
        .padding(8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
