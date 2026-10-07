import Foundation

/// Bridges `wwn_startup_log_sink` to Swift. Replaces `WWNStartupLogger.m`.
@objc(WWNStartupLogger)
public final class WWNStartupLogger: NSObject {
    @objc public static let shared = WWNStartupLogger()

    @objc public weak var delegate: WWNStartupLoggerDelegate?

    private let queue = DispatchQueue(label: "com.aspauldingcode.wawona.startuplog")
    private var lines: [String] = []

    private override init() {
        super.init()
    }

    @objc public func beginCapture() {
        queue.sync { lines.removeAll(keepingCapacity: true) }
        wwn_startup_log_sink = startupLogSinkTrampoline
    }

    @objc public func endCapture() {
        wwn_startup_log_sink = nil
    }

    @objc public func appendLine(_ line: String) {
        queue.async {
            self.lines.append(line)
            let delegate = self.delegate
            DispatchQueue.main.async {
                delegate?.startupLogger(self, didAppendLine: line)
            }
        }
    }

    @objc public func capturedLines() -> [String] {
        queue.sync { lines }
    }
}

@objc public protocol WWNStartupLoggerDelegate: AnyObject {
    @objc(startupLogger:didAppendLine:)
    func startupLogger(_ logger: WWNStartupLogger, didAppendLine line: String)
}

private func startupLogSinkTrampoline(
    _ module: UnsafePointer<CChar>?,
    _ msg: UnsafePointer<CChar>?
) {
    let m = module.map { String(cString: $0) } ?? "?"
    let body = msg.map { String(cString: $0) } ?? ""
    WWNStartupLogger.shared.appendLine("[\(m)] \(body)")
}

@_silgen_name("wwn_startup_log_sink")
var wwn_startup_log_sink: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void)?
