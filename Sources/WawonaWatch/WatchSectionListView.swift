#if os(watchOS)
import SwiftUI
import WawonaModel

/// Colored rows, same language as Watch Settings. Not a sidebar column.
/// Leading control dismisses, same job as the back arrow on other hosts.
struct WatchSectionListView: View {
    @Binding var page: WatchHomePage
    var onClose: () -> Void
    @ObservedObject private var tagStore = WWNMachineTagStore.shared

    var body: some View {
        List {
            Section("Machines") {
                WatchSectionRow(
                    title: "Machines",
                    systemImage: "desktopcomputer",
                    tint: .indigo,
                    identifier: "wwn.watch.section.machines",
                    action: { choose(.machines) }
                )
                WatchSectionRow(
                    title: "Tab Overview",
                    systemImage: "square.on.square",
                    tint: .blue,
                    identifier: "wwn.watch.section.tabs",
                    action: { choose(.tabOverview) }
                )
            }
            if !tagStore.tags.isEmpty {
                Section("Tags") {
                    ForEach(tagStore.tags) { tag in
                        Button(action: { choose(.tag(tag.id)) }) {
                            Label {
                                Text(tag.name)
                            } icon: {
                                WatchTagDot(colorHex: tag.colorHex, size: 12)
                            }
                        }
                        .accessibilityIdentifier("wwn.watch.section.tag.\(tag.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if page == .tag(tag.id) { page = .machines }
                                tagStore.deleteTag(id: tag.id)
                            } label: {
                                Label("Delete Tag", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        // The Machines bar stays up. Its list button closes this page, so
        // this list does not add a second bar.
        .toolbar(.hidden, for: .bottomBar)
    }

    private func choose(_ next: WatchHomePage) {
        page = next
        onClose()
    }
}
#endif
