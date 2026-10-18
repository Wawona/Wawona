#if os(iOS)
import SwiftUI

struct WWNAppleWatchTransferRow: View {
    let name: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "arrow.up.circle")
                .foregroundColor(.secondary)
                .accessibility(hidden: true)
            Text(name)
                .lineLimit(2)
            Spacer(minLength: 12)
            Text("Sending")
                .backport.secondaryForeground()
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibility(label: Text("\(name), Sending"))
    }
}
#endif
