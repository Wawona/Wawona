#if os(iOS)
import SwiftUI

/// Title / value row matching System Settings companion status lines.
struct WWNAppleWatchStatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .backport.secondaryForeground()
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibility(label: Text("\(title), \(value)"))
    }
}
#endif
