import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
public typealias WWNTermPlatformView = NSView
#elseif canImport(UIKit)
import UIKit
public typealias WWNTermPlatformView = UIView
#endif

public typealias WWNTermReply = (Data) -> Void

#if os(macOS)

@_silgen_name("wwn_term_new")
private func wwn_term_new(_ cols: UInt32, _ rows: UInt32) -> OpaquePointer?
@_silgen_name("wwn_term_free")
private func wwn_term_free(_ term: OpaquePointer?)
@_silgen_name("wwn_term_resize")
private func wwn_term_resize(_ term: OpaquePointer?, _ cols: UInt32, _ rows: UInt32)
@_silgen_name("wwn_term_feed")
private func wwn_term_feed(_ term: OpaquePointer?, _ bytes: UnsafePointer<UInt8>?, _ len: Int)
@_silgen_name("wwn_term_viewport")
private func wwn_term_viewport(
    _ term: OpaquePointer?, _ origin: UInt32, _ out: UnsafeMutablePointer<WwnTermCell>?,
    _ cap: UInt32, _ cols: UnsafeMutablePointer<UInt32>?, _ rows: UnsafeMutablePointer<UInt32>?
) -> UInt32
@_silgen_name("wwn_term_origin")
private func wwn_term_origin(_ term: OpaquePointer?) -> UInt32
@_silgen_name("wwn_term_title")
private func wwn_term_title(
    _ term: OpaquePointer?, _ out: UnsafeMutablePointer<UInt8>?, _ cap: UInt32
) -> UInt32
@_silgen_name("wwn_term_string_free")
private func wwn_term_string_free(_ ptr: UnsafeMutablePointer<CChar>?)
@_silgen_name("wwn_term_encode_paste")
private func wwn_term_encode_paste(
    _ term: OpaquePointer?, _ bytes: UnsafePointer<UInt8>?, _ len: Int
) -> UnsafeMutablePointer<CChar>?
@_silgen_name("wwn_term_take_reply")
private func wwn_term_take_reply(
    _ term: OpaquePointer?, _ buf: UnsafeMutablePointer<UInt8>?, _ cap: Int
) -> Int
@_silgen_name("wwn_term_pointer")
private func wwn_term_pointer(
    _ term: OpaquePointer?, _ button: UInt8, _ col: UInt32, _ row: UInt32,
    _ pressed: Int32, _ motion: Int32
)
@_silgen_name("wwn_term_set_cell_px")
private func wwn_term_set_cell_px(_ term: OpaquePointer?, _ width: UInt32, _ height: UInt32)
@_silgen_name("wwn_term_image_count")
private func wwn_term_image_count(_ term: OpaquePointer?) -> UInt32
@_silgen_name("wwn_term_image_meta")
private func wwn_term_image_meta(
    _ term: OpaquePointer?, _ index: UInt32, _ out: UnsafeMutablePointer<WwnTermImage>?
) -> Int32
@_silgen_name("wwn_term_image_rgba")
private func wwn_term_image_rgba(
    _ term: OpaquePointer?, _ index: UInt32, _ out: UnsafeMutablePointer<UInt8>?, _ cap: UInt32
) -> UInt32

struct WwnTermImage {
    var id: UInt32 = 0
    var col: Int32 = 0
    var row: Int32 = 0
    var xPx: Int32 = 0
    var yPx: Int32 = 0
    var pxW: UInt32 = 0
    var pxH: UInt32 = 0
    var cols: UInt32 = 0
    var rows: UInt32 = 0
    var z: Int32 = 0
    var rgbaLen: UInt32 = 0
}

/// AppKit host. The Rust viewport uploads once. Metal draws the grid.
@objc(WWNTermSurface)
public final class WWNTermSurface: NSView {
    @objc public var onReply: WWNTermReply?
    public var onResize: ((UInt32, UInt32) -> Void)?
    public var onTitle: ((String) -> Void)?
    public var gridCols: UInt32 { cols }
    public var gridRows: UInt32 { rows }

    private var term: OpaquePointer?
    private let gpu = TermGpuView(frame: .zero, device: nil)
    private var grid = [WwnTermCell](repeating: WwnTermCell(cp: 32, fg: 0xE8E8E8, bg: 0, attrs: 0), count: 512 * 32)
    private var cols: UInt32 = 80
    private var rows: UInt32 = 24
    private var blinkOn = true
    private var blinkTimer: Timer?
    private let pointSize: CGFloat = 13
    private var cellPxW: CGFloat = 8
    private var cellPxH: CGFloat = 16

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        term = wwn_term_new(cols, rows)
        WawonaTerminalScrollback.apply(to: term)
        gpu.autoresizingMask = [.width, .height]
        gpu.frame = bounds
        addSubview(gpu)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.grid.contains(where: { $0.attrs & 16 != 0 }) else { return }
            self.blinkOn.toggle()
            self.redraw()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        blinkTimer?.invalidate()
        if let term { wwn_term_free(term) }
    }

    public override var acceptsFirstResponder: Bool { true }

    @objc(feed:)
    public func feed(_ bytes: Data) {
        guard let term, !bytes.isEmpty else { return }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            wwn_term_feed(term, base, bytes.count)
        }
        flushReply()
        redraw()
        publishTitle()
    }

    public override func layout() {
        super.layout()
        gpu.frame = bounds
        fit()
    }

    public override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        if event.modifierFlags.contains(.control),
            event.charactersIgnoringModifiers?.lowercased() == "v"
        {
            paste(nil)
            return
        }
        let bytes = macKeyBytes(event)
        if !bytes.isEmpty { onReply?(Data(bytes)) }
    }

    public override func mouseDown(with event: NSEvent) {
        sendPointer(event, pressed: true, motion: false)
    }

    public override func mouseUp(with event: NSEvent) {
        sendPointer(event, pressed: false, motion: false)
    }

    public override func mouseDragged(with event: NSEvent) {
        sendPointer(event, pressed: true, motion: true)
    }

    @objc public func paste(_ sender: Any?) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty, let term else { return }
        let data = Data(text.utf8)
        let wrapped = data.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let ptr = wwn_term_encode_paste(term, base, data.count)
            else { return data }
            let text = String(cString: ptr)
            wwn_term_string_free(ptr)
            return Data(text.utf8)
        }
        onReply?(wrapped)
    }

    private func fit() {
        guard let term, bounds.width > 1, bounds.height > 1 else { return }
        let font = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let cellW = max(1, ("M" as NSString).size(withAttributes: [.font: font]).width)
        let cellH = max(1, font.ascender - font.descender + font.leading)
        let nextCols = UInt32(min(512, max(20, Int((bounds.width - 16) / cellW))))
        let nextRows = UInt32(min(256, max(8, Int(bounds.height / cellH))))
        cellPxW = cellW
        cellPxH = cellH
        wwn_term_set_cell_px(term, UInt32(max(1, cellW.rounded())), UInt32(max(1, cellH.rounded())))
        guard nextCols != cols || nextRows != rows else {
            redraw()
            return
        }
        cols = nextCols
        rows = nextRows
        wwn_term_resize(term, cols, rows)
        onResize?(cols, rows)
        redraw()
    }

    private func publishTitle() {
        guard let term else { return }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = buf.withUnsafeMutableBytes { raw in
            wwn_term_title(term, raw.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt32(raw.count))
        }
        guard n > 0, let title = String(bytes: buf.prefix(Int(n)), encoding: .utf8), !title.isEmpty else {
            return
        }
        onTitle?(title)
    }

    private func flushReply() {
        guard let term else { return }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = buf.withUnsafeMutableBytes { raw in
            wwn_term_take_reply(term, raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        if n > 0 { onReply?(Data(buf.prefix(n))) }
    }

    private func sendPointer(_ event: NSEvent, pressed: Bool, motion: Bool) {
        guard let term else { return }
        let point = convert(event.locationInWindow, from: nil)
        let font = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let cellW = max(1, ("M" as NSString).size(withAttributes: [.font: font]).width)
        let cellH = max(1, font.ascender - font.descender + font.leading)
        let col = UInt32(min(512, max(1, Int((point.x - 8) / cellW) + 1)))
        let rowFromTop = Int((bounds.height - point.y) / cellH) + 1
        let row = UInt32(min(256, max(1, rowFromTop)))
        let button: UInt8
        switch event.buttonNumber {
        case 2: button = 1
        case 1: button = 2
        default: button = 0
        }
        wwn_term_pointer(term, button, col, row, pressed ? 1 : 0, motion ? 1 : 0)
        flushReply()
    }

    private func redraw() {
        guard let term else { return }
        let need = Int(cols) * Int(rows)
        if grid.count < need {
            grid.append(contentsOf: repeatElement(
                WwnTermCell(cp: 32, fg: 0xE8E8E8, bg: 0, attrs: 0),
                count: need - grid.count
            ))
        }
        var outCols: UInt32 = 0
        var outRows: UInt32 = 0
        let n = grid.withUnsafeMutableBufferPointer { buf in
            wwn_term_viewport(
                term, wwn_term_origin(term), buf.baseAddress, UInt32(buf.count), &outCols, &outRows
            )
        }
        gpu.present(
            grid, count: Int(n), cols: Int(outCols), rows: Int(outRows), blinkOn: blinkOn,
            pictures: termPictures(term), cellW: cellPxW, cellH: cellPxH
        )
    }

    private func termPictures(_ term: OpaquePointer) -> [TermPicture] {
        var pictures = [TermPicture]()
        let count = Int(wwn_term_image_count(term))
        guard count > 0 else { return pictures }
        for index in 0..<count {
            var meta = WwnTermImage()
            guard wwn_term_image_meta(term, UInt32(index), &meta) != 0, meta.rgbaLen > 0 else { continue }
            var bytes = [UInt8](repeating: 0, count: Int(meta.rgbaLen))
            let copied = bytes.withUnsafeMutableBufferPointer { buf in
                wwn_term_image_rgba(term, UInt32(index), buf.baseAddress, meta.rgbaLen)
            }
            guard copied == meta.rgbaLen else { continue }
            pictures.append(TermPicture(
                col: meta.col, row: meta.row, xPx: meta.xPx, yPx: meta.yPx,
                cols: Int(meta.cols), rows: Int(meta.rows), z: meta.z,
                pxW: Int(meta.pxW), pxH: Int(meta.pxH), rgba: Data(bytes)
            ))
        }
        return pictures
    }
}

private func macKeyBytes(_ event: NSEvent) -> [UInt8] {
    switch event.keyCode {
    case 36, 76: return [0x0D]
    case 51: return [0x7F]
    case 48: return [0x09]
    case 53: return [0x1B]
    case 126: return Array("\u{1b}[A".utf8)
    case 125: return Array("\u{1b}[B".utf8)
    case 124: return Array("\u{1b}[C".utf8)
    case 123: return Array("\u{1b}[D".utf8)
    case 115: return Array("\u{1b}[H".utf8)
    case 119: return Array("\u{1b}[F".utf8)
    case 116: return Array("\u{1b}[5~".utf8)
    case 121: return Array("\u{1b}[6~".utf8)
    case 117: return Array("\u{1b}[3~".utf8)
    case 122: return Array("\u{1b}OP".utf8)
    case 120: return Array("\u{1b}OQ".utf8)
    case 99: return Array("\u{1b}OR".utf8)
    case 118: return Array("\u{1b}OS".utf8)
    case 96: return Array("\u{1b}[15~".utf8)
    case 97: return Array("\u{1b}[17~".utf8)
    case 98: return Array("\u{1b}[18~".utf8)
    case 100: return Array("\u{1b}[19~".utf8)
    case 101: return Array("\u{1b}[20~".utf8)
    case 109: return Array("\u{1b}[21~".utf8)
    case 103: return Array("\u{1b}[23~".utf8)
    case 111: return Array("\u{1b}[24~".utf8)
    default: break
    }
    if event.modifierFlags.contains(.control), let ch = event.charactersIgnoringModifiers?.lowercased().first,
        ch.isLetter, let ascii = ch.asciiValue
    {
        return [ascii - UInt8(ascii: "a") + 1]
    }
    return Array((event.characters ?? "").utf8)
}

#elseif os(iOS) || os(tvOS) || os(visionOS)
@objc(WWNTermSurface)
public final class WWNTermSurface: WWNTermPlatformView {
    @objc public var onReply: WWNTermReply?

    @objc(feed:)
    public func feed(_ bytes: Data) {
        _ = bytes
    }
}
#endif
