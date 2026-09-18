#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  KeyboardArrowCluster.swift
//  Wawona
//
//  Arrow key cluster with swipe gesture support (ported 1:1 from rootshell).
//

import UIKit

open class KeyboardArrowCluster: UIView {
    // MARK: - Properties

    public weak var delegate: KeyboardButtonDelegate?
    private var sizes: KeyboardSizes

    private var currentPanDirection: ArrowDirection?
    private var lastFiredDirection: ArrowDirection?
    private var autoRepeatTimer: Timer?

    #if !os(visionOS)
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    #endif

    // Visual feedback view
    private let highlightView = UIView()
    private var iconOffsetConstraints: [ArrowDirection: NSLayoutConstraint] = [:]

    // MARK: - Arrow Direction

    public enum ArrowDirection: Sendable {
        case up, down, left, right

        public var key: String {
            switch self {
            case .up: return "\u{1B}[A"
            case .down: return "\u{1B}[B"
            case .left: return "\u{1B}[D"
            case .right: return "\u{1B}[C"
            }
        }

        public var icon: String {
            switch self {
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case .left: return "arrow.left"
            case .right: return "arrow.right"
            }
        }
    }

    // MARK: - Initialization

    public init(sizes: KeyboardSizes) {
        self.sizes = sizes
        super.init(frame: .zero)
        setupView()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .clear

        // Add highlight view
        highlightView.backgroundColor = KeyboardKeyColors.highlight
        highlightView.layer.cornerRadius = sizes.button.cornerRadius
        highlightView.layer.cornerCurve = .continuous
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        addSubview(highlightView)

        // Add arrow icons as visual guides (non-interactive)
        let directions: [ArrowDirection] = [.up, .down, .left, .right]
        for direction in directions {
            let iconView = UIImageView(image: UIImage(systemName: direction.icon))
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = .secondaryLabel
            iconView.alpha = 0.4
            iconView.isUserInteractionEnabled = false
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)

            let iconSize: CGFloat = 14
            let offset: CGFloat = sizes.button.iconWidth / 2 - 4
            let offsetConstraint: NSLayoutConstraint

            switch direction {
            case .up:
                offsetConstraint = iconView.centerYAnchor.constraint(equalTo: topAnchor, constant: offset)
                NSLayoutConstraint.activate([
                    iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                    offsetConstraint,
                    iconView.widthAnchor.constraint(equalToConstant: iconSize),
                    iconView.heightAnchor.constraint(equalToConstant: iconSize)
                ])
            case .down:
                offsetConstraint = iconView.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -offset)
                NSLayoutConstraint.activate([
                    iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                    offsetConstraint,
                    iconView.widthAnchor.constraint(equalToConstant: iconSize),
                    iconView.heightAnchor.constraint(equalToConstant: iconSize)
                ])
            case .left:
                offsetConstraint = iconView.centerXAnchor.constraint(equalTo: leadingAnchor, constant: offset)
                NSLayoutConstraint.activate([
                    offsetConstraint,
                    iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    iconView.widthAnchor.constraint(equalToConstant: iconSize),
                    iconView.heightAnchor.constraint(equalToConstant: iconSize)
                ])
            case .right:
                offsetConstraint = iconView.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -offset)
                NSLayoutConstraint.activate([
                    offsetConstraint,
                    iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    iconView.widthAnchor.constraint(equalToConstant: iconSize),
                    iconView.heightAnchor.constraint(equalToConstant: iconSize)
                ])
            }

            iconOffsetConstraints[direction] = offsetConstraint
        }

        // Add pan gesture for swipe detection
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        // Add tap gesture for precise taps
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        #if !os(visionOS)
        feedbackGenerator.prepare()
        #endif
    }

    // MARK: - Gesture Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began, .changed:
            if gesture.state == .began {
                SystemShiftReader.shared.noteModifierFlags(gesture.modifierFlags)
            }
            let direction = directionFromLocation(location)

            if direction != currentPanDirection {
                // Direction changed
                stopAutoRepeat()
                currentPanDirection = direction

                if let direction = direction {
                    // Send key
                    sendKey(direction)

                    // Show highlight
                    showHighlight(for: direction)

                    // Start auto-repeat after delay (macOS fastest: 225ms)
                    autoRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.225, repeats: false) { [weak self] _ in
                        self?.startAutoRepeat()
                    }
                } else {
                    hideHighlight()
                }
            }

        case .ended, .cancelled:
            currentPanDirection = nil
            lastFiredDirection = nil
            stopAutoRepeat()
            hideHighlight()

        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        SystemShiftReader.shared.noteModifierFlags(gesture.modifierFlags)
        let location = gesture.location(in: self)
        if let direction = directionFromLocation(location) {
            sendKey(direction)
            showHighlight(for: direction)

            // Hide highlight after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.hideHighlight()
            }
        }
    }

    // MARK: - Direction Detection

    private func directionFromLocation(_ location: CGPoint) -> ArrowDirection? {
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2

        let dx = location.x - centerX
        let dy = location.y - centerY

        // Dead zone in center
        let deadZone: CGFloat = 8
        if abs(dx) < deadZone && abs(dy) < deadZone {
            return nil
        }

        // Determine primary direction
        if abs(dx) > abs(dy) {
            // Horizontal
            return dx > 0 ? .right : .left
        } else {
            // Vertical
            return dy > 0 ? .down : .up
        }
    }

    // MARK: - Auto-Repeat

    private func startAutoRepeat() {
        guard currentPanDirection != nil else { return }

        autoRepeatTimer?.invalidate()
        autoRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let dir = self.currentPanDirection else { return }
            self.sendKey(dir)
        }
    }

    private func stopAutoRepeat() {
        autoRepeatTimer?.invalidate()
        autoRepeatTimer = nil
    }

    // MARK: - Key Sending

    private func sendKey(_ direction: ArrowDirection) {
        // Don't send duplicate keys too quickly
        if direction == lastFiredDirection {
            // Already auto-repeating this direction
        } else {
            playHaptic()
            lastFiredDirection = direction
        }

        delegate?.keyPressed(direction.key, modifiers: [])
    }

    // MARK: - Visual Feedback

    private func showHighlight(for direction: ArrowDirection) {
        let size = sizes.button.iconWidth
        let halfSize = size / 2

        var frame = CGRect.zero
        switch direction {
        case .up:
            frame = CGRect(x: bounds.width / 2 - halfSize, y: 0, width: size, height: size)
        case .down:
            frame = CGRect(x: bounds.width / 2 - halfSize, y: bounds.height - size, width: size, height: size)
        case .left:
            frame = CGRect(x: 0, y: bounds.height / 2 - halfSize, width: size, height: size)
        case .right:
            frame = CGRect(x: bounds.width - size, y: bounds.height / 2 - halfSize, width: size, height: size)
        }

        highlightView.frame = frame

        UIView.animate(withDuration: 0.1) {
            self.highlightView.alpha = 1
        }
    }

    private func hideHighlight() {
        UIView.animate(withDuration: 0.2) {
            self.highlightView.alpha = 0
        }
    }

    // MARK: - Haptic Feedback

    private func playHaptic() {
        #if !os(visionOS)
        UIDevice.current.playInputClick()
        #endif
    }

    // MARK: - Layout

    open override var intrinsicContentSize: CGSize {
        let totalWidth = sizes.button.iconWidth * 2.2
        return CGSize(width: totalWidth, height: sizes.button.height)
    }

    open func updateSizes(_ newSizes: KeyboardSizes) {
        sizes = newSizes
        highlightView.layer.cornerRadius = sizes.button.cornerRadius
        highlightView.layer.cornerCurve = .continuous
        let offset = sizes.button.iconWidth / 2 - 4
        iconOffsetConstraints[.up]?.constant = offset
        iconOffsetConstraints[.down]?.constant = -offset
        iconOffsetConstraints[.left]?.constant = offset
        iconOffsetConstraints[.right]?.constant = -offset
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

// Enable haptic feedback for custom view
#if !os(visionOS)
extension KeyboardArrowCluster: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool {
        return true
    }
}
#endif
#endif
