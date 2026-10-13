#if os(watchOS)
import Combine
import SwiftUI

/// Feeds `WWNStartupLogger` into Wawona Terminal during machine Start.
/// Stays front until the user taps Done (Focus). No auto-dismiss on first frame.
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

    /// Kept for call-site compatibility; first frame must not hide Terminal.
    func scheduleDismissAfterFirstFrame() {}

    func startupLogger(_ logger: WWNStartupLogger, didAppendLine line: String) {
        lines.append(line)
    }
}

/// Watch Start host: Wawona Terminal chrome over streamed launch / CLI lines.
struct WatchStartupLogOverlay: View {
    @ObservedObject var model: WatchStartupLogModel
    let clientLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Wawona Terminal")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Done") {
                    model.dismiss()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.cyan)
                .accessibilityLabel("Close Terminal")
                .accessibilityIdentifier("wwn.terminal.done")
            }

            if !clientLabel.isEmpty {
                Text("$ \(clientLabel)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.65))
                    .lineLimit(2)
            }

            // watchOS 10+ has ScrollViewReader natively. Phone Terminal uses
            // WawonaBackport.scrollViewReader (iOS 13 floor); Watch does not
            // link WawonaUI Compatibility.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color(red: 0.41, green: 1.0, blue: 0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                }
                .onChange(of: model.lines.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier("wwn.terminal.root")
    }
}
#endif
