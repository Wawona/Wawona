#if os(iOS) || os(visionOS) || os(macOS) || os(tvOS)
import SwiftUI
import WawonaModel

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Safari-style Tab Overview: search + client preview cards for running sessions.
/// SwiftUI only. Focus reveals the compositor; Stop parks the machine.
struct WWNTabOverviewView: View {
    @ObservedObject private var model = WWNMachinesViewModel.shared
    @State private var searchQuery = ""

    private var runningProfiles: [WWNMachineProfile] {
        model.profiles.filter { profile in
            let status = model.status(for: profile.machineId)
            let active = WWNMachineProfileStore.activeMachineId() == profile.machineId
            return status == .connected || status == .connecting || active
        }
    }

    private var filteredProfiles: [WWNMachineProfile] {
        let titles = runningProfiles.map(\.name)
        let indices = MachineProfileDomain.tabOverviewFilterIndices(
            query: searchQuery,
            titles: titles
        )
        return indices.compactMap { idx in
            guard runningProfiles.indices.contains(idx) else { return nil }
            return runningProfiles[idx]
        }
    }

    private var tabCountString: String {
        let n = filteredProfiles.count
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
            if runningProfiles.isEmpty {
                emptyState
            } else {
                overviewBody
            }
        }
        .backport.navigationTitle("Tab Overview")
        .backport.searchable(text: $searchQuery, prompt: "Search Tabs")
        .backport.background { tabOverviewSearchPlacement }
        .accessibility(identifier: "wwn.tabOverview.detail")
    }

    /// Phone iOS 26: keep search in the navigation bar. The Machines bottom
    /// bar button belongs to a different navigation item and UIKit ignores it
    /// on this page.
    @ViewBuilder
    private var tabOverviewSearchPlacement: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            if #available(iOS 26.0, *) {
                WWNPhoneIntegratedSearchToolbar(placement: .navigationBarStacked, onCompose: {})
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
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
            Text("Start a machine, then open Tab Overview to switch sessions.")
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

            if filteredProfiles.isEmpty {
                Text("No Matching Tabs")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Group {
                        if #available(iOS 14, tvOS 14, macOS 11, *) {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredProfiles, id: \.machineId) { profile in
                                    card(for: profile)
                                }
                            }
                        } else {
                            VStack(spacing: 16) {
                                ForEach(filteredProfiles, id: \.machineId) { profile in
                                    card(for: profile)
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

    private func card(for profile: WWNMachineProfile) -> some View {
        let mid = profile.machineId
        let status = model.status(for: mid)
        let isActive = WWNMachineProfileStore.activeMachineId() == mid
        let title = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "Untitled" : title
        return WWNTabOverviewCard(
            title: displayTitle,
            statusLabel: statusLabel(status, isActive: isActive),
            isSelected: isActive,
            thumbnail: model.thumbnailImage(for: profile),
            onFocus: {
                model.focusRunningMachine(profile)
            },
            onClose: {
                model.disconnect(profile)
            }
        )
        .accessibility(identifier: "wwn.tabOverview.card.\(mid)")
    }

    private func statusLabel(_ status: WWNMachineTransientStatus, isActive: Bool) -> String {
        let base: String
        switch status {
        case .connected: base = "Running"
        case .connecting, .preparing: base = "Starting"
        default: base = "Session"
        }
        if isActive { return "\(base) · Active" }
        return base
    }
}

private struct WWNTabOverviewCard: View {
    let title: String
    let statusLabel: String
    let isSelected: Bool
    let thumbnail: WWNPlatformImage?
    let onFocus: () -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipeOffset: CGFloat = 0

    private var clientRatio: CGFloat? {
        guard let thumbnail, thumbnail.size.height > 1 else { return nil }
        return thumbnail.size.width / thumbnail.size.height
    }

    private var iconName: String {
        let lower = title.lowercased()
        if lower.contains("term") || lower.contains("zsh") || lower.contains("shell") {
            return "terminal.fill"
        }
        if lower.contains("niri") { return "rectangle.split.3x1" }
        if lower.contains("weston") { return "macwindow" }
        return "desktopcomputer"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .accessibility(label: Text("Close \(title)"))
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Button(action: onFocus) {
                WWNTabPreviewWell(
                    iconName: iconName,
                    statusLabel: statusLabel,
                    thumbnail: thumbnail,
                    clientRatio: clientRatio
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .accessibility(label: Text("\(title), \(statusLabel)"))
            .accessibility(hint: Text("Double tap to focus"))
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 2.5 : 0.8
                        )
                )
        )
        #if !os(macOS) && !os(tvOS)
        .offset(x: swipeOffset)
        .simultaneousGesture(swipeToClose)
        #endif
    }

    #if !os(macOS) && !os(tvOS)
    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                let across = value.translation.width
                let down = abs(value.translation.height)
                guard across < 0, down < abs(across) else { return }
                swipeOffset = across
            }
            .onEnded { value in
                let across = value.translation.width
                let down = abs(value.translation.height)
                if across < -56, down < abs(across) {
                    onClose()
                } else if reduceMotion {
                    swipeOffset = 0
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        swipeOffset = 0
                    }
                }
            }
    }
    #endif
}

private struct WWNTabPreviewWell: View {
    let iconName: String
    let statusLabel: String
    let thumbnail: WWNPlatformImage?
    let clientRatio: CGFloat?

    var body: some View {
        Group {
            if let thumbnail {
                #if os(macOS)
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #endif
            } else {
                VStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 28))
                        .foregroundColor(Color.secondary.opacity(0.5))
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(clientRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
#endif
