#if os(watchOS)
import SwiftUI
import WawonaModel
import WawonaUIContracts

/// One settings section. Environment, About, Dependencies, SSH, Waypipe,
/// Graphics, and iCloud Sync use dedicated pages. Remaining sections stay catalog rows.
/// The section accent tints every control on the page, dedicated or not.
struct WatchSettingsSectionPage: View {
    let section: GlobalSettingsSectionID
    @ObservedObject private var preferences = WawonaPreferences.shared

    var body: some View {
        // Environment tints its own rows so the search bar stays neutral.
        page
            .tint(section == .environment ? nil : WawonaSettingsHubChrome.accentColor(for: section))
    }

    @ViewBuilder
    private var page: some View {
        switch section {
        case .environment:
            WatchEnvironmentList(preferences: preferences)
        case .about:
            WatchAboutSettingsPage(preferences: preferences)
        case .dependencies:
            WatchDependenciesPage()
        case .ssh:
            WatchSSHSettingsPage(preferences: preferences)
        case .waypipe:
            WatchWaypipeSettingsPage(preferences: preferences)
        case .graphics:
            WatchGraphicsSettingsPage(preferences: preferences)
        case .iCloudSync:
            WatchICloudSyncSettingsPage()
        default:
            List {
                ForEach(GlobalSettingsCatalog.visibleFields(in: section, for: .watchOS), id: \.self) { field in
                    fieldRow(field)
                }
            }
            .navigationTitle(section.title)
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: GlobalSettingsFieldID) -> some View {
        switch field {
        case .forceSSD:
            Toggle("Force Server-Side Decorations", isOn: $preferences.forceSSD)
                .onChange(of: preferences.forceSSD) { _, _ in preferences.save() }
        case .respectSafeArea:
            Toggle("Respect Safe Area", isOn: $preferences.respectSafeArea)
                .onChange(of: preferences.respectSafeArea) { _, _ in preferences.save() }
        case .colorOperations:
            Toggle("Color Operations / HDR", isOn: $preferences.colorOperations)
                .onChange(of: preferences.colorOperations) { _, _ in preferences.save() }
        case .virtualCursor:
            Toggle("Show Virtual Cursor", isOn: $preferences.renderMacOSPointer)
                .onChange(of: preferences.renderMacOSPointer) { _, _ in preferences.save() }
        case .touchInputType:
            Picker("Touch Input Type", selection: $preferences.defaultInputProfile) {
                Text("Multi-Touch").tag("Multi-Touch")
                Text("Touchpad").tag("Touchpad")
            }
            .onChange(of: preferences.defaultInputProfile) { _, _ in preferences.save() }
        case .touchPointerEmulation:
            Toggle("Pointer for clients without touch", isOn: $preferences.touchPointerEmulation)
                .onChange(of: preferences.touchPointerEmulation) { _, _ in preferences.save() }
        case .swapCmdWithAlt:
            Toggle("Swap CMD / ALT", isOn: $preferences.swapCmdWithAlt)
                .onChange(of: preferences.swapCmdWithAlt) { _, _ in preferences.save() }
        case .resizeDisplayForVirtualKeyboard:
            Toggle("Resize for Virtual Keyboard", isOn: $preferences.resizeDisplayForVirtualKeyboard)
                .onChange(of: preferences.resizeDisplayForVirtualKeyboard) { _, _ in preferences.save() }
        case .universalClipboard:
            Toggle("Universal Clipboard", isOn: $preferences.universalClipboard)
                .onChange(of: preferences.universalClipboard) { _, _ in preferences.save() }
        case .nestedCompositors:
            Toggle("Nested Compositors", isOn: $preferences.nestedCompositorsSupport)
                .onChange(of: preferences.nestedCompositorsSupport) { _, _ in preferences.save() }
        case .compositorBackend:
            Picker("Display Backend", selection: $preferences.compositorBackend) {
                Text("Auto").tag("auto")
                Text("Wayland").tag("wayland")
                Text("DRM/KMS").tag("drm")
            }
            .onChange(of: preferences.compositorBackend) { _, _ in preferences.save() }
        case .multipleClients:
            Toggle("Multiple Clients", isOn: $preferences.multipleClients)
                .onChange(of: preferences.multipleClients) { _, _ in preferences.save() }
        case .shakeToClose:
            Toggle("Shake to Close", isOn: $preferences.shakeToCloseEnabled)
                .onChange(of: preferences.shakeToCloseEnabled) { _, _ in preferences.save() }
        case .swipeBackToClose:
            Toggle("Swipe Back to Exit Machine", isOn: $preferences.swipeBackToCloseEnabled)
                .onChange(of: preferences.swipeBackToCloseEnabled) { _, _ in preferences.save() }
        case .logLevel:
            Picker("Log Level", selection: $preferences.logLevel) {
                ForEach(["error", "warn", "info", "debug", "trace"], id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: preferences.logLevel) { _, _ in preferences.save() }
        default:
            EmptyView()
        }
    }
}
#endif
