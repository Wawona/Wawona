#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  KeyboardButton.swift
//  Wawona
//
//  Base class for keyboard toolbar buttons (ported 1:1 from rootshell).
//

import UIKit

// MARK: - Key Action Protocol

public protocol KeyboardButtonDelegate: AnyObject {
    func keyPressed(_ key: String, modifiers: KeyModifiers)
    func cancelScrollTouches()
    func sendRawData(_ data: Data)
}

public extension KeyboardButtonDelegate {
    // Default no-op for buttons not in scrollable containers
    func cancelScrollTouches() {}
    func sendRawData(_ data: Data) {}

    /// Send a [SequenceStep] sequence to the terminal one step at a time, inserting
    /// a 50ms delay after any step whose data ends with ESC (0x1B). Prevents the
    /// terminal app from interpreting ESC + next-char as Alt+key. Used by both the
    /// keyboard toolbar's custom keys and the swipe gesture binding system.
    func sendSequenceSteps(_ steps: [SequenceStep]) {
        guard !steps.isEmpty else { return }

        var index = 0
        func sendNext() {
            guard index < steps.count else { return }
            let step = steps[index]
            index += 1
            let data = step.terminalData()
            if !data.isEmpty {
                sendRawData(data)
            }
            // If this step's data ends with ESC and there are more steps,
            // delay before sending the next so the terminal doesn't merge
            // ESC with the following byte as an Alt sequence.
            if data.last == 0x1B, index < steps.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    sendNext()
                }
            } else {
                sendNext()
            }
        }
        sendNext()
    }
}

// MARK: - Key Modifiers

public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let alt     = KeyModifiers(rawValue: 1 << 1)
    public static let command = KeyModifiers(rawValue: 1 << 2)
    public static let shift   = KeyModifiers(rawValue: 1 << 3)
}

public enum KeyboardKeyColors {
    public static let highlight = UIColor { traits in
        let base = traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
        let alpha: CGFloat = traits.accessibilityContrast == .high ? 0.28 : 0.18
        return base.withAlphaComponent(alpha)
    }

    public static let active = UIColor { traits in
        let base = traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
        let alpha: CGFloat = traits.accessibilityContrast == .high ? 0.42 : 0.28
        return base.withAlphaComponent(alpha)
    }
}

// MARK: - KeyboardButton

open class KeyboardButton: UIControl {
    // MARK: - Properties

    public weak var delegate: KeyboardButtonDelegate?
    public let key: String
    public var sizes: KeyboardSizes

    private var autoRepeatTimer: Timer?
    private let autoRepeatDelay: TimeInterval = 0.225  // macOS fastest: 225ms
    private let autoRepeatInterval: TimeInterval = 0.1  // Repeat interval
    private var defersCurrentTouchUntilRelease = false
    private var sentKeyDuringCurrentTouch = false

    /// Whether this button should auto-repeat when held
    public var shouldAutoRepeat: Bool = false

    /// In bottom-edge toolbar mode, wait for touch-up so a Home swipe can
    /// cancel the touch without first emitting a terminal key.
    public var defersKeyUntilTouchUp: Bool = false

    // Override isHighlighted to update appearance
    open override var isHighlighted: Bool {
        didSet {
            updateAppearance()
        }
    }

    // MARK: - Initialization

    public init(key: String, sizes: KeyboardSizes = .current()) {
        self.key = key
        self.sizes = sizes
        super.init(frame: .zero)
        setupButton()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupButton() {
        backgroundColor = .clear
        layer.cornerRadius = sizes.button.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        #if os(visionOS)
        hoverStyle = UIHoverStyle(
            shape: .rect(cornerRadius: sizes.button.cornerRadius)
        )
        #endif
    }

    // MARK: - Touch Handling

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        SystemShiftReader.shared.noteTouchEvent(event)
        defersCurrentTouchUntilRelease = defersKeyUntilTouchUp
        sentKeyDuringCurrentTouch = false

        if !defersCurrentTouchUntilRelease {
            playHaptic()
        }

        // Start auto-repeat timer if enabled
        if shouldAutoRepeat {
            autoRepeatTimer?.invalidate()
            autoRepeatTimer = Timer.scheduledTimer(withTimeInterval: autoRepeatDelay, repeats: false) { [weak self] _ in
                guard let self else { return }
                if self.defersCurrentTouchUntilRelease {
                    self.sendKey()
                    self.playHaptic()
                    self.sentKeyDuringCurrentTouch = true
                }
                self.startAutoRepeat()
            }
        }

        if !defersCurrentTouchUntilRelease {
            sendKey()
        }
    }

    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        stopAutoRepeat()
        if defersCurrentTouchUntilRelease && !sentKeyDuringCurrentTouch {
            sendKey()
            playHaptic()
        }
        resetDeferredTouchState()
    }

    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        stopAutoRepeat()
        resetDeferredTouchState()
    }

    private func resetDeferredTouchState() {
        defersCurrentTouchUntilRelease = false
        sentKeyDuringCurrentTouch = false
    }

    // MARK: - Auto-Repeat

    private func startAutoRepeat() {
        autoRepeatTimer?.invalidate()
        autoRepeatTimer = Timer.scheduledTimer(withTimeInterval: autoRepeatInterval, repeats: true) { [weak self] _ in
            self?.sendKey()
            self?.playHaptic()
        }
    }

    private func stopAutoRepeat() {
        autoRepeatTimer?.invalidate()
        autoRepeatTimer = nil
    }

    // MARK: - Key Sending

    open func sendKey() {
        // Get current modifiers from toolbar
        let modifiers = currentModifiers()
        delegate?.keyPressed(key, modifiers: modifiers)
    }

    /// Override this to provide current modifier state
    open func currentModifiers() -> KeyModifiers {
        return []
    }

    // MARK: - Visual Feedback

    private func updateAppearance() {
        UIView.animate(withDuration: 0.1, delay: 0, options: .allowUserInteraction) {
            if self.isHighlighted {
                self.backgroundColor = KeyboardKeyColors.highlight
            } else {
                self.backgroundColor = .clear
            }
        }
    }

    // MARK: - Haptic Feedback

    open func playHaptic() {
        // Play standard input click sound
        #if !os(visionOS)
        UIDevice.current.playInputClick()
        #endif
    }

    // MARK: - Layout

    open override var intrinsicContentSize: CGSize {
        return CGSize(width: sizes.button.normalWidth, height: sizes.button.height)
    }

    open func updateSizes(_ newSizes: KeyboardSizes) {
        sizes = newSizes
        layer.cornerRadius = sizes.button.cornerRadius
        layer.cornerCurve = .continuous
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

// Enable haptic feedback for custom view
#if !os(visionOS)
extension KeyboardButton: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool {
        return true
    }
}
#endif
#endif
