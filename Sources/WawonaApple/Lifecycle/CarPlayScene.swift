#if canImport(CarPlay) && os(iOS)
import CarPlay
import UIKit

/// CarPlay scene host. Exact product chrome uses ExactKit `PresenterCarPlay` +
/// `CarPlayTemplateBridge` (`car.contract` / `VehicleListModel`). This Wawona
/// stub mirrors the same Machines glance until the Exact-hosted IPA is the
/// sole ship path. Never freeform SwiftUI on the car (store templates only).
/// See Exact `docs/vehicle-display-contract.md`.
@objc(WWNCarPlaySceneDelegate)
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    public var interfaceController: CPInterfaceController?

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        WWNSetCarPlaySceneConnected(true)
        WWNRefreshHostSeatForConnectedScreens()
        let list = Self.machinesListTemplate()
        if #available(iOS 14.0, *) {
            interfaceController.setRootTemplate(list, animated: true) { _, _ in }
        } else {
            interfaceController.setRootTemplate(list, animated: true)
        }
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        if self.interfaceController === interfaceController {
            self.interfaceController = nil
        }
        WWNSetCarPlaySceneConnected(false)
        WWNRefreshHostSeatForConnectedScreens()
    }

    /// Same seed as Exact `VehicleListModel.wawonaMachines` / `apps/wawona/car.contract`.
    private static func machinesListTemplate() -> CPListTemplate {
        let rows: [(String, String, String)] = [
            ("Native Shell", "local · native", "car-machine-m-1"),
            ("Remote", "ssh · waypipe", "car-machine-m-2"),
            ("Wasm", "local · wasi", "car-machine-m-3"),
        ]
        let items: [CPListItem] = rows.map { title, subtitle, testId in
            let item = CPListItem(text: title, detailText: subtitle)
            item.handler = { _, completion in
                // testId retained for Exact parity (`car-machine-*`); phone owns interaction.
                _ = testId
                completion()
            }
            return item
        }
        let section = CPListSection(items: items, header: nil, sectionIndexTitle: nil)
        return CPListTemplate(title: "Machines", sections: [section])
    }
}
#endif
