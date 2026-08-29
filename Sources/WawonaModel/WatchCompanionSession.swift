import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Preference keys + status for iOS → Apple Watch document transfer (#151).
public enum WatchCompanionPrefs {
    public static let lastTransferNameKey = "wawona.pref.watchCompanionLastTransferName"
    public static let lastTransferStatusKey = "wawona.pref.watchCompanionLastTransferStatus"
    public static let lastTransferAtKey = "wawona.pref.watchCompanionLastTransferAt"
}

public struct WatchCompanionStatus: Sendable, Equatable {
    public var supported: Bool
    public var paired: Bool
    public var watchAppInstalled: Bool
    public var reachable: Bool
    public var summary: String
    public var lastTransferSummary: String

    public init(
        supported: Bool,
        paired: Bool,
        watchAppInstalled: Bool,
        reachable: Bool,
        summary: String,
        lastTransferSummary: String
    ) {
        self.supported = supported
        self.paired = paired
        self.watchAppInstalled = watchAppInstalled
        self.reachable = reachable
        self.summary = summary
        self.lastTransferSummary = lastTransferSummary
    }
}

public enum WatchCompanionSendResult: Sendable, Equatable {
    case queued(fileName: String)
    case failed(message: String)
}

/// Test seam for WatchConnectivity (no hardware in CI).
public protocol WatchCompanionTransport: AnyObject {
    var isSupported: Bool { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isReachable: Bool { get }
    func activate()
    /// Queue a file for delivery. Caller owns the source URL until this returns.
    func transferFile(from url: URL, metadata: [String: Any]) -> WatchCompanionSendResult
}

public final class WatchCompanionController: @unchecked Sendable {
    public static let shared = WatchCompanionController()

    private let defaults: UserDefaults
    private let transport: WatchCompanionTransport

    public init(
        defaults: UserDefaults = .standard,
        transport: WatchCompanionTransport = WatchCompanionController.makeDefaultTransport()
    ) {
        self.defaults = defaults
        self.transport = transport
    }

    public static func makeDefaultTransport() -> WatchCompanionTransport {
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        return WCSessionWatchCompanionTransport.shared
        #else
        return NullWatchCompanionTransport()
        #endif
    }

    public func activate() {
        transport.activate()
    }

    public func status() -> WatchCompanionStatus {
        let supported = transport.isSupported
        let paired = transport.isPaired
        let installed = transport.isWatchAppInstalled
        let reachable = transport.isReachable
        let summary: String
        if !supported {
            summary = "WatchConnectivity unavailable on this platform."
        } else if !paired {
            summary = "No paired Apple Watch."
        } else if !installed {
            summary = "Wawona is not installed on the paired Watch."
        } else if reachable {
            summary = "Watch reachable. Transfers deliver immediately when possible."
        } else {
            summary = "Watch paired; not reachable. Transfers queue until the Watch wakes."
        }
        return WatchCompanionStatus(
            supported: supported,
            paired: paired,
            watchAppInstalled: installed,
            reachable: reachable,
            summary: summary,
            lastTransferSummary: lastTransferSummary()
        )
    }

    public func sendDocument(at url: URL) -> WatchCompanionSendResult {
        let name = url.lastPathComponent
        let result = transport.transferFile(
            from: url,
            metadata: ["name": name, "kind": "document"]
        )
        switch result {
        case .queued(let fileName):
            defaults.set(fileName, forKey: WatchCompanionPrefs.lastTransferNameKey)
            defaults.set("queued", forKey: WatchCompanionPrefs.lastTransferStatusKey)
            defaults.set(Date().timeIntervalSince1970, forKey: WatchCompanionPrefs.lastTransferAtKey)
        case .failed(let message):
            defaults.set(name, forKey: WatchCompanionPrefs.lastTransferNameKey)
            defaults.set("failed: \(message)", forKey: WatchCompanionPrefs.lastTransferStatusKey)
            defaults.set(Date().timeIntervalSince1970, forKey: WatchCompanionPrefs.lastTransferAtKey)
        }
        return result
    }

    /// Watch-side: persist a received file into Documents/Wawona/inbox/.
    @discardableResult
    public static func ingestReceivedFile(at url: URL, preferredName: String?) -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let inbox = docs.appendingPathComponent("Wawona/inbox", isDirectory: true)
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let name = (preferredName?.isEmpty == false) ? preferredName! : url.lastPathComponent
        let dest = inbox.appendingPathComponent(name)
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: url, to: dest)
            UserDefaults.standard.set(name, forKey: WatchCompanionPrefs.lastTransferNameKey)
            UserDefaults.standard.set("received", forKey: WatchCompanionPrefs.lastTransferStatusKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: WatchCompanionPrefs.lastTransferAtKey)
            return dest
        } catch {
            return nil
        }
    }

    private func lastTransferSummary() -> String {
        let name = defaults.string(forKey: WatchCompanionPrefs.lastTransferNameKey) ?? ""
        let status = defaults.string(forKey: WatchCompanionPrefs.lastTransferStatusKey) ?? ""
        let at = defaults.double(forKey: WatchCompanionPrefs.lastTransferAtKey)
        if name.isEmpty {
            return "No transfers yet."
        }
        if at > 0 {
            let date = Date(timeIntervalSince1970: at)
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "\(name). \(status) (\(formatter.string(from: date)))"
        }
        return "\(name). \(status)"
    }
}

// MARK: - Transports

public final class NullWatchCompanionTransport: WatchCompanionTransport {
    public init() {}
    public var isSupported: Bool { false }
    public var isPaired: Bool { false }
    public var isWatchAppInstalled: Bool { false }
    public var isReachable: Bool { false }
    public func activate() {}
    public func transferFile(from url: URL, metadata: [String: Any]) -> WatchCompanionSendResult {
        .failed(message: "WatchConnectivity unavailable")
    }
}

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
public final class WCSessionWatchCompanionTransport: NSObject, WatchCompanionTransport, WCSessionDelegate {
    public static let shared = WCSessionWatchCompanionTransport()

    private override init() {
        super.init()
    }

    public var isSupported: Bool { WCSession.isSupported() }

    public var isPaired: Bool {
        #if os(iOS)
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isPaired
        #else
        return true
        #endif
    }

    public var isWatchAppInstalled: Bool {
        #if os(iOS)
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isWatchAppInstalled
        #else
        return true
        #endif
    }

    public var isReachable: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isReachable
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
        }
        session.activate()
    }

    public func transferFile(from url: URL, metadata: [String: Any]) -> WatchCompanionSendResult {
        guard WCSession.isSupported() else {
            return .failed(message: "WatchConnectivity unsupported")
        }
        #if os(iOS)
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
        }
        if session.activationState != .activated {
            session.activate()
        }
        guard session.isPaired else {
            return .failed(message: "No paired Apple Watch")
        }
        guard session.isWatchAppInstalled else {
            return .failed(message: "Wawona Watch app not installed")
        }
        _ = session.transferFile(url, metadata: metadata)
        return .queued(fileName: url.lastPathComponent)
        #else
        return .failed(message: "Send is iPhone-only")
        #endif
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        _ = activationState
        _ = error
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    #if os(watchOS)
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let name = file.metadata?["name"] as? String
        _ = WatchCompanionController.ingestReceivedFile(at: file.fileURL, preferredName: name)
    }
    #endif
}
#endif
