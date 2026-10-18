#if os(watchOS)
import SwiftUI
import WawonaModel

/// Safari-style Tab Overview. Same card language as iOS: count, preview, close.
struct WatchTabOverviewList: View {
    let profiles: [MachineProfile]
    @ObservedObject var sessions: SessionOrchestrator
    var searchQuery: String
    var onOpen: (MachineProfile, MachineSession) -> Void
    var onClose: (MachineProfile, MachineSession) -> Void

    private var running: [(MachineProfile, MachineSession)] {
        sessions.sessions.compactMap { session in
            guard session.status == .connected || session.status == .connecting else {
                return nil
            }
            guard let profile = profiles.first(where: { $0.id == session.machineId }) else {
                return nil
            }
            return (profile, session)
        }
    }

    private var rows: [(MachineProfile, MachineSession)] {
        let titles = running.map(\.0.name)
        let indices = MachineProfileDomain.tabOverviewFilterIndices(
            query: searchQuery,
            titles: titles
        )
        return indices.compactMap { idx in
            guard running.indices.contains(idx) else { return nil }
            return running[idx]
        }
    }

    private var tabCountString: String {
        let n = rows.count
        return n == 1 ? "1 Tab" : "\(n) Tabs"
    }

    var body: some View {
        if running.isEmpty {
            ContentUnavailableView(
                "No Active Tabs",
                systemImage: "square.on.square",
                description: Text("Start a machine, then open Tab Overview to switch sessions.")
            )
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 13, weight: .semibold))
                        Text(tabCountString)
                            .font(.system(size: 14, weight: .bold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("wwn.tabOverview.count")

                    if rows.isEmpty {
                        Text("No Matching Tabs")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        ForEach(rows, id: \.1.id) { row in
                            WatchTabOverviewRow(
                                profile: row.0,
                                session: row.1,
                                isActive: sessions.activeSessionId == row.1.id,
                                searchQuery: searchQuery,
                                onOpen: { onOpen(row.0, row.1) },
                                onClose: { onClose(row.0, row.1) }
                            )
                            .accessibilityIdentifier("wwn.tabOverview.card.\(row.0.id)")
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
#endif
