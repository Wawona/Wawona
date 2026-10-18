#if os(watchOS)
import SwiftUI
import WatchKit
import WawonaModel
import WawonaUIContracts

/// Watch Global Settings live in the wrist app (`wawona-global-settings-exclusive`).
/// Same `wawona.pref.*` keys as other targets. Container is `UserDefaults.standard`.
enum WatchKitGlobalSettings {
    static let fallbackPresentationNeeded = Notification.Name("WWNWatchSettingsFallbackNeeded")

    static func registerHost() {}

    @discardableResult
    static func open() -> Bool {
        NotificationCenter.default.post(name: fallbackPresentationNeeded, object: nil)
        return true
    }
}

/// In-app Global Settings. One row per catalog section. Pushed on the
/// Machines navigation stack. A sheet leaves the Machines toolbar in front
/// of these rows, so a tap on a covered row never opens the section.
struct WatchGlobalSettingsView: View {
    @State private var section: GlobalSettingsSectionID?

    private var sections: [GlobalSettingsSectionID] {
        GlobalSettingsCatalog.visibleSections(for: .watchOS)
    }

    var body: some View {
        List(sections, id: \.self) { id in
            // A NavigationLink here pushes the section twice on watchOS.
            Button {
                section = id
            } label: {
                Label(id.title, systemImage: id.systemImage)
                    .foregroundStyle(WawonaSettingsHubChrome.accentColor(for: id))
            }
            .accessibilityIdentifier(id.objcAccessibilityIdentifier)
        }
        .navigationTitle("Wawona Settings")
        .navigationDestination(item: $section) { id in
            WatchSettingsSectionPage(section: id)
        }
        .toolbar(.hidden, for: .bottomBar)
        .accessibilityIdentifier("wwn.settings.watch.catalog")
    }
}
#endif
