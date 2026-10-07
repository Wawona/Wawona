import Foundation

public let kWWNSwingingBridgeNestedSocket = "wawona-nested"
public let kWWNAnowaWNestedSocket = "wawona-nested"

/// Wawona Swinging Bridge lifecycle (planned). macOS-only when AnowawMacBridge ships.
@objc(WWNSwingingBridgeController)
public final class WWNSwingingBridgeController: NSObject {
    @objc(sharedController) public static let sharedController = WWNSwingingBridgeController()

    private override init() {
        super.init()
    }

    @objc public var active: Bool { false }

    @objc(attachForProfile:)
    public func attach(forProfile profile: WWNMachineProfile) {
        _ = profile
    }

    @objc(bridgeAppWithBundleId:)
    public func bridgeApp(withBundleId bundleId: String) {
        _ = bundleId
        NSLog("[SwingingBridge] bridgeApp requested while product bridge is still planned")
    }

    @objc public func detach() {}
}

public typealias WWNAnowaWController = WWNSwingingBridgeController
