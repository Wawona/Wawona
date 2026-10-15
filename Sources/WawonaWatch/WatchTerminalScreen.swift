#if os(watchOS)
import Combine
import CoreGraphics
import CoreText
import SwiftUI

@_silgen_name("wwn_term_bytes_lines_json")
private func wwn_term_bytes_lines_json(
    _ bytes: UnsafePointer<UInt8>?,
    _ len: Int,
    _ cols: UInt32,
    _ rows: UInt32
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("wwn_term_bytes_images_json")
private func wwn_term_bytes_images_json(
    _ bytes: UnsafePointer<UInt8>?,
    _ len: Int,
    _ cols: UInt32,
    _ rows: UInt32,
    _ cellW: UInt32,
    _ cellH: UInt32
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("wwn_term_string_free")
private func wwn_term_string_free(_ ptr: UnsafeMutablePointer<CChar>?)

/// Watch draws the same VT cells as the other hosts. No Metal.
struct WatchTerminalScreen: View {
    let text: String
    @State private var cols: UInt32 = 20
    @State private var gridRows: UInt32 = 8
    @State private var rows: [WatchTerminalRowModel] = []
    @State private var pictures: [WatchTermPicture] = []
    @State private var blinkOn = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        WatchTerminalRow(spans: row.spans, blinkOn: blinkOn)
                            .id(row.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(watchPictures(behind: true))
                .overlay(watchPictures(behind: false), alignment: .topLeading)
            }
            .onChange(of: rows.count) { _, count in
                guard count > 0 else { return }
                proxy.scrollTo(rows[count - 1].id, anchor: .bottom)
            }
        }
        .background(Color.black)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: WatchTerminalViewportKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(WatchTerminalViewportKey.self) { size in
            guard size.width > 1, size.height > 1 else { return }
            let cell = WatchTerminalFonts.cell
            let nextCols = UInt32(min(512, max(20, Int(size.width / cell.0))))
            let nextRows = UInt32(min(256, max(8, Int(size.height / cell.1))))
            if nextCols != cols { cols = nextCols }
            if nextRows != gridRows { gridRows = nextRows }
        }
        .onAppear { reload() }
        .onChange(of: text) { _, _ in reload() }
        .onChange(of: cols) { _, _ in reload() }
        .onChange(of: gridRows) { _, _ in reload() }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if rows.contains(where: { $0.spans.contains(where: \.blink) }) {
                blinkOn.toggle()
            }
        }
    }

    private func reload() {
        let parsed = WatchTerminalSnapshot.lines(from: text, cols: cols, rows: gridRows)
        let keys = parsed.map { $0.map(\.text).joined(separator: "\u{1}") }
        let oldKeys = rows.map { $0.spans.map(\.text).joined(separator: "\u{1}") }
        let ids = alignWatchLineIDs(oldIDs: rows.map(\.id), oldKeys: oldKeys, newKeys: keys)
        rows = zip(ids, parsed).map { WatchTerminalRowModel(id: $0.0, spans: $0.1) }
        let cell = WatchTerminalFonts.cell
        pictures = WatchTerminalSnapshot.pictures(
            from: text,
            cols: cols,
            rows: gridRows,
            cellW: UInt32(max(1, cell.0.rounded())),
            cellH: UInt32(max(1, cell.1.rounded()))
        )
    }

    private func watchPictures(behind: Bool) -> some View {
        let cell = WatchTerminalFonts.cell
        let scrollback = max(0, rows.count - Int(gridRows))
        return ZStack(alignment: .topLeading) {
            ForEach(pictures.filter { behind ? $0.z < 0 : $0.z >= 0 }) { picture in
                Image(decorative: picture.image, scale: 1)
                    .resizable()
                    .frame(
                        width: CGFloat(max(picture.columns, 1)) * cell.0,
                        height: CGFloat(max(picture.rows, 1)) * cell.1
                    )
                    .offset(
                        x: CGFloat(picture.col) * cell.0,
                        y: CGFloat(scrollback + picture.row) * cell.1
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

private struct WatchTerminalViewportKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct WatchTerminalRowModel: Identifiable {
    let id: Int
    let spans: [WatchTerminalSpan]
}

private var watchNextLineID = 1

private func alignWatchLineIDs(oldIDs: [Int], oldKeys: [String], newKeys: [String]) -> [Int] {
    func mint() -> Int {
        let id = watchNextLineID
        watchNextLineID += 1
        return id
    }
    if newKeys == oldKeys, newKeys.count == oldIDs.count { return oldIDs }
    if newKeys.count >= oldKeys.count, Array(newKeys.prefix(oldKeys.count)) == oldKeys {
        var ids = oldIDs
        while ids.count < newKeys.count { ids.append(mint()) }
        return ids
    }
    if !oldKeys.isEmpty, newKeys.count == oldKeys.count,
        Array(newKeys.dropLast()) == Array(oldKeys.dropFirst())
    {
        var ids = Array(oldIDs.dropFirst())
        ids.append(mint())
        return ids
    }
    var ids: [Int] = []
    let overlap = min(oldIDs.count, newKeys.count)
    for _ in 0..<(newKeys.count - overlap) { ids.append(mint()) }
    ids.append(contentsOf: oldIDs.suffix(overlap))
    return ids
}

private enum WatchTerminalFonts {
    static let pointSize: CGFloat = 9
    static var host: Font { Font.system(size: pointSize, design: .monospaced) }
    static var nerd: Font { Font.custom("DejaVuSansM Nerd Font Mono", size: pointSize) }

    static var cell: (CGFloat, CGFloat) {
        let font = CTFontCreateWithName("Menlo" as CFString, pointSize, nil)
        var chars: [UniChar] = [77]
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advance, 1)
        let width = max(pointSize * 0.5, advance.width)
        let height = max(
            pointSize,
            CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        )
        return (width, height)
    }

    static func runs(_ text: String) -> [(String, Bool)] {
        var out: [(String, Bool)] = []
        var current = ""
        var nerd: Bool?
        func flush() {
            guard let nerd, !current.isEmpty else { return }
            out.append((current, nerd))
            current = ""
        }
        for ch in text {
            let flag = isNerd(ch)
            if nerd != flag {
                flush()
                nerd = flag
            }
            current.append(ch)
        }
        flush()
        if out.isEmpty { out.append((" ", false)) }
        return out
    }

    static func isNerd(_ ch: Character) -> Bool {
        !ch.unicodeScalars.isEmpty
            && ch.unicodeScalars.allSatisfy { scalar in
                let u = scalar.value
                return (0xE000...0xF8FF).contains(u)
                    || (0xF0000...0xFFFFD).contains(u)
                    || (0x100000...0x10FFFD).contains(u)
            }
    }
}

private struct WatchTerminalSpan {
    let text: String
    let fg: UInt32
    let bg: UInt32
    let bold: Bool
    let italic: Bool
    let underline: Bool
    let blink: Bool
    let strike: Bool
}

private struct WatchTerminalRow: View {
    let spans: [WatchTerminalSpan]
    var blinkOn: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            let drawn = spans.isEmpty
                ? [WatchTerminalSpan(text: " ", fg: 0xE8E8E8, bg: 0, bold: false, italic: false, underline: false, blink: false, strike: false)]
                : spans
            ForEach(Array(drawn.enumerated()), id: \.offset) { _, span in
                HStack(spacing: 0) {
                    ForEach(Array(WatchTerminalFonts.runs(span.text).enumerated()), id: \.offset) { _, run in
                        styled(run.0, span)
                            .font(run.1 ? WatchTerminalFonts.nerd : WatchTerminalFonts.host)
                    }
                }
                .background(span.bg == 0 ? Color.clear : rgb(span.bg))
                .opacity(span.blink && !blinkOn ? 0.15 : 1)
                .overlay(strikeBar(span), alignment: .center)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .frame(minHeight: WatchTerminalFonts.cell.1, alignment: .leading)
    }

    private func styled(_ raw: String, _ span: WatchTerminalSpan) -> Text {
        var text = Text(raw).foregroundColor(rgb(span.fg))
        if span.bold {
            text = text.bold()
        }
        if span.italic {
            text = text.italic()
        }
        if span.underline {
            text = text.underline()
        }
        return text
    }

    private func strikeBar(_ span: WatchTerminalSpan) -> some View {
        Group {
            if span.strike {
                Rectangle()
                    .fill(rgb(span.fg))
                    .frame(height: 1)
            }
        }
    }

    private func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct WatchTermLineRecord: Decodable {
    struct Span: Decodable {
        let text: String
        let fg: UInt32
        let bg: UInt32
        let bold: Bool
        let italic: Bool
        let underline: Bool
        let blink: Bool
        let strike: Bool
    }

    let spans: [Span]
}

private enum WatchTerminalSnapshot {
    static func lines(from text: String, cols: UInt32, rows: UInt32) -> [[WatchTerminalSpan]] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let raw = Array(normalized.utf8)
        let ptr: UnsafeMutablePointer<CChar>? = raw.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            return wwn_term_bytes_lines_json(base, buf.count, cols, rows)
        }
        guard let ptr else {
            return [[WatchTerminalSpan(text: text, fg: 0xE8E8E8, bg: 0, bold: false, italic: false, underline: false, blink: false, strike: false)]]
        }
        let document = String(cString: ptr)
        wwn_term_string_free(ptr)
        let decoded = (try? JSONDecoder().decode([WatchTermLineRecord].self, from: Data(document.utf8))) ?? []
        if decoded.isEmpty {
            return [[WatchTerminalSpan(text: text, fg: 0xE8E8E8, bg: 0, bold: false, italic: false, underline: false, blink: false, strike: false)]]
        }
        return decoded.map { line in
            line.spans.map { span in
                WatchTerminalSpan(
                    text: span.text,
                    fg: span.fg,
                    bg: span.bg,
                    bold: span.bold,
                    italic: span.italic,
                    underline: span.underline,
                    blink: span.blink,
                    strike: span.strike
                )
            }
        }
    }

    static func pictures(
        from text: String,
        cols: UInt32,
        rows: UInt32,
        cellW: UInt32,
        cellH: UInt32
    ) -> [WatchTermPicture] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let raw = Array(normalized.utf8)
        let ptr: UnsafeMutablePointer<CChar>? = raw.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            return wwn_term_bytes_images_json(base, buf.count, cols, rows, cellW, cellH)
        }
        guard let ptr else { return [] }
        let document = String(cString: ptr)
        wwn_term_string_free(ptr)
        let decoded = (try? JSONDecoder().decode([WatchPictureRecord].self, from: Data(document.utf8))) ?? []
        return decoded.compactMap { record in
            guard let image = watchImage(record) else { return nil }
            return WatchTermPicture(
                id: record.n,
                col: record.col,
                row: record.row,
                columns: record.cols,
                rows: record.rows,
                z: record.z,
                image: image
            )
        }
    }
}

private struct WatchTermPicture: Identifiable {
    let id: Int
    let col: Int
    let row: Int
    let columns: Int
    let rows: Int
    let z: Int
    let image: CGImage
}

private struct WatchPictureRecord: Decodable {
    let n: Int
    let col: Int
    let row: Int
    let w: Int
    let h: Int
    let cols: Int
    let rows: Int
    let z: Int
    let rgba: String
}

private func watchImage(_ record: WatchPictureRecord) -> CGImage? {
    guard record.w > 0, record.h > 0, let data = Data(base64Encoded: record.rgba) else { return nil }
    let count = record.w * record.h * 4
    guard data.count >= count else { return nil }
    let provider = CGDataProvider(data: data as CFData)
    return provider.flatMap { source in
        CGImage(
            width: record.w,
            height: record.h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: record.w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: source,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
#endif
