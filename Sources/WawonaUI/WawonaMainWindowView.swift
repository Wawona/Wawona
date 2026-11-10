#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import UIKit
#endif
import SwiftUI
import WawonaUIContracts
import WawonaModel

#if os(macOS)
/// Client tabs live under Tab Overview only. AppKit window tabs on the
/// Machines / Settings host look like a second chrome strip (title + Close
/// tab) and fight the Settings Done toolbar.
enum WWNMacMainWindowTabbing {
    static func disallow() {
        NSWindow.allowsAutomaticWindowTabbing = false
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
            // Hide the AppKit tab strip even when only one tab remains.
            if let group = window.tabGroup, group.isTabBarVisible {
                window.toggleTabBar(nil)
            }
        }
    }

    /// WindowGroup uses `.windowToolbarStyle(.unified(showsTitle: true))`.
    /// Settings cover must not leave a separated titlebar after remount.
    static func ensureUnifiedToolbar() {
        disallow()
        for window in NSApp.windows {
            guard window.isVisible || window.isKeyWindow else { continue }
            window.toolbarStyle = .unified
            window.titleVisibility = .visible
        }
    }
}

/// Drop the Machines `NavigationSplitView` sidebar toggle from NSToolbar while
/// Global Settings owns Done / Env Vars Add (avoids dual-insert SIGTRAP).
private struct WWNMacStripSidebarToggleWhenSettings: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active, #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}
#endif

/// Bottom cover slide driven by `presented` while the host stays mounted.
/// Unmount after spring so Done does not hard-pop the cover.
private struct WWNSettingsCoverPresentation: ViewModifier {
    let presented: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let travel = max(geo.size.height, 1)
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(y: coverOffset(height: travel))
                .opacity(coverOpacity)
        }
    }

    private var coverOpacity: Double {
        if reduceMotion { return presented ? 1 : 0 }
        return 1
    }

    private func coverOffset(height: CGFloat) -> CGFloat {
        if reduceMotion { return 0 }
        return presented ? 0 : height
    }
}

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
    /// Safari-style Tab Overview card grid (toolbar button, not a sidebar row).
    case tabOverview
    /// One nested Wayland toplevel under the expandable "N Tabs" section.
    case clientTab(UInt64)
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
        #if os(macOS)
        if sessionShowsEmbeddedTerminal {
            WWNMacGuestConsole.shared.endMainWindowEmbed(restoreWindow: false)
            sessionShowsEmbeddedTerminal = false
        }
        #endif
        sessionSurfaceVisible = false
        selection = .machines
    }

    /// Metal host is in the tree (SHM/DRM drain). Distinct from visible chrome.
    @Published var sessionSurfaceMounted = false
    /// When true, the Wayland compositor fills the detail (Focus / Tab Overview).
    @Published var sessionSurfaceVisible = false
    /// Focus for Terminal-only Native Shell: TermSurface fills Present (not empty Metal).
    @Published var sessionShowsEmbeddedTerminal = false

    /// Mount presenter without covering Machines / Terminal (Start path).
    func mountSessionSurface() {
        sessionSurfaceMounted = true
        NSLog("WWNMountSessionSurface: mounted=1 visible=%d", sessionSurfaceVisible ? 1 : 0)
    }

    /// Focus when there is no nested Wayland toplevel: paint Wawona Terminal
    /// in the main window Present area instead of empty CompositorHostView.
    func showTerminalSessionSurface() {
        if isSettingsPresented {
            isSettingsPresented = false
        }
        #if os(macOS)
        sessionShowsEmbeddedTerminal = true
        sessionSurfaceMounted = true
        sessionSurfaceVisible = true
        selection = .tabOverview
        WWNMacGuestConsole.shared.beginMainWindowEmbed()
        NSLog("WWNShowTerminalSessionSurface: embedded TermSurface in main Present")
        #else
        showSessionSurface()
        #endif
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
        if sessionShowsEmbeddedTerminal {
            WWNMacGuestConsole.shared.endMainWindowEmbed(restoreWindow: false)
            sessionShowsEmbeddedTerminal = false
        }
        WWNMacGuestConsole.shared.parkForCompositor()
        // Default Start Type = New Window: Present stays in the dedicated
        // session window. Machines chrome must not grow a global tab bar.
        // Router is not @MainActor (ObjC trampolines); this path is main.
        let deferredWindow = MainActor.assumeIsolated {
            WWNSessionWindowPresenter.orderFrontSessionWindowIfOpen()
        }
        if deferredWindow {
            sessionSurfaceVisible = false
            NSLog("WWNShowSessionSurface: deferred to New Window session")
            return
        }
        #elseif os(iOS) || os(tvOS) || os(visionOS)
        // Router stays nonisolated for ObjC scene trampolines. Terminal
        // park is MainActor. This path runs on the main thread.
        MainActor.assumeIsolated {
            WWNIosGuestConsole.shared.parkForCompositor()
        }
        #endif
        sessionSurfaceMounted = true
        sessionSurfaceVisible = true
        // Tabbed Present lives under Tab Overview chrome (not Machines).
        // Prefer the focused nested client so Focus / attach shows Metal,
        // not the parked card grid. Overview button parks Present later.
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
        let store = WWNNestedClientTabStore.shared
        if let focused = store.focusedId {
            selection = .clientTab(focused)
        } else if let first = store.nestedTabs.first {
            selection = .clientTab(first.id)
        } else {
            selection = .tabOverview
        }
        #else
        selection = .tabOverview
        #endif
        NSLog(
            "WWNShowSessionSurface: mounted=1 visible=1 selection=%@ settings=0",
            String(describing: selection)
        )
    }

    /// Park compositor chrome; keep session running until Stop.
    func hideSessionSurface() {
        NotificationCenter.default.post(
            name: Notification.Name("WWNCaptureActiveMachineThumbnailNotification"),
            object: nil
        )
        #if os(macOS)
        if sessionShowsEmbeddedTerminal {
            WWNMacGuestConsole.shared.endMainWindowEmbed(restoreWindow: true)
            sessionShowsEmbeddedTerminal = false
        }
        #endif
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
        #if os(macOS)
        if sessionShowsEmbeddedTerminal {
            WWNMacGuestConsole.shared.endMainWindowEmbed(restoreWindow: true)
            sessionShowsEmbeddedTerminal = false
        }
        #endif
        #if os(iOS) || os(tvOS) || os(visionOS)
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
    /// Host view is in the ZStack. Must become true **before** the slide so
    /// Machines does not fade to a blank window.
    @Published var settingsHostMounted = false
    @Published var settingsSelection: GlobalSettingsSectionID?

    /// Opens Global Settings in-app (`wawona-global-settings-exclusive`).
    /// Mount off-screen first, then spring so open slides up (not a pop).
    func showSettings() {
        sessionSurfaceVisible = false
        settingsOwnsWindowToolbar = true
        if settingsSelection == nil {
            settingsSelection = GlobalSettingsCatalog.visibleSections(
                for: GlobalSettingsCatalog.currentHost
            ).first
        }
        // Mount under the fold, then animate present. Pairing both as true in
        // one shot left the cover at offset 0 with no slide-in.
        if !settingsHostMounted {
            settingsHostMounted = true
            isSettingsPresented = false
        }
        withAnimation(Self.settingsCoverAnimation) {
            isSettingsPresented = true
        }
    }

    func dismissSettings() {
        // Slide the cover down first; keep it mounted so the motion is not a
        // hard pop. Unmount + reclaim toolbar after the spring settles.
        withAnimation(Self.settingsCoverAnimation) {
            isSettingsPresented = false
        }
        if case .settings? = selection {
            selection = .machines
        }
        let delay = Self.settingsCoverUnmountDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isSettingsPresented else { return }
            self.settingsHostMounted = false
            self.settingsOwnsWindowToolbar = false
        }
    }

    /// Shared spring for Settings cover (insert + remove). iOS 13-safe API.
    static var settingsCoverAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.88)
    }

    /// Slightly past spring settle so Done does not pop Machines mid-slide.
    static var settingsCoverUnmountDelay: TimeInterval { 0.48 }

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
    /// macOS / tvOS / visionOS keep the Machines sidebar (Tab Overview lives
    /// there). Leaving this false on macOS made NavigationSplitView stay
    /// `.detailOnly`, so Tab Overview looked missing / dead.
    #if os(iOS)
    @State private var showSidebar = false
    #else
    @State private var showSidebar = true
    #endif
    /// List selection lives in `@State`, not `@Published`. Binding
    /// `List(selection:)` straight to `router.selection` exclusivity-crashes
    /// on iOS 16 NavigationSplitView (Display / Settings tap): AttributeGraph
    /// still reads the `ObservableObject` while `Published` writes.
    @State private var listSelection: WWNMainDestination? = .machines
    #if os(tvOS)
    /// The floating split sidebar does not take focus when it opens. Route it.
    @FocusState private var tvSidebarFocus: WWNMainDestination?
    #endif
    /// Settings cover sits above Machines. Keep the Machines split **mounted**
    /// so WindowGroup unified titlebar/toolbar stays intact; strip Machines
    /// toolbar items via `settingsOwnsWindowToolbar` and hide the split under
    /// the cover (opacity + hit testing). Unmounting the split used to empty
    /// NSToolbar safely for Env Vars Add, but broke unified chrome.
    /// Mount flag lives on `router` so open mounts before the slide.
    @ObservedObject private var nestedTabs = WWNNestedClientTabStore.shared
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
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
        // Mode A StaticCpu: Machines split stays mounted (Metal Present host
        // alive). `settingsOwnsWindowToolbar` strips Machines searchable /
        // toolbar items and sidebar toggle so Settings Done / Env Vars Add
        // own NSToolbar without SIGTRAP, and unified titlebar stays.
        ZStack {
            machinesChrome
                .opacity(router.isSettingsPresented ? 0 : 1)
                .allowsHitTesting(!router.isSettingsPresented)
                .accessibility(hidden: router.isSettingsPresented)
                #if os(tvOS)
                // Opacity and hit testing do not gate the focus engine. Without
                // this the Remote can focus (and toggle) hidden Machines chrome.
                .disabled(router.isSettingsPresented)
                #endif
                #if os(macOS)
                .modifier(WWNMacStripSidebarToggleWhenSettings(
                    active: router.settingsOwnsWindowToolbar
                ))
                #endif

            if router.settingsHostMounted {
                WWNGlobalSettingsHostView(
                    model: model,
                    selection: $router.settingsSelection,
                    onDismiss: { router.dismissSettings() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Opaque so Machines does not show through mid-slide.
                .background(settingsCoverBackground.edgesIgnoringSafeArea(.all))
                // Drive slide from isSettingsPresented so Done keeps the host
                // mounted through the spring (transition alone pops on unmount).
                .modifier(WWNSettingsCoverPresentation(
                    presented: router.isSettingsPresented,
                    reduceMotion: Self.accessibilityReduceMotionEnabled
                ))
                .zIndex(1)
                .allowsHitTesting(router.isSettingsPresented)
                #if os(tvOS)
                .disabled(!router.isSettingsPresented)
                #endif
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("wawonaOpenInAppGlobalSettingsPanel")
        )) { _ in
            router.showSettings()
        }
        .backport.onChange(of: router.isSettingsPresented) { _, presented in
            #if os(macOS)
            if presented {
                WWNMacMainWindowTabbing.ensureUnifiedToolbar()
            } else {
                // Toolbar reclaim after cover settles (see dismissSettings delay).
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + WWNMainWindowRouter.settingsCoverUnmountDelay
                ) {
                    if !router.isSettingsPresented {
                        WWNMacMainWindowTabbing.ensureUnifiedToolbar()
                    }
                }
            }
            #else
            _ = presented
            #endif
        }
        #if os(macOS)
        .onAppear { WWNMacMainWindowTabbing.ensureUnifiedToolbar() }
        #endif
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
                #if os(tvOS)
                // Must start before Terminal exclusive overlay. tabOverviewPane
                // never appears while Guest Console replaces Machines chrome,
                // so Menu / shake notifications would never fire from there.
                GameControllerBridge.sharedManager().start()
                #endif
            }
            #if os(tvOS)
            .onReceive(NotificationCenter.default.publisher(for: .WWNTvRemoteMenuBeganNotification)) { _ in
                tvosHandleRemoteMenu()
            }
            .onReceive(NotificationCenter.default.publisher(for: .WWNTvRemoteShakeNotification)) { _ in
                guard WWNMachineProfileStore.resolvedShakeToCloseActive() else { return }
                tvosHandleRemoteMenu()
            }
            #endif
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
        #if os(tvOS)
        // Adopting Liquid Glass (WWDC25 / SDK 26): system NavigationSplitView
        // owns the floating glass sidebar. Never replace with an opaque HStack.
        // columnVisibility Binding (not `.constant(.all)`) restores Hide/Show.
        // tvOS: never backgroundExtensionEffect (mirrors title strip + leading edge).
        if #available(tvOS 16.0, *) {
            NavigationSplitView(columnVisibility: Binding(
                get: { showSidebar ? .all : .detailOnly },
                set: { showSidebar = $0 != .detailOnly }
            )) {
                sidebar
                    .backport.sidebarWidth()
                    .focusSection()
                    .onMoveCommand { direction in
                        if direction == .right { withAnimation { showSidebar = false } }
                    }
            } detail: {
                NavigationStack {
                    detail
                        // The Left-edge sidebar peek never takes focus, and Up
                        // cannot reach the toolbar toggle. Menu opens the sidebar;
                        // Menu from the sidebar still exits to the Home screen.
                        .onExitCommand(perform: revealTvSidebar)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    withAnimation {
                                        showSidebar.toggle()
                                    }
                                } label: {
                                    Label(
                                        showSidebar ? "Hide Sidebar" : "Show Sidebar",
                                        systemImage: "sidebar.leading"
                                    )
                                }
                                .accessibility(identifier: "wwn.sidebar.toggle")
                                .accessibility(label: Text(
                                    showSidebar ? "Hide Sidebar" : "Show Sidebar"
                                ))
                            }
                        }
                        // While the sidebar overlays it, a focusable detail (toolbar
                        // toggle included) pulls Up/Down out of the sidebar and the
                        // system collapses it. Disable after `.toolbar` so the item
                        // inherits it.
                        .disabled(showSidebar)
                        .focusSection()
                }
            }
            .preferredColorScheme(.dark)
            .backport.onChange(of: router.sessionSurfaceVisible) { _, visible in
                // Present: park sidebar (detailOnly) so Metal is not under glass.
                if visible {
                    withAnimation { showSidebar = false }
                }
            }
            .backport.onChange(of: showSidebar) { _, open in
                guard open else { return }
                // The sidebar is not focusable until its slide-in finishes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    tvSidebarFocus = listSelection ?? .machines
                }
            }
        } else {
            HStack(spacing: 0) {
                if showSidebar {
                    sidebar
                        .frame(minWidth: 380, idealWidth: 440, maxWidth: 520)
                        .frame(maxHeight: .infinity)
                }
                NavigationStack { detail }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .preferredColorScheme(.dark)
        }
        #elseif os(iOS) || os(macOS) || os(visionOS)
        if #available(iOS 16.0, macOS 13.0, *) {
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
        #endif
    }

    #if os(tvOS)
    private func revealTvSidebar() {
        let target = listSelection ?? .machines
        if showSidebar {
            tvSidebarFocus = target
        } else {
            withAnimation { showSidebar = true }
        }
    }
    #endif

    // MARK: - Sidebar

    /// tvOS: List cells in the floating sidebar never take focus, so the rows
    /// are plain focusable Buttons in a stack. Buttons drive `listSelection`.
    @ViewBuilder
    private func sidebarList<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        #if os(tvOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) { rows() }
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
        }
        #else
        List(selection: $listSelection) { rows() }
        #endif
    }

    private var sidebar: some View {
        sidebarList {
            // Safari-style "N Tabs" above Machines. Overview is a toolbar
            // button, not a flat sidebar row.
            nTabsSidebarSection

            Section(header: sidebarSectionHeader("Machines")) {
                // TN3154: NavigationLink(value:) + .tag. Not Button (double chrome).
                sidebarRow(
                    destination: .machines,
                    title: "Machines",
                    systemImage: "desktopcomputer",
                    color: Self.machinesSidebarIndigo,
                    accessibilityID: WWNA11y.machinesRoot
                )
            }

            Section(header: sidebarSectionHeader("Project")) {
                sidebarRow(
                    destination: .projectStatus,
                    title: "Work Status",
                    systemImage: "chart.bar.xaxis",
                    color: .orange,
                    accessibilityID: "wwn.projectStatus"
                )
            }

            if !tagStore.tags.isEmpty {
                Section(header: sidebarSectionHeader("Tags")) {
                    ForEach(tagStore.tags) { tag in
                        sidebarRow(
                            destination: .machinesTag(tag.id),
                            title: tag.name,
                            tagColorHex: tag.colorHex
                        )
                        #if !os(tvOS)
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
                        #endif
                    }
                }
            }
        }
        .backport.sidebarList()
        .backport.navigationTitle("Wawona")
        #if os(tvOS)
        // Native focus targets. Do not hand-roll Liquid Glass chrome
        // (Adopting Liquid Glass: system NavigationSplitView sidebar).
        .environment(\.defaultMinListRowHeight, 66)
        #endif
        #if os(iOS)
        .backport.dismissKeyboardOnScroll()
        #endif
        #if os(macOS) || os(iOS) || os(tvOS)
        .backport.sidebarWidth()
        #endif
        #if os(iOS)
        .modifier(WWNPhoneLandscapeSidebarSafeArea(active: isPhoneLandscape))
        #endif
    }

    /// Section header with 10-foot breathing room on tvOS.
    @ViewBuilder
    private func sidebarSectionHeader(_ title: String) -> some View {
        #if os(tvOS)
        Text(title)
            .padding(.top, 12)
            .padding(.bottom, 4)
        #else
        Text(title)
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

    /// Safari "N Tabs" expandable group. Children are indented nested toplevels.
    /// Hidden when there are zero nested tabs. Overview opens from toolbar.
    @ViewBuilder
    private var nTabsSidebarSection: some View {
        if nestedTabs.nestedCount > 0 {
            #if os(tvOS)
            // DisclosureGroup is unavailable on tvOS.
            Section(header: sidebarSectionHeader(nestedTabs.tabsSectionTitle)) {
                ForEach(nestedTabs.nestedTabs) { tab in
                    nestedTabSidebarRow(tab)
                }
            }
            #else
            let binding = Binding(
                get: { nestedTabs.tabsSectionExpanded },
                set: { nestedTabs.tabsSectionExpanded = $0 }
            )
            if #available(iOS 14.0, macOS 11.0, visionOS 1.0, *) {
                DisclosureGroup(isExpanded: binding) {
                    ForEach(nestedTabs.nestedTabs) { tab in
                        nestedTabSidebarRow(tab)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.on.square")
                            .foregroundColor(Self.tabOverviewSidebarBlue)
                        Text(nestedTabs.tabsSectionTitle)
                    }
                    .accessibility(identifier: "wwn.tabs.section")
                    .accessibility(label: Text(nestedTabs.tabsSectionTitle))
                }
                #if os(macOS)
                .onDrop(
                    of: [UTType(exportedAs: WWNNestedClientTabStore.pasteboardType)],
                    isTargeted: nil
                ) { providers in
                    nestDroppedWindow(from: providers)
                }
                #endif
            } else {
                Section(header: Text(nestedTabs.tabsSectionTitle)) {
                    ForEach(nestedTabs.nestedTabs) { tab in
                        nestedTabSidebarRow(tab)
                    }
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func nestedTabSidebarRow(_ tab: WWNNestedClientTab) -> some View {
        let destination = WWNMainDestination.clientTab(tab.id)
        Group {
            #if os(macOS)
            Button {
                selectClientTab(tab.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow")
                        .foregroundColor(Self.tabOverviewSidebarBlue)
                    Text(tab.displayTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        #if os(macOS)
                        WWNHostWindowController.shared.closeTab(windowId: tab.id)
                        #else
                        WWNNestedClientTabStore.shared.remove(id: tab.id)
                        #endif
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibility(label: Text("Close \(tab.displayTitle)"))
                }
                .padding(.leading, 12)
            }
            .buttonStyle(.plain)
            .tag(destination)
            .onDrag {
                NSItemProvider(
                    item: NSNumber(value: tab.id),
                    typeIdentifier: WWNNestedClientTabStore.pasteboardType
                )
            }
            .contextMenu {
                Button("Tear Off to Window") {
                    WWNHostWindowController.shared.tearOff(windowId: tab.id)
                }
                Button("Show Tab Overview") {
                    listSelection = .tabOverview
                }
            }
            #else
            sidebarRow(
                destination: destination,
                title: tab.displayTitle,
                systemImage: "macwindow",
                color: Self.tabOverviewSidebarBlue,
                accessibilityID: "wwn.tabs.tab.\(tab.id)"
            )
            .padding(.leading, 12)
            #endif
        }
        .accessibility(identifier: "wwn.tabs.tab.\(tab.id)")
    }

    private func selectClientTab(_ windowId: UInt64) {
        listSelection = .clientTab(windowId)
        #if os(macOS)
        WWNHostWindowController.shared.focusNested(windowId: windowId)
        #else
        WWNNestedClientTabStore.shared.focus(id: windowId)
        NotificationCenter.default.post(
            name: Notification.Name("WWNShowSessionSurfaceNotification"),
            object: nil,
            userInfo: ["source": "focus-nested-tab", "reason": "window-\(windowId)"]
        )
        #endif
    }

    #if os(macOS)
    private func nestDroppedWindow(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(
            forTypeIdentifier: WWNNestedClientTabStore.pasteboardType,
            options: nil
        ) { item, _ in
            let id: UInt64?
            if let num = item as? NSNumber {
                id = num.uint64Value
            } else if let data = item as? Data, data.count >= 8 {
                id = data.withUnsafeBytes { $0.load(as: UInt64.self) }
            } else {
                id = nil
            }
            guard let windowId = id else { return }
            DispatchQueue.main.async {
                WWNHostWindowController.shared.nest(windowId: windowId)
                selectClientTab(windowId)
            }
        }
        return true
    }
    #endif

    /// Apple TN3154 on iOS: `List(selection:)` + `NavigationLink(value:)` + `.tag`.
    /// The split is always regular-width on iOS, so this highlights the row
    /// and swaps the detail column. It does not push a stack page.
    ///
    /// macOS / tvOS: plain `Button` that writes `listSelection`. NavigationLink
    /// would push instead of swapping the split detail. macOS bare
    /// NavigationLink often looks dead.
    private func sidebarRow(
        destination: WWNMainDestination,
        title: String,
        systemImage: String? = nil,
        color: Color? = nil,
        tagColorHex: String? = nil,
        accessibilityID: String? = nil
    ) -> some View {
        Group {
            #if os(macOS) || os(tvOS)
            Button {
                listSelection = destination
                #if os(tvOS)
                withAnimation { showSidebar = false }
                #endif
            } label: {
                sidebarRowLabel(
                    title: title,
                    systemImage: systemImage,
                    color: color,
                    tagColorHex: tagColorHex
                )
            }
            #if os(tvOS)
            .buttonStyle(WWNTvRowButtonStyle(selected: listSelection == destination))
            .focused($tvSidebarFocus, equals: destination)
            #else
            .buttonStyle(.plain)
            #endif
            #else
            if #available(iOS 16.0, *) {
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
            #endif
        }
        .tag(destination)
        #if os(tvOS)
        // The row style paints focus; keep the List cell itself flat.
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .listRowBackground(Color.clear)
        #endif
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
            #if os(tvOS)
            HStack(spacing: 16) {
                WWNTagDot(colorHex: tagColorHex, size: 14)
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            #else
            HStack(spacing: 12) {
                WWNTagDot(colorHex: tagColorHex, size: 10)
                Text(title)
                Spacer(minLength: 0)
            }
            #endif
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
                //
                // Tabbed Start: Metal Present is visible only here (never on
                // Machines). Card grid when parked; Focus reveals Present +
                // the in-section client tab strip (2+ tabs only).
                tabOverviewPane
            } else if case .clientTab? = router.selection {
                tabOverviewPane
            } else {
                machinesPane
            }
        }
    }

    private var isMachinesDestination: Bool {
        switch router.selection {
        case .machines?, .session?, .tabOverview?, .clientTab?, .machinesTag?, nil:
            return true
        default: return false
        }
    }

    /// Tab Overview hosts the card grid and (when Focused) Metal Present +
    /// the in-section client tab strip (Safari: only when 2+ nested tabs).
    /// Never a global AppKit window tab bar. Overview opens from toolbar.
    @ViewBuilder
    private var tabOverviewPane: some View {
        ZStack(alignment: .top) {
            if router.sessionSurfaceMounted {
                #if os(macOS)
                // Metal Present ignores SwiftUI opacity. Terminal Focus must
                // swap CompositorHostView out or TermSurface stays covered black.
                if router.sessionShowsEmbeddedTerminal && router.sessionSurfaceVisible {
                    GeometryReader { geo in
                        WWNMacEmbeddedTerminalHost()
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibility(identifier: WWNA11y.compositorSurface)
                    .accessibility(label: Text("Wawona Terminal"))
                } else {
                    #if !SWIFT_PACKAGE
                    CompositorBridge()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(router.sessionSurfaceVisible ? 1 : 0)
                        .allowsHitTesting(router.sessionSurfaceVisible)
                        .accessibility(hidden: !router.sessionSurfaceVisible)
                    #endif
                }
                #elseif !SWIFT_PACKAGE && (os(iOS) || os(tvOS) || os(visionOS))
                CompositorBridge()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(router.sessionSurfaceVisible ? 1 : 0)
                    .allowsHitTesting(router.sessionSurfaceVisible)
                    .accessibility(hidden: !router.sessionSurfaceVisible)
                #endif
            }
            if !router.sessionSurfaceVisible {
                #if os(macOS)
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                #elseif os(tvOS)
                Color.black
                    .edgesIgnoringSafeArea(.all)
                #elseif os(iOS) || os(visionOS)
                Color(UIColor.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                #endif
                WWNTabOverviewView()
            } else if nestedTabs.showsSessionTabBar {
                WWNTabOverviewSessionTabBar(
                    onShowOverview: { router.showTabOverview() }
                )
            }
            #if os(tvOS)
            // Present fills the detail with no system nav. Always-on Done so
            // Hello WASI / Wayland clients are not a dead end without Menu.
            if router.sessionSurfaceVisible {
                WWNTvosPresentExitChrome(
                    onDone: { tvosExitFocusedSession() }
                )
            }
            #endif
        }
        #if os(macOS)
        .onDrop(
            of: [UTType(exportedAs: WWNNestedClientTabStore.pasteboardType)],
            isTargeted: nil
        ) { providers in
            nestDroppedWindow(from: providers)
        }
        #endif
        #if os(iOS) || os(tvOS) || os(visionOS)
        .navigationBarHidden(router.sessionSurfaceVisible)
        #endif
        #if os(iOS)
        .modifier(WWNSessionHideToolbarWhenVisible(active: router.sessionSurfaceVisible))
        #endif
        #if os(tvOS)
        .background(
            Group {
                if router.sessionSurfaceVisible {
                    WWNTerminalEscapeDismissHost(onEscape: { tvosExitFocusedSession() })
                }
            }
        )
        #endif
        #if os(iOS) || os(visionOS)
        .modifier(WWNSessionSafeAreaModifier(
            respectSafeArea: respectSafeArea,
            sessionVisible: router.sessionSurfaceVisible
        ))
        .modifier(WWNSessionStatusBarModifier(
            hideStatusBar: router.sessionSurfaceVisible && !respectSafeArea
        ))
        .modifier(WWNSessionSurfaceGestureModifier(
            showSidebar: $showSidebar,
            sessionVisible: router.sessionSurfaceVisible,
            onShakePark: {
                router.showTabOverview()
            }
        ))
        #endif
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
        // Mount Metal for SHM/DRM drain while Start runs, but never reveal
        // Present here. Tabbed clients show only under Tab Overview; New
        // Window uses `WWNSessionWindowPresenter`. Machines stays the grid.
        ZStack {
            if router.sessionSurfaceMounted {
                #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
                CompositorBridge()
                    .id("wwn-compositor-bridge")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibility(hidden: true)
                #endif
            }
            WWNMachinesGridView(
                onConnect: onConnect,
                filterTagID: activeTagFilterID,
                onClearTagFilter: { router.showMachines() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Sidebar Machines / tag / project parks Present. Tab Overview keeps
        // Focus Present (showSessionSurface sets selection=.tabOverview).
        .backport.onChange(of: router.selection) { _, newValue in
            switch newValue {
            case .machines?, .machinesTag?, .projectStatus?, .session?:
                if router.sessionSurfaceVisible {
                    router.sessionSurfaceVisible = false
                }
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

    #if os(tvOS)
    /// Park Present (keep session) or Stop Terminal chrome. Menu / Done share this.
    private func tvosExitFocusedSession() {
        if guestConsole.isPresented, !guestConsole.windowed, !router.sessionSurfaceVisible {
            // Client launch log: Done focuses compositor. Shell Done = Stop.
            if guestConsole.isShell {
                guestConsole.userDismiss()
            } else {
                guestConsole.parkForCompositor()
                router.showSessionSurface()
            }
            return
        }
        router.showTabOverview()
    }

    private func tvosHandleRemoteMenu() {
        if guestConsole.isPresented, !guestConsole.windowed, !router.sessionSurfaceVisible {
            // Menu always leaves Terminal (Stop). Focus Present is the Done button.
            guestConsole.userDismiss()
            return
        }
        if router.sessionSurfaceVisible {
            tvosExitFocusedSession()
        }
    }
    #endif

    private func handleSelectionChange() {
        #if os(iOS) || os(visionOS)
        WWNHostKeyboard.dismiss()
        #endif
        // Sidebar List → Tab Overview: snapshot thumbs. Do not force-park
        // Present here; Focus / client-attach calls showSessionSurface with
        // visible=1 on the same selection. Re-tap Overview via tab-bar
        // "Show Overview" (`showTabOverview`) parks deliberately.
        if case .tabOverview? = router.selection {
            NotificationCenter.default.post(
                name: Notification.Name("WWNCaptureActiveMachineThumbnailNotification"),
                object: nil
            )
        }
        if case .clientTab(let windowId)? = router.selection {
            #if os(macOS)
            WWNHostWindowController.shared.focusNested(windowId: windowId)
            #else
            WWNNestedClientTabStore.shared.focus(id: windowId)
            #endif
        }
        // Legacy `.session` destination: Present moved under Tab Overview.
        if case .session? = router.selection {
            router.selection = .tabOverview
        }
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
        #elseif os(macOS) || os(visionOS)
        // Tab Overview / client tabs keep the sidebar column. Never leave
        // macOS stuck in `.detailOnly` after onAppear / selection sync.
        if !router.sessionSurfaceVisible {
            showSidebar = true
        }
        #elseif os(tvOS)
        // Push sidebar is user-toggled. Present hides it for full-width Metal.
        // Do not force `.all` open (that fought Hide Sidebar and overlayed UI).
        if router.sessionSurfaceVisible {
            showSidebar = false
        }
        #endif
    }
}

#if os(tvOS)
/// Always-visible Present exit on the 10-foot UI. tvOS has no swipe-back /
/// nav bar while Metal fills the detail.
private struct WWNTvosPresentExitChrome: View {
    let onDone: () -> Void
    @FocusState private var doneFocused: Bool

    var body: some View {
        VStack {
            HStack {
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline.weight(.semibold))
                        .frame(minWidth: 160, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .focused($doneFocused)
                .wwnA11y(WWNA11y.terminalDone, label: "Done")
                .onAppear { doneFocused = true }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.72))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
        .zIndex(20)
    }
}
#endif

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
        // Terminal exclusive: replace Machines chrome while presented. A
        // ZStack overlay left Machines/nav AX frames covering Done (visionOS
        // 2D hit test) even with allowsHitTesting(false). Keep Metal mounted
        // under sessionSurfaceMounted paths via the outer host, not here.
        let terminalOverlay =
            console.isPresented && !console.windowed && !sessionSurfaceVisible
        return Group {
            if terminalOverlay {
                WWNIosGuestConsoleSheet(console: console)
            } else {
                content
            }
        }
    }
}
#endif
#endif
