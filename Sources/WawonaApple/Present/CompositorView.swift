#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
import QuartzCore

/// UIKit compositor surface. Replaces WWNCompositorView_ios.m.
@objc(WWNCompositorView_ios)
public final class WWNCompositorView_ios: UIView, UITextInput {
    @objc public var wwnWindowId: UInt64 = 0
    @objc public var hostLocked = false
    @objc public var followHostSize = false
    @objc public var clientCommittedSize: CGSize = .zero
    @objc public private(set) var contentLayer: CAMetalLayer = CAMetalLayer()
    @objc public private(set) var waylandLayer: CALayer = CALayer()
    @objc public private(set) var keyboardActive = false
    @objc public private(set) var hardwareKeyboardActive = false
    private var metal = MetalPresenter()
    private var hostKeyboardReady = false
    /// Soft cursor for gamepad / GCMouse injection (Touchpad mode).
    private var virtualPointer = CGPoint.zero
    private var virtualPointerSeeded = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        if let layer = metal.layer {
            contentLayer = layer
            contentLayer.frame = bounds
            self.layer.addSublayer(contentLayer)
        }
        waylandLayer.frame = bounds
        layer.addSublayer(waylandLayer)
        #if !os(tvOS)
        isMultipleTouchEnabled = true
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func layoutSubviews() {
        super.layoutSubviews()
        contentLayer.frame = bounds
        waylandLayer.frame = bounds
        metal.resize(bounds.size)
    }

    @objc public func preferredHostOutputSize() -> CGSize { bounds.size }

    @objc public func activateKeyboard() {
        keyboardActive = true
        _ = becomeFirstResponder()
    }

    @objc public func deactivateKeyboard() {
        keyboardActive = false
        resignFirstResponder()
    }

    @objc public func toggleKeyboard() {
        keyboardActive ? deactivateKeyboard() : activateKeyboard()
    }

    @objc(applyHostKeyboardForTextInputEnabled:)
    public func applyHostKeyboard(forTextInputEnabled enabled: Bool) {
        if enabled && hostKeyboardReady { activateKeyboard() }
        else if !enabled { deactivateKeyboard() }
    }

    @objc public func isHostKeyboardReady() -> Bool { hostKeyboardReady }

    @objc public func armHostKeyboardAfterFirstFrame() {
        hostKeyboardReady = true
    }

    public override var canBecomeFirstResponder: Bool { true }

    // Minimal UITextInput stubs so the class conforms.
    public var selectedTextRange: UITextRange? {
        get { nil }
        set { _ = newValue }
    }
    public var markedTextRange: UITextRange? { nil }
    public var markedTextStyle: [NSAttributedString.Key: Any]? {
        get { nil }
        set { _ = newValue }
    }
    public var beginningOfDocument: UITextPosition { UITextPosition() }
    public var endOfDocument: UITextPosition { UITextPosition() }
    public var inputDelegate: UITextInputDelegate? {
        get { nil }
        set { _ = newValue }
    }
    public var tokenizer: UITextInputTokenizer { UITextInputStringTokenizer(textInput: self) }
    public func text(in range: UITextRange) -> String? { nil }
    public func replace(_ range: UITextRange, withText text: String) { _ = (range, text) }
    public func setMarkedText(_ markedText: String?, selectedRange: NSRange) { _ = (markedText, selectedRange) }
    public func unmarkText() {}
    public func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? { nil }
    public func position(from position: UITextPosition, offset: Int) -> UITextPosition? { nil }
    public func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? { nil }
    public func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult { .orderedSame }
    public func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int { 0 }
    public func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? { nil }
    public func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? { nil }
    public func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection { .natural }
    public func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) { _ = (writingDirection, range) }
    public func firstRect(for range: UITextRange) -> CGRect { .zero }
    public func caretRect(for position: UITextPosition) -> CGRect { .zero }
    public func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }
    public func closestPosition(to point: CGPoint) -> UITextPosition? { nil }
    public func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? { nil }
    public func characterRange(at point: CGPoint) -> UITextRange? { nil }
    public var hasText: Bool { false }
    public func insertText(_ text: String) {
        SeatForwarder.insertText(core: WWNCompositorBridge.sharedBridge.core, text: text)
    }
    public func deleteBackward() {
        SeatForwarder.deleteBackward(core: WWNCompositorBridge.sharedBridge.core)
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches, phase: .down)
    }
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches, phase: .motion)
    }
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches, phase: .up)
    }
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches, phase: .up)
    }

    private func forward(_ touches: Set<UITouch>, phase: SeatForwarder.TouchPhase) {
        let core = WWNCompositorBridge.sharedBridge.core
        for (i, t) in touches.enumerated() {
            let p = t.location(in: self)
            SeatForwarder.injectTouch(
                core: core,
                windowId: wwnWindowId,
                touchId: Int32(i),
                x: p.x,
                y: p.y,
                phase: phase,
                timestampMs: UInt32(t.timestamp * 1000)
            )
        }
    }

    private func ensureVirtualPointerSeeded() {
        guard !virtualPointerSeeded else { return }
        virtualPointer = CGPoint(x: bounds.midX, y: bounds.midY)
        virtualPointerSeeded = true
    }

    private var seatTimestampMs: UInt32 {
        UInt32(CACurrentMediaTime() * 1000.0)
    }

    @objc(moveVirtualPointerByDx:dy:)
    public func moveVirtualPointerByDx(_ dx: CGFloat, dy: CGFloat) {
        ensureVirtualPointerSeeded()
        let next = CGPoint(
            x: min(max(virtualPointer.x + dx, 0), max(bounds.width - 1, 0)),
            y: min(max(virtualPointer.y + dy, 0), max(bounds.height - 1, 0))
        )
        virtualPointer = next
        let t = seatTimestampMs
        WWNCompositorBridge.sharedBridge.injectPointerMotion(
            forWindow: wwnWindowId,
            x: Double(next.x),
            y: Double(next.y),
            timestamp: t
        )
    }

    @objc(clickVirtualPointerButton:pressed:)
    public func clickVirtualPointerButton(_ button: UInt32, pressed: Bool) {
        ensureVirtualPointerSeeded()
        let t = seatTimestampMs
        WWNCompositorBridge.sharedBridge.injectPointerMotion(
            forWindow: wwnWindowId,
            x: Double(virtualPointer.x),
            y: Double(virtualPointer.y),
            timestamp: t
        )
        WWNCompositorBridge.sharedBridge.injectPointerButton(
            forWindow: wwnWindowId,
            button: button,
            pressed: pressed,
            timestamp: t
        )
    }

    @objc(scrollVirtualPointerByDx:dy:)
    public func scrollVirtualPointerByDx(_ dx: CGFloat, dy: CGFloat) {
        ensureVirtualPointerSeeded()
        let t = seatTimestampMs
        if abs(dx) > 0.001 {
            WWNCompositorBridge.sharedBridge.injectPointerAxis(
                forWindow: wwnWindowId,
                axis: 1,
                value: Double(dx),
                discrete: 0,
                timestamp: t
            )
        }
        if abs(dy) > 0.001 {
            WWNCompositorBridge.sharedBridge.injectPointerAxis(
                forWindow: wwnWindowId,
                axis: 0,
                value: Double(dy),
                discrete: 0,
                timestamp: t
            )
        }
    }
}
#endif
