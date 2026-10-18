#if os(watchOS)
import SwiftUI
import WawonaModel
import WawonaUIContracts

/// iCloud Sync on watchOS: CloudKit private database (iCloud Drive does not
/// exist on watchOS). Same records as the iPhone, iPad, Mac, TV, and Vision.
struct WatchICloudSyncSettingsPage: View {
    @ObservedObject private var cloud = WWNCloudSync.shared

    private var enabled: Binding<Bool> {
        Binding(get: { cloud.isEnabled }, set: { cloud.isEnabled = $0 })
    }

    var body: some View {
        List {
            Section {
                Toggle("iCloud Sync", isOn: enabled)
                    .accessibilityIdentifier("wwn.settings.iCloudSync.toggle")
            } footer: {
                Text("Machines, tags, pins, env vars, preferences, and HOME files follow your Apple ID. Passwords stay on this watch.")
            }

            Section {
                LabeledContent("Status", value: statusTitle)
                if let last = cloud.lastSync {
                    LabeledContent("Last Synced") {
                        Text(last, style: .relative)
                    }
                }
                if cloud.homeFileCount > 0 {
                    LabeledContent("HOME Files", value: "\(cloud.homeFileCount)")
                }
                Button {
                    Task { await cloud.syncNow() }
                } label: {
                    if cloud.status == .syncing {
                        HStack {
                            Text("Syncing")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Sync Now")
                    }
                }
                .disabled(!cloud.isEnabled || cloud.status == .syncing || !cloud.isEntitled)
                .accessibilityIdentifier("wwn.settings.iCloudSync.syncNow")
            } header: {
                Text("CloudKit")
            } footer: {
                Text(cloud.status.summary)
            }
        }
        .navigationTitle(GlobalSettingsSectionID.iCloudSync.title)
    }

    private var statusTitle: String {
        switch cloud.status {
        case .off: return "Off"
        case .idle: return "Up to Date"
        case .syncing: return "Syncing"
        case .failed: return "Error"
        case .notEntitled, .needsNewerOS, .unavailable: return "Unavailable"
        }
    }
}
#endif
