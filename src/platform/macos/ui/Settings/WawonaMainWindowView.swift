#if os(macOS)
import AppKit
import SwiftUI

/// Destinations in the unified window sidebar.
enum WWNMainDestination: Hashable {
    case machines
    /// A settings section, keyed by its title (stable across section rebuilds).
    case settings(String)
}

/// Selection state shared between the SwiftUI window and the ObjC bridge
/// (`WWNUnifiedWindowController`), so menu items / the gear button can pick a
/// section in the same window.
@MainActor
final class WWNMainWindowRouter: ObservableObject {
    @Published var selection: WWNMainDestination = .machines

    func showMachines() {
        selection = .machines
    }

    func showSettings() {
        let first = WWNPreferences.shared().sections.first?.title ?? ""
        selection = first.isEmpty ? .machines : .settings(first)
    }

    func selectSettings(title: String) {
        let exists = WWNPreferences.shared().sections.contains { $0.title == title }
        selection = exists ? .settings(title) : .machines
    }

    /// After `WWNPreferences` rebuilds its sections (auth method / cursor
    /// changes), drop selections that no longer exist.
    func validate(sections: [WWNPreferencesSection]) {
        if case .settings(let title) = selection,
           !sections.contains(where: { $0.title == title }) {
            selection = .machines
        }
    }
}

/// The unified macOS window: Machine Configuration + the full Settings sidebar
/// in one SwiftUI `NavigationSplitView`. Replaces the standalone Machines
/// window and the AppKit settings window.
struct WawonaMainWindowView: View {
    @ObservedObject var model: WWNSettingsValueModel
    @ObservedObject var router: WWNMainWindowRouter

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Wawona")
        .onChange(of: model.sections) { _, newValue in
            router.validate(sections: newValue)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $router.selection) {
            Section {
                Label("Machine Configuration", systemImage: "desktopcomputer")
                    .tag(WWNMainDestination.machines)
                    .accessibilityIdentifier(WWNA11y.machinesRoot)
            } header: {
                Text("Machines")
            }

            Section("Settings") {
                ForEach(model.sections, id: \.title) { section in
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(systemName: section.icon)
                            .foregroundStyle(Color(nsColor: section.iconColor))
                    }
                    .tag(WWNMainDestination.settings(section.title))
                    .accessibilityIdentifier(
                        section.accessibilityIdentifier
                            ?? "wwn.settings.\(section.title.lowercased().replacingOccurrences(of: " ", with: "."))"
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch router.selection {
        case .machines:
            machinesPane
        case .settings(let title):
            if let section = model.sections.first(where: { $0.title == title }) {
                WWNSettingsSectionView(section: section, model: model)
            } else {
                ContentUnavailableView(
                    "Section Unavailable",
                    systemImage: "questionmark.circle",
                    description: Text("This settings section is no longer available.")
                )
            }
        }
    }

    /// The existing Machines grid (search / add / edit / launch), embedded as
    /// the first sidebar destination. The gear now jumps to Settings instead
    /// of opening a second window.
    private var machinesPane: some View {
        WWNMachinesGridView(
            onConnect: nil,
            onOpenSettings: { router.showSettings() }
        )
    }
}
#endif
