#if canImport(UIKit) && !os(watchOS)
import UIKit
import SwiftUI
import MetalKit

/// UIKit host for Wawona Terminal grid on iOS / tvOS / visionOS.
/// Paint is `TerminalMetalPresent` (libghostty VT cells). No UITextView span path.
@objc(WWNGhosttyTermView)
public final class WWNGhosttyTermView: UIView {
  public var onReply: WWNTermReply?

  private var surface: OpaquePointer?
  private var cols: UInt32 = 80
  private var rows: UInt32 = 24
  private var metal: TerminalMetalPresent?
  private var blinkOn = true
  private var blinkTimer: Timer?

  public override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    _ = wwn_term_init()
    surface = wwn_term_new(cols, rows)
    let gpu = TerminalMetalPresent(frame: bounds, device: MTLCreateSystemDefaultDevice())
    gpu.translatesAutoresizingMaskIntoConstraints = false
    addSubview(gpu)
    NSLayoutConstraint.activate([
      gpu.topAnchor.constraint(equalTo: topAnchor),
      gpu.bottomAnchor.constraint(equalTo: bottomAnchor),
      gpu.leadingAnchor.constraint(equalTo: leadingAnchor),
      gpu.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    metal = gpu
    blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.blinkOn.toggle()
      self.redraw()
    }
    if let blinkTimer {
      RunLoop.main.add(blinkTimer, forMode: .common)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  deinit {
    blinkTimer?.invalidate()
    if let surface { wwn_term_free(surface) }
  }

  public func feed(_ data: Data) {
    guard let surface, !data.isEmpty else { return }
    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      wwn_term_feed(surface, base, data.count)
    }
    flushReply()
    redraw()
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    let nextCols = UInt32(max(20, min(200, Int(bounds.width / 7))))
    let nextRows = UInt32(max(8, min(100, Int(bounds.height / 14))))
    guard nextCols != cols || nextRows != rows, let surface else { return }
    cols = nextCols
    rows = nextRows
    wwn_term_resize(surface, cols, rows)
    redraw()
  }

  private func flushReply() {
    guard let surface else { return }
    var buf = [UInt8](repeating: 0, count: 256)
    let n = buf.withUnsafeMutableBytes { raw in
      wwn_term_take_reply(surface, raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
    }
    if n > 0 { onReply?(Data(buf.prefix(n))) }
  }

  private func redraw() {
    guard let surface, let metal else { return }
    let scale: CGFloat
    #if os(visionOS)
    scale = traitCollection.displayScale
    #elseif os(tvOS)
    scale = window?.windowScene?.screen.scale
      ?? traitCollection.displayScale
    #else
    scale = window?.screen.scale
      ?? window?.windowScene?.screen.scale
      ?? traitCollection.displayScale
    #endif
    metal.syncBackingScale(scale)
    let cap = Int(cols * rows)
    var cells = [WwnTermCell](
      repeating: WwnTermCell(cp: 32, fg: 0xE8E8E8, bg: 0, attrs: 0),
      count: max(1, cap)
    )
    var outCols: UInt32 = 0
    var outRows: UInt32 = 0
    let origin = wwn_term_origin(surface)
    let n = cells.withUnsafeMutableBufferPointer { buf in
      wwn_term_viewport(surface, origin, buf.baseAddress, UInt32(buf.count), &outCols, &outRows)
    }
    let c = Int(outCols == 0 ? cols : outCols)
    let r = Int(outRows == 0 ? rows : outRows)
    let count = max(Int(n), c * r)
    if cells.count < count {
      cells.append(
        contentsOf: Array(
          repeating: WwnTermCell(cp: 32, fg: 0xE8E8E8, bg: 0, attrs: 0),
          count: count - cells.count
        )
      )
    }
    metal.present(
      cells,
      count: count,
      cols: c,
      rows: r,
      blinkOn: blinkOn,
      cellW: 7,
      cellH: 14
    )
  }
}

@_silgen_name("wwn_term_init")
private func wwn_term_init() -> Int32
@_silgen_name("wwn_term_new")
private func wwn_term_new(_ cols: UInt32, _ rows: UInt32) -> OpaquePointer?
@_silgen_name("wwn_term_free")
private func wwn_term_free(_ s: OpaquePointer?)
@_silgen_name("wwn_term_resize")
private func wwn_term_resize(_ s: OpaquePointer?, _ cols: UInt32, _ rows: UInt32)
@_silgen_name("wwn_term_feed")
private func wwn_term_feed(_ s: OpaquePointer?, _ bytes: UnsafePointer<UInt8>?, _ len: Int)
@_silgen_name("wwn_term_take_reply")
private func wwn_term_take_reply(_ s: OpaquePointer?, _ buf: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("wwn_term_viewport")
private func wwn_term_viewport(
  _ s: OpaquePointer?, _ origin: UInt32, _ out: UnsafeMutablePointer<WwnTermCell>?, _ cap: UInt32,
  _ cols: UnsafeMutablePointer<UInt32>?, _ rows: UnsafeMutablePointer<UInt32>?
) -> UInt32
@_silgen_name("wwn_term_origin")
private func wwn_term_origin(_ s: OpaquePointer?) -> UInt32

public struct WWNGhosttyTermRepresentable: UIViewRepresentable {
  public var feed: Data
  public var onReply: WWNTermReply?

  public init(feed: Data, onReply: WWNTermReply? = nil) {
    self.feed = feed
    self.onReply = onReply
  }

  public func makeUIView(context: Context) -> WWNGhosttyTermView {
    let view = WWNGhosttyTermView(frame: .zero)
    view.onReply = onReply
    return view
  }

  public func updateUIView(_ uiView: WWNGhosttyTermView, context: Context) {
    uiView.onReply = onReply
    if !feed.isEmpty { uiView.feed(feed) }
  }
}
#endif
