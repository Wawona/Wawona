#if os(iOS)
import SwiftUI
import WawonaModel

struct WWNAppleWatchTransfersSection: View {
    let summary: String
    let outstanding: [WatchOutstandingTransfer]

    var body: some View {
        Section {
            if outstanding.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Recent")
                    Spacer(minLength: 12)
                    Text(summary.isEmpty ? "None" : summary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                        .backport.secondaryForeground()
                }
                .frame(minHeight: 44, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibility(label: Text("Recent transfers, \(summary.isEmpty ? "None" : summary)"))
            } else {
                if !summary.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Status")
                        Spacer(minLength: 12)
                        Text(summary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                            .backport.secondaryForeground()
                    }
                    .frame(minHeight: 44, alignment: .center)
                }
                ForEach(outstanding) { transfer in
                    WWNAppleWatchTransferRow(name: transfer.name)
                }
            }
        } header: {
            Text("Transfers")
        } footer: {
            Text("Outstanding file transfers stay queued until the Watch is reachable.")
        }
    }
}
#endif
