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

/// Dedicated Global Settings host (in-app only; never Settings.app / PrefPane).
///
/// Chrome matches Machines home: system `SidebarListStyle`, tinted SF Symbol
/// rows, `List` selection. Dismiss stays on the **detail / split toolbar**
/// via `backport.settingsCloseAction` (trailing `xmark` on iOS / iPadOS /
/// visionOS; `Done` on macOS / tvOS). Never put a close control on the
/// sidebar list column.
struct WWNGlobalSettingsHostView: View {
    @ObservedObject var model: WWNSettingsValueModel
    @Binding var selection: GlobalSettingsSectionID?
    var onDismiss: () -> Void

    @State private var showSidebar = true
    /// Local list selection. Never bind `List(selection:)` to `@Published`
    /// (iOS 16 NavigationSplitView AttributeGraph exclusivity crash).
    @State private var listSelection: GlobalSettingsSectionID?
    #if os(iOS) || os(visionOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
        #elseif os(macOS) || os(visionOS)
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
            HStack(spacing: 0) {
                if showSidebar {
                    settingsSidebar.frame(width: 240)
                    Divider()
                }
                WawonaBackport<Any>.navigation {
                    settingsDetail
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - tvOS (10-foot: stack, not phone-style overlay split)

    #if os(tvOS)
    @ViewBuilder
    private var tvSettingsBody: some View {
        if #available(tvOS 16.0, *) {
            NavigationStack {
                List(selection: $listSelection) {
                    Section {
                        ForEach(catalogSections, id: \.self) { id in
                            settingsSidebarRow(id)
                        }
                    }
                }
                .listStyle(.plain)
                .backport.navigationTitle("Settings")
                .backport.settingsCloseAction(onClose: onDismiss)
                .navigationDestination(for: GlobalSettingsSectionID.self) { id in
                    tvDetail(for: id)
                }
            }
            .backport.onChange(of: listSelection) { _, newValue in
                selection = newValue
            }
        } else {
            WawonaBackport<Any>.navigation {
                List {
                    ForEach(catalogSections, id: \.self) { id in
                        Button {
                            listSelection = id
                            selection = id
                        } label: {
                            settingsRowLabel(id)
                        }
                        .accessibility(identifier: "wwn.settings.\(id.rawValue)")
                    }
                }
                .listStyle(.plain)
                .backport.navigationTitle("Settings")
                .backport.settingsCloseAction(onClose: onDismiss)
            }
        }
    }

    @ViewBuilder
    private func tvDetail(for id: GlobalSettingsSectionID) -> some View {
        if let section = WawonaMainWindowView.objcSection(id, in: model.sections) {
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
    #endif

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        Group {
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
        }
        .backport.sidebarList()
        .backport.navigationTitle("Settings")
        #if os(macOS) || os(iOS) || os(visionOS)
        .backport.sidebarWidth()
        #endif
    }

    @ViewBuilder
    private var sidebarSection: some View {
        Section(header: Text("Settings")) {
            ForEach(catalogSections, id: \.self) { id in
                settingsSidebarRow(id)
            }
        }
    }

    /// Same row shape as Machines home: tinted SF Symbol + title.
    @ViewBuilder
    private func settingsSidebarRow(_ id: GlobalSettingsSectionID) -> some View {
        let objc = WawonaMainWindowView.objcSection(id, in: model.sections)
        Group {
            if #available(iOS 16.0, macOS 13.0, visionOS 1.0, *) {
                NavigationLink(value: id) { settingsRowLabel(id) }
            } else {
                Button { listSelection = id } label: { settingsRowLabel(id) }
            }
        }
        .tag(id)
        .accessibility(identifier: objc?.accessibilityIdentifier ?? "wwn.settings.\(id.rawValue)")
        .accessibility(addTraits: listSelection == id ? .isSelected : [])
    }

    private func settingsRowLabel(_ id: GlobalSettingsSectionID) -> some View {
        let objc = WawonaMainWindowView.objcSection(id, in: model.sections)
        let color = objc?.swiftUIIconColor ?? .accentColor
        return WawonaLabel {
            Text(id.title)
        } icon: {
            Image(systemName: id.systemImage)
                .foregroundColor(color)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var settingsDetail: some View {
        // Toolbar on the split detail column only (same pattern as Machines
        // home). Do not nest NavigationStack here: NavigationSplitView already
        // owns column chrome. Do not put close on the sidebar list.
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
        .backport.settingsCloseAction(onClose: onDismiss)
    }
}
#endif
