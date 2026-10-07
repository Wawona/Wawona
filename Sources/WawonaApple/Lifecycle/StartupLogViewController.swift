#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

@objc(WWNStartupLogViewController)
public final class WWNStartupLogViewController: UIViewController, WWNStartupLoggerDelegate {

    @objc public var clientLabel: String? {
        didSet {
            if isViewLoaded {
                titleLabel?.text = (clientLabel?.isEmpty == false) ? clientLabel : "Starting…"
            }
        }
    }

    private let fadeDuration: TimeInterval = 0.4
    private let autoTimeout: TimeInterval = 60
    private let cornerRadius: CGFloat = 16
    private let maxOverlayHeight: CGFloat = 0.72

    private var blurContainer: UIVisualEffectView!
    private var titleLabel: UILabel!
    private var spinner: UIActivityIndicatorView!
    #if os(visionOS)
    private var logLabel: UILabel!
    #else
    private var textView: UITextView!
    #endif
    private var doneButton: UIButton!
    private var dismissing = false
    private var timeoutTimer: Timer?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildUI()
        WWNStartupLogger.shared.delegate = self
        let existing = WWNStartupLogger.shared.capturedLines() as? [String] ?? []
        if !existing.isEmpty {
            setLogText(existing.joined(separator: "\n"))
            scrollToBottom()
        }
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: autoTimeout, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if WWNStartupLogger.shared.delegate === self {
            WWNStartupLogger.shared.delegate = nil
        }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    @objc(dismissWithCompletion:)
    public func dismissWithCompletion(_ completion: (() -> Void)?) {
        if dismissing {
            completion?()
            return
        }
        dismissing = true
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        WWNStartupLogger.shared.delegate = nil
        WWNStartupLogger.shared.endCapture()
        spinner.stopAnimating()
        UIView.animate(withDuration: fadeDuration, animations: {
            self.view.alpha = 0
        }, completion: { _ in
            self.willMove(toParent: nil)
            self.view.removeFromSuperview()
            self.removeFromParent()
            completion?()
        })
    }

    public func startupLogger(_ logger: WWNStartupLogger, didAppendLine line: String) {
        guard !dismissing else { return }
        let current = logText
        setLogText(current.isEmpty ? line : current + "\n" + line)
        scrollToBottom()
    }

    private func buildUI() {
        let root = view!
        let bgTap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        bgTap.cancelsTouchesInView = false
        root.addGestureRecognizer(bgTap)

        #if os(tvOS)
        let blur = UIBlurEffect(style: .extraDark)
        #else
        let blur = UIBlurEffect(style: .systemThickMaterialDark)
        #endif
        blurContainer = UIVisualEffectView(effect: blur)
        blurContainer.translatesAutoresizingMaskIntoConstraints = false
        blurContainer.layer.cornerRadius = cornerRadius
        blurContainer.layer.masksToBounds = true
        root.addSubview(blurContainer)

        let card = blurContainer.contentView
        spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .systemGreen
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        card.addSubview(spinner)

        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.textColor = .label
        titleLabel.text = clientLabel ?? "Starting…"
        card.addSubview(titleLabel)

        doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        doneButton.addTarget(self, action: #selector(handleDone), for: .touchUpInside)
        card.addSubview(doneButton)

        #if os(visionOS)
        logLabel = UILabel()
        logLabel.translatesAutoresizingMaskIntoConstraints = false
        logLabel.numberOfLines = 0
        logLabel.lineBreakMode = .byTruncatingHead
        logLabel.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        logLabel.textColor = .systemGreen
        logLabel.backgroundColor = UIColor(white: 0, alpha: 0.4)
        logLabel.layer.cornerRadius = 8
        logLabel.layer.masksToBounds = true
        card.addSubview(logLabel)
        #else
        textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        #if !os(tvOS)
        textView.isEditable = false
        #endif
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor(white: 0, alpha: 0.4)
        textView.layer.cornerRadius = 8
        textView.layer.masksToBounds = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .systemGreen
        card.addSubview(textView)
        #endif

        let hintLabel = UILabel()
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabel
        hintLabel.text = "Select text to copy · auto-dismisses on first frame"
        hintLabel.textAlignment = .center
        card.addSubview(hintLabel)

        let margin: CGFloat = 16
        let inner: CGFloat = 12
        NSLayoutConstraint.activate([
            blurContainer.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            blurContainer.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -44),
            blurContainer.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.94),
            blurContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            blurContainer.heightAnchor.constraint(lessThanOrEqualTo: root.heightAnchor, multiplier: maxOverlayHeight),
            blurContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            spinner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: margin),
            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: margin),
            titleLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: spinner.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -8),
            doneButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -margin),
            doneButton.centerYAnchor.constraint(equalTo: spinner.centerYAnchor),
        ])

        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = .separator
        card.addSubview(sep)
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            sep.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: inner),
            sep.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        #if os(visionOS)
        let logView = logLabel!
        #else
        let logView = textView!
        #endif
        NSLayoutConstraint.activate([
            logView.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: inner),
            logView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: margin),
            logView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -margin),
            hintLabel.topAnchor.constraint(equalTo: logView.bottomAnchor, constant: inner),
            hintLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: margin),
            hintLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -margin),
            hintLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -margin),
        ])
    }

    @objc private func handleDone() { dismissWithCompletion(nil) }
    @objc private func handleBackgroundTap() {}
    @objc private func handleTimeout() { dismissWithCompletion(nil) }

    private var logText: String {
        #if os(visionOS)
        return logLabel.text ?? ""
        #else
        return textView.text ?? ""
        #endif
    }

    private func setLogText(_ text: String) {
        #if os(visionOS)
        logLabel.text = text
        #else
        textView.text = text
        #endif
    }

    private func scrollToBottom() {
        #if !os(visionOS)
        guard let textView, !textView.text.isEmpty else { return }
        let end = NSRange(location: textView.text.count - 1, length: 1)
        textView.scrollRangeToVisible(end)
        #endif
    }
}
#endif
