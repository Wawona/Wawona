#if os(iOS) || os(tvOS) || os(visionOS)
import Combine
import SwiftUI

/// Styled lines from `wwn_term_export`. Face: bundled DejaVuSansM Nerd Font Mono.
struct WawonaTerminalSpan: Identifiable {
    let id: Int
    let text: String
    let fg: UInt32
    let bg: UInt32
    let bold: Bool
    let italic: Bool
    let underline: Bool
}

struct WawonaTerminalLine: Identifiable {
    let id: Int
    let spans: [WawonaTerminalSpan]
}

final class WawonaTerminalModel: ObservableObject {
    @Published var lines: [WawonaTerminalLine] = []

    func applySnapshot(_ data: Data) {
        let next = WawonaTerminalSnapshot.lines(from: data)
        if Thread.isMainThread {
            lines = next
        } else {
            DispatchQueue.main.async { [weak self] in self?.lines = next }
        }
    }
}

enum WawonaTerminalSnapshot {
    static func lines(from data: Data) -> [WawonaTerminalLine] {
        if data.count < 4 { return [] }
        var offset = 0
        let lineCount = Int(readU32(data, &offset))
        var lines: [WawonaTerminalLine] = []
        lines.reserveCapacity(lineCount)
        for lineIndex in 0..<lineCount {
            if offset + 4 > data.count { break }
            let cells = Int(readU32(data, &offset))
            var pieces: [(UInt32, UInt32, UInt32, UInt32)] = []
            pieces.reserveCapacity(cells)
            for _ in 0..<cells {
                if offset + 16 > data.count { break }
                let cp = readU32(data, &offset)
                let fg = readU32(data, &offset)
                let bg = readU32(data, &offset)
                let attrs = readU32(data, &offset)
                pieces.append((cp, fg, bg, attrs))
            }
            var end = pieces.count
            while end > 0 {
                let cell = pieces[end - 1]
                if (cell.0 == 0 || cell.0 == 32) && cell.2 == 0 {
                    end -= 1
                } else {
                    break
                }
            }
            var spans: [WawonaTerminalSpan] = []
            var text = ""
            var style: (UInt32, UInt32, UInt32)?
            var spanID = 0
            for index in 0..<end {
                let cell = pieces[index]
                let key = (cell.1, cell.2, cell.3)
                let changed =
                    style.map { $0.0 != key.0 || $0.1 != key.1 || $0.2 != key.2 } ?? true
                if changed {
                    if !text.isEmpty, let style {
                        spans.append(makeSpan(id: spanID, text: text, style: style))
                        spanID += 1
                        text = ""
                    }
                    style = key
                }
                let cp = cell.0 == 0 ? 32 : cell.0
                if let scalar = Unicode.Scalar(cp) {
                    text.append(Character(scalar))
                }
            }
            if !text.isEmpty, let style {
                spans.append(makeSpan(id: spanID, text: text, style: style))
            }
            lines.append(WawonaTerminalLine(id: lineIndex, spans: spans))
        }
        return lines
    }

    private static func makeSpan(id: Int, text: String, style: (UInt32, UInt32, UInt32))
        -> WawonaTerminalSpan
    {
        WawonaTerminalSpan(
            id: id, text: text, fg: style.0, bg: style.1,
            bold: style.2 & 1 != 0, italic: style.2 & 4 != 0, underline: style.2 & 8 != 0
        )
    }

    private static func readU32(_ data: Data, _ offset: inout Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        offset += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}

struct WawonaTerminalView: View {
    @ObservedObject var model: WawonaTerminalModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.lines) { line in
                    lineText(line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(Color.black)
    }

    private func lineText(_ line: WawonaTerminalLine) -> some View {
        let body = line.spans.reduce(Text("")) { acc, span in
            acc + spanText(span)
        }
        return (line.spans.isEmpty ? Text(" ") : body)
            .font(.custom("DejaVuSansM Nerd Font Mono", size: 13))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .frame(minHeight: 16, alignment: .leading)
    }

    private func spanText(_ span: WawonaTerminalSpan) -> Text {
        var text = Text(span.text).foregroundColor(rgb(span.fg))
        if span.bold { text = text.bold() }
        if span.italic { text = text.italic() }
        if span.underline { text = text.underline() }
        return text
    }

    private func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
#endif
