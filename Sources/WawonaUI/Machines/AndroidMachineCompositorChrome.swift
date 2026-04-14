import SwiftUI
import WawonaModel

#if SKIP && os(Android)
/// Full-screen compositor surface with a way to return to the machine list.
struct AndroidMachineCompositorChrome: View {
    let session: MachineSession
    @ObservedObject var sessions: SessionOrchestrator
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            CompositorBridge()
                .ignoresSafeArea()
            Button {
                sessions.disconnect(sessionId: session.id)
                NativeCompositorPrefs.clearLauncherFlags()
                onDismiss()
            } label: {
                Text("Close")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.22), in: Capsule())
            }
            .padding(.leading, 16)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
#endif
