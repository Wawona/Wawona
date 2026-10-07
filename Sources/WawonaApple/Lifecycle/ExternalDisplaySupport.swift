#if canImport(UIKit) && !os(watchOS)
import UIKit

public extension NSNotification.Name {
    static let WWNExternalDisplayDidConnectNotification =
        NSNotification.Name("WWNExternalDisplayDidConnectNotification")
    static let WWNExternalDisplayDidDisconnectNotification =
        NSNotification.Name("WWNExternalDisplayDidDisconnectNotification")
    static let WWNVirtualCursorStateNotification =
        NSNotification.Name("WWNVirtualCursorStateNotification")
}

private var externalDisplayConnected = false
private var carPlayConnected = false

@_cdecl("WWNExternalDisplayIsConnected")
public func WWNExternalDisplayIsConnected() -> Bool {
    externalDisplayConnected
}

@_cdecl("WWNCarPlaySceneIsConnected")
public func WWNCarPlaySceneIsConnected() -> Bool {
    carPlayConnected
}

@_cdecl("WWNSetCarPlaySceneConnected")
public func WWNSetCarPlaySceneConnected(_ connected: Bool) {
    carPlayConnected = connected
    WWNRefreshHostSeatForConnectedScreens()
}

@_cdecl("WWNRefreshHostSeatForConnectedScreens")
public func WWNRefreshHostSeatForConnectedScreens() {
    let bridge = WWNCompositorBridge.sharedBridge
    if externalDisplayConnected {
        bridge.setHostSeatMode(2)
        return
    }
    if carPlayConnected {
        bridge.setHostSeatMode(1)
        return
    }
    let type = WWNPreferencesManager.sharedManager().touchInputType()
    if type == "Touchpad" {
        bridge.setHostSeatMode(2)
    } else {
        bridge.setHostSeatMode(0)
    }
}

@objc(WWNExternalMirrorView)
public final class ExternalMirrorView: UIView {
    private var windowLayers: [UInt64: CALayer] = [:]
    private let cursorLayer = CALayer()
    private var lastContainerSize = CGSize.zero

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        cursorLayer.zPosition = 10_000
        cursorLayer.isHidden = true
        cursorLayer.contentsGravity = .resize
        layer.addSublayer(cursorLayer)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cursorStateChanged(_:)),
            name: .WWNVirtualCursorStateNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc(mirrorWindow:image:frame:contentRect:containerSize:contentsScale:contentsGravity:)
    public func mirrorWindow(
        _ windowId: UInt64,
        image: CGImage?,
        frame: CGRect,
        contentRect: CGRect,
        containerSize: CGSize,
        contentsScale: CGFloat,
        contentsGravity: String
    ) {
        guard let image else {
            removeWindow(windowId)
            return
        }
        lastContainerSize = containerSize
        let layer = windowLayers[windowId] ?? {
            let created = CALayer()
            created.masksToBounds = true
            created.minificationFilter = .linear
            created.magnificationFilter = .linear
            self.layer.insertSublayer(created, below: cursorLayer)
            windowLayers[windowId] = created
            return created
        }()
        let fit = fitTransform(for: containerSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = frame.applying(fit)
        layer.contentsGravity = CALayerContentsGravity(rawValue: contentsGravity)
        layer.contentsScale = contentsScale > 0 ? contentsScale : 1
        layer.contentsRect = contentRect
        layer.contents = image
        CATransaction.commit()
    }

    @objc(removeWindow:)
    public func removeWindow(_ windowId: UInt64) {
        windowLayers.removeValue(forKey: windowId)?.removeFromSuperlayer()
    }

    @objc private func cursorStateChanged(_ note: Notification) {
        guard let info = note.userInfo else { return }
        if (info["hidden"] as? NSNumber)?.boolValue == true {
            cursorLayer.isHidden = true
            return
        }
        var scale: CGFloat = 1
        let fit = fitTransform(for: lastContainerSize, outScale: &scale)
        let pos = (info["position"] as? NSValue)?.cgPointValue ?? .zero
        let mapped = pos.applying(fit)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let contents = info["contents"] { cursorLayer.contents = contents }
        let w = (info["width"] as? NSNumber)?.doubleValue ?? 0
        let h = (info["height"] as? NSNumber)?.doubleValue ?? 0
        if w > 0, h > 0 {
            cursorLayer.bounds = CGRect(x: 0, y: 0, width: w * scale, height: h * scale)
        }
        cursorLayer.position = mapped
        cursorLayer.isHidden = cursorLayer.contents == nil
        CATransaction.commit()
    }

    private func fitTransform(for containerSize: CGSize, outScale: UnsafeMutablePointer<CGFloat>? = nil) -> CGAffineTransform {
        let bounds = self.bounds.size
        guard containerSize.width > 0, containerSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            outScale?.pointee = 1
            return .identity
        }
        let scale = min(bounds.width / containerSize.width, bounds.height / containerSize.height)
        outScale?.pointee = scale
        let offsetX = (bounds.width - containerSize.width * scale) / 2
        let offsetY = (bounds.height - containerSize.height * scale) / 2
        return CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
    }
}

@objc(WWNExternalSceneDelegate)
public final class ExternalSceneDelegate: NSObject, UIWindowSceneDelegate {
    @objc public var window: UIWindow?

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let mirror = ExternalMirrorView(frame: window.bounds)
        mirror.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let controller = UIViewController()
        controller.view = mirror
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        externalDisplayConnected = true
        WWNCompositorBridge.sharedBridge.externalMirrorView = mirror
        WWNRefreshHostSeatForConnectedScreens()
        NotificationCenter.default.post(name: .WWNExternalDisplayDidConnectNotification, object: nil)
    }

    public func sceneDidDisconnect(_ scene: UIScene) {
        _ = scene
        externalDisplayConnected = false
        WWNCompositorBridge.sharedBridge.externalMirrorView = nil
        window = nil
        WWNRefreshHostSeatForConnectedScreens()
        NotificationCenter.default.post(name: .WWNExternalDisplayDidDisconnectNotification, object: nil)
    }
}
#endif
