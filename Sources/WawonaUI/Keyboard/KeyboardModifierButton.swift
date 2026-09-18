#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  KeyboardModifierButton.swift
//  Wawona
//
//  Modifier keys with three-state sticky behavior (Ctrl, Alt, Cmd, Shift, Esc)
//  Single tap = one-shot (applies to next key then auto-clears)
//  Double tap = locked (stays on until tapped off)
//  Ported 1:1 from rootshell.
//

import UIKit
import os

// MARK: - ModifierState

public enum ModifierState: Equatable, Sendable {
    case inactive   // Not active
    case oneShot    // Active for next key only
    case locked     // Active until tapped off
}

open class KeyboardModifierButton: KeyboardButton {
    private nonisolated static let logger = Logger(subsystem: "io.wawona.Wawona", category: "KeyboardModifierButton")

    // MARK: - Properties

    private let label: UILabel
    private let iconView: UIImageView?
    private let systemImageName: String?
    private let lockIndicatorBar: UIView
    private var lastTapTimestamp: CFAbsoluteTime = 0
    private let doubleTapThreshold: CFAbsoluteTime = 0.5

    /// Three-state modifier: inactive → oneShot → locked → inactive
    public var modifierState: ModifierState = .inactive {
        didSet {
            updateVisualState()
        }
    }

    /// Convenience: whether the modifier is active (one-shot or locked)
    public var isModifierActive: Bool { modifierState != .inactive }

    /// The modifier this button represents
    public let modifier: KeyModifiers?

    /// Callback when modifier state changes
    public var onStateChange: ((ModifierState) -> Void)?

    // MARK: - Initialization

    public init(title: String, systemImage: String? = nil, modifier: KeyModifiers? = nil, sizes: KeyboardSizes = .current()) {
        self.modifier = modifier
        self.systemImageName = systemImage

        // Create label
        label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: sizes.button.fontSize, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        // Create icon if provided
        if let systemImage = systemImage {
            let config = UIImage.SymbolConfiguration(pointSize: sizes.button.symbolSize, weight: .medium)
            iconView = UIImageView(image: UIImage(systemName: systemImage, withConfiguration: config))
            iconView?.contentMode = .scaleAspectFit
            iconView?.translatesAutoresizingMaskIntoConstraints = false
        } else {
            iconView = nil
        }

        // Create lock indicator bar (shown when locked)
        lockIndicatorBar = UIView()
        lockIndicatorBar.backgroundColor = .label
        lockIndicatorBar.layer.cornerRadius = 1
        lockIndicatorBar.alpha = 0
        lockIndicatorBar.translatesAutoresizingMaskIntoConstraints = false

        super.init(key: title, sizes: sizes)

        setupViews()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        // Add icon or label
        if let iconView = iconView {
            addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.7),
                iconView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.7)
            ])
        } else {
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        // Add lock indicator bar at bottom center
        addSubview(lockIndicatorBar)
        NSLayoutConstraint.activate([
            lockIndicatorBar.centerXAnchor.constraint(equalTo: centerXAnchor),
            lockIndicatorBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            lockIndicatorBar.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.6),
            lockIndicatorBar.heightAnchor.constraint(equalToConstant: 2)
        ])

        // Register for trait changes (iOS 17+ replacement for traitCollectionDidChange)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: KeyboardModifierButton, _: UITraitCollection) in
            self.updateVisualState()
        }

        updateVisualState()
    }

    // MARK: - Touch Handling

    open override func sendKey() {
        // Esc fires immediately, never enters sticky cycle
        if key == "Esc" {
            delegate?.keyPressed("\u{1B}", modifiers: [])
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastTapTimestamp

        switch modifierState {
        case .inactive:
            if elapsed < doubleTapThreshold {
                // Quick second tap (one-shot was consumed between taps) → lock
                modifierState = .locked
            } else {
                modifierState = .oneShot
            }
            lastTapTimestamp = now

        case .oneShot:
            if elapsed < doubleTapThreshold {
                // Quick double-tap → lock
                modifierState = .locked
            } else {
                // Slow second tap → toggle off
                modifierState = .inactive
            }
            lastTapTimestamp = now

        case .locked:
            modifierState = .inactive
            lastTapTimestamp = 0
        }

        let modifierValue = modifier?.rawValue ?? 0
        let stateName = switch modifierState {
        case .inactive: "inactive"
        case .oneShot: "oneShot"
        case .locked: "locked"
        }
        Self.logger.debug("Modifier '\(self.key)' → \(stateName), modifier rawValue: \(modifierValue)")
        onStateChange?(modifierState)
    }

    // MARK: - Visual State

    open override var isHighlighted: Bool {
        didSet {
            updateVisualState()
        }
    }

    private func updateVisualState() {
        // Background and icon change instantly so double-tap feels responsive
        switch modifierState {
        case .inactive:
            backgroundColor = isHighlighted ? KeyboardKeyColors.highlight : .clear
            updateIconVariant(filled: false)
        case .oneShot:
            backgroundColor = KeyboardKeyColors.active
            updateIconVariant(filled: true)
        case .locked:
            backgroundColor = KeyboardKeyColors.active
            updateIconVariant(filled: true)
        }
        label.textColor = .label
        iconView?.tintColor = .label

        // Only the lock indicator bar animates
        let targetAlpha: CGFloat = modifierState == .locked ? 1 : 0
        if lockIndicatorBar.alpha != targetAlpha {
            UIView.animate(withDuration: 0.15, delay: 0, options: .allowUserInteraction) {
                self.lockIndicatorBar.alpha = targetAlpha
            }
        }
    }

    /// Update icon to filled/outline variant. Only Shift has a .fill variant.
    private func updateIconVariant(filled: Bool) {
        guard let iconView = iconView, let baseName = systemImageName else { return }

        // Only shift has a distinct .fill variant
        let targetName: String
        if baseName == "shift" {
            targetName = filled ? "shift.fill" : "shift"
        } else {
            return // Other modifiers keep the same icon
        }

        let config = UIImage.SymbolConfiguration(pointSize: sizes.button.symbolSize, weight: .medium)
        iconView.image = UIImage(systemName: targetName, withConfiguration: config)
    }

    // MARK: - Accessibility

    open override var accessibilityTraits: UIAccessibilityTraits {
        get {
            var traits = super.accessibilityTraits
            if isModifierActive {
                traits.insert(.selected)
            }
            return traits
        }
        set { super.accessibilityTraits = newValue }
    }

    open override var accessibilityValue: String? {
        get {
            switch modifierState {
            case .inactive: return nil
            case .oneShot: return "One-shot"
            case .locked: return "Locked"
            }
        }
        set { super.accessibilityValue = newValue }
    }

    // MARK: - Layout

    open override var intrinsicContentSize: CGSize {
        return CGSize(width: sizes.button.wideWidth, height: sizes.button.height)
    }

    open override func updateSizes(_ newSizes: KeyboardSizes) {
        super.updateSizes(newSizes)
        label.font = .systemFont(ofSize: newSizes.button.fontSize, weight: .medium)

        if let iconView = iconView {
            let config = UIImage.SymbolConfiguration(pointSize: newSizes.button.symbolSize, weight: .medium)
            iconView.preferredSymbolConfiguration = config
        }
    }

    // MARK: - State Management

    /// Clear one-shot state only (locked state persists)
    public func clearIfOneShot() {
        if modifierState == .oneShot {
            modifierState = .inactive
        }
    }

    /// Force reset to inactive regardless of state
    public func reset() {
        modifierState = .inactive
    }
}
#endif
