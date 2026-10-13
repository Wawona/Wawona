import Foundation
import WawonaModel
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Darwin)
import Darwin
#endif

#if os(iOS) || os(tvOS) || os(visionOS)
@_silgen_name("waypipe_main")
private func waypipe_main(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32
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
        let root = Bundle.main.bundleURL
        let candidates = [
            root.appendingPathComponent("Contents/Resources/bin/waypipe").path,
            root.appendingPathComponent("Contents/MacOS/waypipe").path,
            root.appendingPathComponent("waypipe").path,
            "/opt/homebrew/bin/waypipe",
            "/usr/local/bin/waypipe",
            "/usr/bin/waypipe",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "waypipe"
    }

    /// Build `waypipe [opts] ssh [ssh-opts] user@host -- remote`.
    /// Mirrors Android `android_jni.c` SSH argv (port, key, StrictHostKeyChecking).
    @objc(buildWaypipeArguments:)
    public func buildWaypipeArguments(_ prefs: WWNPreferencesManager) -> [String] {
        var args: [String] = [findWaypipeBinary()]
        let compress = prefs.waypipeCompress()
        if !compress.isEmpty {
            args.append(contentsOf: ["--compress", compress])
        }
        if prefs.waypipeDebug() { args.append("--debug") }
        if prefs.waypipeNoGpu() { args.append("--no-gpu") }
        if prefs.waypipeOneshot() { args.append("--oneshot") }
        let threads = prefs.waypipeThreads()
        if !threads.isEmpty, threads != "0" {
            args.append(contentsOf: ["--threads", threads])
        }
        let video = prefs.waypipeVideo()
        if !video.isEmpty, video != "none" {
            args.append(contentsOf: ["--video", video])
        }
        let sshBin = prefs.waypipeSSHBinary()
        if !sshBin.isEmpty, sshBin != "ssh" {
            args.append(contentsOf: ["--ssh-bin", sshBin])
        }
        args.append("ssh")
        args.append(contentsOf: [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=/dev/null",
            "-T",
            "-p", "\(prefs.sshPort())",
        ])
        let keyPath = prefs.sshKeyPath()
        if !keyPath.isEmpty {
            args.append(contentsOf: [
                "-i", (keyPath as NSString).expandingTildeInPath,
                "-o", "PreferredAuthentications=publickey",
                "-o", "IdentitiesOnly=yes",
            ])
        }
        let host = prefs.sshHost()
        let user = prefs.sshUser()
        if !host.isEmpty {
            args.append(user.isEmpty ? host : "\(user)@\(host)")
        }
        args.append("--")
        let remote = prefs.waypipeRemoteCommand()
        let cmd = remote.isEmpty ? "weston-simple-shm" : remote
        args.append(remoteSwayEnvPrefixedCommand(cmd))
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
        var env = ProcessInfo.processInfo.environment
        let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
        env["XDG_RUNTIME_DIR"] = runtime
        env["WAYLAND_DISPLAY"] = prefs.waypipeDisplay()
        let pass = prefs.sshPassword()
        if !pass.isEmpty {
            env["SSHPASS"] = pass
        }
        task.environment = env
        Self.attachProcessOutputPipes(
            task,
            argvBanner: generateWaypipePreviewString(prefs)
        )
        task.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                Self.appendClientLaunchLog(
                    "exit: waypipe status=\(proc.terminationStatus)\n"
                )
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
            Self.appendClientLaunchLog("error: \(error.localizedDescription)\n")
        }
        #elseif os(iOS) || os(tvOS) || os(visionOS)
        launchWaypipeInProcess(prefs)
        #else
        _ = prefs
        delegate?.runnerDidReceiveError?("waypipe is unavailable on this platform.")
        #endif
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    /// In-process `waypipe_main` (libssh2). Same argv shape as Android JNI.
    private func launchWaypipeInProcess(_ prefs: WWNPreferencesManager) {
        if let err = validatePreflight(forPrefs: prefs) {
            delegate?.runnerDidReceiveError?(err)
            return
        }
        let args = buildWaypipeArguments(prefs)
        // Drop host Process path; argv[0] is still "waypipe" for waypipe_main.
        let argvStrings = ["waypipe"] + Array(args.dropFirst())
        Self.appendClientLaunchLog(
            "$ \(generateWaypipePreviewString(prefs))\n"
        )
        Self.appendClientLaunchLog(
            "# in-process waypipe_main (libssh2); Close Terminal to Focus compositor\n"
        )
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
            try? FileManager.default.createDirectory(
                atPath: runtime, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            setenv("XDG_RUNTIME_DIR", runtime, 1)
            setenv("WAYLAND_DISPLAY", prefs.waypipeDisplay(), 1)
            let pass = prefs.sshPassword()
            if !pass.isEmpty { setenv("SSHPASS", pass, 1) }
            var cStrings: [UnsafeMutablePointer<CChar>?] = argvStrings.map { strdup($0) }
            cStrings.append(nil)
            defer {
                for ptr in cStrings where ptr != nil {
                    free(ptr)
                }
            }
            let rc = cStrings.withUnsafeMutableBufferPointer { buf in
                waypipe_main(Int32(argvStrings.count), buf.baseAddress)
            }
            DispatchQueue.main.async {
                self?.isRunning = false
                Self.appendClientLaunchLog("exit: waypipe_main status=\(rc)\n")
                if rc != 0 {
                    self?.delegate?.runnerDidReceiveError?("waypipe exited \(rc)")
                }
                self?.delegate?.runnerDidStop?()
            }
        }
    }
    #endif
    @objc public func stopWaypipe() {
        #if os(macOS)
        waypipeTask?.terminate()
        waypipeTask = nil
        #endif
        isRunning = false
        delegate?.runnerDidStop?()
    }
    @objc public func launchWestonSimpleSHM() {
        isWestonSimpleSHMRunning = false
        let msg = Self.optionalSoftwareMissingMessage(for: "weston-simple-shm")
        delegate?.runnerDidReceiveError?(msg)
        Self.appendClientLaunchLog("error: \(msg)\n")
    }
    @objc public func stopWestonSimpleSHM() {
        isWestonSimpleSHMRunning = false
    }
    @objc public func launchWeston() { launchInProcessWeston(drm: false) }
    @objc public func launchWestonDrm() { launchInProcessWeston(drm: true) }
    @objc public func stopWeston() {
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

        // Prefer installed deb / process binary (optional software). Store Mode A
        // has no APT; scan is empty there. See wawona-optional-software.
        if clientId != "wawona-shell",
           clientId != "wawona-wasm",
           clientId != "hello-wasi-gui",
           let installed = InstalledOptionalSoftware.scanDebClients()
            .first(where: { $0.id == clientId })
        {
            _ = launchBundledExecutable(names: [installed.executablePath], clientKey: clientId)
            return
        }

        switch clientId {
        case "wawona-shell":
            break
        case "wawona-wasm", "hello-wasi-gui":
            let msg =
                "No .wasm module selected. Set a module path or install a package with wpm."
            delegate?.runnerDidReceiveError?(msg)
            Self.appendClientLaunchLog("error: \(msg)\n")
        default:
            // Prefer installed deb path (above). Otherwise fail closed.
            _ = launchBundledExecutable(names: [clientId], clientKey: clientId)
        }
    }
    @objc(launchWasmModuleAtPath:machineId:)
    public func launchWasmModule(atPath path: String, machineId: String?) {
        if let machineId { machineClients[machineId] = "wawona-wasm" }
        Self.appendClientLaunchLog("$ wpm run \(path)\n")
        DispatchQueue.global(qos: .userInitiated).async {
            let rc: Int32 = path.withCString { pathC in
                "wasm".withCString { nameC in
                    var argv: [UnsafePointer<CChar>?] = [nameC, pathC, nil]
                    return argv.withUnsafeMutableBufferPointer { buf in
                        wawona_wasm_run(2, buf.baseAddress)
                    }
                }
            }
            DispatchQueue.main.async {
                Self.appendClientLaunchLog("exit: wasm status=\(rc)\n")
                if rc != 0 {
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
