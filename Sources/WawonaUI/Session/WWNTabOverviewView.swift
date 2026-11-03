#if os(iOS) || os(visionOS) || os(macOS) || os(tvOS)
import SwiftUI
import WawonaModel

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import UIKit
#endif

/// In-section client tab strip while Metal Present is visible under Tab Overview.
/// One chip per nested Wayland toplevel (`window_id`). Safari: host only when 2+.
/// Not AppKit window tabs.
struct WWNTabOverviewSessionTabBar: View {
    @ObservedObject private var nestedTabs = WWNNestedClientTabStore.shared
    var onShowOverview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onShowOverview) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibility(identifier: "wwn.tabOverview.showOverview")
            .accessibility(label: Text("Show Tab Overview"))
            #if os(macOS)
            .help("Show Tab Overview")
            #endif

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(nestedTabs.nestedTabs) { tab in
                        tabChip(for: tab)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        #else
        .background(Color.primary.opacity(0.06))
        #endif
        .accessibility(identifier: "wwn.tabOverview.sessionTabBar")
    }

    private func tabChip(for tab: WWNNestedClientTab) -> some View {
        let selected = nestedTabs.focusedId == tab.id
        return HStack(spacing: 6) {
            Button {
                focusTab(tab.id)
            } label: {
                Text(tab.displayTitle)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Button {
                closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibility(label: Text("Close \(tab.displayTitle)"))
        }
        .foregroundColor(selected ? Color.accentColor : Color.primary)
        .background(
            Capsule(style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
        )
        .accessibility(identifier: "wwn.tabOverview.tab.\(tab.id)")
        #if os(macOS)
        .onDrag {
            NSItemProvider(
                item: NSNumber(value: tab.id),
                typeIdentifier: WWNNestedClientTabStore.pasteboardType
            )
        }
        #endif
    }

    private func focusTab(_ windowId: UInt64) {
        #if os(macOS)
        WWNHostWindowController.shared.focusNested(windowId: windowId)
        #else
        nestedTabs.focus(id: windowId)
        #endif
        WWNMainWindowRouter.shared.selection = .clientTab(windowId)
        NotificationCenter.default.post(
            name: Notification.Name("WWNShowSessionSurfaceNotification"),
            object: nil,
            userInfo: ["source": "tab-strip", "reason": "window-\(windowId)"]
        )
    }

    private func closeTab(_ windowId: UInt64) {
        #if os(macOS)
        WWNHostWindowController.shared.closeTab(windowId: windowId)
        #else
        WWNNestedClientTabStore.shared.remove(id: windowId)
        #endif
    }
}

/// Safari-style Tab Overview: search + nested Wayland toplevel preview cards.
/// Opens from the Machines toolbar Tab Overview button. Focus reveals Present.
struct WWNTabOverviewView: View {
    @ObservedObject private var nestedTabs = WWNNestedClientTabStore.shared
    @ObservedObject private var model = WWNMachinesViewModel.shared
    @State private var searchQuery = ""

    private var overviewTabs: [WWNNestedClientTab] {
        nestedTabs.nestedTabs
    }

    private var filteredTabs: [WWNNestedClientTab] {
        let titles = overviewTabs.map(\.displayTitle)
        let indices = MachineProfileDomain.tabOverviewFilterIndices(
            query: searchQuery,
            titles: titles
        )
        return indices.compactMap { idx in
            guard overviewTabs.indices.contains(idx) else { return nil }
            return overviewTabs[idx]
        }
    }

    private var tabCountString: String {
        let n = filteredTabs.count
        return n == 1 ? "1 Tab" : "\(n) Tabs"
    }

    @available(iOS 14, tvOS 14, macOS 11, *)
    private var columns: [GridItem] {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [
                GridItem(.flexible(), spacing: 18),
                GridItem(.flexible(), spacing: 18),
                GridItem(.flexible(), spacing: 18),
            ]
        }
        #elseif os(macOS) || os(visionOS)
        return [
            GridItem(.adaptive(minimum: 220), spacing: 18),
        ]
        #endif
        return [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
        ]
    }

    var body: some View {
        Group {
            if overviewTabs.isEmpty {
                emptyState
            } else {
                overviewBody
            }
        }
        .backport.navigationTitle("Tab Overview")
        .backport.searchable(text: $searchQuery, prompt: "Search Tabs")
        .background(tabOverviewSearchPlacement)
        .accessibility(identifier: "wwn.tabOverview.detail")
        #if os(macOS)
        .onDrop(
            of: [UTType(exportedAs: WWNNestedClientTabStore.pasteboardType)],
            isTargeted: nil
        ) { providers in
            nestDropped(from: providers)
        }
        #endif
    }

    @ViewBuilder
    private var tabOverviewSearchPlacement: some View {
        #if os(iOS)
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone {
            WWNPhoneIntegratedSearchToolbar(placement: .navigationBarStacked, onCompose: {})
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.on.square")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text("No Active Tabs")
                .font(.headline)
            Text("Start a machine. Nested Wayland windows appear here and in the sidebar Tabs list.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overviewBody: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 15, weight: .semibold))
                    Text(tabCountString)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if filteredTabs.isEmpty {
                Text("No Matching Tabs")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Group {
                        if #available(iOS 14, tvOS 14, macOS 11, *) {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredTabs) { tab in
                                    card(for: tab)
                                }
                            }
                        } else {
                            VStack(spacing: 16) {
                                ForEach(filteredTabs) { tab in
                                    card(for: tab)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(for tab: WWNNestedClientTab) -> some View {
        let selected = nestedTabs.focusedId == tab.id
        let thumbProfile = model.profiles.first {
            WWNMachineProfileStore.activeMachineId() == $0.machineId
        }
        return WWNTabOverviewCard(
            title: tab.displayTitle,
            statusLabel: selected ? "Running · Active" : "Running",
            isSelected: selected,
            thumbnail: thumbProfile.flatMap { model.thumbnailImage(for: $0) },
            onFocus: {
                focusTab(tab.id)
            },
            onClose: {
                closeTab(tab.id)
            }
        )
        .accessibility(identifier: "wwn.tabOverview.card.\(tab.id)")
        #if os(macOS)
        .onDrag {
            NSItemProvider(
                item: NSNumber(value: tab.id),
                typeIdentifier: WWNNestedClientTabStore.pasteboardType
            )
        }
        #endif
    }

    private func focusTab(_ windowId: UInt64) {
        #if os(macOS)
        WWNHostWindowController.shared.focusNested(windowId: windowId)
        #else
        nestedTabs.focus(id: windowId)
        #endif
        WWNMainWindowRouter.shared.selection = .clientTab(windowId)
        NotificationCenter.default.post(
            name: Notification.Name("WWNShowSessionSurfaceNotification"),
            object: nil,
            userInfo: ["source": "tab-overview", "reason": "window-\(windowId)"]
        )
    }

    private func closeTab(_ windowId: UInt64) {
        #if os(macOS)
        WWNHostWindowController.shared.closeTab(windowId: windowId)
        #else
        WWNNestedClientTabStore.shared.remove(id: windowId)
        #endif
    }

    #if os(macOS)
    private func nestDropped(from providers: [NSItemProvider]) -> Bool {
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
                focusTab(windowId)
            }
        }
        return true
    }
    #endif
}

private struct WWNTabOverviewCard: View {
    let title: String
    let statusLabel: String
    let isSelected: Bool
    let thumbnail: WWNPlatformImage?
    let onFocus: () -> Void
    let onClose: () -> Void

    private var iconName: String {
        let lower = title.lowercased()
        if lower.contains("term") || lower.contains("zsh") || lower.contains("shell") {
            return "terminal"
        }
        if lower.contains("niri") || lower.contains("weston") {
            return "rectangle.on.rectangle"
        }
        return "app.dashed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button(action: onFocus) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                        if let thumbnail {
                            #if os(macOS)
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                            #else
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                            #endif
                        } else {
                            Image(systemName: iconName)
                                .font(.system(size: 36, weight: .light))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 140)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibility(label: Text("Close \(title)"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
    }
}

#endif
