#if os(watchOS)
import Foundation

@objc(WWNWatchCompositorBridge)
public final class WWNWatchCompositorBridge: NSObject {
    @objc public static let shared = WWNWatchCompositorBridge()

    @objc public private(set) var isRunning = false
    @objc public private(set) var isCompositorAvailable = true
    @objc public private(set) var socketPath: String?
    @objc public private(set) var hostShellActive = false

    @objc public static func sharedBridge() -> WWNWatchCompositorBridge { shared }

    @objc(startWithSocketName:)
    public func start(withSocketName socketName: String?) -> Bool {
        let name = (socketName?.isEmpty == false) ? socketName! : "wayland-0"
        socketPath = "/tmp/\(name)"
        isRunning = true
        return true
    }

    @objc public func stop() {
        isRunning = false
        hostShellActive = false
    }

    @objc public func launchWestonSimpleSHM() {}
    @objc public func launchWeston() {}
    @objc public func launchWestonTerminal() {}
    @objc public func launchFoot() {}
    @objc public func launchNiri() {}

    @objc(launchClientWithId:)
    public func launchClient(withId clientId: String) {
        if clientId == "wawona-wasm" {
            launchWasmModule(atPath: nil)
        }
    }

    @objc public func startHostShellConsole() { hostShellActive = true }
    @objc(writeHostShell:)
    public func writeHostShell(_ text: String) { _ = text }
    @objc public func stopHostShellConsole() { hostShellActive = false }

    @objc(launchWasmModuleAtPath:)
    public func launchWasmModule(atPath path: String?) {
        _ = path
        // Relay Pulley runs hello-wasi-gui.wasm on watchOS.
    }

    @objc public func stopClient() {}
}
#endif
