#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

/// Retired Start preview overlay. Machine Start uses Wawona Terminal /
/// `WWNIosGuestConsole` instead. Kept as a no-op ObjC-named type so any
/// leftover selector references fail closed without presenting UI.
@objc(WWNStartupLogViewController)
public final class WWNStartupLogViewController: UIViewController {
    @objc public var clientLabel: String?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = true
        DispatchQueue.main.async { [weak self] in
            self?.dismiss(animated: false)
        }
    }

    @objc public func appendLogLine(_ line: String) {
        _ = line
    }
}
#endif
