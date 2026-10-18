#if os(watchOS)
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WawonaModel

extension Notification.Name {
    static let wwnWatchMachineThumbnail = Notification.Name("WWNWatchMachineThumbnailNotification")
}

/// Saved session preview for Machine Configuration rows.
/// Same idea as `WWNMachineThumbnailStore` on the other Apple targets.
enum WatchMachineThumbnailStore {
    private static var lastCapture: [String: Date] = [:]

    @MainActor
    static func isEnabled(profile: MachineProfile, preferences: WawonaPreferences) -> Bool {
        if let override = profile.runtimeOverrides.machineThumbnailEnabledOverride {
            return override
        }
        return preferences.machineSessionThumbnailsEnabled
    }

    static func load(machineId: String) -> UIImage? {
        guard let url = fileURL(machineId: machineId),
              let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        return image
    }

    @MainActor
    static func captureIfEnabled(
        profile: MachineProfile,
        preferences: WawonaPreferences,
        image: CGImage?
    ) {
        guard isEnabled(profile: profile, preferences: preferences), let image else { return }
        let now = Date()
        if let previous = lastCapture[profile.id], now.timeIntervalSince(previous) < 2 {
            return
        }
        lastCapture[profile.id] = now
        guard let url = fileURL(machineId: profile.id),
              let data = pngData(image, maxEdge: 160)
        else { return }
        try? data.write(to: url, options: .atomic)
        NotificationCenter.default.post(
            name: .wwnWatchMachineThumbnail,
            object: nil,
            userInfo: ["machineId": profile.id]
        )
    }

    private static func fileURL(machineId: String) -> URL? {
        guard !machineId.isEmpty else { return nil }
        let safe = machineId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let dir = base
            .appendingPathComponent("Wawona", isDirectory: true)
            .appendingPathComponent("MachineThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(safe + ".png")
    }

    private static func pngData(_ image: CGImage, maxEdge: Int) -> Data? {
        let longest = max(image.width, image.height)
        let scale = min(1, CGFloat(maxEdge) / CGFloat(max(longest, 1)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded(.down)))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded(.down)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, scaled, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

/// Preview above the machine name. Full row width so the title stays readable.
struct WatchMachineRowPreview: View {
    let profile: MachineProfile
    var tags: [WWNMachineTag] = []
    var isPinned = false
    @ObservedObject private var preferences = WawonaPreferences.shared
    @State private var image: UIImage?

    private var enabled: Bool {
        WatchMachineThumbnailStore.isEnabled(profile: profile, preferences: preferences)
    }

    var body: some View {
        Group {
            if enabled, let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .clipped()
            } else if enabled {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.35), Color.indigo.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
        }
        .overlay {
            if enabled, !tags.isEmpty || isPinned {
                HStack(spacing: 4) {
                    WatchTagDots(tags: tags)
                    Spacer(minLength: 2)
                    if isPinned {
                        WatchMachinePinMark()
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .compositingGroup()
        .modifier(WatchMachineThumbnailClip())
        .padding(.top, enabled ? 6 : 0)
        .padding(.horizontal, enabled ? -4 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!enabled)
        .accessibilityIdentifier("wwn.machine.thumbnail.\(profile.id)")
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .wwnWatchMachineThumbnail)) { note in
            guard note.userInfo?["machineId"] as? String == profile.id else { return }
            reload()
        }
        .onChange(of: enabled) { _, _ in reload() }
    }

    private func reload() {
        image = enabled ? WatchMachineThumbnailStore.load(machineId: profile.id) : nil
    }
}

/// Nested in the machine platter. Concentric corners follow that platter
/// and never collapse to a square when the inset is large.
private struct WatchMachineThumbnailClip: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *) {
            content.clipShape(
                ConcentricRectangle(
                    corners: .concentric(minimum: .fixed(10)),
                    isUniform: true
                )
            )
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
#endif
