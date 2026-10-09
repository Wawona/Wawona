import Foundation
#if canImport(AppKit)
import AppKit
#endif

@objc public protocol WWNWaypipeRunnerDelegate: AnyObject {
    @objc optional func runnerDidReceiveError(_ message: String)
    @objc optional func runnerDidStop()
}
@objc(WWNWaypipeRunner)
public final class WWNWaypipeRunner: NSObject {
    @objc public static let shared = WWNWaypipeRunner()
    @objc public weak var delegate: WWNWaypipeRunnerDelegate?
    @objc public var isRunning = false
    @objc public var isWestonSimpleSHMRunning = false
    @objc public var westonRunning = false
    @objc public var westonTerminalRunning = false
    @objc public var footRunning = false
    #if os(iOS) || os(tvOS) || os(visionOS)
    @objc public var activeIOSBundledClientId: String = ""
    #endif
    var machineClients: [String: String] = [:]
    #if os(macOS)
    var waypipeTask: Process?
    var clientTasks: [String: Process] = [:]
    #endif
    let lock = NSLock()
    @objc public static func sharedRunner() -> WWNWaypipeRunner { shared }
    @objc public func findWaypipeBinary() -> String {
        let bundle = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/waypipe", isDirectory: false).path
        for p in [bundle, "/opt/homebrew/bin/waypipe", "/usr/local/bin/waypipe", "/usr/bin/waypipe"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return "waypipe"
    }
    @objc(buildWaypipeArguments:)
    public func buildWaypipeArguments(_ prefs: WWNPreferencesManager) -> [String] {
        var args = [findWaypipeBinary(), "ssh"]
        let host = prefs.sshHost()
        let user = prefs.sshUser()
        if !host.isEmpty {
            args.append(user.isEmpty ? host : "\(user)@\(host)")
        }
        let remote = prefs.waypipeRemoteCommand()
        args.append(remoteSwayEnvPrefixedCommand(remote.isEmpty ? "sway" : remote))
        return args
    }
    @objc(remoteSwayEnvPrefixedCommand:)
    public func remoteSwayEnvPrefixedCommand(_ remoteCommand: String) -> String {
        let assignments = [
            "WLR_RENDERER=pixman",
            "WLR_NO_HARDWARE_CURSORS=1",
        ].joined(separator: " ")
        return String(format: "env %@ %@", assignments, remoteCommand)
    }
    @objc(generateWaypipePreviewString:)
    public func generateWaypipePreviewString(_ prefs: WWNPreferencesManager) -> String {
        buildWaypipeArguments(prefs).joined(separator: " ")
    }
    @objc(validatePreflightForPrefs:)
    public func validatePreflight(forPrefs prefs: WWNPreferencesManager) -> String? {
        if prefs.sshHost().isEmpty { return "SSH host is required for waypipe." }
        return nil
    }
    @objc(launchWaypipe:)
    public func launchWaypipe(_ prefs: WWNPreferencesManager) {
        #if os(macOS)
        if let err = validatePreflight(forPrefs: prefs) {
            delegate?.runnerDidReceiveError?(err)
            return
        }
        stopWaypipe()
        let args = buildWaypipeArguments(prefs)
        guard let exe = args.first else {
            delegate?.runnerDidReceiveError?("waypipe binary missing.")
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: exe)
        task.arguments = Array(args.dropFirst())
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.delegate?.runnerDidStop?()
            }
        }
        do {
            try task.run()
            waypipeTask = task
            isRunning = true
        } catch {
            delegate?.runnerDidReceiveError?(error.localizedDescription)
        }
        #else
        _ = prefs
        delegate?.runnerDidReceiveError?("waypipe Process is macOS-only.")
        #endif
    }
    @objc public func stopWaypipe() {
        #if os(macOS)
        waypipeTask?.terminate()
        waypipeTask = nil
        #endif
        isRunning = false
        delegate?.runnerDidStop?()
    }
    @objc public func launchWestonSimpleSHM() {
        guard !isWestonSimpleSHMRunning else { return }
        isWestonSimpleSHMRunning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var name = strdup("weston-simple-shm")
            defer { free(name) }
            var argv: [UnsafeMutablePointer<CChar>?] = [name, nil]
            let result = argv.withUnsafeMutableBufferPointer { buf in
                weston_simple_shm_main(1, buf.baseAddress)
            }
            DispatchQueue.main.async {
                self?.isWestonSimpleSHMRunning = false
                if result != 0 {
                    self?.delegate?.runnerDidReceiveError?(
                        "weston-simple-shm exited with \(result)."
                    )
                }
            }
        }
    }
    @objc public func stopWestonSimpleSHM() {
        isWestonSimpleSHMRunning = false
    }
    @objc public func launchWeston() { launchInProcessWeston(drm: false) }
    @objc public func launchWestonDrm() { launchInProcessWeston(drm: true) }
    @objc public func stopWeston() {
        wwn_weston_compositor_shutdown_requested = 1
        westonRunning = false
    }
    @objc public func launchWestonTerminal() {
        westonTerminalRunning = launchBundledExecutable(
            names: ["weston-terminal"], clientKey: "weston-terminal")
    }
    @objc public func stopWestonTerminal() {
        stopClientProcess(key: "weston-terminal")
        westonTerminalRunning = false
    }
    @objc public func launchFoot() {
        footRunning = launchBundledExecutable(names: ["foot"], clientKey: "foot")
    }
    @objc public func stopFoot() {
        stopClientProcess(key: "foot")
        footRunning = false
    }
    @objc(launchBundledClientWithId:)
    public func launchBundledClient(withId clientId: String) {
        launchBundledClient(withId: clientId, machineId: nil)
    }
    @objc(launchBundledClientWithId:machineId:)
    public func launchBundledClient(withId clientId: String, machineId: String?) {
        if let machineId { machineClients[machineId] = clientId }
        #if os(iOS) || os(tvOS) || os(visionOS)
        activeIOSBundledClientId = clientId
        #endif
        NotificationCenter.default.post(name: .WWNNativeClientWillLaunch, object: clientId)
        switch clientId {
        case "weston":
            launchWeston()
        case "weston-terminal":
            launchWestonTerminal()
        case "foot":
            launchFoot()
        case "weston-simple-shm":
            launchWestonSimpleSHM()
        case "wawona-wasm", "hello-wasi-gui":
            let bundled = Bundle.main.path(forResource: "hello-wasi-gui", ofType: "wasm") ?? ""
            if !bundled.isEmpty {
                launchWasmModule(atPath: bundled, machineId: machineId)
            } else {
                delegate?.runnerDidReceiveError?("Bundled hello-wasi-gui.wasm is missing.")
            }
        default:
            _ = launchBundledExecutable(names: [clientId], clientKey: clientId)
        }
    }
    @objc(launchWasmModuleAtPath:machineId:)
    public func launchWasmModule(atPath path: String, machineId: String?) {
        if let machineId { machineClients[machineId] = "wawona-wasm" }
        DispatchQueue.global(qos: .userInitiated).async {
            let rc: Int32 = path.withCString { pathC in
                "wasm".withCString { nameC in
                    var argv: [UnsafePointer<CChar>?] = [nameC, pathC, nil]
                    return argv.withUnsafeMutableBufferPointer { buf in
                        wawona_wasm_run(2, buf.baseAddress)
                    }
                }
            }
            if rc != 0 {
                DispatchQueue.main.async {
                    self.delegate?.runnerDidReceiveError?("wasm exited \(rc) for \(path)")
                }
            }
        }
    }
    @objc(stopBundledClientForMachineId:)
    public func stopBundledClient(forMachineId machineId: String) {
        guard let clientId = machineClients.removeValue(forKey: machineId) else { return }
        switch clientId {
        case "weston": stopWeston()
        case "weston-terminal": stopWestonTerminal()
        case "foot": stopFoot()
        case "weston-simple-shm": stopWestonSimpleSHM()
        default: stopClientProcess(key: clientId)
        }
    }
    @objc(isBundledClientRunningForMachineId:)
    public func isBundledClientRunning(forMachineId machineId: String) -> Bool {
        machineClients[machineId] != nil
    }
    @objc(runningInstanceCountForClientId:)
    public func runningInstanceCount(forClientId clientId: String) -> UInt {
        UInt(machineClients.values.filter { $0 == clientId }.count)
    }
    @objc public func stopAllNativeClients() {
        stopWeston()
        stopWestonTerminal()
        stopFoot()
        stopWestonSimpleSHM()
        #if os(macOS)
        lock.lock()
        let keys = Array(clientTasks.keys)
        lock.unlock()
        for key in keys { stopClientProcess(key: key) }
        #endif
        machineClients.removeAll()
        #if os(iOS) || os(tvOS) || os(visionOS)
        activeIOSBundledClientId = ""
        #endif
    }
    @objc public var isAnyNativeClientRunning: Bool {
        #if os(macOS)
        return westonRunning || westonTerminalRunning || footRunning || isWestonSimpleSHMRunning
            || !clientTasks.isEmpty || !machineClients.isEmpty
        #else
        return westonRunning || westonTerminalRunning || footRunning || isWestonSimpleSHMRunning
            || !machineClients.isEmpty
        #endif
    }
    #if os(iOS) || os(tvOS) || os(visionOS)
    @objc public func stopActiveIOSBundledClient() {
        if !activeIOSBundledClientId.isEmpty {
            stopBundledClient(forMachineId: "__ios_active__")
            switch activeIOSBundledClientId {
            case "weston": stopWeston()
            case "weston-terminal": stopWestonTerminal()
            case "foot": stopFoot()
            default: stopClientProcess(key: activeIOSBundledClientId)
            }
            activeIOSBundledClientId = ""
        }
        stopAllNativeClients()
    }
    #endif
    #if os(macOS)
    @objc(baremetalCompositorLaunchSpecForProfile:executable:arguments:environment:error:)
    public func baremetalCompositorLaunchSpec(
        for profile: WWNMachineProfile,
        executable outPath: AutoreleasingUnsafeMutablePointer<NSString?>,
        arguments outArgs: AutoreleasingUnsafeMutablePointer<NSArray?>,
        environment outEnv: AutoreleasingUnsafeMutablePointer<NSDictionary?>,
        error: NSErrorPointer
    ) -> Bool {
        _ = profile
        guard WWNHostSessionUsesOwnDisplayDRM() else {
            if let error {
                error.pointee = NSError(
                    domain: "WWNWaypipeRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Not in own-display Mode B session."])
            }
            return false
        }
        let weston = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/weston").path
        outPath.pointee = weston as NSString
        outArgs.pointee = ["--backend=drm"] as NSArray
        var env = ProcessInfo.processInfo.environment
        env["WWN_MODEB_TTY"] = "1"
        env["NIRI_BACKEND"] = "tty"
        outEnv.pointee = env as NSDictionary
        return true
    }
    #endif
}
