#if canImport(GameController) && canImport(UIKit)
import Foundation
import GameController
import QuartzCore
import UIKit

public extension NSNotification.Name {
    static let WWNTvRemoteShakeNotification = NSNotification.Name("WWNTvRemoteShakeNotification")
    static let WWNTvRemoteMenuBeganNotification = NSNotification.Name("WWNTvRemoteMenuBeganNotification")
    static let WWNTvRemoteMenuEndedNotification = NSNotification.Name("WWNTvRemoteMenuEndedNotification")
    static let WWNTvRemoteMenuCancelledNotification =
        NSNotification.Name("WWNTvRemoteMenuCancelledNotification")
}

@objc(WWNGameControllerManager)
public final class GameControllerBridge: NSObject {
    private static let singleton = GameControllerBridge()

    @objc(sharedManager)
    public class func sharedManager() -> GameControllerBridge {
        singleton
    }

    @objc public private(set) var gamepadConnected = false
    @objc public private(set) var mouseConnected = false
    @objc public private(set) var keyboardConnected = false

    private var started = false
    private var stickLink: CADisplayLink?
    private var lastStickTick: CFTimeInterval = 0
    private var lastRemoteShakeTime: CFTimeInterval = 0

    private let btnLeft: UInt32 = 0x110
    private let btnRight: UInt32 = 0x111
    private let btnMiddle: UInt32 = 0x112
    private let stickCursorSpeed: CGFloat = 900
    private let siriTouchpadSpeed: CGFloat = 1400
    private let stickScrollSpeed: CGFloat = 600
    private let stickDeadzone: Float = 0.15
    private let remoteShakeG = 2.2
    private let remoteShakeCooldown = 1.2

    @objc public func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(controllerDisconnected(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        for controller in GCController.controllers() {
            configureController(controller)
        }
        if #available(iOS 14.0, tvOS 14.0, *) {
            center.addObserver(self, selector: #selector(mouseConnected(_:)), name: .GCMouseDidConnect, object: nil)
            center.addObserver(
                self,
                selector: #selector(mouseDisconnected(_:)),
                name: .GCMouseDidDisconnect,
                object: nil
            )
            for mouse in GCMouse.mice() { configureMouse(mouse) }
            center.addObserver(
                self,
                selector: #selector(keyboardChanged(_:)),
                name: .GCKeyboardDidConnect,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(keyboardChanged(_:)),
                name: .GCKeyboardDidDisconnect,
                object: nil
            )
            keyboardConnected = GCKeyboard.coalesced != nil
        }
        NSLog("[GAMEPAD] GameController manager started (\(GCController.controllers().count))")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stickLink?.invalidate()
    }

    private func targetView() -> WWNCompositorView_ios? {
        guard let container = WWNCompositorBridge.sharedBridge.containerView else { return nil }
        for case let sub as WWNCompositorView_ios in container.subviews.reversed() where !sub.isHidden {
            return sub
        }
        return container as? WWNCompositorView_ios
    }

    @objc private func controllerConnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        configureController(controller)
    }

    @objc private func controllerDisconnected(_ note: Notification) {
        _ = note
        gamepadConnected = !GCController.controllers().isEmpty
        if !gamepadConnected { stopStickLink() }
    }

    @objc private func mouseConnected(_ note: Notification) {
        guard #available(iOS 14.0, tvOS 14.0, *),
              let mouse = note.object as? GCMouse else { return }
        configureMouse(mouse)
    }

    @objc private func mouseDisconnected(_ note: Notification) {
        guard #available(iOS 14.0, tvOS 14.0, *) else { return }
        _ = note
        mouseConnected = !GCMouse.mice().isEmpty
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard #available(iOS 14.0, tvOS 14.0, *) else { return }
        _ = note
        keyboardConnected = GCKeyboard.coalesced != nil
    }

    private func configureController(_ controller: GCController) {
        var any = false
        if let pad = controller.extendedGamepad {
            configureExtendedGamepad(pad)
            any = true
        }
        if let micro = controller.microGamepad {
            configureMicroGamepad(micro)
            any = true
        }
        #if os(tvOS)
        configureMotion(controller)
        #endif
        guard any else { return }
        gamepadConnected = true
        startStickLink()
    }

    private func configureExtendedGamepad(_ pad: GCExtendedGamepad) {
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            self.targetView()?.clickVirtualPointerButton(self.btnLeft, pressed: pressed)
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            self.targetView()?.clickVirtualPointerButton(self.btnRight, pressed: pressed)
        }
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            guard abs(x) > 0.5 || abs(y) > 0.5 else { return }
            let dx = CGFloat(x) * 10
            let dy = -CGFloat(y) * 10
            self?.targetView()?.moveVirtualPointerByDx(dx, dy: dy)
        }
        if #available(iOS 14.0, tvOS 14.0, *) {
            #if os(tvOS)
            bindMenuButton(pad.buttonMenu)
            #endif
        }
    }

    private func configureMicroGamepad(_ micro: GCMicroGamepad) {
        micro.reportsAbsoluteDpadValues = false
        if #available(iOS 14.0, tvOS 14.0, *) {
            #if os(tvOS)
            bindMenuButton(micro.buttonMenu)
            #endif
        }
    }

    #if os(tvOS)
    private func bindMenuButton(_ button: GCControllerButtonInput?) {
        button?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.postTvMenuPressed(pressed)
        }
    }

    private func postTvMenuPressed(_ pressed: Bool) {
        let name = pressed ? WWNTvRemoteMenuBeganNotification : WWNTvRemoteMenuEndedNotification
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    private func configureMotion(_ controller: GCController) {
        guard shouldEnableRemoteShake(controller), let motion = controller.motion else { return }
        if #available(iOS 14.0, tvOS 14.0, *) { motion.sensorsActive = true }
        motion.valueChangedHandler = { [weak self] motion in
            let a = motion.userAcceleration
            let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if mag >= self?.remoteShakeG ?? 2.2 {
                self?.noteRemoteShake()
            }
        }
    }

    private func shouldEnableRemoteShake(_ controller: GCController) -> Bool {
        guard controller.motion != nil else { return false }
        if #available(iOS 15.0, tvOS 15.0, *) {
            let cat = controller.productCategory
            if cat == GCProductCategorySiriRemote1stGen { return true }
            if cat == GCProductCategorySiriRemote2ndGen { return false }
            if cat == GCProductCategoryControlCenterRemote { return false }
            if cat == GCProductCategoryCoalescedRemote { return false }
        }
        return controller.extendedGamepad != nil
    }

    private func noteRemoteShake() {
        let now = CACurrentMediaTime()
        guard now - lastRemoteShakeTime >= remoteShakeCooldown else { return }
        lastRemoteShakeTime = now
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WWNTvRemoteShakeNotification, object: nil)
        }
    }
    #endif

    private func startStickLink() {
        guard stickLink == nil else { return }
        lastStickTick = 0
        let link = CADisplayLink(target: self, selector: #selector(stickTick(_:)))
        link.add(to: .main, forMode: .common)
        stickLink = link
    }

    private func stopStickLink() {
        stickLink?.invalidate()
        stickLink = nil
    }

    @objc private func stickTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastStickTick > 0 ? now - lastStickTick : 0
        lastStickTick = now
        guard dt > 0, dt <= 0.25, let view = targetView() else { return }
        let dtCg = CGFloat(dt)
        for controller in GCController.controllers() {
            if let pad = controller.extendedGamepad {
                let lx = CGFloat(pad.leftThumbstick.xAxis.value)
                let ly = CGFloat(pad.leftThumbstick.yAxis.value)
                if abs(lx) > CGFloat(stickDeadzone) || abs(ly) > CGFloat(stickDeadzone) {
                    view.moveVirtualPointerByDx(lx * stickCursorSpeed * dtCg, dy: -ly * stickCursorSpeed * dtCg)
                }
                let rx = CGFloat(pad.rightThumbstick.xAxis.value)
                let ry = CGFloat(pad.rightThumbstick.yAxis.value)
                if abs(rx) > CGFloat(stickDeadzone) || abs(ry) > CGFloat(stickDeadzone) {
                    view.scrollVirtualPointerByDx(rx * stickScrollSpeed * dtCg, dy: -ry * stickScrollSpeed * dtCg)
                }
                continue
            }
            if let micro = controller.microGamepad {
                let x = CGFloat(micro.dpad.xAxis.value)
                let y = CGFloat(micro.dpad.yAxis.value)
                if abs(x) > CGFloat(stickDeadzone) || abs(y) > CGFloat(stickDeadzone) {
                    view.moveVirtualPointerByDx(x * siriTouchpadSpeed * dtCg, dy: -y * siriTouchpadSpeed * dtCg)
                }
            }
        }
    }

    @available(iOS 14.0, tvOS 14.0, *)
    private func configureMouse(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        mouseConnected = true
        input.mouseMovedHandler = { [weak self] _, dx, dy in
            DispatchQueue.main.async {
                self?.targetView()?.moveVirtualPointerByDx(CGFloat(dx), dy: -CGFloat(dy))
            }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async {
                guard let self else { return }
                self.targetView()?.clickVirtualPointerButton(self.btnLeft, pressed: pressed)
            }
        }
        if let right = input.rightButton {
            right.pressedChangedHandler = { [weak self] _, _, pressed in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.targetView()?.clickVirtualPointerButton(self.btnRight, pressed: pressed)
                }
            }
        }
        if let middle = input.middleButton {
            middle.pressedChangedHandler = { [weak self] _, _, pressed in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.targetView()?.clickVirtualPointerButton(self.btnMiddle, pressed: pressed)
                }
            }
        }
        input.scroll.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                self?.targetView()?.scrollVirtualPointerByDx(CGFloat(x) * 10, dy: CGFloat(y) * 10)
            }
        }
    }
}
#endif
