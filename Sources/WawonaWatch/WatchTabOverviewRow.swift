#if os(watchOS)
import SwiftUI
import WawonaModel

/// One Tab Overview card. Matches the iOS preview well: title, close, frame.
struct WatchTabOverviewRow: View {
    let profile: MachineProfile
    let session: MachineSession
    let isActive: Bool
    var searchQuery: String = ""
    var onOpen: () -> Void
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameTick = 0
    @State private var swipeOffset: CGFloat = 0

    private var liveFrame: CGImage? {
        guard isActive else { return nil }
        return WWNWatchCompositorBridge.shared.latestFrame
    }

    private var clientRatio: CGFloat? {
        guard let liveFrame, liveFrame.height > 0 else { return nil }
        _ = frameTick
        return CGFloat(liveFrame.width) / CGFloat(liveFrame.height)
    }

    private var title: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
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

    private var statusLabel: String {
        let base: String
        switch session.status {
        case .connected: base = "Running"
        case .connecting: base = "Starting"
        default: base = "Session"
        }
        return isActive ? "\(base) · Active" : base
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                Text(WatchSearchHighlight.name(title, query: searchQuery, scheme: colorScheme))
                    .font(.system(size: 12, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Button(action: onOpen) {
                previewWell
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .accessibilityLabel("\(title), \(statusLabel)")
            .accessibilityHint("Double tap to focus")
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isActive ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isActive ? 2 : 0.8
                        )
                )
        )
        .offset(x: swipeOffset)
        .simultaneousGesture(swipeToClose)
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("WWNWatchCompositorFrameReadyNotification")
        )) { _ in
            frameTick &+= 1
        }
    }

    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                let across = value.translation.width
                let down = abs(value.translation.height)
                guard across < 0, down < abs(across) else { return }
                swipeOffset = across
            }
            .onEnded { value in
                let across = value.translation.width
                let down = abs(value.translation.height)
                if across < -48, down < abs(across) {
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

    private var previewWell: some View {
        Group {
            if let liveFrame {
                Image(uiImage: UIImage(cgImage: liveFrame))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .id(frameTick)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(clientRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
#endif
