#if os(watchOS)
import SwiftUI
import WatchKit
import WawonaUIContracts

/// Watch Global Settings live in the iPhone Watch app (`Settings-Watch.bundle`).
/// The wrist app must not host a second Global Settings catalog
/// (`wawona-global-settings-exclusive`).
enum WatchKitGlobalSettings {
    static let fallbackPresentationNeeded = Notification.Name("WWNWatchSettingsFallbackNeeded")

    static func registerHost() {}

    @discardableResult
    static func open() -> Bool {
        NotificationCenter.default.post(name: fallbackPresentationNeeded, object: nil)
        return true
    }
}

/// Points the user at the iPhone Watch app. Not a catalog host.
struct WatchGlobalSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Global Wawona Settings for Apple Watch are in the iPhone Watch app under My Watch → Wawona."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("wwn.settings.watch.redirect")
                }
            }
            .navigationTitle("Wawona Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
