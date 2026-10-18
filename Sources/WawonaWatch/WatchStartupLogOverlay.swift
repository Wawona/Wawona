#if os(watchOS)
import Combine
import SwiftUI

/// Feeds `WWNStartupLogger` into Wawona Terminal during machine Start.
/// Parks when a Wayland client attaches. Done still focuses the surface.
final class WatchStartupLogModel: NSObject, ObservableObject, WWNStartupLoggerDelegate {
    @Published private(set) var lines: [String] = []
    @Published var isPresented = false

    func attach() {
        let logger = WWNStartupLogger.shared
        logger.delegate = self
        lines = logger.capturedLines()
        isPresented = true
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        let logger = WWNStartupLogger.shared
        if logger.delegate === self {
            logger.delegate = nil
        }
        logger.endCapture()
    }

    /// A mapped Wayland client parks this log. The shell stays up.
    func scheduleDismissAfterFirstFrame() {
        dismiss()
    }

    func startupLogger(_ logger: WWNStartupLogger, didAppendLine line: String) {
        lines.append(line)
    }
}

/// Watch Start host: Wawona Terminal chrome over streamed launch / CLI lines.
struct WatchStartupLogOverlay: View {
    @ObservedObject var model: WatchStartupLogModel
    let clientLabel: String
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !clientLabel.isEmpty {
                Text("$ \(clientLabel)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.65))
                    .lineLimit(1)
            }

            WatchTerminalScreen(text: model.lines.joined(separator: "\n"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier("wwn.terminal.root")
        .accessibilityAction(named: "Leave Terminal", onClose)
    }
}
#endif
