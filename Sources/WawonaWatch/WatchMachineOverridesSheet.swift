import SwiftUI
import WawonaModel

/// Sheet wrapper so per-machine `MachineSettingsView` can be dismissed on watch.
struct WatchMachineOverridesSheet: View {
    let machineID: String
    @ObservedObject var profileStore: MachineProfileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MachineSettingsView(
                preferences: WawonaPreferences.shared,
                profileStore: profileStore,
                machineID: machineID
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
