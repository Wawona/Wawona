#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import WawonaUIContracts
import WawonaModel

#if os(iOS)
/// Phone overlay vs iPad/landscape balanced. Styles are distinct types,
/// so a ternary on `navigationSplitViewStyle` will not compile.
@available(iOS 16.0, *)
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

/// Phone landscape reports the sensor housing on both horizontal edges so a
/// full-width view does not jump when the housing swaps sides. A sidebar
/// column only meets the leading screen edge. The opposite inset belongs
/// to the detail. Drop that mirrored trailing inset from this column.
private struct WWNPhoneLandscapeSidebarSafeArea: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .modifier(WWNIgnoreTrailingContainerSafeArea(active: active))
            .background(WWNSidebarColumnSafeAreaProbe())
    }
}

private struct WWNIgnoreTrailingContainerSafeArea: ViewModifier {
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.ignoresSafeArea(.container, edges: .trailing)
        } else {
            content
        }
    }
}

/// UIKit still copies the window's symmetric landscape insets onto the
/// primary column. Cancel the inner edge when that edge does not touch
/// the screen's unsafe region. Negative `additionalSafeAreaInsets` shrink
/// the system inset (UIKit adds them to the safe area).
private struct WWNSidebarColumnSafeAreaProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> WWNSidebarSafeAreaProbeView {
        let view = WWNSidebarSafeAreaProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: WWNSidebarSafeAreaProbeView, context: Context) {
        uiView.sync()
    }
}

private final class WWNSidebarSafeAreaProbeView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        sync()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        sync()
    }

    func sync() {
        guard #available(iOS 14.0, *),
              let split: UISplitViewController = ancestor(),
              let primary = split.viewController(for: .primary),
              primary.viewIfLoaded != nil
        else { return }

        let phone = UIDevice.current.userInterfaceIdiom == .phone
        let landscape = window?.windowScene?.interfaceOrientation.isLandscape == true
        guard phone, landscape, let window else {
            clearHorizontal(primary)
            return
        }

        guard let column = primary.viewIfLoaded else { return }
        let frame = column.convert(column.bounds, to: window)
        guard frame.width > 1, frame.height > 1 else { return }
        let windowInsets = window.safeAreaInsets
        let innerIsPhysicalRight =
            column.effectiveUserInterfaceLayoutDirection != .rightToLeft
        let geometricInner: CGFloat
        let currentInner: CGFloat
        let applied: CGFloat
        if innerIsPhysicalRight {
            geometricInner = max(0, frame.maxX - (window.bounds.width - windowInsets.right))
            currentInner = column.safeAreaInsets.right
            applied = primary.additionalSafeAreaInsets.right
        } else {
            geometricInner = max(0, windowInsets.left - frame.minX)
            currentInner = column.safeAreaInsets.left
            applied = primary.additionalSafeAreaInsets.left
        }
        let systemInner = currentInner - applied
        let extra = systemInner - geometricInner
        let cancel: CGFloat = extra > 1 ? -extra : 0
        var next = primary.additionalSafeAreaInsets
        if innerIsPhysicalRight {
            guard abs(next.right - cancel) > 0.5 || next.left != 0 else { return }
            next.right = cancel
            next.left = 0
        } else {
            guard abs(next.left - cancel) > 0.5 || next.right != 0 else { return }
            next.left = cancel
            next.right = 0
        }
        primary.additionalSafeAreaInsets = next
    }

    private func clearHorizontal(_ primary: UIViewController) {
        var next = primary.additionalSafeAreaInsets
        guard next.left != 0 || next.right != 0 else { return }
        next.left = 0
        next.right = 0
        DispatchQueue.main.async {
            guard primary.viewIfLoaded != nil else { return }
            primary.additionalSafeAreaInsets = next
        }
    }

    private func ancestor<T: UIResponder>() -> T? {
        var responder: UIResponder? = self
        while let current = responder {
            if let found = current as? T { return found }
            responder = current.next
        }
        return nil
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

private struct WWNSidebarToggleKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var wwnSidebarToggle: (() -> Void)? {
        get { self[WWNSidebarToggleKey.self] }
        set { self[WWNSidebarToggleKey.self] = newValue }
    }
}

/// Destinations in the unified window sidebar.
enum WWNMainDestination: Hashable {
    case machines
    case projectStatus
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

    /// Opens Global Settings via the sole host for this platform
    /// (`wawona-global-settings-exclusive`). Sidebar Destinations stay
    /// Desktop / About / Dependencies only (not Global Settings).
    /// tvOS / visionOS: in-app panel. macOS PrefPane. iOS Settings.app.
    @Published var showGlobalSettingsPanel = false

    func showSettings() {
        #if os(macOS)
        WawonaSystemSettings.openPreferencePane()
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        #else
        // tvOS / visionOS only: in-app Global Settings.
        showGlobalSettingsPanel = true
        #endif
    }

    /// In-app sidebar Settings destination (Desktop / About / Dependencies).
    func showSidebarSettings() {
        if let first = GlobalSettingsCatalog.appSidebarSections(
            for: GlobalSettingsCatalog.currentHost
        ).first {
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
        Color(iconColor)
        #endif
    }
}

/// Unified Machine Configuration + Settings sidebar.
/// Apple `NavigationSplitView` + `List(selection:)` + `.backport.sidebarList()`
/// on macOS, iOS, iPadOS, tvOS, and visionOS (TN3154). iPhone uses the same
/// sidebar column and toggle as iPad and macOS. Never a back-arrow stack to
/// a sidebar page. Watch stays on `WawonaWatch`.
struct WawonaMainWindowView: View {
    @ObservedObject var model: WWNSettingsValueModel
    @ObservedObject var router: WWNMainWindowRouter
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    var onConnect: (() -> Void)? = nil
    @ObservedObject private var tagStore = WWNMachineTagStore.shared

    @State private var tagEditorTag: WWNMachineTag?
    @State private var showTagEditor = false
    /// Sidebar column visibility. Phone portrait starts `.detailOnly` so
    /// Machines is the main view; the system sidebar toggle reveals the column.
    @State private var showSidebar = false
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var body: some View {
        splitView
            .onAppear { syncSplitColumns() }
            .backport.onChange(of: router.selection) { _, _ in handleSelectionChange() }
            .backport.onChange(of: model.sections) { _, newValue in
                DispatchQueue.main.async {
                    router.validate(sections: newValue)
                }
            }
            .backport.onChange(of: tagStore.tags) { _, newValue in
                DispatchQueue.main.async {
                    router.validateTags(newValue)
                }
            }
            #if os(iOS) || os(visionOS)
            .backport.onChange(of: horizontalSizeClass) { _, _ in syncSplitColumns() }
            .backport.onChange(of: verticalSizeClass) { _, _ in syncSplitColumns() }
            .backport.onChange(of: showSidebar) { _, _ in
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
            #if os(tvOS) || os(visionOS)
            .sheet(isPresented: $router.showGlobalSettingsPanel) {
                WawonaBackport<Any>.navigation {
                    WawonaGlobalSettingsPanelView(
                        model: model,
                        onDismiss: { router.showGlobalSettingsPanel = false }
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("wawonaOpenInAppGlobalSettingsPanel")
            )) { _ in
                router.showGlobalSettingsPanel = true
            }
            #endif
    }

    @ViewBuilder
    private var splitView: some View {
        if #available(iOS 16.0, tvOS 16.0, macOS 13.0, *) {
            NavigationSplitView(columnVisibility: Binding(
                get: { showSidebar ? .all : .detailOnly },
                set: { showSidebar = $0 != .detailOnly }
            )) {
                sidebar
            } detail: {
                detail
            }
            #if os(iOS)
            .modifier(WWNPhoneSplitStyle(isPhone: isPhoneIdiom))
            .environment(\.horizontalSizeClass, .regular)
            #endif
        } else {
            HStack(spacing: 0) {
                if showSidebar {
                    sidebar.frame(width: 240)
                    Divider()
                }
                WawonaBackport<Any>.navigation {
                    if isMachinesDestination {
                        detail
                    } else {
                        detail.backport.navigationActions {
                            Button { withAnimation { showSidebar.toggle() } } label: {
                                Image(systemName: "list.bullet")
                            }.backport.accessibilityLabel("Toggle Sidebar")
                        } trailing: { EmptyView() }
                    }
                }
                .environment(\.wwnSidebarToggle, { withAnimation { showSidebar.toggle() } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $router.selection) {
            Section(header: Text("Machines")) {
                sidebarRow(
                    destination: .machines,
                    title: "Machines",
                    systemImage: "desktopcomputer",
                    color: .indigo,
                    accessibilityID: WWNA11y.machinesRoot
                )
            }

            Section(header: Text("Project")) {
                sidebarRow(
                    destination: .projectStatus,
                    title: "Work Status",
                    systemImage: "chart.bar.xaxis",
                    color: .orange,
                    accessibilityID: "wwn.projectStatus"
                )
            }

            Section(header: Text("Settings")) {
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
                Section(header: Text("Tags")) {
                    ForEach(tagStore.tags) { tag in
                        sidebarRow(
                            destination: .machinesTag(tag.id),
                            title: tag.name,
                            tagColorHex: tag.colorHex
                        )
                        .contextMenu {
                            WawonaButton {
                                tagEditorTag = tag
                                showTagEditor = true
                            } label: {
                                WawonaLabel("Edit Tag…", systemImage: "pencil")
                            }
                            WawonaButton(role: .destructive) {
                                tagStore.deleteTag(id: tag.id)
                            } label: {
                                WawonaLabel("Delete Tag", systemImage: "trash")
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
        .backport.sidebarList()
        #endif
        .backport.navigationTitle("Wawona")
        #if os(iOS)
        .backport.dismissKeyboardOnScroll()
        #endif
        #if os(macOS) || os(iOS)
        .backport.sidebarWidth()
        #endif
        #if os(iOS)
        .modifier(WWNPhoneLandscapeSidebarSafeArea(active: isPhoneLandscape))
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
        let sidebarLabel = WawonaLabel {
            Text(title)
        } icon: {
            if let tagColorHex {
                WWNTagDot(colorHex: tagColorHex, size: 10)
            } else if let systemImage {
                Image(systemName: systemImage).foregroundColor(color ?? .accentColor)
            }
        }
        return Group {
            if #available(iOS 16.0, tvOS 16.0, macOS 13.0, *) {
                NavigationLink(value: destination) { sidebarLabel }
            } else {
                Button { router.selection = destination } label: { sidebarLabel }
            }
        }
        .tag(destination)
        .accessibility(identifier: accessibilityID ?? "")
        .accessibility(addTraits: router.selection == destination ? .isSelected : [])
    }

    // MARK: - Detail

    /// In-app sidebar: Desktop, About, Dependencies only.
    private var catalogSections: [GlobalSettingsSectionID] {
        var sections = GlobalSettingsCatalog.appSidebarSections(
            for: GlobalSettingsCatalog.currentHost
        )
        #if WWN_MODE_B && os(iOS)
        if !sections.contains(.desktop) {
            sections.insert(.desktop, at: 0)
        }
        #endif
        return sections
    }

    static func objcSection(
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
            if case .projectStatus? = router.selection {
                WawonaProjectStatusView()
                    .backport.navigationTitle("Work Status")
            } else if case .settings(let id)? = router.selection {
                if let section = Self.objcSection(id, in: model.sections) {
                    WWNSettingsSectionView(section: section, model: model)
                        .backport.navigationTitle(id.title)
                } else {
                    WawonaEmptyState(
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

    private var isMachinesDestination: Bool {
        switch router.selection {
        case .machines?, .machinesTag?, nil: return true
        default: return false
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

    /// Landscape phone. Height is compact. The sensor housing is on one
    /// side, but UIKit's safe area is symmetric.
    private var isPhoneLandscape: Bool {
        isPhoneIdiom && verticalSizeClass == .compact
    }
    #endif

    private func handleSelectionChange() {
        #if os(iOS) || os(visionOS)
        WWNHostKeyboard.dismiss()
        #endif
        #if os(iOS)
        if isPhonePortrait {
            withAnimation {
                showSidebar = false
            }
        }
        #endif
    }

    private func syncSplitColumns() {
        if router.selection == nil {
            router.selection = .machines
        }
        #if os(iOS)
        showSidebar = !isPhonePortrait
        #elseif os(visionOS)
        showSidebar = true
        #endif
    }
}
#endif
