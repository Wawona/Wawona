#if canImport(UIKit) && !os(watchOS)
import UIKit
import SwiftUI

/// UIKit host for Wawona Terminal grid on iOS / tvOS / visionOS.
/// Product contract is UniFFI `GhosttySurface` (see staged `apple/Terminal`).
/// This view still uses optional C `wwn_term_*` until UniFFI Swift is linked.
@objc(WWNGhosttyTermView)
public final class WWNGhosttyTermView: UIView {
  public var onReply: WWNTermReply?

  private var surface: OpaquePointer?
  private var cols: UInt32 = 80
  private var rows: UInt32 = 24
  private let textView = UITextView()
  private var grid = ""

  public override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
    textView.isEditable = false
    textView.isSelectable = false
    textView.backgroundColor = .clear
    textView.textColor = UIColor(white: 0.91, alpha: 1)
    textView.font = UIFont(name: "Menlo", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(textView)
    NSLayoutConstraint.activate([
      textView.topAnchor.constraint(equalTo: topAnchor),
      textView.bottomAnchor.constraint(equalTo: bottomAnchor),
      textView.leadingAnchor.constraint(equalTo: leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    wwn_term_init()
    surface = wwn_term_new(cols, rows)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  deinit {
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
    guard let surface else { return }
    let cap = Int(cols * rows)
    var cells = [GhosttyCell](repeating: GhosttyCell(cp: 32, fg: 0xE8E8E8, bg: 0, attrs: 0), count: cap)
    var outCols: UInt32 = 0
    var outRows: UInt32 = 0
    let origin = wwn_term_origin(surface)
    let n = cells.withUnsafeMutableBufferPointer { buf in
      wwn_term_viewport(surface, origin, buf.baseAddress, UInt32(cap), &outCols, &outRows)
    }
    var lines = [String]()
    let c = Int(outCols == 0 ? cols : outCols)
    let r = Int(outRows == 0 ? rows : outRows)
    for row in 0..<r {
      var line = ""
      for col in 0..<c {
        let idx = row * c + col
        guard idx < Int(n) else { break }
        let cp = cells[idx].cp
        if let scalar = UnicodeScalar(cp), scalar.isASCII {
          line.append(Character(scalar))
        } else if cp != 0 {
          line.append("\u{FFFD}")
        } else {
          line.append(" ")
        }
      }
      lines.append(line)
    }
    textView.text = lines.joined(separator: "\n")
  }
}

private struct GhosttyCell {
  var cp: UInt32
  var fg: UInt32
  var bg: UInt32
  var attrs: UInt32
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
  _ s: OpaquePointer?, _ origin: UInt32, _ out: UnsafeMutablePointer<GhosttyCell>?, _ cap: UInt32,
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
