#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import WawonaUIContracts

#if os(iOS)
/// Phone overlay vs iPad/landscape balanced. Styles are distinct types,
/// so a ternary on `navigationSplitViewStyle` will not compile.
private struct WWNPhoneSplitStyle: ViewModifier {
    let isPhone: Bool

    func body(content: Content) -> some View {
        if isPhone {
            content.navigationSplitViewStyle(.prominentDetail)
        } else {
            content.navigationSplitViewStyle(.balanced)
        }
    }
}
#endif

#if os(iOS) || os(visionOS)
/// `.searchable` and settings `TextField`s keep a first responder after
/// `NavigationSplitView` column changes. End editing on the key window so
/// the host IME does not stay up on the sidebar.
enum WWNHostKeyboard {
    static func dismiss() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if windows.isEmpty {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
            return
        }
        windows.forEach { $0.endEditing(true) }
    }
}
#endif

/// Destinations in the unified window sidebar.
enum WWNMainDestination: Hashable {
    case machines
    /// Rust `settings_catalog` slug (`display`, `input`, …).
    case settings(GlobalSettingsSectionID)
    /// A tag-filtered machine list (Finder-style sidebar tag).
    case machinesTag(String)
}

/// Selection state shared between the SwiftUI window and the ObjC bridge
/// (`WWNUnifiedWindowController`), so menu items can pick a section in the
/// same window. Not `@MainActor`: ObjC scene-delegate trampolines construct
/// this on the main thread without a hop.
final class WWNMainWindowRouter: ObservableObject {
    static let shared = WWNMainWindowRouter()

    /// Always a destination. The iOS sidebar is a toggleable column, not a
    /// stack page, so nil (sidebar-as-root) is never used.
    @Published var selection: WWNMainDestination? = .machines

    func showMachines() {
        selection = .machines
    }

    func showSettings() {
        if let first = GlobalSettingsCatalog.visibleSections(for: GlobalSettingsCatalog.currentHost).first {
            selection = .settings(first)
        } else {
            selection = .machines
        }
    }

    func selectSettings(title: String) {
        if let id = GlobalSettingsSectionID.allCases.first(where: {
            $0.title.caseInsensitiveCompare(title) == .orderedSame || $0.rawValue == title
        }) {
            selection = .settings(id)
        } else {
            selection = .machines
        }
    }

    func selectTag(_ tagId: String) {
        selection = .machinesTag(tagId)
    }

    /// After `WWNPreferences` rebuilds its sections (auth method / cursor
    /// changes), drop selections that no longer exist.
    func validate(sections: [WWNPreferencesSection]) {
        if case .settings(let id)? = selection,
           WawonaMainWindowView.objcSection(id, in: sections) == nil {
            selection = .machines
        }
    }

    /// Drop a tag destination when the tag itself was deleted.
    func validateTags(_ tags: [WWNMachineTag]) {
        if case .machinesTag(let tagId)? = selection,
           !tags.contains(where: { $0.id == tagId }) {
            selection = .machines
        }
    }
}

extension WWNPreferencesSection {
    var swiftUIIconColor: Color {
        #if os(macOS)
        Color(nsColor: iconColor)
        #else
        Color(uiColor: iconColor)
        #endif
    }
}

/// Unified Machine Configuration + Settings sidebar.
/// Apple `NavigationSplitView` + `List(selection:)` + `.listStyle(.sidebar)`
/// on macOS, iOS, iPadOS, tvOS, and visionOS (TN3154). iPhone uses the same
/// sidebar column and toggle as iPad and macOS. Never a back-arrow stack to
/// a sidebar page. Watch stays on `WawonaWatch`.
struct WawonaMainWindowView: View {
    @ObservedObject var model: WWNSettingsValueModel
    @ObservedObject var router: WWNMainWindowRouter
    var onConnect: (() -> Void)? = nil
    @ObservedObject private var tagStore = WWNMachineTagStore.shared

    @State private var tagEditorTag: WWNMachineTag?
    @State private var showTagEditor = false
    /// Sidebar column visibility. Phone portrait starts `.detailOnly` so
    /// Machines is the main view; the system sidebar toggle reveals the column.
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var body: some View {
        splitView
            .onAppear { syncSplitColumns() }
            .onChange(of: router.selection) { _, _ in handleSelectionChange() }
            .onChange(of: model.sections) { _, newValue in
                router.validate(sections: newValue)
            }
            .onChange(of: tagStore.tags) { _, newValue in
                router.validateTags(newValue)
            }
            #if os(iOS) || os(visionOS)
            .onChange(of: horizontalSizeClass) { _, _ in syncSplitColumns() }
            .onChange(of: verticalSizeClass) { _, _ in syncSplitColumns() }
            .onChange(of: columnVisibility) { _, _ in
                WWNHostKeyboard.dismiss()
            }
            #endif
            #if !os(tvOS)
            .sheet(isPresented: $showTagEditor) {
                WWNTagEditorSheet(tag: tagEditorTag) { name, colorHex in
                    if let existing = tagEditorTag {
                        var updated = existing
                        updated.name = name
                        updated.colorHex = colorHex
                        tagStore.updateTag(updated)
                    } else {
                        tagStore.createTag(name: name, colorHex: colorHex)
                    }
                }
            }
            #endif
    }

    private var splitView: some View {
        #if os(iOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .modifier(WWNPhoneSplitStyle(isPhone: isPhoneIdiom))
        .environment(\.horizontalSizeClass, .regular)
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        #endif
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $router.selection) {
            Section("Machines") {
                sidebarRow(
                    destination: .machines,
                    title: "Machine Configuration",
                    systemImage: "desktopcomputer",
                    accessibilityID: WWNA11y.machinesRoot
                )
            }

            Section("Settings") {
                ForEach(catalogSections, id: \.self) { id in
                    let objc = WawonaMainWindowView.objcSection(id, in: model.sections)
                    sidebarRow(
                        destination: .settings(id),
                        title: id.title,
                        systemImage: id.systemImage,
                        color: objc?.swiftUIIconColor,
                        accessibilityID: objc?.accessibilityIdentifier ?? "wwn.settings.\(id.rawValue)"
                    )
                }
            }

            #if !os(tvOS)
            if !tagStore.tags.isEmpty {
                Section("Tags") {
                    ForEach(tagStore.tags) { tag in
                        sidebarRow(
                            destination: .machinesTag(tag.id),
                            title: tag.name,
                            tagColorHex: tag.colorHex
                        )
                        .contextMenu {
                            Button {
                                tagEditorTag = tag
                                showTagEditor = true
                            } label: {
                                Label("Edit Tag…", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                tagStore.deleteTag(id: tag.id)
                            } label: {
                                Label("Delete Tag", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            #endif
        }
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .listStyle(.sidebar)
        #endif
        .navigationTitle("Wawona")
        #if os(iOS) || os(visionOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
        #if os(macOS) || os(iOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        #endif
    }

    /// Apple TN3154: `List(selection:)` + `NavigationLink(value:)` + `.tag`.
    /// The split is always regular-width on iOS, so this highlights the row
    /// and swaps the detail column. It does not push a stack page.
    private func sidebarRow(
        destination: WWNMainDestination,
        title: String,
        systemImage: String? = nil,
        color: Color? = nil,
        tagColorHex: String? = nil,
        accessibilityID: String? = nil
    ) -> some View {
        NavigationLink(value: destination) {
            Label {
                Text(title)
            } icon: {
                if let tagColorHex {
                    WWNTagDot(colorHex: tagColorHex, size: 10)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(color ?? .accentColor)
                }
            }
        }
        .tag(destination)
        .accessibilityIdentifier(accessibilityID ?? "")
        .accessibilityAddTraits(router.selection == destination ? .isSelected : [])
    }

    // MARK: - Detail

    private var catalogSections: [GlobalSettingsSectionID] {
        GlobalSettingsCatalog.visibleSections(for: GlobalSettingsCatalog.currentHost)
    }

    fileprivate static func objcSection(
        _ id: GlobalSettingsSectionID,
        in sections: [WWNPreferencesSection]
    ) -> WWNPreferencesSection? {
        let a11y = id.objcAccessibilityIdentifier
        if let match = sections.first(where: { $0.accessibilityIdentifier == a11y }) {
            return match
        }
        return sections.first(where: { $0.title == id.title })
    }

    private var detail: some View {
        Group {
            if case .settings(let id)? = router.selection {
                if let section = Self.objcSection(id, in: model.sections) {
                    WWNSettingsSectionView(section: section, model: model)
                        .navigationTitle(id.title)
                } else {
                    ContentUnavailableView(
                        "Section Unavailable",
                        systemImage: "questionmark.circle",
                        description: Text("This settings section is no longer available.")
                    )
                }
            } else {
                machinesPane
            }
        }
    }

    private var machinesPane: some View {
        WWNMachinesGridView(
            onConnect: onConnect,
            filterTagID: activeTagFilterID,
            onClearTagFilter: { router.showMachines() }
        )
    }

    private var activeTagFilterID: String? {
        if case .machinesTag(let tagId)? = router.selection {
            return tagId
        }
        return nil
    }

    // MARK: - Split sizing

    #if os(iOS)
    /// Idiom, not size class. This view forces `.regular` on the split so
    /// Apple never collapses it into a stack.
    private var isPhoneIdiom: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Portrait phone: overlay sidebar + system toggle. Not a stack.
    private var isPhonePortrait: Bool {
        isPhoneIdiom && verticalSizeClass == .regular
    }
    #endif

    private func handleSelectionChange() {
        #if os(iOS) || os(visionOS)
        WWNHostKeyboard.dismiss()
        #endif
        #if os(iOS)
        if isPhonePortrait {
            withAnimation {
                columnVisibility = .detailOnly
            }
        }
        #endif
    }

    private func syncSplitColumns() {
        if router.selection == nil {
            router.selection = .machines
        }
        #if os(iOS)
        columnVisibility = isPhonePortrait ? .detailOnly : .all
        #elseif os(visionOS)
        columnVisibility = .all
        #endif
    }
}
#endif
