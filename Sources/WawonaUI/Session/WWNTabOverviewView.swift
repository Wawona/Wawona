#if os(iOS) || os(visionOS) || os(macOS) || os(tvOS)
import SwiftUI

#if os(iOS) || os(visionOS)
private struct WWNTabOverviewListStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 14.0, visionOS 1.0, *) {
            content.listStyle(.insetGrouped)
        } else {
            content.listStyle(.grouped)
        }
    }
}
#endif

/// Sidebar "Tab Overview": running clients. Tap Focus / card to show Metal.
struct WWNTabOverviewView: View {
    @ObservedObject private var model = WWNMachinesViewModel.shared

    private var running: [WWNMachineProfile] {
        model.profiles.filter { profile in
            let st = model.status(for: profile.machineId)
            return st == .connected || st == .connecting || st == .preparing
        }
    }

    var body: some View {
        Group {
            if running.isEmpty {
                WawonaEmptyState(
                    "No Running Clients",
                    systemImage: "square.on.square",
                    description: Text("Start a machine, then open it from here or Focus on the card.")
                )
            } else {
                List {
                    ForEach(running, id: \.machineId) { profile in
                        Button {
                            model.focusRunningMachine(profile)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "display")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name.isEmpty ? "Machine" : profile.name)
                                        .foregroundColor(.primary)
                                    Text(subtitle(for: profile))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Focus")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .accessibility(identifier: "wwn.tabOverview.row.\(profile.machineId ?? "")")
                    }
                }
                #if os(iOS) || os(visionOS)
                .modifier(WWNTabOverviewListStyle())
                #endif
            }
        }
        .backport.navigationTitle("Tab Overview")
    }

    private func subtitle(for profile: WWNMachineProfile) -> String {
        let st = model.status(for: profile.machineId).title
        if WWNMachineSessionBridge.profileUsesNativeCompositorClient(profile) {
            let client = WWNMachineSessionBridge.nativeClientId(forProfile: profile) ?? "wayland"
            return "\(st) · \(client)"
        }
        return st
    }
}
#endif
