import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
import QuartzCore
public typealias WWNTermPlatformView = NSView
#elseif canImport(UIKit)
import UIKit
public typealias WWNTermPlatformView = UIView
#endif

public typealias WWNTermReply = (Data) -> Void

#if os(macOS)

@_silgen_name("ghostty_surface_new")
private func ghostty_surface_new(_ cols: UInt32, _ rows: UInt32) -> OpaquePointer?
@_silgen_name("ghostty_surface_free")
private func ghostty_surface_free(_ term: OpaquePointer?)
@_silgen_name("ghostty_surface_resize")
private func ghostty_surface_resize(_ term: OpaquePointer?, _ cols: UInt32, _ rows: UInt32)
@_silgen_name("ghostty_surface_write")
private func ghostty_surface_write(_ term: OpaquePointer?, _ bytes: UnsafePointer<UInt8>?, _ len: Int)
@_silgen_name("ghostty_surface_viewport")
private func ghostty_surface_viewport(
    _ term: OpaquePointer?, _ origin: UInt32, _ out: UnsafeMutablePointer<WwnTermCell>?,
    _ cap: UInt32, _ cols: UnsafeMutablePointer<UInt32>?, _ rows: UnsafeMutablePointer<UInt32>?
) -> UInt32
@_silgen_name("ghostty_surface_origin")
private func ghostty_surface_origin(_ term: OpaquePointer?) -> UInt32
@_silgen_name("ghostty_surface_title")
private func ghostty_surface_title(
    _ term: OpaquePointer?, _ out: UnsafeMutablePointer<UInt8>?, _ cap: UInt32
) -> UInt32
@_silgen_name("ghostty_string_free")
private func ghostty_string_free(_ ptr: UnsafeMutablePointer<CChar>?)
@_silgen_name("ghostty_surface_encode_paste")
private func ghostty_surface_encode_paste(
    _ term: OpaquePointer?, _ bytes: UnsafePointer<UInt8>?, _ len: Int
) -> UnsafeMutablePointer<CChar>?
@_silgen_name("ghostty_surface_take_reply")
private func ghostty_surface_take_reply(
    _ term: OpaquePointer?, _ buf: UnsafeMutablePointer<UInt8>?, _ cap: Int
) -> Int
@_silgen_name("ghostty_surface_pointer")
private func ghostty_surface_pointer(
    _ term: OpaquePointer?, _ button: UInt8, _ col: UInt32, _ row: UInt32,
    _ pressed: Int32, _ motion: Int32
)
@_silgen_name("ghostty_surface_set_cell_px")
private func ghostty_surface_set_cell_px(_ term: OpaquePointer?, _ width: UInt32, _ height: UInt32)
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

/// AppKit host. Rust libghostty-vt viewport. Metal paint is interim
/// `GhosttyGpuView` (staged `.nix-deps/terminal`). Do not grow the atlas.
/// TODO(metal-surface): swap to Zig GhosttyLib when
/// `wwn-ghostty#libghostty-macos` is green (fails closed today; see
/// `Ghostty/docs/METAL-SURFACE.md`).
@objc(WWNTermSurface)
public final class WWNTermSurface: NSView {
    @objc public var onReply: WWNTermReply?
    public var onResize: ((UInt32, UInt32) -> Void)?
    public var onTitle: ((String) -> Void)?
    public var gridCols: UInt32 { cols }
    public var gridRows: UInt32 { rows }

    private var term: OpaquePointer?
    private let gpu = GhosttyGpuView(frame: .zero, device: nil)
    private var grid = [WwnTermCell](repeating: WwnTermCell(cp: 32, fg: 0xE8E8E8, bg: 0, attrs: 0), count: 512 * 32)
    private var cols: UInt32 = 80
    private var rows: UInt32 = 24
    private var blinkOn = true
    private var blinkTimer: Timer?
    private let pointSize: CGFloat = 13
    private var cellPxW: CGFloat = 8
    private var cellPxH: CGFloat = 16
    private var selAnchor: (col: Int, row: Int)?
    private var selEnd: (col: Int, row: Int)?
    private var selecting = false
    private var lastCursor: (col: Int, row: Int)?
    private var prevCursor: (col: Int, row: Int)?
    private var cursorJumpAt: CFTimeInterval = 0

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        term = ghostty_surface_new(cols, rows)
        // Scrollback host factor is applied after the first layout once the
        // surface paints. Calling refresh in init raced a tip ABI mismatch
        // (SEGV in VtEngine.cols / snap at +0x790 on Start).
        gpu.autoresizingMask = [.width, .height]
        gpu.frame = bounds
        addSubview(gpu)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let blink = self.grid.contains(where: { $0.attrs & 16 != 0 })
            let jump = CACurrentMediaTime() - self.cursorJumpAt < 0.35
            guard blink || jump else { return }
            if blink { self.blinkOn.toggle() }
            self.redraw()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        blinkTimer?.invalidate()
        if let term { ghostty_surface_free(term) }
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// MTKView fills bounds for drawing only. Keep mouse + keys on this view.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        WWNBundleShareEnvironment.registerBundledFontsIfNeeded()
        guard let window else { return }
        window.initialFirstResponder = self
        window.makeFirstResponder(self)
    }

    @objc(feed:)
    public func feed(_ bytes: Data) {
        guard let term, !bytes.isEmpty else { return }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            ghostty_surface_write(term, base, bytes.count)
        }
        flushReply()
        redraw()
        publishTitle()
    }

    public override func layout() {
        super.layout()
        gpu.frame = bounds
        syncDrawableScale()
        fit()
    }

    /// After reparent into main Present (Focus embed). Force Metal + grid fit.
    @objc public func refreshAfterHostMove() {
        needsLayout = true
        layoutSubtreeIfNeeded()
        gpu.frame = bounds
        syncDrawableScale()
        fit()
        redraw()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncDrawableScale()
        redraw()
    }

    private func syncDrawableScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        gpu.layer?.contentsScale = scale
        gpu.syncBackingScale(scale)
        let w = max(1, bounds.width * scale)
        let h = max(1, bounds.height * scale)
        gpu.drawableSize = CGSize(width: w, height: h)
        // Identity only. Focus embed must not affine- or geometry-flip Metal;
        // that parked the prompt or painted the grid 180° vs standalone.
        gpu.layer?.setAffineTransform(.identity)
        if let layer = gpu.layer {
            layer.isGeometryFlipped = false
        }
    }

    public override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let ch = event.charactersIgnoringModifiers?.lowercased()
            switch ch {
            case "c": copySelection(nil); return
            case "v": paste(nil); return
            case "a": selectAll(nil); return
            default: break
            }
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
        if event.type == .rightMouseDown || event.buttonNumber == 1 {
            showContextMenu(event)
            return
        }
        let cell = cellAt(event)
        // Option-drag = host selection (Ghostty-style). Plain click = VT mouse.
        if event.modifierFlags.contains(.option) {
            selecting = true
            selAnchor = cell
            selEnd = cell
            redraw()
            return
        }
        if event.clickCount >= 3 {
            selectLine(cell.row)
            return
        }
        if event.clickCount == 2 {
            selectWord(at: cell)
            return
        }
        selecting = false
        selAnchor = nil
        selEnd = nil
        sendPointer(event, pressed: true, motion: false)
        redraw()
    }

    public override func mouseUp(with event: NSEvent) {
        if selecting {
            selecting = false
            if let text = selectedText(), !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            redraw()
            return
        }
        sendPointer(event, pressed: false, motion: false)
    }

    public override func mouseDragged(with event: NSEvent) {
        if selecting || event.modifierFlags.contains(.option) {
            selecting = true
            if selAnchor == nil { selAnchor = cellAt(event) }
            selEnd = cellAt(event)
            redraw()
            return
        }
        sendPointer(event, pressed: true, motion: true)
    }

    public override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        showContextMenu(event)
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu()
    }

    @objc public func copySelection(_ sender: Any?) {
        guard let text = selectedText(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc public func paste(_ sender: Any?) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty, let term else { return }
        let data = Data(text.utf8)
        let wrapped = data.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let ptr = ghostty_surface_encode_paste(term, base, data.count)
            else { return data }
            let text = String(cString: ptr)
            ghostty_string_free(ptr)
            return Data(text.utf8)
        }
        onReply?(wrapped)
    }

    @objc public override func selectAll(_ sender: Any?) {
        selAnchor = (0, 0)
        selEnd = (max(0, Int(cols) - 1), max(0, Int(rows) - 1))
        redraw()
    }

    private func terminalMetricsFont() -> NSFont {
        WWNBundleShareEnvironment.registerBundledFontsIfNeeded()
        if let nerd = NSFont(name: "DejaVuSansM Nerd Font Mono", size: pointSize) {
            return nerd
        }
        if let mono = NSFont(name: "DejaVu Sans Mono", size: pointSize) {
            return mono
        }
        return NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }

    private func fit() {
        guard let term, bounds.width > 1, bounds.height > 1 else { return }
        let font = terminalMetricsFont()
        let cellW = max(1, ("M" as NSString).size(withAttributes: [.font: font]).width)
        let cellH = max(1, font.ascender - font.descender + font.leading)
        let nextCols = UInt32(min(512, max(20, Int((bounds.width - 16) / cellW))))
        let nextRows = UInt32(min(256, max(8, Int(bounds.height / cellH))))
        cellPxW = cellW
        cellPxH = cellH
        ghostty_surface_set_cell_px(term, UInt32(max(1, cellW.rounded())), UInt32(max(1, cellH.rounded())))
        guard nextCols != cols || nextRows != rows else {
            redraw()
            return
        }
        cols = nextCols
        rows = nextRows
        ghostty_surface_resize(term, cols, rows)
        onResize?(cols, rows)
        redraw()
    }

    private func publishTitle() {
        guard let term else { return }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = buf.withUnsafeMutableBytes { raw in
            ghostty_surface_title(term, raw.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt32(raw.count))
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
            ghostty_surface_take_reply(term, raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        if n > 0 { onReply?(Data(buf.prefix(n))) }
    }

    private func cellAt(_ event: NSEvent) -> (col: Int, row: Int) {
        let point = convert(event.locationInWindow, from: nil)
        let font = terminalMetricsFont()
        let cellW = max(1, ("M" as NSString).size(withAttributes: [.font: font]).width)
        let cellH = max(1, font.ascender - font.descender + font.leading)
        let col = min(max(0, Int((point.x - 8) / cellW)), max(0, Int(cols) - 1))
        let row = min(max(0, Int((bounds.height - point.y) / cellH)), max(0, Int(rows) - 1))
        return (col, row)
    }

    private func sendPointer(_ event: NSEvent, pressed: Bool, motion: Bool) {
        guard let term else { return }
        let cell = cellAt(event)
        // VT mouse is 1-based.
        let col = UInt32(cell.col + 1)
        let row = UInt32(cell.row + 1)
        let button: UInt8
        switch event.buttonNumber {
        case 2: button = 1
        case 1: button = 2
        default: button = 0
        }
        ghostty_surface_pointer(term, button, col, row, pressed ? 1 : 0, motion ? 1 : 0)
        flushReply()
    }

    private func selectionRange() -> (start: Int, end: Int)? {
        guard let a = selAnchor, let b = selEnd else { return nil }
        let i0 = a.row * Int(cols) + a.col
        let i1 = b.row * Int(cols) + b.col
        return (min(i0, i1), max(i0, i1))
    }

    private func selectedText() -> String? {
        guard let range = selectionRange() else { return nil }
        var out = ""
        let c = Int(cols)
        for i in range.start...range.end {
            if i > range.start, c > 0, i % c == 0 { out.append("\n") }
            guard i < grid.count else { break }
            let cp = grid[i].cp
            if let scalar = UnicodeScalar(cp), cp >= 32 {
                out.append(Character(scalar))
            } else {
                out.append(" ")
            }
        }
        return out
    }

    private func selectLine(_ row: Int) {
        let r = min(max(0, row), max(0, Int(rows) - 1))
        selAnchor = (0, r)
        selEnd = (max(0, Int(cols) - 1), r)
        if let text = selectedText(), !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        redraw()
    }

    private func selectWord(at cell: (col: Int, row: Int)) {
        let c = Int(cols)
        let base = cell.row * c
        guard base < grid.count else { return }
        var lo = cell.col
        var hi = cell.col
        func isWord(_ cp: UInt32) -> Bool {
            guard let s = UnicodeScalar(cp) else { return false }
            return Character(s).isLetter || Character(s).isNumber || s == "_"
        }
        while lo > 0, base + lo - 1 < grid.count, isWord(grid[base + lo - 1].cp) { lo -= 1 }
        while hi + 1 < c, base + hi + 1 < grid.count, isWord(grid[base + hi + 1].cp) { hi += 1 }
        selAnchor = (lo, cell.row)
        selEnd = (hi, cell.row)
        if let text = selectedText(), !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        redraw()
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu(title: "Terminal")
        menu.addItem(withTitle: "Copy", action: #selector(copySelection(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a")
        for item in menu.items {
            item.target = self
            item.keyEquivalentModifierMask = [.command]
        }
        return menu
    }

    private func showContextMenu(_ event: NSEvent) {
        NSMenu.popUpContextMenu(contextMenu(), with: event, for: self)
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
            ghostty_surface_viewport(
                term, ghostty_surface_origin(term), buf.baseAddress, UInt32(buf.count), &outCols, &outRows
            )
        }
        if let cursorIdx = grid.prefix(Int(n)).firstIndex(where: { $0.attrs & 64 != 0 }) {
            let c = Int(max(outCols, 1))
            let cur = (col: cursorIdx % c, row: cursorIdx / c)
            if let last = lastCursor, last != cur {
                prevCursor = last
                cursorJumpAt = CACurrentMediaTime()
            }
            lastCursor = cur
        }
        let jumpT = Float(max(0, 1 - (CACurrentMediaTime() - cursorJumpAt) / 0.28))
        gpu.present(
            grid, count: Int(n), cols: Int(outCols), rows: Int(outRows), blinkOn: blinkOn,
            pictures: termPictures(term), cellW: cellPxW, cellH: cellPxH,
            selection: selectionRange(),
            cursorJumpFrom: prevCursor, cursorJumpTo: lastCursor, cursorJumpT: jumpT
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
    // Option-as-Meta only when macOS did not compose an alternate glyph (å, Ω, …).
    if flags.contains(.option),
        !flags.contains(.command),
        let ignoring = event.charactersIgnoringModifiers,
        ignoring.utf8.count == 1,
        let chars = event.characters,
        chars == ignoring || chars.isEmpty
    {
        var bytes = Array(ignoring.utf8)
        bytes.insert(0x1B, at: 0)
        return bytes
    }
    return Array((event.characters ?? event.charactersIgnoringModifiers ?? "").utf8)
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
