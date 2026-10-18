#if os(watchOS)
import SwiftUI
import WawonaModel

struct WatchSectionRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(tint)
        }
        .accessibilityIdentifier(identifier)
    }
}
#endif
