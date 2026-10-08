#if canImport(CarPlay) && os(iOS)
import CarPlay
import UIKit

/// CarPlay scene host. Replaces `WWNCarPlaySceneDelegate.m`.
@objc(WWNCarPlaySceneDelegate)
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    public var interfaceController: CPInterfaceController?

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let list = CPListTemplate(title: "Wawona", sections: [])
        if #available(iOS 14.0, *) {
            interfaceController.setRootTemplate(list, animated: true) { _, _ in }
        } else {
            interfaceController.setRootTemplate(list, animated: true)
        }
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        if self.interfaceController === interfaceController {
            self.interfaceController = nil
        }
    }
}
#endif
