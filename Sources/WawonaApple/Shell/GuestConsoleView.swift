#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

@objc(WWNGuestConsoleView)
public final class WWNGuestConsoleView: UIView {
    @objc public private(set) var machineId: String = ""
    private let textView = UITextView()

    @objc(initWithMachineId:)
    public convenience init(machineId: String) {
        self.init(machineId: machineId, source: "local")
    }

    @objc(initWithMachineId:source:)
    public init(machineId: String, source: String) {
        self.machineId = machineId
        super.init(frame: .zero)
        _ = source
        #if !os(tvOS)
        textView.isEditable = false
        #endif
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc(appendOutput:)
    public func appendOutput(_ bytes: Data) {
        if let s = String(data: bytes, encoding: .utf8) {
            DispatchQueue.main.async {
                self.textView.text += s
            }
        }
    }

    @objc public func stop() {}
}
#endif
