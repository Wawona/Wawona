import Foundation
#if os(macOS)
import AppKit
#endif

@objc(WWNMachineThumbnailStore)
public final class WWNMachineThumbnailStore: NSObject {

    @objc public static func thumbnailsDirectory() -> String {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return (NSTemporaryDirectory() as NSString).appendingPathComponent("wawona-thumbnails")
        }
        let dirURL = base
            .appendingPathComponent("Wawona", isDirectory: true)
            .appendingPathComponent("MachineThumbnails", isDirectory: true)
        try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL.path
    }

    @objc public static func safeMachineId(_ machineId: String) -> String {
        machineId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    }

    @objc(thumbnailPathForMachineId:)
    public static func thumbnailPath(forMachineId machineId: String) -> String? {
        guard !machineId.isEmpty else { return nil }
        let file = safeMachineId(machineId) + ".png"
        return (thumbnailsDirectory() as NSString).appendingPathComponent(file)
    }

    #if os(macOS)
    @objc(thumbnailForMachineId:)
    public static func thumbnail(forMachineId machineId: String) -> NSImage? {
        guard let path = thumbnailPath(forMachineId: machineId), !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    @objc(saveThumbnailPNGData:forMachineId:)
    public static func saveThumbnail(pngData: Data, forMachineId machineId: String) -> Bool {
        guard !pngData.isEmpty, !machineId.isEmpty,
              let path = thumbnailPath(forMachineId: machineId), !path.isEmpty else {
            return false
        }
        return (pngData as NSData).write(toFile: path, atomically: true)
    }

    @objc(saveThumbnailFromWindow:machineId:)
    public static func saveThumbnail(from window: NSWindow, machineId: String) -> Bool {
        guard let view = window.contentView, !machineId.isEmpty else { return false }
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return false }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)

        let maxEdge: CGFloat = 320
        let scale = min(1, maxEdge / max(bounds.width, bounds.height))
        let outW = max(1, Int(floor(bounds.width * scale)))
        let outH = max(1, Int(floor(bounds.height * scale)))

        guard let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outW,
            pixelsHigh: outH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            guard let png = rep.representation(using: .png, properties: [:]) else { return false }
            return saveThumbnail(pngData: png, forMachineId: machineId)
        }

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: outRep) {
            NSGraphicsContext.current = ctx
            let full = NSImage(size: rep.size)
            full.addRepresentation(rep)
            full.draw(
                in: NSRect(x: 0, y: 0, width: CGFloat(outW), height: CGFloat(outH)),
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.medium]
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let png = outRep.representation(using: .png, properties: [:]) else { return false }
        return saveThumbnail(pngData: png, forMachineId: machineId)
    }

    @objc(captureAndSaveThumbnailForMachineId:)
    public static func captureAndSaveThumbnail(forMachineId machineId: String) -> Bool {
        guard !machineId.isEmpty else { return false }
        guard let png = WWNCompositorBridge.sharedBridge.captureCurrentSessionThumbnailPNGData() else {
            return false
        }
        return saveThumbnail(pngData: png, forMachineId: machineId)
    }
    #endif

    @objc(deleteThumbnailForMachineId:)
    public static func deleteThumbnail(forMachineId machineId: String) {
        guard let path = thumbnailPath(forMachineId: machineId), !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
