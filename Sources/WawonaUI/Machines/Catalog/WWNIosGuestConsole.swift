#if os(iOS) || os(tvOS) || os(visionOS)
import Combine
import SwiftUI
import UIKit

/// Styled lines from UniFFI `TerminalSession`. Host monospaced face, Nerd Font for private-use icons.
struct WawonaTerminalSpan: Identifiable {
  let id: Int
  let text: String
  let fg: UInt32
  let bg: UInt32
  let bold: Bool
  let italic: Bool
  let underline: Bool
  let blink: Bool
  let strike: Bool
}

struct WawonaTerminalLine: Identifiable {
  let id: Int
  let spans: [WawonaTerminalSpan]
}

final class WawonaTerminalModel: ObservableObject {
  @Published var lines: [WawonaTerminalLine] = []
  @Published var pictures: [WawonaTerminalPicture] = []
  /// Bumps on every document apply, including in-place last-line edits.
  @Published var pinToken = 0
  private var nextLineID = 1
  private var lineIDs: [Int] = []
  private var lineKeys: [String] = []

  func reset() {
    lines = []
    pictures = []
    lineIDs = []
    lineKeys = []
    pinToken += 1
  }

  func applyPictures(_ document: String) {
    let next = WawonaTerminalDocument.pictures(from: document)
    if Thread.isMainThread {
      pictures = next
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.pictures = next
      }
    }
  }

  func applyLines(_ document: String) {
    let parsed = WawonaTerminalDocument.lines(from: document)
    let keys = parsed.map { $0.spans.map(\.text).joined(separator: "\u{1}") }
    lineIDs = alignLineIDs(oldIDs: lineIDs, oldKeys: lineKeys, newKeys: keys) {
      let id = nextLineID
      nextLineID += 1
      return id
    }
    lineKeys = keys
    let next = zip(lineIDs, parsed).map { id, line in
      WawonaTerminalLine(
        id: id,
        spans: line.spans.enumerated().map { index, span in
          WawonaTerminalSpan(
            id: index,
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
      )
    }
    if Thread.isMainThread {
      lines = next
      pinToken += 1
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.lines = next
        self?.pinToken += 1
      }
    }
  }
}

private func alignLineIDs(
  oldIDs: [Int],
  oldKeys: [String],
  newKeys: [String],
  mint: () -> Int
) -> [Int] {
  if newKeys == oldKeys, newKeys.count == oldIDs.count {
    return oldIDs
  }
  if newKeys.count >= oldKeys.count, Array(newKeys.prefix(oldKeys.count)) == oldKeys {
    var ids = oldIDs
    while ids.count < newKeys.count {
      ids.append(mint())
    }
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
  let fresh = newKeys.count - overlap
  for _ in 0..<fresh {
    ids.append(mint())
  }
  ids.append(contentsOf: oldIDs.suffix(overlap))
  return ids
}

private struct TermLineRecord: Decodable {
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

enum WawonaTerminalDocument {
  static func lines(from document: String) -> [WawonaTerminalLine] {
    let data = Data(document.utf8)
    let decoded = (try? JSONDecoder().decode([TermLineRecord].self, from: data)) ?? []
    return decoded.enumerated().map { index, line in
      WawonaTerminalLine(
        id: index,
        spans: line.spans.enumerated().map { spanIndex, span in
          WawonaTerminalSpan(
            id: spanIndex,
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
      )
    }
  }

  static func pictures(from document: String) -> [WawonaTerminalPicture] {
    let data = Data(document.utf8)
    let decoded = (try? JSONDecoder().decode([PictureRecord].self, from: data)) ?? []
    return decoded.compactMap { record in
      guard let image = cgImage(record) else { return nil }
      return WawonaTerminalPicture(
        id: record.n, col: record.col, row: record.row,
        columns: max(1, record.cols), rows: max(1, record.rows), z: record.z, image: image
      )
    }
  }
}

struct WawonaTerminalPicture: Identifiable {
  let id: Int
  let col: Int
  let row: Int
  let columns: Int
  let rows: Int
  let z: Int
  let image: CGImage
}

private struct PictureRecord: Decodable {
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

private func cgImage(_ record: PictureRecord) -> CGImage? {
  guard record.w > 0, record.h > 0, let data = Data(base64Encoded: record.rgba, options: .ignoreUnknownCharacters),
    data.count >= record.w * record.h * 4
  else { return nil }
  let space = CGColorSpaceCreateDeviceRGB()
  let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
  guard let provider = CGDataProvider(data: data as CFData) else { return nil }
  return CGImage(
    width: record.w, height: record.h, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: record.w * 4, space: space, bitmapInfo: info, provider: provider,
    decode: nil, shouldInterpolate: true, intent: .defaultIntent
  )
}

struct WawonaTerminalRun: Identifiable {
  let id: Int
  let text: String
  let nerd: Bool
}

enum WawonaTerminalFonts {
  static let pointSize: CGFloat = 13
  static var host: Font { Font.system(size: pointSize, design: .monospaced) }
  static var nerd: Font { Font.custom("DejaVuSansM Nerd Font Mono", size: pointSize) }

  static var rowHeight: CGFloat {
    max(1, metricsFont.lineHeight)
  }

  static var metricsFont: UIFont {
    UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
  }

  static var cellWidth: CGFloat {
    max(1, ("M" as NSString).size(withAttributes: [.font: metricsFont]).width)
  }

  static func runs(_ text: String) -> [WawonaTerminalRun] {
    var out: [WawonaTerminalRun] = []
    var current = ""
    var nerd: Bool?
    var id = 0
    func flush() {
      guard let nerd, !current.isEmpty else { return }
      out.append(WawonaTerminalRun(id: id, text: current, nerd: nerd))
      id += 1
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
    if out.isEmpty {
      out.append(WawonaTerminalRun(id: 0, text: " ", nerd: false))
    }
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

struct WawonaTerminalViewportKey: PreferenceKey {
  static var defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
    let next = nextValue()
    if next != .zero {
      value = next
    }
  }
}

private final class WWNTermPointerHold {
  var down = false
  var sent = false
  var button: UInt32 = 0
  var touches = 0
  var slid = false
  var id = 0
  var col: UInt32 = 0
  var row: UInt32 = 0
  var onRelease: ((UInt32, UInt32, UInt32) -> Void)?

  func cancelPointer() {
    if down, sent { onRelease?(col, row, button) }
    down = false
    sent = false
    slid = false
    touches = 0
    id += 1
  }
}

private final class WWNTermTouchCountRecognizer: UIGestureRecognizer {
  var onCount: ((Int) -> Void)?
  var onCancel: (() -> Void)?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    note(event)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesEnded(touches, with: event)
    note(event)
    finish(event)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesCancelled(touches, with: event)
    let done = event.allTouches?.allSatisfy { $0.phase == .ended || $0.phase == .cancelled } ?? true
    if done { onCancel?() }
    finish(event)
  }

  private func note(_ event: UIEvent) {
    onCount?(event.allTouches?.count ?? 0)
  }

  private func finish(_ event: UIEvent) {
    let done = event.allTouches?.allSatisfy { $0.phase == .ended || $0.phase == .cancelled } ?? true
    if done { state = .failed }
  }
}

private final class WWNTermTouchProbeView: UIView, UIGestureRecognizerDelegate {
  weak var hold: WWNTermPointerHold?
  private var probe: UIGestureRecognizer?

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    attach()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    attach()
  }

  private func attach() {
    guard probe == nil, let host = superview else { return }
    let recognizer = WWNTermTouchCountRecognizer()
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delegate = self
    recognizer.onCount = { [weak self] count in
      guard let hold = self?.hold, count > hold.touches else { return }
      hold.touches = count
    }
    recognizer.onCancel = { [weak self] in
      self?.hold?.cancelPointer()
    }
    host.addGestureRecognizer(recognizer)
    probe = recognizer
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

private struct WWNTermTouchProbe: UIViewRepresentable {
  var hold: WWNTermPointerHold
  var onRelease: (UInt32, UInt32, UInt32) -> Void

  func makeUIView(context: Context) -> WWNTermTouchProbeView {
    let view = WWNTermTouchProbeView()
    view.hold = hold
    hold.onRelease = onRelease
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: WWNTermTouchProbeView, context: Context) {
    uiView.hold = hold
    hold.onRelease = onRelease
  }
}

private extension View {
  @ViewBuilder
  func applyPointerDrag<G: Gesture>(_ gesture: G, tracking: Bool) -> some View {
    if tracking {
      self.gesture(gesture, including: .all)
    } else {
      self.simultaneousGesture(gesture)
    }
  }
}

struct WawonaTerminalView: View {
  @ObservedObject var model: WawonaTerminalModel
  var screenRows: UInt32 = 28
  var onPointer: ((UInt32, UInt32, UInt32, Bool, Bool) -> Void)?
  @State private var blinkOn = true
  @State private var stick = true
  @State private var userDragged = false
  @State private var pointerHold = WWNTermPointerHold()

  var body: some View {
    // ScrollViewReader via Dave DeLong namespace (`WawonaBackport`). Never bare
    // ScrollViewReader at the call site (iOS 13 floor).
    WawonaBackport<Any>.scrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(model.lines) { line in
            lineText(line)
              .frame(maxWidth: .infinity, alignment: .leading)
              .id(line.id)
          }
          Color.clear.frame(height: 1).id("wwn-term-end")
            .onAppear {
              stick = true
              userDragged = false
            }
            .onDisappear {
              if userDragged { stick = false }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(terminalPictures(behind: true))
        .overlay(terminalPictures(behind: false), alignment: .topLeading)
        #if !os(tvOS)
        .applyPointerDrag(
          DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
              guard let cell = cellInStack(value.location) else { return }
              let hold = pointerHold
              let moved = abs(value.translation.width) > 8 || abs(value.translation.height) > 8
              if !hold.down {
                hold.down = true
                hold.sent = false
                hold.slid = false
                hold.button = 0
                hold.col = cell.0
                hold.row = cell.1
                hold.id += 1
                let id = hold.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                  guard hold.id == id, hold.down, !hold.sent, hold.touches < 2 else { return }
                  hold.button = 2
                  hold.sent = true
                  onPointer?(hold.col, hold.row, 2, true, false)
                }
              }
              hold.col = cell.0
              hold.row = cell.1
              if moved { hold.slid = true }
              if moved, hold.touches < 2 {
                if !hold.sent {
                  hold.button = 0
                  hold.sent = true
                  onPointer?(cell.0, cell.1, 0, true, false)
                }
                onPointer?(cell.0, cell.1, hold.button, true, true)
              }
            }
            .onEnded { value in
              let hold = pointerHold
              let cell = cellInStack(value.location) ?? (hold.col, hold.row)
              if hold.down {
                if !hold.sent, hold.touches >= 2, !hold.slid {
                  onPointer?(cell.0, cell.1, 1, true, false)
                  onPointer?(cell.0, cell.1, 1, false, false)
                } else if hold.sent || hold.touches < 2 {
                  if !hold.sent {
                    hold.button = 0
                    onPointer?(cell.0, cell.1, 0, true, false)
                  }
                  onPointer?(cell.0, cell.1, hold.button, false, false)
                }
              }
              hold.down = false
              hold.sent = false
              hold.slid = false
              hold.touches = 0
              hold.id += 1
            },
          tracking: WWNTerminalCursorMode.pointerDrags
        )
        .background(WWNTermTouchProbe(hold: pointerHold) { col, row, button in
          onPointer?(col, row, button, false, false)
        })
        #endif
        .padding(8)
      }
      .background(Color.black)
      .onAppear { scrollTerminalToEnd(proxy) }
      .backport.onChange(of: model.pinToken) { _ in
        if model.lines.isEmpty { stick = true }
        guard stick else { return }
        scrollTerminalToEnd(proxy)
      }
      #if !os(tvOS)
      .simultaneousGesture(
        DragGesture(minimumDistance: 8).onChanged { value in
          if abs(value.translation.height) > 16, !WWNTerminalCursorMode.pointerDrags { userDragged = true }
        }
      )
      #endif
      .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
        if model.lines.contains(where: { $0.spans.contains(where: \.blink) }) {
          blinkOn.toggle()
        }
      }
    }
  }

  private func terminalPictures(behind: Bool) -> some View {
    let live = Int(screenRows)
    let start = max(0, model.lines.count - live)
    let rowH = WawonaTerminalFonts.rowHeight
    let cellW = WawonaTerminalFonts.cellWidth
    return ZStack(alignment: .topLeading) {
      ForEach(model.pictures.filter { behind ? $0.z < 0 : $0.z >= 0 }) { picture in
        Image(decorative: picture.image, scale: 1)
          .resizable()
          .frame(width: cellW * CGFloat(picture.columns), height: rowH * CGFloat(picture.rows))
          .offset(x: cellW * CGFloat(picture.col), y: rowH * CGFloat(start + picture.row))
          .allowsHitTesting(false)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(false)
  }

  private func cellInStack(_ location: CGPoint) -> (UInt32, UInt32)? {
    let col = UInt32(max(1, Int(location.x / WawonaTerminalFonts.cellWidth) + 1))
    let rowIndex = Int(location.y / WawonaTerminalFonts.rowHeight)
    let live = Int(screenRows)
    let start = max(0, model.lines.count - live)
    guard rowIndex >= start, rowIndex < model.lines.count else { return nil }
    return (col, UInt32(rowIndex - start + 1))
  }

  private func scrollTerminalToEnd(_ proxy: WawonaScrollViewProxy) {
    DispatchQueue.main.async {
      proxy.scrollTo("wwn-term-end", anchor: .bottom)
    }
  }

  private func lineText(_ line: WawonaTerminalLine) -> some View {
    let spans = line.spans.isEmpty
      ? [WawonaTerminalSpan(id: 0, text: " ", fg: 0xE8E8E8, bg: 0, bold: false, italic: false, underline: false, blink: false, strike: false)]
      : line.spans
    return HStack(spacing: 0) {
      ForEach(spans) { span in
        spanView(span, blinkOn: blinkOn)
      }
    }
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .frame(height: WawonaTerminalFonts.rowHeight, alignment: .leading)
    .clipped()
  }

  private func spanView(_ span: WawonaTerminalSpan, blinkOn: Bool) -> some View {
    HStack(spacing: 0) {
      ForEach(WawonaTerminalFonts.runs(span.text)) { run in
        styled(run.text, span)
          .font(run.nerd ? WawonaTerminalFonts.nerd : WawonaTerminalFonts.host)
      }
    }
    .background(span.bg == 0 ? Color.clear : rgb(span.bg))
    .opacity(span.blink && !blinkOn ? 0.15 : 1)
    .overlay(strikeBar(span), alignment: .center)
  }

  private func strikeBar(_ span: WawonaTerminalSpan) -> some View {
    Group {
      if span.strike {
        Rectangle()
          .fill(rgb(span.fg))
          .frame(height: 1)
      }
    }
  }

  private func styled(_ text: String, _ span: WawonaTerminalSpan) -> Text {
    var view = Text(text).foregroundColor(rgb(span.fg))
    if span.bold { view = view.bold() }
    if span.italic { view = view.italic() }
    if span.underline { view = view.underline() }
    return view
  }

  private func rgb(_ value: UInt32) -> Color {
    Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }
}

/// iOS / visionOS host for Guest console. Shell source runs in-process zsh
/// via `IosShellSession` (not a stub splash).
@MainActor
final class WWNIosGuestConsole: ObservableObject {
  static let shared = WWNIosGuestConsole()

  @Published var isPresented = false
  /// New Window on iPad / visionOS. The main window must not also show the tab.
  @Published var windowed = false
  /// Set by Start before the present notification. Cleared in `present`.
  static var openNextInWindow = false
  @Published var title = "Guest console"
  @Published var inputLine = ""
  @Published var statusMessage = ""

  let termModel = WawonaTerminalModel()
  @Published var screenRows: UInt32 = 28

  private var machineId = ""
  private var source = "relay"
  private var fed = 0
  private var pumpTimer: Timer?
  private var observer: NSObjectProtocol?
  private var launchLogObserver: NSObjectProtocol?
  private var started = false
  private var shell: IosShellSession?
  private var logTerm: IosLogTermSession?
  private var keyRepeatTimer: Timer?
  private var keyRepeatBytes: [UInt8]?
  private var keyRepeatTicks = 0

  var isShell: Bool { source == "shell" }

  /// Hide Terminal chrome while keeping its shell or log session alive.
  func parkForCompositor() {
    guard isPresented else { return }
    isPresented = false
    NSLog("WWNIosGuestConsole: parked Terminal (session kept alive) mid=%@", machineId)
  }

  func startObservingIfNeeded() {
    guard !started else { return }
    started = true
    observer = NotificationCenter.default.addObserver(
      forName: Notification.Name("WWNRelayGuestConsoleNeededNotification"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let console = self else { return }
      let info = note.userInfo ?? [:]
      let mid = info["machineId"] as? String ?? ""
      let src = info["source"] as? String ?? "relay"
      if src == "close" {
        console.dismiss(machineId: mid)
      } else {
        console.present(machineId: mid, source: src)
      }
    }
    launchLogObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("WWNClientLaunchLogNotification"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let console = self, console.isPresented else { return }
      guard console.source == "client" || console.source == "relay" else { return }
      if let line = note.userInfo?["line"] as? String, !line.isEmpty {
        console.appendLog(line)
      }
    }
  }

  func present(machineId: String, source: String) {
    guard !machineId.isEmpty else { return }
    if self.machineId == machineId, self.source == source {
      if !isPresented {
        windowed = Self.openNextInWindow
        Self.openNextInWindow = false
        isPresented = true
      }
      return
    }
    stopPump()
    stopShell()
    stopLogTerm()
    self.machineId = machineId
    self.source = source
    fed = 0
    inputLine = ""
    statusMessage = ""
    termModel.reset()
    windowed = Self.openNextInWindow
    Self.openNextInWindow = false
    title = "Wawona Terminal"
    switch source {
    case "shell":
      startShell()
    case "ssh":
      startLogTerm()
      appendLog("SSH session starting.\n")
    case "client":
      startLogTerm()
      appendLog(clientStartBanner(machineId: machineId))
    default:
      startLogTerm()
      appendLog("Wawona Terminal\n")
    }
    isPresented = true
    if source == "relay" || source == "client" {
      startPump()
    }
  }

  func fitTerminal(to size: CGSize) {
    guard size.width > 1, size.height > 1 else { return }
    let cellW = WawonaTerminalFonts.cellWidth
    let cellH = WawonaTerminalFonts.rowHeight
    let cols = UInt32(min(512, max(20, Int((size.width - 16) / cellW))))
    let rows = UInt32(min(256, max(8, Int((size.height - 16) / cellH))))
    screenRows = rows
    let pxW = UInt32(max(1, cellW.rounded()))
    let pxH = UInt32(max(1, cellH.rounded()))
    shell?.resize(cols: cols, rows: rows, cellW: pxW, cellH: pxH)
    logTerm?.resize(cols: cols, rows: rows, cellW: pxW, cellH: pxH)
  }

  func dismiss(machineId: String) {
    if !self.machineId.isEmpty, !machineId.isEmpty, machineId != self.machineId {
      return
    }
    stopPump()
    stopShell()
    stopLogTerm()
    isPresented = false
    windowed = false
    self.machineId = ""
    source = "relay"
    fed = 0
    inputLine = ""
    statusMessage = ""
  }

  /// Scene activation failed. Show the terminal in the current window.
  func fallBackToTab() {
    windowed = false
    if !machineId.isEmpty {
      isPresented = true
    }
  }

  /// Done = Focus: park Terminal, reveal mounted Wayland / Metal client.
  func userDismiss() {
    let mid = machineId
    let wasWindow = windowed
    dismiss(machineId: mid)
    #if os(iOS) || os(visionOS)
    if wasWindow {
      WWNSessionWindowPresenter.closeTerminalWindow()
    }
    #endif
    guard !mid.isEmpty else { return }
    WWNMachineProfileStore.setActiveMachineId(mid)
    WWNMainWindowRouter.shared.showSessionSurface()
    NotificationCenter.default.post(
      name: .WWNClientFocusRequested,
      object: nil,
      userInfo: ["machineId": mid]
    )
  }

  private func appendLog(_ chunk: String) {
    guard !chunk.isEmpty else { return }
    if isShell {
      shell?.feedLocal(Data(chunk.utf8))
    } else {
      logTerm?.feed(chunk)
    }
  }

  func pointer(button: UInt32, col: UInt32, row: UInt32, pressed: Bool, motion: Bool) {
    guard isShell else { return }
    shell?.pointer(button: UInt8(truncatingIfNeeded: button), col: col, row: row, pressed: pressed, motion: motion)
  }

  func clearScreen() {
    let erase = Data([0x1B, 0x5B, 0x33, 0x4A])
    if isShell {
      shell?.feedLocal(erase)
    } else {
      logTerm?.feed(erase)
    }
  }

  func submitInput() {
    guard isShell else { return }
    var payload = inputLine
    if !payload.hasSuffix("\n") {
      payload += "\n"
    }
    shell?.write(Data(payload.utf8))
    inputLine = ""
  }

  func sendControl(_ byte: UInt8) {
    guard isShell else { return }
    shell?.write(Data([byte]))
  }

  /// Toolbar Keys / soft keyboard → PTY (shell) or log echo (relay Terminal).
  func injectTerminalText(_ text: String) {
    guard !text.isEmpty else { return }
    if isShell {
      if text.utf8.count > 1, text.contains("\n") || text.contains("\r") {
        shell?.writePaste(Data(text.utf8))
      } else {
        var data = Data(text.utf8)
        #if os(iOS) || os(tvOS) || os(visionOS)
        data = WWNTerminalCursorMode.mapArrow(data)
        #endif
        shell?.write(data)
      }
    } else {
      appendLog(text)
    }
  }

  func injectTerminalPaste(_ text: String) {
    guard !text.isEmpty else { return }
    if isShell {
      shell?.writePaste(Data(text.utf8))
    } else {
      appendLog(text)
    }
  }

  func armKeyRepeat(_ bytes: [UInt8]) {
    keyRepeatTimer?.invalidate()
    keyRepeatBytes = bytes
    keyRepeatTicks = 0
    keyRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
      guard let self, let bytes = self.keyRepeatBytes else { timer.invalidate(); return }
      self.keyRepeatTicks += 1
      guard self.keyRepeatTicks >= 8 else { return }
      self.injectTerminalData(Data(bytes))
    }
  }

  func cancelKeyRepeat() {
    keyRepeatBytes = nil
    keyRepeatTimer?.invalidate()
    keyRepeatTimer = nil
  }

  func injectTerminalData(_ data: Data) {
    guard !data.isEmpty else { return }
    #if os(iOS) || os(tvOS) || os(visionOS)
    let bytes = isShell ? WWNTerminalCursorMode.mapArrow(data) : data
    #else
    let bytes = data
    #endif
    if isShell {
      shell?.write(bytes)
    } else if let text = String(data: data, encoding: .utf8) {
      appendLog(text)
    }
  }

  private func startShell() {
    let session = IosShellSession()
    session.onScreen = { [weak self] data in
      self?.termModel.applyLines(data)
    }
    session.onPictures = { [weak self] data in
      self?.termModel.applyPictures(data)
    }
    session.onFailure = { [weak self] message in
      self?.statusMessage = message
      self?.appendLog(message + "\n")
    }
    shell = session
    session.start(cols: 80, rows: 28)
  }

  private func stopShell() {
    cancelKeyRepeat()
    shell?.stop()
    shell = nil
  }

  private func startLogTerm() {
    stopLogTerm()
    let session = IosLogTermSession()
    session.onScreen = { [weak self] data in
      self?.termModel.applyLines(data)
    }
    session.onPictures = { [weak self] data in
      self?.termModel.applyPictures(data)
    }
    logTerm = session
    session.start(cols: 80, rows: 28)
  }

  private func stopLogTerm() {
    logTerm?.stop()
    logTerm = nil
  }

  private func startPump() {
    stopPump()
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let console = self else { return }
      if Thread.isMainThread {
        console.pumpOnce()
      } else {
        DispatchQueue.main.async { console.pumpOnce() }
      }
    }
    pumpTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopPump() {
    pumpTimer?.invalidate()
    pumpTimer = nil
  }

  private func pumpOnce() {
    guard source == "relay" || source == "client", !machineId.isEmpty else { return }
    if let log = WWNRelay.sharedRelay.consoleLog(forMachineId: machineId),
       log.count > fed
    {
      let delta = log.subdata(in: fed..<log.count)
      fed = log.count
      if let chunk = String(data: delta, encoding: .utf8), !chunk.isEmpty {
        appendLog(chunk)
      }
    }
  }

  private func clientStartBanner(machineId: String) -> String {
    guard let profile = WWNMachineProfileStore.profile(byId: machineId) else {
      return "Wawona Terminal\n"
    }
    let prefs = WWNPreferencesManager.sharedManager()
    let kind = WWNNativeShellConfiguration.kind(for: profile)
    if kind == kWWNNativeShellKindWaypipe
      || profile.type == kWWNMachineTypeSSHWaypipe
    {
      let preview = WWNWaypipeRunner.sharedRunner().generateWaypipePreviewString(prefs)
      return "$ \(preview)\n# Done focuses the compositor.\n"
    }
    let client = WWNMachineSessionBridge.nativeClientId(forProfile: profile) ?? "client"
    let display = WWNCompositorBridge.sharedBridge.socketName()
    return """
    $ wwn-exec \(client)
    WAYLAND_DISPLAY=\(display.isEmpty ? "wayland-0" : display)
    # Done focuses the compositor.

    """
  }
}

struct WWNIosGuestConsoleSheet: View {
  @ObservedObject var console: WWNIosGuestConsole
  @State private var keyFocus = 0

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        WawonaTerminalView(model: console.termModel, screenRows: console.screenRows) { col, row, button, pressed, motion in
          console.pointer(button: button, col: col, row: row, pressed: pressed, motion: motion)
          if !pressed { keyFocus += 1 }
        }
          .background(
            GeometryReader { geo in
              Color.clear.preference(key: WawonaTerminalViewportKey.self, value: geo.size)
            }
          )
          .onPreferenceChange(WawonaTerminalViewportKey.self) { size in
            console.fitTerminal(to: size)
          }
        if !console.statusMessage.isEmpty {
          Text(console.statusMessage)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        #if os(iOS)
        // Toolbar Keys owns soft-keyboard chrome (Esc/Tab/arrows/modifiers).
        // Host is near-invisible; accessory draws above the system keyboard.
        WWNTerminalToolbarHost(
          isShell: console.isShell,
          onInjectData: { console.injectTerminalData($0) },
          onInjectText: { console.injectTerminalText($0) },
          onPaste: { console.injectTerminalPaste($0) },
          onDismissKeyboard: {},
          autoFocus: true,
          focusTick: keyFocus,
          onKeyRepeat: { console.armKeyRepeat($0) },
          onKeyUp: { console.cancelKeyRepeat() }
        )
        .frame(width: 1, height: 1)
        .accessibility(identifier: "wwn.guestConsole.send")
        #elseif os(tvOS) || os(visionOS)
        if console.isShell {
          WWNTerminalKeyHost(
            onInjectData: { console.injectTerminalData($0) },
            onInjectText: { console.injectTerminalText($0) },
            autoFocus: true,
            focusTick: keyFocus
          )
          .frame(width: 1, height: 1)
          .accessibility(identifier: "wwn.guestConsole.send")
          #if os(visionOS)
          HStack {
            Button("^C") { console.sendControl(0x03) }
              .accessibility(identifier: "wwn.guestConsole.ctrlC")
          }
          .padding(8)
          .background(Color.black)
          #endif
        }
        #endif
      }
      .background(Color.black)
      .accessibility(identifier: WWNA11y.terminalRoot)
      .backport.navigationTitle(console.title, inline: true)
      .backport.navigationActions {
        Button("Done") { console.userDismiss() }
          .accessibility(identifier: WWNA11y.terminalDone)
      } trailing: {
        Button("Clear") { console.clearScreen() }
          .accessibility(identifier: "wwn.terminal.clear")
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
      guard console.isShell, let bytes = WWNTerminalCursorMode.focusReport(false) else { return }
      console.injectTerminalData(bytes)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      guard console.isShell, let bytes = WWNTerminalCursorMode.focusReport(true) else { return }
      console.injectTerminalData(bytes)
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .preferredColorScheme(.dark)
  }
}
#endif
