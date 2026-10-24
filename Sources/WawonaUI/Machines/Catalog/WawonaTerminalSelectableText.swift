#if os(iOS) || os(tvOS) || os(visionOS)
import SwiftUI
import UIKit

/// Range selection (length > 0) owns the gate. Caret-only typing does not.
/// Keeps ToolbarKeys / inject paths from treating a live caret as "selecting".
enum WawonaTerminalSelectionGate {
  static let began = Notification.Name("WWNTerminalSelectionBeganNotification")
  static let ended = Notification.Name("WWNTerminalSelectionEndedNotification")
  static let restoreKeyboard = Notification.Name(
    "WWNTerminalRestoreKeyboardFocusNotification"
  )
  /// System Paste from the UITextView caret edit menu → PTY inject.
  static let pasteToPty = Notification.Name("WWNTerminalPasteToPtyNotification")

  private static let lock = NSLock()
  private static var _active = false

  static var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _active
  }

  static func setActive(_ active: Bool) {
    lock.lock()
    let changed = _active != active
    _active = active
    lock.unlock()
    guard changed else { return }
    NotificationCenter.default.post(
      name: active ? began : ended,
      object: nil
    )
    if !active {
      NotificationCenter.default.post(name: restoreKeyboard, object: nil)
    }
  }
}

/// Soft / hardware Return can hit ShouldReturn + pressesBegan + insertText
/// on one keystroke. Coalesce to a single PTY `0x0A`.
enum WawonaTerminalReturnInject {
  private static let lock = NSLock()
  private static var last: CFAbsoluteTime = 0

  static func once(_ body: () -> Void) {
    lock.lock()
    let now = CFAbsoluteTimeGetCurrent()
    if now - last < 0.08 {
      lock.unlock()
      return
    }
    last = now
    lock.unlock()
    body()
  }
}

/// Host UITextView: VT mirror for viewing, native caret for editing.
/// Soft keyboard + ToolbarKeys live on this view (not a second FR field).
struct WawonaTerminalSelectableText: UIViewRepresentable {
  @ObservedObject var model: WawonaTerminalModel
  var blinkOn: Bool
  var stickToBottom: Bool
  /// When true (iOS shell / console), this view owns keyboard + accessory.
  var ownsKeyboard: Bool = false
  var isShell: Bool = false
  var onInjectData: ((Data) -> Void)?
  var onInjectText: ((String) -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> WawonaTerminalSelectTextView {
    let tv = WawonaTerminalSelectTextView()
    tv.delegate = context.coordinator
    tv.backgroundColor = .black
    tv.textColor = UIColor(white: 0.91, alpha: 1)
    tv.tintColor = UIColor(white: 0.85, alpha: 1)
    #if !os(tvOS)
    tv.isEditable = true
    #endif
    tv.isSelectable = true
    tv.isScrollEnabled = true
    tv.alwaysBounceVertical = true
    tv.showsVerticalScrollIndicator = true
    tv.indicatorStyle = .white
    #if !os(visionOS)
    tv.keyboardDismissMode = .none
    #endif
    #if !os(tvOS)
    tv.dataDetectorTypes = []
    #endif
    tv.textContainer.lineFragmentPadding = 0
    tv.textContainer.lineBreakMode = .byClipping
    tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    #if !os(tvOS)
    tv.autocorrectionType = .no
    tv.spellCheckingType = .no
    tv.smartDashesType = .no
    tv.smartQuotesType = .no
    tv.smartInsertDeleteType = .no
    tv.autocapitalizationType = .none
    tv.keyboardAppearance = .dark
    tv.keyboardType = .asciiCapable
    #endif
    context.coordinator.textView = tv
    tv.selectionCoordinator = context.coordinator
    context.coordinator.applyKeyboardOwnership(to: tv)
    return tv
  }

  func updateUIView(_ tv: WawonaTerminalSelectTextView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.textView = tv
    tv.selectionCoordinator = context.coordinator
    context.coordinator.applyKeyboardOwnership(to: tv)

    let fingerprint = Self.contentFingerprint(model.lines)
    let rangeSelecting = tv.selectedRange.length > 0
    let selecting =
      WawonaTerminalSelectionGate.isActive || rangeSelecting
    if selecting, fingerprint == context.coordinator.lastFingerprint {
      return
    }
    let sameDoc = fingerprint == context.coordinator.lastFingerprint
    // Native caret mode: skip blink-only redraws (caret is the cursor).
    let hideBlockCursor = ownsKeyboard && tv.isFirstResponder && !rangeSelecting
    if sameDoc, !selecting {
      if hideBlockCursor || blinkOn == context.coordinator.lastBlinkOn {
        context.coordinator.syncCaretToVtCursor(in: tv, force: false)
        return
      }
      context.coordinator.lastBlinkOn = blinkOn
      guard Self.hasBlinkSpans(model.lines) else { return }
      let attr = Self.attributedDocument(
        lines: model.lines, blinkOn: blinkOn, hideBlockCursor: false
      )
      let saved = tv.selectedRange
      context.coordinator.applyingDocument = true
      tv.attributedText = attr
      if saved.location + saved.length <= attr.length {
        tv.selectedRange = saved
      }
      context.coordinator.applyingDocument = false
      return
    }
    context.coordinator.lastFingerprint = fingerprint
    context.coordinator.lastBlinkOn = blinkOn
    let attr = Self.attributedDocument(
      lines: model.lines,
      blinkOn: blinkOn,
      hideBlockCursor: hideBlockCursor
    )
    let saved = selecting ? tv.selectedRange : NSRange(location: NSNotFound, length: 0)
    context.coordinator.applyingDocument = true
    tv.attributedText = attr
    if selecting, saved.location != NSNotFound,
      saved.location + saved.length <= attr.length
    {
      tv.selectedRange = saved
    } else if ownsKeyboard {
      context.coordinator.syncCaretToVtCursor(in: tv, force: true)
    } else if stickToBottom {
      context.coordinator.scrollToEnd(animated: false)
    }
    context.coordinator.applyingDocument = false

    if ownsKeyboard, !tv.isFirstResponder {
      DispatchQueue.main.async {
        guard context.coordinator.parent.ownsKeyboard else { return }
        guard !WawonaTerminalSelectionGate.isActive else { return }
        _ = tv.becomeFirstResponder()
      }
    }
  }

  static func hasBlinkSpans(_ lines: [WawonaTerminalLine]) -> Bool {
    lines.contains { line in line.spans.contains(where: \.blink) }
  }

  static func contentFingerprint(_ lines: [WawonaTerminalLine]) -> String {
    lines.map { $0.spans.map(\.text).joined() }.joined(separator: "\n")
  }

  /// UTF-16 offset of the VT blink cursor cell, or nil if absent.
  static func vtCursorUTF16Offset(lines: [WawonaTerminalLine]) -> Int? {
    var offset = 0
    for (index, line) in lines.enumerated() {
      if index > 0 { offset += 1 }
      let spans = line.spans.isEmpty
        ? [
          WawonaTerminalSpan(
            id: 0, text: " ", fg: 0xE8E8E8, bg: 0, bold: false, italic: false,
            underline: false, blink: false, strike: false
          )
        ]
        : line.spans
      for span in spans {
        if span.blink {
          return offset
        }
        offset += (span.text as NSString).length
      }
    }
    return nil
  }

  static func attributedDocument(
    lines: [WawonaTerminalLine],
    blinkOn: Bool,
    hideBlockCursor: Bool
  ) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let rowH = WawonaTerminalFonts.rowHeight
    let para = NSMutableParagraphStyle()
    para.minimumLineHeight = rowH
    para.maximumLineHeight = rowH
    para.lineBreakMode = .byClipping
    para.paragraphSpacing = 0
    para.paragraphSpacingBefore = 0

    for (index, line) in lines.enumerated() {
      if index > 0 {
        out.append(
          NSAttributedString(
            string: "\n",
            attributes: [
              .font: WawonaTerminalFonts.metricsFont,
              .foregroundColor: UIColor.clear,
              .paragraphStyle: para,
            ]
          )
        )
      }
      let spans = line.spans.isEmpty
        ? [
          WawonaTerminalSpan(
            id: 0, text: " ", fg: 0xE8E8E8, bg: 0, bold: false, italic: false,
            underline: false, blink: false, strike: false
          )
        ]
        : line.spans
      for span in spans {
        out.append(
          attributedSpan(
            span, paragraph: para, blinkOn: blinkOn, hideBlockCursor: hideBlockCursor
          )
        )
      }
    }
    if out.length == 0 {
      out.append(
        NSAttributedString(
          string: " ",
          attributes: [
            .font: WawonaTerminalFonts.metricsFont,
            .foregroundColor: UIColor(white: 0.91, alpha: 1),
            .paragraphStyle: para,
          ]
        )
      )
    }
    return out
  }

  private static func attributedSpan(
    _ span: WawonaTerminalSpan,
    paragraph: NSParagraphStyle,
    blinkOn: Bool,
    hideBlockCursor: Bool
  ) -> NSAttributedString {
    let chunk = NSMutableAttributedString()
    for run in WawonaTerminalFonts.runs(span.text) {
      var font = run.nerd
        ? (UIFont(name: "DejaVuSansM Nerd Font Mono", size: WawonaTerminalFonts.pointSize)
          ?? WawonaTerminalFonts.metricsFont)
        : WawonaTerminalFonts.metricsFont
      if span.bold, let desc = font.fontDescriptor.withSymbolicTraits(.traitBold) {
        font = UIFont(descriptor: desc, size: font.pointSize)
      }
      if span.italic, let desc = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
        font = UIFont(descriptor: desc, size: font.pointSize)
      }
      var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: uiColor(span.fg),
        .paragraphStyle: paragraph,
      ]
      if span.bg != 0 {
        attrs[.backgroundColor] = uiColor(span.bg)
      }
      if span.underline {
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
      }
      if span.strike {
        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
      }
      if span.blink {
        if hideBlockCursor {
          // Native caret is the cursor; keep cell width, hide block glyph.
          attrs[.foregroundColor] = UIColor.clear
          attrs[.backgroundColor] = UIColor.clear
        } else if !blinkOn {
          attrs[.foregroundColor] = uiColor(span.fg).withAlphaComponent(0.15)
        }
      }
      chunk.append(NSAttributedString(string: run.text, attributes: attrs))
    }
    return chunk
  }

  private static func uiColor(_ value: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: WawonaTerminalSelectableText
    weak var textView: WawonaTerminalSelectTextView?
    var lastFingerprint = ""
    var lastBlinkOn: Bool?
    var applyingDocument = false
    #if os(iOS)
    private var accessory: WWNKeyboardAccessoryView?
    #endif

    init(parent: WawonaTerminalSelectableText) {
      self.parent = parent
    }

    func applyKeyboardOwnership(to tv: WawonaTerminalSelectTextView) {
      #if os(iOS)
      if parent.ownsKeyboard {
        tv.inputView = nil
        if accessory == nil {
          let view = WWNKeyboardAccessoryView()
          view.wwnDelegate = self
          accessory = view
        }
        accessory?.wwnDelegate = self
        tv.inputAccessoryView = accessory
      } else {
        // Selection-only host: empty inputView keeps soft keys elsewhere.
        if tv.inputView == nil {
          tv.inputView = UIView(frame: .zero)
        }
        tv.inputAccessoryView = nil
      }
      #endif
    }

    func scrollToEnd(animated: Bool) {
      guard let tv = textView, tv.attributedText.length > 0 else { return }
      let end = NSRange(location: max(0, tv.attributedText.length - 1), length: 1)
      tv.scrollRangeToVisible(end)
    }

    /// Place native caret on the VT blink cell. Skip while user has a range.
    func syncCaretToVtCursor(in tv: UITextView, force: Bool) {
      guard parent.ownsKeyboard else { return }
      guard tv.selectedRange.length == 0 || force else { return }
      guard !WawonaTerminalSelectionGate.isActive || force else { return }
      let len = tv.attributedText.length
      guard len > 0 else { return }
      let offset =
        WawonaTerminalSelectableText.vtCursorUTF16Offset(lines: parent.model.lines)
        ?? max(0, len - 1)
      let loc = min(max(0, offset), len)
      let next = NSRange(location: loc, length: 0)
      if !NSEqualRanges(tv.selectedRange, next) {
        applyingDocument = true
        tv.selectedRange = next
        applyingDocument = false
      }
      if parent.stickToBottom {
        tv.scrollRangeToVisible(next)
      }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      guard !applyingDocument else { return }
      // Range select only. Caret moves (long-press, tap) must not snap back
      // to the VT blink cell or Select / Select All never sticks.
      WawonaTerminalSelectionGate.setActive(textView.selectedRange.length > 0)
    }

    func textView(
      _ textView: UITextView,
      shouldChangeTextIn range: NSRange,
      replacementText text: String
    ) -> Bool {
      _ = range
      guard parent.ownsKeyboard else { return false }
      guard !WawonaTerminalSelectionGate.isActive else { return false }
      injectReplacement(text)
      return false
    }

    func injectReplacement(_ text: String) {
      if text.isEmpty {
        parent.onInjectData?(Data([0x7F]))
        return
      }
      if text == "\n" || text == "\r" {
        WawonaTerminalReturnInject.once {
          parent.onInjectData?(Data([0x0A]))
        }
        return
      }
      parent.onInjectText?(text)
    }

    #if os(iOS)
    // MARK: ToolbarKeys

    func keyboardAccessoryDidSendKey(name: String, keycode: UInt32, character: String?) {
      guard !WawonaTerminalSelectionGate.isActive else { return }
      if parent.isShell {
        if let character, !character.isEmpty {
          parent.onInjectText?(character)
        } else if keycode == WWNEvdevKeycode.esc {
          parent.onInjectData?(Data([0x1B]))
        } else if keycode == WWNEvdevKeycode.tab {
          parent.onInjectData?(Data([0x09]))
        } else if keycode == WWNEvdevKeycode.enter {
          WawonaTerminalReturnInject.once {
            parent.onInjectData?(Data([0x0A]))
          }
        } else if keycode == WWNEvdevKeycode.backspace {
          parent.onInjectData?(Data([0x7F]))
        } else if keycode == WWNEvdevKeycode.up {
          parent.onInjectData?(Data([0x1B, 0x5B, 0x41]))
        } else if keycode == WWNEvdevKeycode.down {
          parent.onInjectData?(Data([0x1B, 0x5B, 0x42]))
        } else if keycode == WWNEvdevKeycode.right {
          parent.onInjectData?(Data([0x1B, 0x5B, 0x43]))
        } else if keycode == WWNEvdevKeycode.left {
          parent.onInjectData?(Data([0x1B, 0x5B, 0x44]))
        } else if !name.isEmpty, name != "raw" {
          parent.onInjectText?(name)
        }
      } else if let character, !character.isEmpty {
        parent.onInjectText?(character)
      }
      accessory?.clearOneShotModifiers()
    }

    func keyboardAccessoryModifierChanged(modifier: String, active: Bool, locked: Bool) {
      _ = (modifier, active, locked)
    }

    func keyboardAccessoryDidRequestDismiss() {
      textView?.resignFirstResponder()
    }

    func keyboardAccessoryDidRequestTabOverview() {
      WWNClientTabChromeController.active?.openTabExpose()
    }

    func keyboardAccessoryDidRequestNewTab() {
      WWNClientTabChromeController.active?.createNewTab()
    }

    func keyboardAccessoryDidRequestPaste() {
      guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
      parent.onInjectText?(text)
    }

    func keyboardAccessoryGeometryDidChange() {}

    func keyboardAccessorySendRawData(_ data: Data) {
      if parent.isShell {
        parent.onInjectData?(data)
      } else if let text = String(data: data, encoding: .utf8) {
        parent.onInjectText?(text)
      }
    }
    #endif
  }
}

#if os(iOS)
extension WawonaTerminalSelectableText.Coordinator: WWNKeyboardAccessoryDelegate {}
#endif

/// Editable VT mirror. Keys → PTY. Native caret tracks blink cell.
final class WawonaTerminalSelectTextView: UITextView {
  weak var selectionCoordinator: WawonaTerminalSelectableText.Coordinator?

  override var canBecomeFirstResponder: Bool { true }

  @discardableResult
  override func becomeFirstResponder() -> Bool {
    let ok = super.becomeFirstResponder()
    if ok {
      if selectedRange.length > 0 {
        WawonaTerminalSelectionGate.setActive(true)
      }
      // Editing focus: put native caret on the VT blink cell.
      selectionCoordinator?.syncCaretToVtCursor(in: self, force: true)
    }
    return ok
  }

  @discardableResult
  override func resignFirstResponder() -> Bool {
    let ok = super.resignFirstResponder()
    if ok {
      WawonaTerminalSelectionGate.setActive(false)
    }
    return ok
  }

  override func insertText(_ text: String) {
    guard selectionCoordinator?.parent.ownsKeyboard == true else { return }
    guard !WawonaTerminalSelectionGate.isActive else { return }
    selectionCoordinator?.injectReplacement(text)
  }

  override func deleteBackward() {
    guard selectionCoordinator?.parent.ownsKeyboard == true else { return }
    guard !WawonaTerminalSelectionGate.isActive else { return }
    selectionCoordinator?.parent.onInjectData?(Data([0x7F]))
  }

  override func copy(_ sender: Any?) {
    super.copy(sender)
    // Keep FR; snap caret back to VT after range clears.
  }

  override func paste(_ sender: Any?) {
    #if !os(tvOS)
    guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
    if selectionCoordinator?.parent.ownsKeyboard == true {
      selectionCoordinator?.parent.onInjectText?(text)
    } else {
      NotificationCenter.default.post(
        name: WawonaTerminalSelectionGate.pasteToPty,
        object: text
      )
    }
    #endif
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard selectionCoordinator?.parent.ownsKeyboard == true,
      selectionCoordinator?.parent.isShell == true,
      !WawonaTerminalSelectionGate.isActive
    else {
      super.pressesBegan(presses, with: event)
      return
    }
    if #available(iOS 13.4, *) {
      var rest = Set<UIPress>()
      for press in presses {
        if let key = press.key, let bytes = WWNTerminalKeyBytes.special(for: key) {
          if key.keyCode == .keyboardReturnOrEnter {
            WawonaTerminalReturnInject.once {
              selectionCoordinator?.parent.onInjectData?(Data([0x0A]))
            }
          } else {
            selectionCoordinator?.parent.onInjectData?(Data(bytes))
          }
        } else {
          rest.insert(press)
        }
      }
      if !rest.isEmpty {
        super.pressesBegan(rest, with: event)
      }
      return
    }
    super.pressesBegan(presses, with: event)
  }
}
#endif
