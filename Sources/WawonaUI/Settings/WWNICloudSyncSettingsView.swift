#if os(iOS) || os(macOS) || os(visionOS) || os(tvOS)
import SwiftUI
import WawonaModel
import WawonaUIContracts

/// iCloud Sync detail. CloudKit mirrors machines, tags, pins, env vars,
/// portable prefs, and shell HOME on every Apple target. iOS, macOS, and
/// visionOS also offer the older iCloud Drive HOME location (Drive does not
/// exist on tvOS / watchOS, Apple QA1935).
struct WWNICloudSyncSettingsView: View {
    @Environment(\.settingsSectionAccent) private var sectionAccent
    @ObservedObject private var cloud = WWNCloudSync.shared
    #if !os(tvOS)
    @State private var driveEnabled = false
    @State private var driveSummary = ""
    @State private var locationPath = ""
    @State private var errorMessage = ""
    @State private var showError = false
    /// Suppresses onChange while `refresh()` writes `@State`.
    @State private var isRefreshing = false
    #endif

    private var cloudEnabled: Binding<Bool> {
        Binding(get: { cloud.isEnabled }, set: { cloud.isEnabled = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: cloudEnabled) {
                    Text("iCloud Sync")
                }
                .backport.tint(sectionAccent)
                .accessibility(identifier: WWNA11y.settingsICloudSyncToggle)
            } footer: {
                Text("Machines, tags, pins, environment variables, preferences, and shell HOME files follow this Apple ID on every Apple device. Passwords stay on this device.")
            }

            Section {
                statusRow(title: "Status", value: statusTitle)
                if let last = cloud.lastSync {
                    statusRow(title: "Last Synced", value: Self.relative.localizedString(for: last, relativeTo: Date()))
                }
                if cloud.homeFileCount > 0 {
                    statusRow(title: "HOME Files", value: "\(cloud.homeFileCount)")
                }
                Button {
                    Task { await cloud.syncNow() }
                } label: {
                    Text("Sync Now")
                }
                .disabled(!cloud.isEnabled || cloud.status == .syncing || !cloud.isEntitled)
                .accessibility(identifier: WWNA11y.settingsICloudSyncNow)
            } header: {
                Text("CloudKit")
            } footer: {
                Text(statusFooter)
            }

            #if !os(tvOS)
            Section {
                Toggle(isOn: $driveEnabled) {
                    Text("Keep HOME in iCloud Drive")
                }
                .backport.tint(sectionAccent)
                .accessibility(identifier: WWNA11y.settingsICloudDriveToggle)
                if !locationPath.isEmpty {
                    statusRow(title: "Location", value: shortenedPath(locationPath))
                }
            } header: {
                Text("iCloud Drive")
            } footer: {
                Text(driveSummary)
            }
            #endif
        }
        #if os(macOS)
        .backport.groupedForm()
        #endif
        #if os(iOS)
        .backport.dismissKeyboardOnScroll()
        #endif
        #if !os(tvOS)
        .onAppear(perform: refresh)
        .backport.onChange(of: driveEnabled) { newValue in
            guard !isRefreshing else { return }
            applyDrive(newValue)
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("iCloud Drive Failed"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibility(identifier: WWNA11y.settingsICloudSync)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var statusTitle: String {
        switch cloud.status {
        case .off: return "Off"
        case .idle: return "Up to Date"
        case .syncing: return "Syncing"
        case .failed: return "Error"
        case .notEntitled, .needsNewerOS, .unavailable: return "Unavailable"
        }
    }

    private var statusFooter: String {
        var text = cloud.status.summary
        if cloud.homeLimitReached {
            text += " Some large HOME files stay on this device."
        }
        return text
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .backport.secondaryForeground()
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibility(label: Text("\(title), \(value)"))
    }

    #if !os(tvOS)
    private func applyDrive(_ value: Bool) {
        if value == WWNRootfsICloudSync.isEnabled() {
            refresh()
            return
        }
        do {
            _ = try WWNRootfsProvider.setICloudSyncEnabled(value)
            refresh()
            cloud.requestSync(after: 1)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            refresh()
        }
    }

    private func refresh() {
        isRefreshing = true
        driveEnabled = WWNRootfsICloudSync.isEnabled()
        driveSummary = WWNRootfsICloudSync.statusSummary()
        if driveEnabled, let drive = WWNRootfsICloudSync.icloudHomePath(), !drive.isEmpty {
            locationPath = drive
        } else {
            locationPath = WWNRootfsICloudSync.localHomePath()
        }
        isRefreshing = false
    }

    /// Prefer a short trailing path for Settings rows (full paths wrap badly).
    private func shortenedPath(_ path: String) -> String {
        if path.contains("/Mobile Documents/") || path.contains("com~apple~CloudDocs") {
            let parts = path.split(separator: "/")
            if parts.count > 3 {
                return "iCloud Drive/…" + parts.suffix(2).joined(separator: "/")
            }
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
        if let docs, path.hasPrefix(docs) {
            return "Documents" + String(path.dropFirst(docs.count))
        }
        let parts = path.split(separator: "/")
        if parts.count > 3 {
            return "…/" + parts.suffix(3).joined(separator: "/")
        }
        return path
    }
    #endif
}
#endif
