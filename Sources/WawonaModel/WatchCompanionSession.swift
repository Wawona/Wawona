import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Typed constant (replaces deleted ObjC `WWNWatchDisplayTouchNotification`).
public let WWNWatchDisplayTouchNotification =
    Notification.Name("WWNWatchDisplayTouchNotification")

/// Preference keys + status for iOS → Apple Watch document transfer (#151).
public enum WatchCompanionPrefs {
    public static let lastTransferNameKey = "wawona.pref.watchCompanionLastTransferName"
    public static let lastTransferStatusKey = "wawona.pref.watchCompanionLastTransferStatus"
    public static let lastTransferAtKey = "wawona.pref.watchCompanionLastTransferAt"
}

/// Posted on the main queue when pairing, reachability, or a transfer changes.
public let WWNWatchCompanionTransferDidChange =
    Notification.Name("WWNWatchCompanionTransferDidChange")

public struct WatchOutstandingTransfer: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
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

    /// Copy a document-picker URL into a stable outbox, then queue it.
    /// `WCSession.transferFile` requires the file to stay until delivery finishes.
    public func stageAndSend(securityScopedSource url: URL) -> WatchCompanionSendResult {
        let displayName = WatchCompanionController.safeFileName(url.lastPathComponent)
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let result = WatchCompanionSendResult.failed(message: "Choose a file, not a folder.")
            record(result, fallbackName: displayName)
            return result
        }
        let staged: URL
        do {
            staged = try stageCopy(of: url, displayName: displayName)
        } catch {
            let result = WatchCompanionSendResult.failed(message: error.localizedDescription)
            record(result, fallbackName: displayName)
            return result
        }
        let result = sendDocument(at: staged, displayName: displayName)
        if case .failed = result {
            try? FileManager.default.removeItem(at: staged)
        }
        return result
    }

    public func sendDocument(at url: URL, displayName: String? = nil) -> WatchCompanionSendResult {
        let name = WatchCompanionController.safeFileName(displayName ?? url.lastPathComponent)
        let transferred = transport.transferFile(
            from: url,
            metadata: ["name": name, "kind": "document"]
        )
        let result: WatchCompanionSendResult
        switch transferred {
        case .queued:
            result = .queued(fileName: name)
        case .failed(let message):
            result = .failed(message: message)
        }
        record(result, fallbackName: name)
        return result
    }

    /// Sender-side completion from `WCSession` `didFinish`.
    public func noteTransferFinished(fileName: String, errorMessage: String?) {
        let name = WatchCompanionController.safeFileName(fileName)
        if let errorMessage, !errorMessage.isEmpty {
            record(.failed(message: errorMessage), fallbackName: name)
            return
        }
        defaults.set(name, forKey: WatchCompanionPrefs.lastTransferNameKey)
        defaults.set("delivered", forKey: WatchCompanionPrefs.lastTransferStatusKey)
        defaults.set(Date().timeIntervalSince1970, forKey: WatchCompanionPrefs.lastTransferAtKey)
        postTransferDidChange()
    }

    public func outstandingTransfers() -> [WatchOutstandingTransfer] {
        #if canImport(WatchConnectivity) && os(iOS)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            return []
        }
        return WCSession.default.outstandingFileTransfers.map { transfer in
            let url = transfer.file.fileURL
            let name = WatchCompanionController.safeFileName(
                (transfer.file.metadata?["name"] as? String) ?? url.lastPathComponent
            )
            return WatchOutstandingTransfer(id: url.path, name: name)
        }
        #else
        return []
        #endif
    }

    /// Watch-side inbox. iPhone sends land here after `transferFile`.
    public static func inboxDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Wawona/inbox", isDirectory: true)
    }

    public static func inboxFileNames() -> [String] {
        guard let inbox = inboxDirectory() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.map(\.lastPathComponent).sorted()
    }

    /// Watch-side: persist a received file into Documents/Wawona/inbox/.
    @discardableResult
    public static func ingestReceivedFile(at url: URL, preferredName: String?) -> URL? {
        let fm = FileManager.default
        guard let inbox = inboxDirectory() else {
            return nil
        }
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let name = WatchCompanionController.safeFileName(
            (preferredName?.isEmpty == false) ? preferredName! : url.lastPathComponent
        )
        let dest = inbox.appendingPathComponent(name)
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: url, to: dest)
            UserDefaults.standard.set(name, forKey: WatchCompanionPrefs.lastTransferNameKey)
            UserDefaults.standard.set("received", forKey: WatchCompanionPrefs.lastTransferStatusKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: WatchCompanionPrefs.lastTransferAtKey)
            if Thread.isMainThread {
                NotificationCenter.default.post(name: WWNWatchCompanionTransferDidChange, object: nil)
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: WWNWatchCompanionTransferDidChange, object: nil)
                }
            }
            return dest
        } catch {
            return nil
        }
    }

    private func record(_ result: WatchCompanionSendResult, fallbackName: String) {
        switch result {
        case .queued(let fileName):
            defaults.set(fileName, forKey: WatchCompanionPrefs.lastTransferNameKey)
            defaults.set("queued", forKey: WatchCompanionPrefs.lastTransferStatusKey)
        case .failed(let message):
            defaults.set(fallbackName, forKey: WatchCompanionPrefs.lastTransferNameKey)
            defaults.set("failed: \(message)", forKey: WatchCompanionPrefs.lastTransferStatusKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: WatchCompanionPrefs.lastTransferAtKey)
        postTransferDidChange()
    }

    private func postTransferDidChange() {
        let post = {
            NotificationCenter.default.post(name: WWNWatchCompanionTransferDidChange, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    private func stageCopy(of url: URL, displayName: String) throws -> URL {
        let fileManager = FileManager.default
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root
            .appendingPathComponent("Wawona", isDirectory: true)
            .appendingPathComponent("watch-outbox", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(displayName)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: url, to: destination)
        return destination
    }

    static func safeFileName(_ raw: String) -> String {
        let base = (raw as NSString).lastPathComponent
        if base.isEmpty || base == "." || base == ".." {
            return "document"
        }
        return base
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
        if session.delegate !== self {
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
        if session.delegate !== self {
            session.delegate = self
        }
        if session.activationState != .activated {
            session.activate()
            return .failed(message: "Watch session is still starting. Try again in a moment.")
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
        _ = session
        _ = activationState
        _ = error
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WWNWatchCompanionTransferDidChange, object: nil)
        }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        _ = session
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WWNWatchCompanionTransferDidChange, object: nil)
        }
    }

    #if os(iOS)
    public func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        _ = session
        let url = fileTransfer.file.fileURL
        let name = (fileTransfer.file.metadata?["name"] as? String) ?? url.lastPathComponent
        WatchCompanionController.shared.noteTransferFinished(
            fileName: name,
            errorMessage: error?.localizedDescription
        )
        if error == nil {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        _ = session
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WWNWatchCompanionTransferDidChange, object: nil)
        }
    }

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

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard (message["kind"] as? String) == "display-frame",
              let data = message["jpeg"] as? Data else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("WWNWatchDisplayFrameNotification"),
                object: nil,
                userInfo: ["jpeg": data]
            )
        }
    }
    #endif

    #if os(iOS)
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard (message["kind"] as? String) == "display-touch" else { return }
        let info: [String: Any] = [
            "phase": message["phase"] ?? "",
            "x": message["x"] ?? 0,
            "y": message["y"] ?? 0,
        ]
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: WWNWatchDisplayTouchNotification,
                object: nil,
                userInfo: info
            )
        }
    }
    #endif
}
#endif
