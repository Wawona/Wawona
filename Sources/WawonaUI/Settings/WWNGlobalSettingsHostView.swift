#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import WawonaModel
import WawonaUIContracts

#if os(iOS)
/// Same split style as Machines home (`WWNPhoneSplitStyle`).
@available(iOS 16.0, *)
private struct WWNSettingsPhoneSplitStyle: ViewModifier {
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

/// Dedicated Global Settings host. Replaces Machines chrome in the same window
/// (in-app only; never sheet, PrefPane, or Settings.app).
///
/// Chrome matches Machines home: system `SidebarListStyle`, section-tinted SF
/// Symbol sidebar rows (`WawonaSettingsHubChrome.hubRow`), `List` selection.
/// Sidebar chrome matches Machines. System `NavigationSplitView` sidebar
/// (Liquid Glass on SDK 26+). Do not strip the system toggle; do not replace
/// with an opaque HStack. tvOS: `columnVisibility` Binding + leading Hide/Show
/// (never `.constant(.all)`). Detail trailing is Add? + Close via
/// `settingsCloseAction` + `WWNSettingsChromeBridge`. Pre-16 HStack has no
/// system toggle: pass `showSidebar` there only. macOS / tvOS: `Done` only.
/// Never put close on the sidebar list column.
struct WWNGlobalSettingsHostView: View {
    @ObservedObject var model: WWNSettingsValueModel
    @Binding var selection: GlobalSettingsSectionID?
    var onDismiss: () -> Void

    @State private var showSidebar = true
    /// Local list selection. Never bind `List(selection:)` to `@Published`
    /// (iOS 16 NavigationSplitView AttributeGraph exclusivity crash).
    @State private var listSelection: GlobalSettingsSectionID?
    #if os(tvOS)
    /// The floating split sidebar does not take focus when it opens. Route it.
    @FocusState private var tvSidebarFocus: GlobalSettingsSectionID?
    #endif
    #if os(iOS) || os(visionOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    #if os(macOS) || os(iOS) || os(visionOS)
    /// Env Vars registers Add here so chrome owns one trailing group
    /// (`[+]?` + Done / close). Never a second Machines-style primary Add.
    /// `StateObject` is iOS 14; product floor is 13 (`WawonaStateObject`).
    @WawonaStateObject private var chromeBridge = WWNSettingsChromeBridge()
    #endif

    private var catalogSections: [GlobalSettingsSectionID] {
        GlobalSettingsCatalog.visibleSections(for: GlobalSettingsCatalog.currentHost)
    }

    #if os(iOS)
    private var isPhoneIdiom: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var isPhonePortrait: Bool {
        isPhoneIdiom && verticalSizeClass == .regular
    }
    #endif

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { model.actionNoticeMessage != nil },
            set: { if !$0 { model.clearActionNotice() } }
        )
    }

    var body: some View {
        Group {
            #if os(tvOS)
            tvSettingsBody
            #else
            splitOrLegacyBody
            #endif
        }
        .onAppear(perform: ensureSelection)
        .backport.onChange(of: listSelection) { _, newValue in
            guard newValue != selection else { return }
            DispatchQueue.main.async {
                selection = newValue
                #if os(iOS)
                if isPhonePortrait, newValue != nil {
                    withAnimation { showSidebar = false }
                }
                #endif
            }
        }
        .backport.onChange(of: selection) { _, newValue in
            if listSelection != newValue {
                listSelection = newValue
            }
        }
        .backport.onChange(of: model.sections) { _, _ in
            if let id = selection,
               WawonaMainWindowView.objcSection(id, in: model.sections) == nil {
                selection = catalogSections.first
                listSelection = selection
            }
        }
        .alert(isPresented: noticePresented) {
            Alert(
                title: Text(model.actionNoticeTitle),
                message: Text(model.actionNoticeMessage ?? ""),
                dismissButton: .default(Text("OK")) {
                    model.clearActionNotice()
                }
            )
        }
        // ToolbarKeys UIKit settings view is iOS/iPadOS only (xcodegen omits it
        // on tvOS/visionOS).
        #if os(iOS)
        .sheet(isPresented: $model.presentToolbarKeysSettings) {
            NavigationView {
                KeyboardToolbarSettingsView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        #endif
    }

    private func ensureSelection() {
        if selection == nil {
            selection = catalogSections.first
        }
        listSelection = selection
        #if os(iOS)
        // Phone: open on the detail column so the trailing close toolbar is
        // visible immediately. Sidebar stays a column toggle, not dismiss chrome.
        if isPhonePortrait {
            showSidebar = false
        } else {
            showSidebar = true
        }
        #elseif os(macOS) || os(tvOS) || os(visionOS)
        showSidebar = true
        #endif
    }

    // MARK: - macOS / iOS / iPadOS / visionOS

    @ViewBuilder
    private var splitOrLegacyBody: some View {
        if #available(iOS 16.0, macOS 13.0, visionOS 1.0, *) {
            NavigationSplitView(columnVisibility: Binding(
                get: { showSidebar ? .all : .detailOnly },
                set: { showSidebar = $0 != .detailOnly }
            )) {
                settingsSidebar
            } detail: {
                settingsDetail
            }
            #if os(iOS)
            .modifier(WWNSettingsPhoneSplitStyle(isPhone: isPhoneIdiom))
            .environment(\.horizontalSizeClass, .regular)
            #endif
        } else {
            // iOS 13-15: no NavigationSplitView / system toggle. Custom
            // leading toggle via settingsCloseAction(showSidebar:).
            HStack(spacing: 0) {
                if showSidebar {
                    settingsSidebar.frame(width: 240)
                    Divider()
                }
                WawonaBackport<Any>.navigation {
                    settingsDetailBody
                        #if os(macOS) || os(iOS) || os(visionOS)
                        .environment(\.wwnSettingsChromeBridge, chromeBridge)
                        .backport.settingsCloseAction(
                            showSidebar: $showSidebar,
                            onClose: onDismiss,
                            chromeBridge: chromeBridge
                        )
                        #else
                        .backport.settingsCloseAction(
                            showSidebar: $showSidebar,
                            onClose: onDismiss
                        )
                        #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - tvOS (Liquid Glass sidebar + detail, macOS Settings parity)

    #if os(tvOS)
    /// Adopting Liquid Glass: system `NavigationSplitView` floating sidebar.
    /// `columnVisibility` Binding (not `.constant(.all)`) for Hide/Show.
    /// Detail `NavigationStack` owns pushes (text editor, Env Vars, pickers)
    /// so Menu / Cancel pop the stack. Done sits trailing on the detail
    /// column only; Menu on the sidebar closes Settings.
    @ViewBuilder
    private var tvSettingsBody: some View {
        if #available(tvOS 16.0, *) {
            NavigationSplitView(columnVisibility: Binding(
                get: { showSidebar ? .all : .detailOnly },
                set: { showSidebar = $0 != .detailOnly }
            )) {
                settingsSidebar
                    .backport.sidebarWidth()
                    .focusSection()
                    .onExitCommand(perform: onDismiss)
                    .onMoveCommand { direction in
                        if direction == .right { withAnimation { showSidebar = false } }
                    }
            } detail: {
                NavigationStack {
                    // tvOS: no backgroundExtensionEffect (mirrors / shifts chrome).
                    // focusSection lets Up from the first row reach Done.
                    settingsDetailBody
                        .focusSection()
                        // The Left-edge sidebar peek never takes focus, and Up
                        // cannot reach the toolbar toggle. Menu opens the sidebar.
                        .onExitCommand(perform: revealTvSidebar)
                        // While the sidebar overlays it, a focusable detail pulls
                        // Up/Down out of the sidebar and the system collapses it.
                        .disabled(showSidebar)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    withAnimation { showSidebar.toggle() }
                                } label: {
                                    Label(
                                        showSidebar ? "Hide Sidebar" : "Show Sidebar",
                                        systemImage: "sidebar.leading"
                                    )
                                }
                                .accessibility(identifier: "wwn.settings.sidebar.toggle")
                                .accessibility(label: Text(
                                    showSidebar ? "Hide Sidebar" : "Show Sidebar"
                                ))
                            }
                        }
                        .backport.settingsCloseAction(onClose: onDismiss)
                }
            }
            .preferredColorScheme(.dark)
            .backport.onChange(of: showSidebar) { _, open in
                guard open else { return }
                // The sidebar is not focusable until its slide-in finishes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    tvSidebarFocus = listSelection ?? catalogSections.first
                }
            }
        } else {
            HStack(spacing: 0) {
                if showSidebar {
                    settingsSidebar
                        .frame(minWidth: 380, idealWidth: 440, maxWidth: 520)
                        .frame(maxHeight: .infinity)
                        .onExitCommand(perform: onDismiss)
                }
                NavigationStack {
                    settingsDetailBody
                        .backport.settingsCloseAction(onClose: onDismiss)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func revealTvSidebar() {
        let target = listSelection ?? catalogSections.first
        if showSidebar {
            tvSidebarFocus = target
        } else {
            withAnimation { showSidebar = true }
        }
    }
    #endif

    // MARK: - Sidebar

    /// Same column chrome as Machines home: `sidebarList` + width + system
    /// sidebar toggle (never strip on the split path).
    private var settingsSidebar: some View {
        Group {
            #if os(tvOS)
            // tvOS: List cells in the floating sidebar never take focus, so the
            // rows are plain focusable Buttons in a stack. Buttons drive selection.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) { sidebarSection }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 20)
            }
            #else
            if #available(iOS 14.0, macOS 11.0, visionOS 1.0, *) {
                List(selection: $listSelection) {
                    sidebarSection
                }
            } else {
                // iOS 13: no List selection binding; Button rows drive detail.
                List {
                    sidebarSection
                }
            }
            #endif
        }
        .backport.sidebarList()
        .backport.navigationTitle("Settings")
        #if os(tvOS)
        .environment(\.defaultMinListRowHeight, 66)
        #endif
        #if os(iOS)
        .backport.dismissKeyboardOnScroll()
        #endif
        #if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        .backport.sidebarWidth()
        #endif
    }

    @ViewBuilder
    private var sidebarSection: some View {
        Section(header: settingsSidebarSectionHeader) {
            ForEach(catalogSections, id: \.self) { id in
                settingsSidebarRow(id)
            }
        }
    }

    @ViewBuilder
    private var settingsSidebarSectionHeader: some View {
        #if os(tvOS)
        Text("Settings")
            .padding(.top, 12)
            .padding(.bottom, 4)
        #else
        Text("Settings")
        #endif
    }

    /// Same row shape as Machines home: plain SF Symbol + title.
    /// macOS / tvOS: plain `Button` writing `listSelection` (Machines parity).
    /// A bare `NavigationLink(value:)` in `NavigationSplitView` often fails to
    /// update selection on macOS, so Env Vars / other sections look dead.
    @ViewBuilder
    private func settingsSidebarRow(_ id: GlobalSettingsSectionID) -> some View {
        let objc = WawonaMainWindowView.objcSection(id, in: model.sections)
        Group {
            #if os(macOS) || os(tvOS)
            Button {
                // Write both: detail binds `selection`; List highlights
                // `listSelection`. Async-only sync left Env Vars looking dead.
                listSelection = id
                selection = id
                #if os(tvOS)
                withAnimation { showSidebar = false }
                #endif
            } label: {
                settingsRowLabel(id)
            }
            #if os(tvOS)
            .buttonStyle(WWNTvRowButtonStyle(selected: listSelection == id))
            .focused($tvSidebarFocus, equals: id)
            #else
            .buttonStyle(.plain)
            #endif
            #else
            if #available(iOS 16.0, visionOS 1.0, *) {
                NavigationLink(value: id) { settingsRowLabel(id) }
            } else {
                Button { listSelection = id } label: { settingsRowLabel(id) }
            }
            #endif
        }
        .tag(id)
        #if os(tvOS)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        #endif
        .accessibility(identifier: objc?.accessibilityIdentifier ?? "wwn.settings.\(id.rawValue)")
        .accessibility(addTraits: listSelection == id ? .isSelected : [])
    }

    private func settingsRowLabel(_ id: GlobalSettingsSectionID) -> some View {
        // Section accent tints the glyph (no rounded tile). Same colors as
        // detail controls / PreferencesSectionsBuilder.
        let objc = WawonaMainWindowView.objcSection(id, in: model.sections)
        let color = objc?.swiftUIIconColor
            ?? WawonaSettingsHubChrome.accentColor(for: id)
        return WawonaSettingsHubChrome.hubRow(
            title: id.title,
            systemImage: id.systemImage,
            iconColor: color
        )
    }

    // MARK: - Detail

    /// Split detail: `NavigationStack` for Env Vars drill-in (system back).
    /// Trailing `[+]?[x]` only. Leading sidebar toggle = system split control
    /// (Machines parity). Do not pass `showSidebar` here.
    @ViewBuilder
    private var settingsDetail: some View {
        #if os(macOS)
        settingsDetailBody
            .environment(\.wwnSettingsChromeBridge, chromeBridge)
            .backport.settingsCloseAction(
                onClose: onDismiss,
                chromeBridge: chromeBridge
            )
        #elseif os(iOS) || os(visionOS)
        settingsDetailStack
            .environment(\.wwnSettingsChromeBridge, chromeBridge)
            .backport.settingsCloseAction(
                onClose: onDismiss,
                chromeBridge: chromeBridge
            )
        #else
        settingsDetailBody
            .backport.settingsCloseAction(onClose: onDismiss)
        #endif
    }

    #if os(iOS) || os(visionOS)
    /// Detail column stack for deeper pushes (Env Vars row → editor).
    /// Skill: NavigationStack in the split detail column.
    @ViewBuilder
    private var settingsDetailStack: some View {
        if #available(iOS 16.0, visionOS 1.0, *) {
            NavigationStack {
                settingsDetailBody
            }
        } else {
            settingsDetailBody
        }
    }
    #endif

    @ViewBuilder
    private var settingsDetailBody: some View {
        // Column chrome (sidebar / close / add) lives on `settingsDetail`.
        // Do not put close on the sidebar list.
        Group {
            if let id = selection,
               let section = WawonaMainWindowView.objcSection(id, in: model.sections) {
                WWNSettingsSectionView(section: section, model: model)
                    .backport.navigationTitle(id.detailTitle)
            } else {
                WawonaEmptyState(
                    "Settings",
                    systemImage: "gearshape",
                    description: Text("Choose a section.")
                )
            }
        }
    }
}
#endif
