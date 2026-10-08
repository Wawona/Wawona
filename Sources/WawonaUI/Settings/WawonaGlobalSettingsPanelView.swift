#if !SWIFT_PACKAGE && (os(tvOS) || os(visionOS))
import SwiftUI
import WawonaModel
import WawonaUIContracts

/// In-app Global Settings for tvOS / visionOS only.
///
/// Those targets have no Settings.bundle / PrefPane. macOS uses PrefPane;
/// iOS / iPadOS use Settings.bundle. Never ship this panel beside an OS host
/// (`wawona-global-settings-exclusive`).
struct WawonaGlobalSettingsPanelView: View {
    @ObservedObject var model: WWNSettingsValueModel
    var onDismiss: (() -> Void)? = nil
    @State private var path = NavigationPath()

    private var panelSections: [WWNPreferencesSection] {
        let ids = GlobalSettingsCatalog.systemPanelSections(
            for: GlobalSettingsCatalog.currentHost
        )
        return ids.compactMap { id in
            WawonaMainWindowView.objcSection(id, in: model.sections)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    ForEach(
                        Array(panelSections.enumerated()),
                        id: \.element.accessibilityIdentifier
                    ) { _, section in
                        NavigationLink(value: section.accessibilityIdentifier) {
                            globalSettingsHubRow(section)
                        }
                        .accessibilityIdentifier(section.accessibilityIdentifier)
                    }
                } footer: {
                    Text(
                        "Global Settings live in the app on this platform. "
                            + "macOS and iPhone use System Settings instead."
                    )
                }
            }
            .formStyle(.grouped)
            .backport.navigationTitle("Wawona Settings")
            .navigationDestination(for: String.self) { sectionID in
                if let section = panelSections.first(where: {
                    $0.accessibilityIdentifier == sectionID
                }) {
                    globalSettingsSectionPage(section)
                } else {
                    Text("Section unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .backport.navigationActions(trailingIsPrimary: true, leading: {
                if let onDismiss {
                    WawonaButton("Done", action: onDismiss)
                        .wwnA11y(WWNA11y.settingsDone, label: "Done")
                } else {
                    EmptyView()
                }
            }, trailing: {
                EmptyView()
            })
        }
    }

    private func globalSettingsHubRow(_ section: WWNPreferencesSection) -> some View {
        WawonaSettingsHubChrome.hubRow(
            title: section.title,
            systemImage: section.icon.isEmpty
                ? WawonaSettingsHubChrome.systemImage(forSectionTitle: section.title)
                : section.icon,
            iconColor: section.swiftUIIconColor
        )
    }

    @ViewBuilder
    private func globalSettingsSectionPage(_ section: WWNPreferencesSection) -> some View {
        WWNSettingsSectionView(section: section, model: model)
            .backport.navigationTitle(section.title)
    }
}
#endif
