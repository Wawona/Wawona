#if os(iOS)
import SwiftUI
import WawonaModel

struct WWNAppleWatchStatusSection: View {
    let status: WatchCompanionStatus

    var body: some View {
        Section {
            WWNAppleWatchStatusRow(title: "Paired", value: status.paired ? "Yes" : "No")
            WWNAppleWatchStatusRow(
                title: "Wawona on Watch",
                value: status.watchAppInstalled ? "Installed" : "Not Installed"
            )
            WWNAppleWatchStatusRow(title: "Reachable", value: status.reachable ? "Now" : "Later")
        } header: {
            Text("Companion")
        } footer: {
            Text(status.summary)
        }
    }
}
#endif
