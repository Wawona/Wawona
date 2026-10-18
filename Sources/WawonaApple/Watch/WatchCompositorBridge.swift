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

@_silgen_name("WWNCoreNew")
private func WWNCoreNew() -> UnsafeMutableRawPointer?
@_silgen_name("WWNCoreStart")
private func WWNCoreStart(_ core: UnsafeMutableRawPointer?, _ socket: UnsafePointer<CChar>?) -> Bool
@_silgen_name("WWNCoreStop")
private func WWNCoreStop(_ core: UnsafeMutableRawPointer?) -> Bool
@_silgen_name("WWNCoreIsRunning")
private func WWNCoreIsRunning(_ core: UnsafeMutableRawPointer?) -> Bool
@_silgen_name("WWNCoreGetSocketPath")
private func WWNCoreGetSocketPath(_ core: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("WWNStringFree")
private func WWNStringFree(_ s: UnsafeMutablePointer<CChar>?)
@_silgen_name("WWNCoreProcessEvents")
private func WWNCoreProcessEvents(_ core: UnsafeMutableRawPointer?) -> Bool
@_silgen_name("WWNCoreFlushClients")
private func WWNCoreFlushClients(_ core: UnsafeMutableRawPointer?)
@_silgen_name("WWNCorePopPendingBuffer")
private func WWNCorePopPendingBuffer(_ core: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
@_silgen_name("WWNBufferDataFree")
private func WWNBufferDataFree(_ data: UnsafeMutableRawPointer?)
@_silgen_name("WWNCoreNotifyFramePresented")
private func WWNCoreNotifyFramePresented(
    _ core: UnsafeMutableRawPointer?,
    _ surfaceId: UInt32,
    _ bufferId: UInt64,
    _ timestamp: UInt32
)
@_silgen_name("WWNCoreGetTimestampMs")
private func WWNCoreGetTimestampMs(_ core: UnsafeMutableRawPointer?) -> UInt32
@_silgen_name("WWNCoreGetClientCount")
private func WWNCoreGetClientCount(_ core: UnsafeMutableRawPointer?) -> UInt32

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
    /// True while a Wayland client is attached. Terminal must park.
    @objc public private(set) var clientSurfaceFront = false
    private var lastClientCount: UInt32 = 0
    private var lastSurfaceFront = false
    @objc public var outputWidth: UInt32 = 184
    @objc public var outputHeight: UInt32 = 224

    private let eventQueue = DispatchQueue(
        label: "com.aspauldingcode.wawona.watch-compositor",
        qos: .utility
    )
    private var pump: Timer?
    private var core: UnsafeMutableRawPointer?
    private var socketName = "wayland-0"

    @objc public static func sharedBridge() -> WWNWatchCompositorBridge { shared }

    @objc public static func styledTerminalText(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text)
    }

    @objc(startWithSocketName:)
    public func start(withSocketName socketName: String?) -> Bool {
        let name = (socketName?.isEmpty == false) ? socketName! : "wayland-0"
        self.socketName = name
        WWNWatchShellEnvironment.publishWaylandSession(display: name)
        if let core, WWNCoreIsRunning(core), socketFileExists() {
            isRunning = true
            startPumpIfNeeded()
            return true
        }
        if core != nil {
            tearDownCore()
        }
        core = WWNCoreNew()
        guard let core else {
            NSLog("WATCH: WWNCoreNew failed")
            isRunning = false
            return false
        }
        let started = name.withCString { WWNCoreStart(core, $0) }
        let running = started || WWNCoreIsRunning(core)
        if let pathPtr = WWNCoreGetSocketPath(core) {
            socketPath = String(cString: pathPtr)
            WWNStringFree(pathPtr)
        } else {
            let runtime = WWNWatchShellEnvironment.watchRuntimeDir()
            socketPath = (runtime as NSString).appendingPathComponent(name)
        }
        guard running, socketFileExists() else {
            NSLog("WATCH: compositor socket missing at %@", socketPath ?? name)
            tearDownCore()
            isRunning = false
            return false
        }
        setenv("WAYLAND_DISPLAY", name, 1)
        isRunning = true
        startPumpIfNeeded()
        return true
    }

    @objc public func stop() {
        stopClient()
        stopWaypipe()
        pump?.invalidate()
        pump = nil
        tearDownCore()
        isRunning = false
        hostShellActive = false
        latestFrame = nil
        socketPath = nil
        lastClientCount = 0
        lastSurfaceFront = false
        setClientSurfaceFront(false)
    }

    @objc public func launchWestonSimpleSHM() { isClientRunning = true }
    @objc public func launchWeston() { isClientRunning = true }
    @objc public func launchWestonTerminal() { isClientRunning = true }
    @objc public func launchFoot() { isClientRunning = true }
    @objc public func launchNiri() { isClientRunning = true }

    @objc(launchClientWithId:)
    public func launchClient(withId clientId: String) {
        if clientId == "wawona-shell" || clientId.isEmpty {
            startHostShellConsole()
            isClientRunning = true
            return
        }
        if clientId == "wawona-wasm" || clientId == "hello-wasi-gui" {
            launchWasmModule(atPath: nil)
            return
        }
        isClientRunning = true
    }

    @objc public func startHostShellConsole() { hostShellActive = true }
    @objc(writeHostShell:)
    public func writeHostShell(_ text: String) {
        guard !text.isEmpty else { return }
        let line = text.hasSuffix("\n") ? text : text + "\n"
        NotificationCenter.default.post(
            name: WWNGuestConsoleOutputNotification,
            object: nil,
            userInfo: ["text": line]
        )
    }
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

    private func socketFileExists() -> Bool {
        guard let socketPath, !socketPath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: socketPath)
    }

    private func tearDownCore() {
        if let core {
            _ = WWNCoreStop(core)
        }
        core = nil
    }

    private func startPumpIfNeeded() {
        guard pump == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pumpEvents()
        }
        RunLoop.main.add(timer, forMode: .common)
        pump = timer
    }

    private func pumpEvents() {
        let core = self.core
        eventQueue.async { [weak self] in
            guard let self, let core else { return }
            _ = WWNCoreProcessEvents(core)
            self.noteClientSurface(core)
            self.drainFrames(core)
        }
    }

    /// iOS parks Wawona Terminal when the client count rises. Same signal here.
    private func noteClientSurface(_ core: UnsafeMutableRawPointer) {
        let count = WWNCoreGetClientCount(core)
        let front = count > 0
        lastClientCount = count
        guard front != lastSurfaceFront else { return }
        lastSurfaceFront = front
        DispatchQueue.main.async { [weak self] in
            self?.setClientSurfaceFront(front)
        }
    }

    private func setClientSurfaceFront(_ front: Bool) {
        guard clientSurfaceFront != front else { return }
        clientSurfaceFront = front
        NotificationCenter.default.post(
            name: WWNWatchClientSurfaceNotification,
            object: nil,
            userInfo: ["front": front]
        )
    }

    /// `CBufferData` field offsets (64-bit). Same layout as the iOS SHM drain.
    private func drainFrames(_ core: UnsafeMutableRawPointer) {
        var presented = false
        while let raw = WWNCorePopPendingBuffer(core) {
            let base = UnsafeRawPointer(raw)
            let surfaceId = base.load(fromByteOffset: 8, as: UInt32.self)
            let bufferId = base.load(fromByteOffset: 16, as: UInt64.self)
            let width = Int(base.load(fromByteOffset: 24, as: UInt32.self))
            let height = Int(base.load(fromByteOffset: 28, as: UInt32.self))
            let stride = Int(base.load(fromByteOffset: 32, as: UInt32.self))
            // Offset 72 is `top_origin_row_reverse` from the compositor core.
            // CGImage and SKTexture(cgImage:) are top-origin, like wl_shm.
            // Offset 68 is the Metal V remap and must not reverse these rows.
            let reverseRows = base.load(fromByteOffset: 72, as: UInt8.self) != 0
            let pixels = base.load(
                fromByteOffset: 40, as: UnsafeMutablePointer<UInt8>?.self)
            let image = pixels.flatMap {
                Self.image(
                    width: width, height: height, stride: stride, pixels: $0,
                    reverseRows: reverseRows)
            }
            WWNCoreNotifyFramePresented(core, surfaceId, bufferId, WWNCoreGetTimestampMs(core))
            WWNBufferDataFree(raw)
            if let image {
                presented = true
                DispatchQueue.main.async { [weak self] in
                    self?.latestFrame = image
                    NotificationCenter.default.post(
                        name: WWNWatchCompositorFrameReadyNotification,
                        object: nil
                    )
                }
            }
        }
        if presented {
            WWNCoreFlushClients(core)
        }
    }

    private static func image(
        width: Int,
        height: Int,
        stride: Int,
        pixels: UnsafePointer<UInt8>,
        reverseRows: Bool
    ) -> CGImage? {
        guard width > 0, height > 0, stride >= width * 4 else { return nil }
        let count = stride * height
        var bytes = [UInt8](repeating: 0, count: count)
        if reverseRows {
            for y in 0..<height {
                let src = pixels.advanced(by: (height - 1 - y) * stride)
                bytes.withUnsafeMutableBytes { dest in
                    dest.baseAddress!.advanced(by: y * stride).copyMemory(from: src, byteCount: stride)
                }
            }
        } else {
            bytes.withUnsafeMutableBytes { dest in
                dest.baseAddress!.copyMemory(from: pixels, byteCount: count)
            }
        }
        let data = Data(bytes: bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let info = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

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
