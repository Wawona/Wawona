#if os(watchOS)
import Combine
import SwiftUI

/// Feeds `WWNStartupLogger` into SwiftUI during machine connect (parity with
/// iOS `WWNStartupLogViewController` / Android `StartupLogOverlay`).
final class WatchStartupLogModel: NSObject, ObservableObject, WWNStartupLoggerDelegate {
    @Published private(set) var lines: [String] = []
    @Published var isPresented = false

    private var didScheduleDismiss = false
    private var timeoutWorkItem: DispatchWorkItem?

    func attach() {
        let logger = WWNStartupLogger.shared()
        logger.delegate = self
        lines = logger.capturedLines as? [String] ?? []
        isPresented = true
        didScheduleDismiss = false
        timeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        timeoutWorkItem = timeout
        // Match iOS WWNStartupLogViewController auto-timeout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        let logger = WWNStartupLogger.shared()
        if logger.delegate === self {
            logger.delegate = nil
        }
        logger.endCapture()
    }

    /// Call on first Wayland SHM frame; brief delay so a few lines are readable.
    func scheduleDismissAfterFirstFrame() {
        guard isPresented, !didScheduleDismiss else { return }
        didScheduleDismiss = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.dismiss()
        }
    }

    func startupLogger(_ logger: Any, didAppendLine line: String) {
        lines.append(line)
    }
}

/// Compact watch overlay: spinner header + mono scroll of launch lines.
struct WatchStartupLogOverlay: View {
    @ObservedObject var model: WatchStartupLogModel
    let clientLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Starting \(clientLabel)")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Done") {
                    model.dismiss()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.cyan)
            }

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
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.88))
        .accessibilityIdentifier("wwn.watch.startupLog")
    }
}
#endif
