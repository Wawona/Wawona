import Combine
import Foundation
#if os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// iCloud sync for every Apple target through the private CloudKit database
/// (`iCloud.com.aspauldingcode.Wawona`). Mirrors machine profiles, tags,
/// pins, env overrides, portable prefs, and shell HOME files. Policy (which
/// keys, redaction, HOME skips, conflict winner) is rust `cloud_sync`; this
/// type moves records.
@MainActor
public final class WWNCloudSync: ObservableObject {
    public static let shared = WWNCloudSync()
    public static let containerIdentifier = "iCloud.com.aspauldingcode.Wawona"
    nonisolated public static let enabledKey = "wawona.pref.cloudKitSyncEnabled"
    nonisolated public static let didApplyRemoteChanges = Notification.Name("WWNCloudSyncDidApplyRemoteChanges")
    static let backgroundRefreshIdentifier = "wawona.cloudsync"

    public enum Status: Equatable {
        case off
        case notEntitled
        case needsNewerOS
        case unavailable(String)
        case idle
        case syncing
        case failed(String)

        public var summary: String {
            switch self {
            case .off: return "Off. Settings and files stay on this device."
            case .notEntitled: return "This build is not signed for iCloud."
            case .needsNewerOS: return "iCloud sync needs iOS 15 or later."
            case .unavailable(let why): return why
            case .idle: return "On. Synced with iCloud."
            case .syncing: return "Syncing with iCloud..."
            case .failed(let why): return "Last sync failed: \(why)"
            }
        }
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var lastSync: Date?
    @Published public private(set) var homeFileCount = 0
    @Published public private(set) var homeLimitReached = false

    public var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                requestSync(after: 0)
            } else {
                debounce?.cancel()
                status = .off
            }
        }
    }

    /// True when this process may create a `CKContainer`.
    public let isEntitled = CloudSyncEntitlement.processHasCloudKit(container: WWNCloudSync.containerIdentifier)

    var homePath: () -> String = WWNCloudSync.defaultHomePath
    var applyingRemote = false
    private var started = false
    private var running = false
    private var rerun = false
    private var debounce: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {
        if !isEnabled { status = .off }
    }

    public static func defaultHomePath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return docs.appendingPathComponent("Wawona/home", isDirectory: true).path
    }

    /// Call once at launch. `homePath` returns the live shell HOME (iCloud
    /// Drive HOME on iOS / macOS when that toggle is on).
    public func start(homePath: (() -> String)? = nil) {
        if let homePath { self.homePath = homePath }
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let sync = WWNCloudSync.shared
                guard !sync.applyingRemote, sync.localDefaultsChanged() else { return }
                sync.requestSync(after: 3)
            }
        })
        observers.append(center.addObserver(
            forName: Notification.Name("CKAccountChanged"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in WWNCloudSync.shared.requestSync(after: 0) }
        })
        if let active = Self.becameActiveNotification {
            observers.append(center.addObserver(forName: active, object: nil, queue: .main) { _ in
                Task { @MainActor in WWNCloudSync.shared.requestSync(after: 0.5) }
            })
        }
        requestSync(after: 1)
    }

    public func requestSync(after delay: TimeInterval) {
        debounce?.cancel()
        debounce = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Manual Sync Now, push wake, and background refresh all land here.
    public func syncNow() async {
        guard isEnabled else { status = .off; return }
        guard CloudSyncPolicy.rustLinked, isEntitled else { status = .notEntitled; return }
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            status = .needsNewerOS
            return
        }
        if running { rerun = true; return }
        running = true
        status = .syncing
        let outcome = await CloudSyncPass(owner: self).run()
        running = false
        switch outcome {
        case .synced(let files, let limited):
            lastSync = Date()
            homeFileCount = files
            homeLimitReached = limited
            status = .idle
        case .unavailable(let why):
            status = .unavailable(why)
        case .failed(let why):
            status = .failed(why)
        }
        scheduleBackgroundRefresh()
        if rerun {
            rerun = false
            requestSync(after: 0.5)
        }
    }

    func announceRemoteChanges() {
        NotificationCenter.default.post(name: Self.didApplyRemoteChanges, object: nil)
    }

    private func localDefaultsChanged() -> Bool {
        guard isEnabled, CloudSyncPolicy.rustLinked else { return false }
        let state = CloudSyncState.load()
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where CloudSyncPolicy.isSyncedDefaultsKey(key)
        {
            let hash = CloudSyncDefaults.payload(for: key).map(CloudSyncState.digest)
            if hash != state.defaults[key]?.hash { return true }
        }
        return false
    }

    private func scheduleBackgroundRefresh() {
        #if os(watchOS)
        guard isEnabled else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(30 * 60),
            userInfo: Self.backgroundRefreshIdentifier as NSString
        ) { _ in }
        #endif
    }

    private static var becameActiveNotification: Notification.Name? {
        #if os(watchOS)
        return WKApplication.didBecomeActiveNotification
        #elseif canImport(UIKit)
        return UIApplication.didBecomeActiveNotification
        #elseif canImport(AppKit)
        return NSApplication.didBecomeActiveNotification
        #else
        return nil
        #endif
    }
}
