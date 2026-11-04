#if os(watchOS)
import CoreGraphics
import CoreText
import SpriteKit
import SwiftUI
import UIKit

/// Watch Terminal present accelerator: CoreText CPU cell raster → `SKTexture`
/// / `SKSpriteNode`. No Metal. No `SKShader`.
///
/// OS floor: `SpriteView` (same host as Wayland SHM present) needs watchOS 8+.
/// Product `WATCHOS_DEPLOYMENT_TARGET` is 10.0, so no alternate WKInterface path.
/// Toggle / env: reuse `PlatformCapabilities.watchPresentAcceleratorEnabled`
/// (`SpritePresentAccelerator` / `WWN_WATCH_SK_PRESENT=0`).

final class WatchTerminalSpriteScene: SKScene {
    private let sprite = SKSpriteNode()

    override func sceneDidLoad() {
        super.sceneDidLoad()
        backgroundColor = .black
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .resizeFill
        if sprite.parent == nil {
            addChild(sprite)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutSprite()
    }

    func applyFrame(_ image: CGImage) {
        if size.width < 1 || size.height < 1 {
            size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        sprite.texture = texture
        layoutSprite()
    }

    private func layoutSprite() {
        guard let texture = sprite.texture else { return }
        let ts = texture.size()
        let ss = size
        guard ts.width > 0, ts.height > 0, ss.width > 0, ss.height > 0 else {
            return
        }
        let fit = min(ss.width / ts.width, ss.height / ts.height)
        let scale = min(fit, CGFloat(1))
        sprite.size = CGSize(width: ts.width * scale, height: ts.height * scale)
        sprite.position = .zero
    }
}

final class WatchTerminalSpritePresenter: ObservableObject {
    let scene: WatchTerminalSpriteScene

    init() {
        let scene = WatchTerminalSpriteScene(size: CGSize(width: 200, height: 200))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .black
        self.scene = scene
    }

    func apply(_ image: CGImage) {
        scene.applyFrame(image)
    }

    func setPaused(_ paused: Bool) {
        scene.isPaused = paused
    }
}

/// CoreText stamp of VT spans into one RGBA bitmap (GhosttyGpu-style CPU path,
/// atlas-free). Prefer full viewport raster over growing a Metal atlas.
enum WatchTerminalCPURaster {
    static func image(
        rows: [[WatchTerminalSpan]],
        pictures: [WatchTermPicture],
        cols: Int,
        rowsVisible: Int,
        cellW: CGFloat,
        cellH: CGFloat,
        blinkOn: Bool
    ) -> CGImage? {
        let cols = max(1, cols)
        let rowsVisible = max(1, rowsVisible)
        let width = max(1, Int((CGFloat(cols) * cellW).rounded(.up)))
        let height = max(1, Int((CGFloat(rowsVisible) * cellH).rounded(.up)))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Top-left origin like the Text grid / Metal atlas stamp.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)

        // Last `rowsVisible` lines = VT screen. Short buffers pad at top (black).
        let visible = Array(rows.suffix(rowsVisible))
        let padTop = max(0, rowsVisible - visible.count)

        // Pictures use VT screen coords (visible window). Text overlay adds
        // scrollback for the full ScrollView; Sprite viewport is already that
        // window, so stamp at picture.row directly.
        for picture in pictures where picture.z < 0 {
            stampPicture(picture, into: ctx, cellW: cellW, cellH: cellH, rowsVisible: rowsVisible)
        }

        for (visIndex, spans) in visible.enumerated() {
            let rowIndex = padTop + visIndex
            var x: CGFloat = 0
            let y = CGFloat(rowIndex) * cellH
            let drawn: [WatchTerminalSpan] = spans.isEmpty
                ? [
                    WatchTerminalSpan(
                        text: " ",
                        fg: 0xE8E8E8,
                        bg: 0,
                        bold: false,
                        italic: false,
                        underline: false,
                        blink: false,
                        strike: false
                    )
                ]
                : spans
            for span in drawn {
                let opacity: CGFloat = span.blink && !blinkOn ? 0.15 : 1
                let runs = WatchTerminalFonts.runs(span.text)
                for run in runs {
                    let runWidth = CGFloat(run.0.count) * cellW
                    if span.bg != 0 {
                        ctx.setFillColor(rgb(span.bg, alpha: opacity))
                        ctx.fill(CGRect(x: x, y: y, width: runWidth, height: cellH))
                    }
                    drawGlyphRun(
                        run.0,
                        nerd: run.1,
                        span: span,
                        opacity: opacity,
                        origin: CGPoint(x: x, y: y),
                        cellW: cellW,
                        cellH: cellH,
                        into: ctx
                    )
                    x += runWidth
                    if x >= CGFloat(cols) * cellW { break }
                }
                if x >= CGFloat(cols) * cellW { break }
            }
        }

        for picture in pictures where picture.z >= 0 {
            stampPicture(picture, into: ctx, cellW: cellW, cellH: cellH, rowsVisible: rowsVisible)
        }

        return ctx.makeImage()
    }

    private static func stampPicture(
        _ picture: WatchTermPicture,
        into ctx: CGContext,
        cellW: CGFloat,
        cellH: CGFloat,
        rowsVisible: Int
    ) {
        guard picture.row < rowsVisible, picture.col >= 0 else { return }
        let x = CGFloat(picture.col) * cellW
        let y = CGFloat(picture.row) * cellH
        let w = CGFloat(max(picture.columns, 1)) * cellW
        let h = CGFloat(max(picture.rows, 1)) * cellH
        ctx.draw(picture.image, in: CGRect(x: x, y: y, width: w, height: h))
    }

    private static func drawGlyphRun(
        _ text: String,
        nerd: Bool,
        span: WatchTerminalSpan,
        opacity: CGFloat,
        origin: CGPoint,
        cellW: CGFloat,
        cellH: CGFloat,
        into ctx: CGContext
    ) {
        let pointSize = WatchTerminalFonts.pointSize
        let baseName: CFString = nerd
            ? "DejaVuSansM Nerd Font Mono" as CFString
            : "Menlo" as CFString
        var font = CTFontCreateWithName(baseName, pointSize, nil)
        if span.bold {
            if let bold = CTFontCreateCopyWithSymbolicTraits(
                font, pointSize, nil, .traitBold, .traitBold
            ) {
                font = bold
            }
        }
        if span.italic {
            if let italic = CTFontCreateCopyWithSymbolicTraits(
                font, pointSize, nil, .traitItalic, .traitItalic
            ) {
                font = italic
            }
        }

        let fg = rgbComponents(span.fg)
        let uiColor = UIColor(red: fg.0, green: fg.1, blue: fg.2, alpha: opacity)
        let stroke = uiColor.cgColor

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: uiColor,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let lineHeight = ascent + descent + leading
        let baseline = origin.y + max(CGFloat(1), (cellH - lineHeight) * 0.5 + descent)

        ctx.textPosition = CGPoint(x: origin.x, y: baseline)
        CTLineDraw(line, ctx)

        if span.underline {
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(1)
            let uy = origin.y + cellH - max(CGFloat(1), descent * 0.35)
            ctx.move(to: CGPoint(x: origin.x, y: uy))
            ctx.addLine(to: CGPoint(x: origin.x + CGFloat(text.count) * cellW, y: uy))
            ctx.strokePath()
        }
        if span.strike {
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(1)
            let sy = origin.y + cellH * 0.5
            ctx.move(to: CGPoint(x: origin.x, y: sy))
            ctx.addLine(to: CGPoint(x: origin.x + CGFloat(text.count) * cellW, y: sy))
            ctx.strokePath()
        }
    }

    private static func rgb(_ value: UInt32, alpha: CGFloat) -> CGColor {
        let c = rgbComponents(value)
        return CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [c.0, c.1, c.2, alpha]
        ) ?? CGColor(gray: 0, alpha: alpha)
    }

    private static func rgbComponents(_ value: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }
}

/// SpriteKit host for Watch Terminal grid. Accessibility id matches Text path.
struct WatchTerminalSpritePresent: View {
    let rows: [[WatchTerminalSpan]]
    let pictures: [WatchTermPicture]
    let cols: UInt32
    let gridRows: UInt32
    let blinkOn: Bool

    @StateObject private var presenter = WatchTerminalSpritePresenter()
    @Environment(\.scenePhase) private var scenePhase

    private var shouldRun: Bool { scenePhase != .background }

    var body: some View {
        SpriteView(
            scene: presenter.scene,
            isPaused: false,
            preferredFramesPerSecond: 30
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier("wwn.watch.terminal.surface")
        .accessibilityLabel("Terminal")
        .onAppear {
            presenter.setPaused(!shouldRun)
            refresh()
        }
        .onDisappear {
            presenter.setPaused(true)
        }
        .onChange(of: scenePhase) { _, _ in
            presenter.setPaused(!shouldRun)
        }
        .onChange(of: blinkOn) { _, _ in refresh() }
        .onChange(of: cols) { _, _ in refresh() }
        .onChange(of: gridRows) { _, _ in refresh() }
        .onChange(of: rowsSignature) { _, _ in refresh() }
        .onChange(of: pictures.count) { _, _ in refresh() }
    }

    private var rowsSignature: String {
        rows.map { $0.map(\.text).joined(separator: "\u{1}") }.joined(separator: "\n")
    }

    private func refresh() {
        let cell = WatchTerminalFonts.cell
        guard let image = WatchTerminalCPURaster.image(
            rows: rows,
            pictures: pictures,
            cols: Int(cols),
            rowsVisible: Int(gridRows),
            cellW: cell.0,
            cellH: cell.1,
            blinkOn: blinkOn
        ) else {
            return
        }
        presenter.apply(image)
    }
}
#endif
