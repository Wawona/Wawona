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
            if #available(iOS 14.0, tvOS 14.0, macOS 11.0, visionOS 1.0, *) {
                content.ignoresSafeArea(.container, edges: .trailing)
            } else {
                content.edgesIgnoringSafeArea(.trailing)
            }
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
    /// In-window Wayland session surface (tabbed Start). Sidebar Machines
    /// returns here to the grid; no floating overlay button on the client.
    case session
    /// Running clients; Focus opens the compositor deliberately.
    case tabOverview
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

    private var sessionSurfaceObserver: NSObjectProtocol?
    #if os(macOS)
    private var distributedSessionSurfaceObserver: NSObjectProtocol?
    #endif
    /// Lab remount / park: touch `$XDG_RUNTIME_DIR/show-session-surface` or
    /// `hide-session-surface` (macOS + iOS sim). Avoids lldb on live StaticCpu.
    private var sessionSurfaceFlagTimer: Timer?

    private init() {
        sessionSurfaceObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("WWNShowSessionSurfaceNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showSessionSurface()
        }
        #if os(macOS)
        // CLI `nix run .#wawona-microvm-session` is out-of-process; local NC
        // never reaches Regular UI. Distributed + runtime flag cover that path.
        distributedSessionSurfaceObserver = DistributedNotificationCenter.default()
            .addObserver(
                forName: Notification.Name("WWNShowSessionSurfaceNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.showSessionSurface()
            }
        #endif
        // Mode A StaticCpu / AUTO_START: if Machines chrome covers Metal again,
        // lab can remount without lldb by touching the runtime flag. Same timer
        // parks via `hide-session-surface` for N11 Stop without sidebar selection.
        sessionSurfaceFlagTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in
            self?.consumeSessionSurfaceFlagIfPresent()
        }
        if let sessionSurfaceFlagTimer {
            RunLoop.main.add(sessionSurfaceFlagTimer, forMode: .common)
        }
    }

    private func consumeSessionSurfaceFlagIfPresent() {
        let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
        let hideFlag = (runtime as NSString).appendingPathComponent("hide-session-surface")
        if FileManager.default.fileExists(atPath: hideFlag) {
            try? FileManager.default.removeItem(atPath: hideFlag)
            hideSessionSurface()
            NSLog("WWNHideSessionSurface: sessionSurfaceVisible=0 (flag)")
            return
        }
        let flag = (runtime as NSString).appendingPathComponent("show-session-surface")
        guard FileManager.default.fileExists(atPath: flag) else { return }
        try? FileManager.default.removeItem(atPath: flag)
        showSessionSurface()
    }

    func showMachines() {
        sessionSurfaceVisible = false
        selection = .machines
    }

    /// Metal host is in the tree (SHM/DRM drain). Distinct from visible chrome.
    @Published var sessionSurfaceMounted = false
    /// When true, the Wayland compositor fills the detail (Focus / Tab Overview).
    @Published var sessionSurfaceVisible = false

    /// Mount presenter without covering Machines / Terminal (Start path).
    func mountSessionSurface() {
        sessionSurfaceMounted = true
        NSLog("WWNMountSessionSurface: mounted=1 visible=%d", sessionSurfaceVisible ? 1 : 0)
    }

    func showSessionSurface() {
        // Global Settings replaces `machinesChrome` (CompositorBridge) with
        // `WWNGlobalSettingsHostView`. Leaving Settings up leaves
        // activeIlandPresenter nil forever: Mode A SHM imports but never
        // presents ("no IlandPresenter"). First-frame / AUTO_START must
        // dismiss Settings so Metal remounts.
        if isSettingsPresented {
            isSettingsPresented = false
        }
        // Wawona Terminal can start Wayland clients. Park Terminal chrome
        // (keep PTY) so Present is not covered; never require Done/Close.
        #if os(macOS)
        WWNMacGuestConsole.shared.parkForCompositor()
        #elseif os(iOS) || os(tvOS) || os(visionOS)
        // Router stays nonisolated for ObjC scene trampolines. Terminal
        // park is MainActor. This path runs on the main thread.
        MainActor.assumeIsolated {
            WWNIosGuestConsole.shared.parkForCompositor()
        }
        #endif
        sessionSurfaceMounted = true
        sessionSurfaceVisible = true
        selection = .session
        NSLog(
            "WWNShowSessionSurface: mounted=1 visible=1 selection=session settings=0"
        )
    }

    /// Park compositor chrome; keep session running until Stop.
    func hideSessionSurface() {
        NotificationCenter.default.post(
            name: Notification.Name("WWNCaptureActiveMachineThumbnailNotification"),
            object: nil
        )
        sessionSurfaceVisible = false
        selection = .machines
    }

    func showTabOverview() {
        // Snapshot thumb while Metal is still showing, then park chrome.
        // Do not Stop the shell / StaticCpu; do not tear down IlandPresenter.
        NotificationCenter.default.post(
            name: Notification.Name("WWNCaptureActiveMachineThumbnailNotification"),
            object: nil
        )
        #if os(iOS) || os(visionOS)
        MainActor.assumeIsolated {
            WWNIosGuestConsole.shared.parkForCompositor()
        }
        #endif
        sessionSurfaceVisible = false
        selection = .tabOverview
    }

    /// Dedicated Global Settings host replaces Machines chrome in the same
    /// window (never a sheet / PrefPane / Settings.app).
    @Published var isSettingsPresented = false
    /// True from the moment Settings is requested until Machines chrome
    /// owns the window toolbar again. Machines must not register search
    /// or toolbar items during this span.
    @Published var settingsOwnsWindowToolbar = false
    @Published var settingsSelection: GlobalSettingsSectionID?

    /// Opens Global Settings in-app (`wawona-global-settings-exclusive`).
    /// Slide-up animation is driven from the host view transition; this wraps
    /// the flag change in the shared spring.
    func showSettings() {
        sessionSurfaceVisible = false
        settingsOwnsWindowToolbar = true
        if settingsSelection == nil {
            settingsSelection = GlobalSettingsCatalog.visibleSections(
                for: GlobalSettingsCatalog.currentHost
            ).first
        }
        withAnimation(Self.settingsCoverAnimation) {
            isSettingsPresented = true
        }
    }

    func dismissSettings() {
        withAnimation(Self.settingsCoverAnimation) {
            isSettingsPresented = false
        }
        if case .settings? = selection {
            selection = .machines
        }
    }

    /// Shared spring for Settings cover (insert + remove). iOS 13-safe API.
    static var settingsCoverAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.88)
    }

    /// Deep-link into a Settings section inside the dedicated host.
    func selectSettings(title: String) {
        if let id = GlobalSettingsSectionID.allCases.first(where: {
            $0.title.caseInsensitiveCompare(title) == .orderedSame || $0.rawValue == title
        }) {
            settingsSelection = id
        }
        showSettings()
    }

    func selectTag(_ tagId: String) {
        selection = .machinesTag(tagId)
    }

    /// After `WWNPreferences` rebuilds its sections (auth method / cursor
    /// changes), drop settings selections that no longer exist.
    func validate(sections: [WWNPreferencesSection]) {
        if let id = settingsSelection,
           WawonaMainWindowView.objcSection(id, in: sections) == nil {
            settingsSelection = GlobalSettingsCatalog.visibleSections(
                for: GlobalSettingsCatalog.currentHost
            ).first
        }
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

/// Unified Machine Configuration window. Global Settings covers this chrome
/// in-window with a bottom slide (`WWNGlobalSettingsHostView` from gear /
/// Cmd-,). Never a sheet, PrefPane, or Settings.app host (macOS sheet
/// backport is a floating popup). Section list stays out of the Machines
/// sidebar.
struct WawonaMainWindowView: View {
    @ObservedObject var model: WWNSettingsValueModel
    @ObservedObject var router: WWNMainWindowRouter
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    var onConnect: (() -> Void)? = nil
    @ObservedObject private var tagStore = WWNMachineTagStore.shared
    #if os(iOS) || os(tvOS) || os(visionOS)
    @ObservedObject private var guestConsole = WWNIosGuestConsole.shared
    #endif

    @State private var tagEditorTag: WWNMachineTag?
    @State private var showTagEditor = false
    /// Sidebar column visibility. Phone portrait starts `.detailOnly` so
    /// Machines is the main view; the system sidebar toggle reveals the column.
    @State private var showSidebar = false
    /// List selection lives in `@State`, not `@Published`. Binding
    /// `List(selection:)` straight to `router.selection` exclusivity-crashes
    /// on iOS 16 NavigationSplitView (Display / Settings tap): AttributeGraph
    /// still reads the `ObservableObject` while `Published` writes.
    @State private var listSelection: WWNMainDestination? = .machines
    /// Machines `NavigationSplitView` and Settings `NavigationSplitView` share
    /// one `NSToolbar`. Inserting the sidebar toggle (or Done) while the other
    /// item is still registered throws, and AppKit turns that into SIGTRAP.
    /// Drop Machines chrome, let the bar go empty, then mount Settings.
    @State private var machinesSplitMounted = true
    @State private var settingsHostMounted = false
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    /// Bottom cover insert/remove. Same motion on every Apple target.
    /// Reduce Motion (UIKit/AppKit, iOS 13 floor): fade only.
    private var settingsCoverTransition: AnyTransition {
        if Self.accessibilityReduceMotionEnabled {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    private static var accessibilityReduceMotionEnabled: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        UIAccessibility.isReduceMotionEnabled
        #endif
    }

    /// System grouped / window background under the Settings cover.
    private var settingsCoverBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(tvOS)
        Color.black
        #else
        Color(UIColor.systemBackground)
        #endif
    }

    var body: some View {
        // Global Settings slides up over Machines (in-window cover). Never
        // sheet / fullScreenCover: on macOS that backport is a floating popup.
        //
        // Mode A StaticCpu: keep `machinesChrome` mounted under the cover so
        // CompositorBridge / IlandPresenter stay alive while Settings is up.
        ZStack {
            machinesChrome
                .allowsHitTesting(!router.isSettingsPresented)
                .accessibility(hidden: router.isSettingsPresented)

            if settingsHostMounted {
                WWNGlobalSettingsHostView(
                    model: model,
                    selection: $router.settingsSelection,
                    onDismiss: { router.dismissSettings() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Opaque so Machines does not show through mid-slide.
                .background(settingsCoverBackground.edgesIgnoringSafeArea(.all))
                .transition(settingsCoverTransition)
                .zIndex(1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("wawonaOpenInAppGlobalSettingsPanel")
        )) { _ in
            router.showSettings()
        }
        .backport.onChange(of: router.isSettingsPresented) { _, presented in
            if presented {
                router.settingsOwnsWindowToolbar = true
                machinesSplitMounted = false
                DispatchQueue.main.async {
                    settingsHostMounted = true
                }
            } else {
                settingsHostMounted = false
                DispatchQueue.main.async {
                    machinesSplitMounted = true
                    router.settingsOwnsWindowToolbar = false
                }
            }
        }
        .backport.onChange(of: model.sections) { _, newValue in
            DispatchQueue.main.async {
                router.validate(sections: newValue)
            }
        }
    }

    /// Machines home + session surface. Hidden while Global Settings is up.
    @ViewBuilder
    private var machinesChrome: some View {
        splitView
            .onAppear {
                listSelection = router.selection ?? .machines
                syncSplitColumns()
                #if os(iOS) || os(tvOS) || os(visionOS)
                guestConsole.startObservingIfNeeded()
                #endif
            }
            #if os(iOS) || os(tvOS) || os(visionOS)
            .modifier(
                WWNGuestConsoleHostModifier(
                    console: guestConsole,
                    sessionSurfaceMounted: router.sessionSurfaceMounted,
                    sessionSurfaceVisible: router.sessionSurfaceVisible
                )
            )
            #endif
            .backport.onChange(of: listSelection) { _, newValue in
                guard newValue != router.selection else { return }
                // Next turn: keep Published write off the List exclusivity window.
                DispatchQueue.main.async {
                    router.selection = newValue
                }
            }
            .backport.onChange(of: router.selection) { _, newValue in
                if listSelection != newValue {
                    listSelection = newValue
                }
                handleSelectionChange()
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
            .backport.onChange(of: router.sessionSurfaceVisible) { _, visible in
                if visible {
                    withAnimation { showSidebar = false }
                }
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

    @ViewBuilder
    private var splitView: some View {
        if !machinesSplitMounted {
            detail
        } else if #available(iOS 16.0, tvOS 16.0, macOS 13.0, *) {
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
        List(selection: $listSelection) {
            Section(header: Text("Machines")) {
                // TN3154: NavigationLink(value:) + .tag. Not Button (double chrome).
                sidebarRow(
                    destination: .machines,
                    title: "Machines",
                    systemImage: "desktopcomputer",
                    color: Self.machinesSidebarIndigo,
                    accessibilityID: WWNA11y.machinesRoot
                )
                sidebarRow(
                    destination: .tabOverview,
                    title: "Tab Overview",
                    systemImage: "square.on.square",
                    color: Self.tabOverviewSidebarBlue,
                    accessibilityID: "wwn.tabOverview"
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

    /// systemIndigo (Settings Machines / PreferencesSectionsBuilder).
    private static var machinesSidebarIndigo: Color {
        #if os(macOS)
        Color(nsColor: .systemIndigo)
        #else
        Color(UIColor.systemIndigo)
        #endif
    }

    /// systemBlue (Settings Display / SSH accent).
    private static var tabOverviewSidebarBlue: Color {
        #if os(macOS)
        Color(nsColor: .systemBlue)
        #else
        Color(UIColor.systemBlue)
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
        Group {
            if #available(iOS 16.0, tvOS 16.0, macOS 13.0, *) {
                NavigationLink(value: destination) {
                    sidebarRowLabel(
                        title: title,
                        systemImage: systemImage,
                        color: color,
                        tagColorHex: tagColorHex
                    )
                }
            } else {
                Button {
                    listSelection = destination
                } label: {
                    sidebarRowLabel(
                        title: title,
                        systemImage: systemImage,
                        color: color,
                        tagColorHex: tagColorHex
                    )
                }
            }
        }
        .tag(destination)
        .accessibility(identifier: accessibilityID ?? "")
        .accessibility(addTraits: listSelection == destination ? .isSelected : [])
    }

    /// Section-tinted SF Symbol + title (matches Global Settings sidebar).
    @ViewBuilder
    private func sidebarRowLabel(
        title: String,
        systemImage: String?,
        color: Color?,
        tagColorHex: String?
    ) -> some View {
        if let tagColorHex {
            HStack(spacing: 12) {
                WWNTagDot(colorHex: tagColorHex, size: 10)
                Text(title)
                Spacer(minLength: 0)
            }
        } else if let systemImage {
            WawonaSettingsHubChrome.hubRow(
                title: title,
                systemImage: systemImage,
                iconColor: color ?? .accentColor
            )
        } else {
            Text(title)
        }
    }

    // MARK: - Detail

    static func objcSection(
        _ id: GlobalSettingsSectionID,
        in sections: [WWNPreferencesSection]
    ) -> WWNPreferencesSection? {
        let a11y = id.objcAccessibilityIdentifier
        if let match = sections.first(where: { $0.accessibilityIdentifier == a11y }) {
            return match
        }
        return sections.first(where: {
            $0.title == id.title || $0.title == id.detailTitle
        })
    }

    private var detail: some View {
        Group {
            if case .projectStatus? = router.selection {
                WawonaProjectStatusView()
                    .backport.navigationTitle("Work Status")
            } else if case .settings(let id)? = router.selection {
                // Deep-link: swap Machines chrome for the in-window Settings host.
                Color.clear
                    .onAppear {
                        router.settingsSelection = id
                        router.showSettings()
                    }
            } else if case .tabOverview? = router.selection {
                // Keep CompositorBridge mounted under Tab Overview. Swapping
                // it out deinits IlandPresenter; Focus then remounts an empty
                // Metal layer (black) until the client paints again. Static
                // wasm like hello-wasi-gui often never repaints.
                ZStack {
                    if router.sessionSurfaceMounted {
                        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(visionOS))
                        CompositorBridge()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(0)
                            .allowsHitTesting(false)
                            .accessibility(hidden: true)
                        #endif
                    }
                    WWNTabOverviewView()
                }
            } else {
                machinesPane
            }
        }
    }

    private var isMachinesDestination: Bool {
        switch router.selection {
        case .machines?, .session?, .tabOverview?, .machinesTag?, nil: return true
        default: return false
        }
    }

    private var respectSafeArea: Bool {
        let global = WWNPreferencesManager.sharedManager().respectSafeArea()
        guard let id = WWNMachineProfileStore.activeMachineId(),
              let profile = WWNMachineProfileStore.profile(byId: id),
              let override = profile.runtimeOverrides["RespectSafeArea"] as? Bool
        else {
            return global
        }
        return override
    }

    private var machinesPane: some View {
        // Mount Metal when a Wayland/VM session needs the presenter (SHM drain).
        // Visible only after Focus / Tab Overview. Start keeps Machines + Terminal.
        ZStack {
            // visible implies mount. visible=1 + mounted=0 was a black empty
            // ZStack (no Metal, no Machines grid) during AUTO_START.
            if router.sessionSurfaceMounted || router.sessionSurfaceVisible {
                #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(visionOS))
                // macOS: stay inside contentLayoutRect so the titled / tabbed
                // chrome is not drawn over Wayland (weston-smoke / SHM).
                // iOS / visionOS: Respect Safe Area is applied on the pane.
                CompositorBridge()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(router.sessionSurfaceVisible ? 1 : 0)
                    .allowsHitTesting(router.sessionSurfaceVisible)
                    .accessibility(hidden: !router.sessionSurfaceVisible)
                #endif
            }
            if !router.sessionSurfaceVisible {
                WWNMachinesGridView(
                    onConnect: onConnect,
                    filterTagID: activeTagFilterID,
                    onClearTagFilter: { router.showMachines() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS) || os(visionOS)
        // Whole pane: Respect Safe Area off → edge-to-edge phone; on → notch/home inset.
        .modifier(WWNSessionSafeAreaModifier(
            respectSafeArea: respectSafeArea,
            sessionVisible: router.sessionSurfaceVisible
        ))
        .modifier(WWNSessionStatusBarModifier(
            hideStatusBar: router.sessionSurfaceVisible && !respectSafeArea
        ))
        #endif
        #if os(iOS) || os(tvOS) || os(visionOS)
        .navigationBarHidden(router.sessionSurfaceVisible)
        #endif
        #if os(iOS)
        .modifier(WWNSessionHideToolbarWhenVisible(active: router.sessionSurfaceVisible))
        #endif
        #if os(iOS) || os(visionOS)
        .modifier(WWNSessionSurfaceGestureModifier(
            showSidebar: $showSidebar,
            sessionVisible: router.sessionSurfaceVisible,
            onShakePark: {
                router.hideSessionSurface()
            }
        ))
        #endif
        // Sidebar Machines / tag / Tab Overview parks compositor chrome.
        .backport.onChange(of: router.selection) { _, newValue in
            switch newValue {
            case .machines?, .machinesTag?, .tabOverview?, .projectStatus?:
                if router.sessionSurfaceVisible {
                    router.sessionSurfaceVisible = false
                }
                #if os(iOS) || os(visionOS)
                if case .tabOverview? = newValue {
                    MainActor.assumeIsolated {
                        WWNIosGuestConsole.shared.parkForCompositor()
                    }
                }
                #endif
            default:
                break
            }
        }
        #if os(iOS) || os(visionOS)
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("WWNRespectSafeAreaChangedNotification")
        )) { _ in
            // Force SwiftUI to re-read respectSafeArea after Settings toggle.
            router.objectWillChange.send()
        }
        #endif
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
            // Defer column collapse off the selection write / AG update.
            DispatchQueue.main.async {
                withAnimation {
                    showSidebar = false
                }
            }
        }
        #endif
    }

    private func syncSplitColumns() {
        if router.selection == nil {
            router.selection = .machines
            listSelection = .machines
        }
        #if os(iOS)
        // Wayland fullscreen: no system sidebar toggle chrome.
        if router.sessionSurfaceVisible {
            showSidebar = false
        } else {
            showSidebar = !isPhonePortrait
        }
        #elseif os(visionOS)
        showSidebar = true
        #endif
    }
}

#if os(iOS) || os(tvOS) || os(visionOS)
/// Host Guest Console without killing Mode A Metal. A fullScreenCover can
/// dismantle CompositorHostView (deinit clears activeIlandPresenter) so SHM
/// present stops after one frame. Overlay while the session surface is mounted.
private struct WWNGuestConsoleHostModifier: ViewModifier {
    @ObservedObject var console: WWNIosGuestConsole
    let sessionSurfaceMounted: Bool
    let sessionSurfaceVisible: Bool

    func body(content: Content) -> some View {
        // Never fullScreenCover while a Relay/VM session needs Metal.
        // Cover dismantles CompositorHostView (deinit clears
        // activeIlandPresenter) and Mode A SHM present dies. Overlay only.
        // ZStack (not overlay{}) for iOS 13 floor.
        // A mapped Wayland client sets sessionSurfaceVisible. The Terminal
        // sheet must not stay above that surface until Done.
        return ZStack {
            content
            if console.isPresented && !console.windowed && !sessionSurfaceVisible {
                WWNIosGuestConsoleSheet(console: console)
            }
        }
    }
}
#endif
#endif
