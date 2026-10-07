#if os(watchOS)
import CoreGraphics
import Foundation

/// C ABI from `wawona_wasm.h` / `libwawona_wasm.a` (argc/argv, not a path ptr).
@_silgen_name("wawona_wasm_run")
private func wawona_wasm_run(
    _ argc: Int32,
    _ argv: UnsafePointer<UnsafePointer<CChar>?>?
) -> Int32

@_silgen_name("wawona_wasm_can_run")
private func wawona_wasm_can_run(_ path: UnsafePointer<CChar>?) -> Int32

/// watchOS Wayland present bridge (SpriteKit blit of SHM frames).
/// Machines Start for `wawona-wasm` / hello-wasi-gui calls `wawona_wasm_run`.
@objc(WWNWatchCompositorBridge)
public final class WWNWatchCompositorBridge: NSObject {
    @objc public static let shared = WWNWatchCompositorBridge()

    @objc public private(set) var isRunning = false
    @objc public private(set) var isCompositorAvailable = true
    @objc public private(set) var socketPath: String?
    @objc public private(set) var hostShellActive = false
    @objc public private(set) var isClientRunning = false
    @objc public private(set) var isWaypipeRunning = false
    @objc public private(set) var latestFrame: CGImage?
    @objc public var outputWidth: UInt32 = 184
    @objc public var outputHeight: UInt32 = 224

    @objc public static func sharedBridge() -> WWNWatchCompositorBridge { shared }

    @objc public static func styledTerminalText(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text)
    }

    @objc(startWithSocketName:)
    public func start(withSocketName socketName: String?) -> Bool {
        let name = (socketName?.isEmpty == false) ? socketName! : "wayland-0"
        socketPath = "/tmp/\(name)"
        isRunning = true
        return true
    }

    @objc public func stop() {
        stopClient()
        stopWaypipe()
        isRunning = false
        hostShellActive = false
        latestFrame = nil
    }

    @objc public func launchWestonSimpleSHM() { isClientRunning = true }
    @objc public func launchWeston() { isClientRunning = true }
    @objc public func launchWestonTerminal() { isClientRunning = true }
    @objc public func launchFoot() { isClientRunning = true }
    @objc public func launchNiri() { isClientRunning = true }

    @objc(launchClientWithId:)
    public func launchClient(withId clientId: String) {
        if clientId == "wawona-wasm" || clientId == "hello-wasi-gui" {
            launchWasmModule(atPath: nil)
            return
        }
        isClientRunning = true
    }

    @objc public func startHostShellConsole() { hostShellActive = true }
    @objc(writeHostShell:)
    public func writeHostShell(_ text: String) { _ = text }
    @objc public func stopHostShellConsole() { hostShellActive = false }

    @objc(sendText:)
    public func sendText(_ text: String) { _ = text }

    @objc(sendKeyCode:pressed:)
    public func sendKeyCode(_ evdevKeycode: UInt32, pressed: Bool) {
        _ = evdevKeycode
        _ = pressed
    }

    @objc(launchWaypipeWithHost:user:port:password:remoteCommand:)
    public func launchWaypipe(
        withHost host: String,
        user: String,
        port: Int,
        password: String,
        remoteCommand: String
    ) {
        _ = (host, user, port, password, remoteCommand)
        isWaypipeRunning = true
    }

    @objc public func stopWaypipe() { isWaypipeRunning = false }

    /// Run a WASI Wayland module in-process via Relay Pulley (`wawona_wasm_run`).
    /// Nil / missing path uses bundled `hello-wasi-gui.wasm` (wl_shm + xdg).
    @objc(launchWasmModuleAtPath:)
    public func launchWasmModule(atPath path: String?) {
        guard let resolved = resolveWasmModulePath(path) else {
            NSLog("WATCH: No hello-wasi-gui.wasm in Watch bundle or Documents/Wawona/inbox")
            return
        }
        let canRun = resolved.withCString { wawona_wasm_can_run($0) } != 0
        if !canRun {
            NSLog("WATCH: Not a readable WASM module: %@", resolved)
            return
        }
        isClientRunning = true
        NSLog("WATCH: Launching Relay wasm %@", resolved)
        DispatchQueue.global(qos: .userInitiated).async {
            let rc: Int32 = resolved.withCString { pathC in
                "wasm".withCString { nameC in
                    var argv: [UnsafePointer<CChar>?] = [nameC, pathC, nil]
                    return argv.withUnsafeMutableBufferPointer { buf in
                        wawona_wasm_run(2, buf.baseAddress)
                    }
                }
            }
            DispatchQueue.main.async {
                self.isClientRunning = false
                if rc != 0 {
                    NSLog("WATCH: wawona_wasm_run exited %d for %@", rc, resolved)
                }
            }
        }
    }

    @objc public func stopClient() { isClientRunning = false }

    private func resolveWasmModulePath(_ explicitPath: String?) -> String? {
        if let trimmed = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty
        {
            let expanded = (trimmed as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
            NSLog(
                "WATCH: Wasm path missing %@. Falling back to bundled hello-wasi-gui",
                expanded
            )
        }
        return Self.bundledHelloWasiGuiPath()
    }

    private static func bundledHelloWasiGuiPath() -> String? {
        if let path = Bundle.main.path(forResource: "hello-wasi-gui", ofType: "wasm"),
           FileManager.default.fileExists(atPath: path)
        {
            return path
        }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let inbox = docs
                .appendingPathComponent("Wawona", isDirectory: true)
                .appendingPathComponent("inbox", isDirectory: true)
                .appendingPathComponent("hello-wasi-gui.wasm")
            if FileManager.default.fileExists(atPath: inbox.path) {
                return inbox.path
            }
        }
        return nil
    }
}
#endif
