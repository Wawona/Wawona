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

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        window?.makeFirstResponder(self)
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
    let flags = event.modifierFlags
    let param = 1
        + (flags.contains(.shift) ? 1 : 0)
        + (flags.contains(.option) ? 2 : 0)
        + (flags.contains(.control) ? 4 : 0)
    switch event.keyCode {
    case 36, 76: return param & 2 == 2 ? [0x1B, 0x0D] : [0x0D]
    case 51:
        let byte: UInt8 = flags.contains(.control) ? 0x08 : 0x7F
        return flags.contains(.option) ? [0x1B, byte] : [byte]
    case 48: return flags.contains(.shift) ? Array("\u{1b}[Z".utf8) : [0x09]
    case 53: return [0x1B]
    case 49:
      if flags.contains(.control) {
        return flags.contains(.option) ? [0x1B, 0x00] : [0x00]
      }
      if flags.contains(.option) { return [0x1B, 0x20] }
      return [0x20]
    case 126: return macCSI("A", param, "\u{1b}[A")
    case 125: return macCSI("B", param, "\u{1b}[B")
    case 124: return macCSI("C", param, "\u{1b}[C")
    case 123: return macCSI("D", param, "\u{1b}[D")
    case 115: return macCSI("H", param, "\u{1b}[H")
    case 119: return macCSI("F", param, "\u{1b}[F")
    case 116: return macTilde("5", param, "\u{1b}[5~")
    case 121: return macTilde("6", param, "\u{1b}[6~")
    case 117: return macTilde("3", param, "\u{1b}[3~")
    case 114: return macTilde("2", param, "\u{1b}[2~")
    case 110: return macTilde("29", param, "\u{1b}[29~")
    case 122: return macCSI("P", param, "\u{1b}OP")
    case 120: return macCSI("Q", param, "\u{1b}OQ")
    case 99: return macCSI("R", param, "\u{1b}OR")
    case 118: return macCSI("S", param, "\u{1b}OS")
    case 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90:
        return macFnTilde(event.keyCode, param)
    case 65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95:
        if !(event.characters ?? "").isEmpty { break }
        switch event.keyCode {
        case 91: return macCSI("A", param, "\u{1b}[A")
        case 84: return macCSI("B", param, "\u{1b}[B")
        case 88: return macCSI("C", param, "\u{1b}[C")
        case 86: return macCSI("D", param, "\u{1b}[D")
        case 89: return macCSI("H", param, "\u{1b}[H")
        case 83: return macCSI("F", param, "\u{1b}[F")
        case 92: return macTilde("5", param, "\u{1b}[5~")
        case 85: return macTilde("6", param, "\u{1b}[6~")
        case 65: return macTilde("3", param, "\u{1b}[3~")
        case 82: return macTilde("2", param, "\u{1b}[2~")
        case 87: return Array("\u{1b}[E".utf8)
        case 75: return flags.contains(.option) ? [0x1B, 0x2F] : [0x2F]
        case 67: return flags.contains(.option) ? [0x1B, 0x2A] : [0x2A]
        case 78: return flags.contains(.option) ? [0x1B, 0x2D] : [0x2D]
        case 69: return flags.contains(.option) ? [0x1B, 0x2B] : [0x2B]
        case 81: return flags.contains(.option) ? [0x1B, 0x3D] : [0x3D]
        case 95: return flags.contains(.option) ? [0x1B, 0x2C] : [0x2C]
        default: break
        }
    default: break
    }
    if flags.contains(.control), let byte = macControlByte(event) {
        return flags.contains(.option) ? [0x1B, byte] : [byte]
    }
    if event.modifierFlags.contains(.option),
        let ch = event.charactersIgnoringModifiers, ch.utf8.count == 1
    {
        var bytes = Array(ch.utf8)
        bytes.insert(0x1B, at: 0)
        return bytes
    }
    return Array((event.characters ?? "").utf8)
}

private func macControlByte(_ event: NSEvent) -> UInt8? {
    if let ch = event.charactersIgnoringModifiers?.uppercased().first,
        let ascii = ch.asciiValue, (0x40...0x5F).contains(ascii) { return ascii & 0x1F }
    switch event.keyCode {
    case 19: return 0x00
    case 20, 33: return 0x1B
    case 21, 42: return 0x1C
    case 23, 30: return 0x1D
    case 22: return 0x1E
    case 26, 27: return 0x1F
    case 28, 44: return event.keyCode == 44 && !event.modifierFlags.contains(.shift) ? 0x1F : 0x7F
    default: return nil
    }
}

private func macCSI(_ letter: String, _ param: Int, _ plain: String) -> [UInt8] {
    if param == 1 { return Array(plain.utf8) }
    return Array("\u{1b}[1;\(param)\(letter)".utf8)
}

private func macFnTilde(_ code: UInt16, _ param: Int) -> [UInt8] {
    let table = [96: "15", 97: "17", 98: "18", 100: "19", 101: "20", 109: "21", 103: "23", 111: "24", 105: "25", 107: "26", 113: "28", 106: "29", 64: "31", 79: "32", 80: "33", 90: "34"]
    let n = table[Int(code)] ?? "15"
    return macTilde(n, param, "\u{1b}[\(n)~")
}

private func macTilde(_ code: String, _ param: Int, _ plain: String) -> [UInt8] {
    if param == 1 { return Array(plain.utf8) }
    return Array("\u{1b}[\(code);\(param)~".utf8)
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
