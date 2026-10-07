import Foundation
import WawonaModel
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@objc(WWNWatchCompanionBridge)
public final class WWNWatchCompanionBridge: NSObject {

    @objc public static let sharedBridge: WWNWatchCompanionBridge = {
        WWNWatchCompanionBridge()
    }()

    private let controller = WatchCompanionController.shared

    @objc public func activate() {
        controller.activate()
    }

    @objc public func statusSummary() -> String {
        controller.status().summary
    }

    @objc public func lastTransferSummary() -> String {
        controller.status().lastTransferSummary
    }

    @objc(sendDocumentAtURL:)
    public func sendDocument(atURL fileURL: URL?) -> String? {
        guard let fileURL else { return "No file selected." }
        switch controller.sendDocument(at: fileURL) {
        case .queued:
            return nil
        case .failed(let message):
            return message
        }
    }

    @objc public func watchDisplayReachable() -> Bool {
        #if canImport(WatchConnectivity) && os(iOS)
        guard WCSession.isSupported() else { return false }
        controller.activate()
        let session = WCSession.default
        return session.activationState == .activated && session.isReachable
        #else
        return false
        #endif
    }

    @objc(offerDisplayJPEG:width:height:)
    public func offerDisplay(jpeg: Data?, width: CGFloat, height: CGFloat) {
        #if canImport(WatchConnectivity) && os(iOS)
        guard let jpeg, !jpeg.isEmpty, watchDisplayReachable() else { return }
        let message: [String: Any] = [
            "kind": "display-frame",
            "jpeg": jpeg,
            "w": width,
            "h": height,
        ]
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        #else
        _ = jpeg
        _ = width
        _ = height
        #endif
    }
}
