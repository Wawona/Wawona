#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  KeyboardAccessoryView.swift
//  Wawona
//
//  UIInputView wrapper for keyboard toolbar (ported 1:1 from rootshell).
//

import UIKit

open class KeyboardAccessoryView: UIInputView {
    // MARK: - Properties

    public private(set) var toolbarView: KeyboardToolbarView
    public weak var delegate: KeyboardButtonDelegate? {
        didSet {
            toolbarView.delegate = delegate
        }
    }

    public var onModifiersChanged: ((KeyModifiers) -> Void)? {
        didSet {
            toolbarView.onModifiersChanged = onModifiersChanged
        }
    }

    public var onDismissRequested: (() -> Void)? {
        didSet {
            toolbarView.onDismissRequested = onDismissRequested
        }
    }

    public var onCollapseRequested: (() -> Void)? {
        didSet {
            toolbarView.onCollapseRequested = onCollapseRequested
        }
    }

    public var onPinHiddenRequested: (() -> Void)? {
        didSet {
            toolbarView.onPinHiddenRequested = onPinHiddenRequested
        }
    }

    public var onTabSwitcherRequested: (() -> Void)? {
        didSet {
            toolbarView.onTabSwitcherRequested = onTabSwitcherRequested
        }
    }

    public var onComposeRequested: (() -> Void)? {
        didSet {
            toolbarView.onComposeRequested = onComposeRequested
        }
    }

    public var onToolbarSettingsRequested: (() -> Void)? {
        didSet {
            toolbarView.onToolbarSettingsRequested = onToolbarSettingsRequested
        }
    }

    public var onPasteRequested: (() -> Void)? {
        didSet {
            toolbarView.onPasteRequested = onPasteRequested
        }
    }

    public var onToggleFullScreenRequested: (() -> Void)? {
        didSet {
            toolbarView.onToggleFullScreenRequested = onToggleFullScreenRequested
        }
    }

    public var onToggleTabBarRequested: (() -> Void)? {
        didSet {
            toolbarView.onToggleTabBarRequested = onToggleTabBarRequested
        }
    }

    public var onNewConnectionRequested: (() -> Void)? {
        didSet {
            toolbarView.onNewConnectionRequested = onNewConnectionRequested
        }
    }

    public var onAppSettingsRequested: (() -> Void)? {
        didSet {
            toolbarView.onAppSettingsRequested = onAppSettingsRequested
        }
    }

    public var onToggleMouseCaptureRequested: (() -> Void)? {
        didSet {
            toolbarView.onToggleMouseCaptureRequested = onToggleMouseCaptureRequested
        }
    }

    public var onAIAgentRequested: (() -> Void)? {
        didSet {
            toolbarView.onAIAgentRequested = onAIAgentRequested
        }
    }

    public var onBrightnessBoostRequested: (() -> Void)? {
        didSet {
            toolbarView.onBrightnessBoostRequested = onBrightnessBoostRequested
        }
    }

    public var onClipboardManagerRequested: (() -> Void)? {
        didSet {
            toolbarView.onClipboardManagerRequested = onClipboardManagerRequested
        }
    }

    public var onLayoutInvalidated: (() -> Void)?

    private var layoutChangeObserver: NSObjectProtocol?
    private var toolbarBottomConstraint: NSLayoutConstraint?

    private let bottomStripBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let bottomStripTintView = UIView()

    public private(set) var reservedBottomSafeArea: CGFloat = 0


    // MARK: - Initialization

    public init(sizes: KeyboardSizes = .current()) {
        toolbarView = KeyboardToolbarView(sizes: sizes)

        let frame = CGRect(
            x: 0,
            y: 0,
            width: UIScreen.main.bounds.width,
            height: sizes.toolbar.height
        )

        super.init(frame: frame, inputViewStyle: .keyboard)

        setupView()
        observeLayoutChanges()
    }

    public override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        let sizes = KeyboardSizes.current()
        toolbarView = KeyboardToolbarView(sizes: sizes)

        let finalFrame = frame.isEmpty ? CGRect(
            x: 0,
            y: 0,
            width: UIScreen.main.bounds.width,
            height: sizes.toolbar.height
        ) : frame

        super.init(frame: finalFrame, inputViewStyle: inputViewStyle)

        setupView()
        observeLayoutChanges()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = layoutChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        allowsSelfSizing = true
        backgroundColor = .clear

        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbarView)

        let toolbarBottom = toolbarView.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            toolbarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbarView.topAnchor.constraint(equalTo: topAnchor),
            toolbarBottom
        ])
        toolbarBottomConstraint = toolbarBottom

        bottomStripBlurView.translatesAutoresizingMaskIntoConstraints = false
        bottomStripBlurView.isUserInteractionEnabled = false
        bottomStripBlurView.isHidden = true
        bottomStripTintView.translatesAutoresizingMaskIntoConstraints = false
        bottomStripTintView.backgroundColor = toolbarView.glassTintColor(for: traitCollection)
        insertSubview(bottomStripBlurView, belowSubview: toolbarView)
        bottomStripBlurView.contentView.addSubview(bottomStripTintView)
        NSLayoutConstraint.activate([
            bottomStripBlurView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            bottomStripBlurView.leadingAnchor.constraint(equalTo: toolbarView.plateLeadingAnchor),
            bottomStripBlurView.trailingAnchor.constraint(equalTo: toolbarView.plateTrailingAnchor),
            bottomStripBlurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomStripTintView.topAnchor.constraint(equalTo: bottomStripBlurView.contentView.topAnchor),
            bottomStripTintView.leadingAnchor.constraint(equalTo: bottomStripBlurView.contentView.leadingAnchor),
            bottomStripTintView.trailingAnchor.constraint(equalTo: bottomStripBlurView.contentView.trailingAnchor),
            bottomStripTintView.bottomAnchor.constraint(equalTo: bottomStripBlurView.contentView.bottomAnchor),
        ])
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: KeyboardAccessoryView, _: UITraitCollection) in
            self.bottomStripTintView.backgroundColor = self.toolbarView.glassTintColor(for: self.traitCollection)
        }

        toolbarView.onDrawerStateChanged = { [weak self] in
            self?.invalidateLayoutAndNotify()
        }

    }

    private func invalidateLayoutAndNotify() {
        toolbarView.setNeedsLayout()
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        onLayoutInvalidated?()
    }

    private func observeLayoutChanges() {
        layoutChangeObserver = NotificationCenter.default.addObserver(
            forName: KeyboardToolbarManager.layoutDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildToolbar()
        }
    }

    private func rebuildToolbar() {
        toolbarView.rebuildForCurrentWidth()
        invalidateLayoutAndNotify()
    }

    // MARK: - Layout

    open override var intrinsicContentSize: CGSize {
        var size = toolbarView.intrinsicContentSize
        size.height += reservedBottomSafeArea
        return size
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width,
            height: toolbarView.intrinsicContentSize.height + reservedBottomSafeArea
        )
    }

    // MARK: - Public Methods

    public func updateForTraitCollection(_ traitCollection: UITraitCollection) {
        let newSizes = KeyboardSizes.current(traitCollection: traitCollection)
        toolbarView.updateSizes(newSizes)
        invalidateLayoutAndNotify()
    }

    @discardableResult
    public func setReservedBottomSafeArea(_ reserve: CGFloat) -> Bool {
        let clamped = max(0, reserve)
        guard abs(clamped - reservedBottomSafeArea) > 0.5 else { return false }
        reservedBottomSafeArea = clamped
        toolbarBottomConstraint?.constant = -clamped
        bottomStripBlurView.isHidden = clamped <= 0
        toolbarView.setBottomEdgeSquared(clamped > 0)
        toolbarView.setNeedsLayout()
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        return true
    }

    public func setBottomEdgeHomeGestureProtectionEnabled(_ enabled: Bool) {
        toolbarView.setDefersKeysForBottomEdgeGesture(enabled)
    }

    public func setDismissButtonPinned(_ pinned: Bool) {
        toolbarView.setDismissButtonPinned(pinned)
    }

    public func setDismissButtonShowsRestore(_ showsRestore: Bool) {
        toolbarView.setDismissButtonShowsRestore(showsRestore)
    }

    public func setMouseCaptureOverrideActive(_ active: Bool) {
        toolbarView.setMouseCaptureOverrideActive(active)
    }
}
#endif
