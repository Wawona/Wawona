import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// macOS MicroVM dogfood supervision (vfkit + waypipe via `wawona-microvm-session`).
/// Product Relay backends (VZ / StaticCpu) remain the long-term Machines engine;
/// this runner owns the supervised flake session so Start/Stop are recoverable
/// without two manual terminals. Never QEMU/UTM.
@objc(WWNVirtualMachineRunner)
public final class WWNVirtualMachineRunner: NSObject {
    @objc(sharedRunner) public static let sharedRunner = WWNVirtualMachineRunner()

    private let lock = NSLock()
    private var tasksByMachineId: [String: Process] = [:]

    private override init() {
        super.init()
    }

    @objc(launchProfile:error:)
    public func launchProfile(_ profile: WWNMachineProfile, error: NSErrorPointer) -> Bool {
        #if os(macOS)
        let machineId = profile.machineId
        guard !machineId.isEmpty else {
            error?.pointee = NSError(
                domain: "WWNVirtualMachineRunner",
                code: 201,
                userInfo: [NSLocalizedDescriptionKey: "Virtual machine profile has no machine id."]
            )
            return false
        }

        stopProfile(withMachineId: machineId)

        guard let exe = Self.resolveSessionExecutable() else {
            error?.pointee = NSError(
                domain: "WWNVirtualMachineRunner",
                code: 202,
                userInfo: [NSLocalizedDescriptionKey:
                    "wawona-microvm-session not found. Set WAWONA_MICROVM_SESSION, "
                        + "install it on PATH, or set WAWONA_FLAKE and ensure nix is available."]
            )
            return false
        }

        let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
        let wayland = (runtime as NSString).appendingPathComponent("wayland-0")
        guard FileManager.default.fileExists(atPath: wayland) else {
            error?.pointee = NSError(
                domain: "WWNVirtualMachineRunner",
                code: 203,
                userInfo: [NSLocalizedDescriptionKey:
                    "Host compositor socket missing at \(wayland). Start Wawona first."]
            )
            return false
        }

        let task = Process()
        var env = ProcessInfo.processInfo.environment
        env["WAWONA_RUNTIME"] = runtime
        env["WAWONA_VSOCK_SOCKET"] = env["WAWONA_VSOCK_SOCKET"] ?? "/tmp/wawona-guest-vsock.sock"
        if let port = profile.vmSettings["vsockPort"] as? String, !port.isEmpty {
            // Guest module keeps port 1024; surface the override for diagnostics only.
            env["WAWONA_VSOCK_PORT"] = port
        }
        task.environment = env

        if exe.useNixRun {
            task.executableURL = URL(fileURLWithPath: exe.nixPath)
            var nixArgs = [
                "--extra-experimental-features", "nix-command flakes",
                "run",
            ]
            // Prefer local Relay guest module when developing beside the checkout.
            let relaySibling = (exe.flakeRef as NSString)
                .appendingPathComponent("../Relay")
            if FileManager.default.fileExists(
                atPath: (relaySibling as NSString).appendingPathComponent(
                    "import/vms/dependencies/vms/microvm-guest.nix"
                )
            ) {
                nixArgs += ["--override-input", "wwn-relay", relaySibling]
            }
            nixArgs += ["\(exe.flakeRef)#wawona-microvm-session"]
            task.arguments = nixArgs
        } else {
            task.executableURL = URL(fileURLWithPath: exe.path)
            task.arguments = []
        }

        let logDir = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent(".local/state/wawona-microvm")
        try? FileManager.default.createDirectory(
            atPath: logDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let outPath = (logDir as NSString).appendingPathComponent("machines-\(machineId).log")
        FileManager.default.createFile(atPath: outPath, contents: nil)
        if let handle = FileHandle(forWritingAtPath: outPath) {
            task.standardOutput = handle
            task.standardError = handle
        }

        task.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.lock.lock()
            if self.tasksByMachineId[machineId] === proc {
                self.tasksByMachineId.removeValue(forKey: machineId)
            }
            self.lock.unlock()
            NSLog(
                "[WWNVirtualMachineRunner] session exited machine=%@ status=%d log=%@",
                machineId, proc.terminationStatus, outPath
            )
        }

        do {
            try task.run()
        } catch {
            error?.pointee = error as NSError
            return false
        }

        lock.lock()
        tasksByMachineId[machineId] = task
        lock.unlock()
        NSLog(
            "[WWNVirtualMachineRunner] started microvm session machine=%@ pid=%d",
            machineId, task.processIdentifier
        )
        return true
        #else
        _ = profile
        error?.pointee = NSError(
            domain: "WWNVirtualMachineRunner",
            code: 200,
            userInfo: [NSLocalizedDescriptionKey:
                "MicroVM session dogfood is macOS-only. Mobile VMs use Relay StaticCpu."]
        )
        return false
        #endif
    }

    @objc(stopProfileWithMachineId:)
    public func stopProfile(withMachineId machineId: String) {
        #if os(macOS)
        lock.lock()
        let task = tasksByMachineId.removeValue(forKey: machineId)
        lock.unlock()
        guard let task, task.isRunning else { return }
        task.terminate()
        // Allow the session trap to tear down vfkit + bridge.
        let deadline = Date().addingTimeInterval(8)
        while task.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if task.isRunning {
            task.interrupt()
        }
        #else
        _ = machineId
        #endif
    }

    @objc public func stopAll() {
        #if os(macOS)
        lock.lock()
        let ids = Array(tasksByMachineId.keys)
        lock.unlock()
        for id in ids {
            stopProfile(withMachineId: id)
        }
        #endif
    }

    @objc(hasOwnedSessionForMachineId:)
    public func hasOwnedSession(forMachineId machineId: String) -> Bool {
        #if os(macOS)
        lock.lock()
        defer { lock.unlock() }
        guard let task = tasksByMachineId[machineId] else { return false }
        return task.isRunning
        #else
        _ = machineId
        return false
        #endif
    }

    #if os(macOS)
    private struct SessionExe {
        let path: String
        let useNixRun: Bool
        let nixPath: String
        let flakeRef: String

        init(path: String) {
            self.path = path
            self.useNixRun = false
            self.nixPath = ""
            self.flakeRef = ""
        }

        init(nixPath: String, flakeRef: String) {
            self.path = ""
            self.useNixRun = true
            self.nixPath = nixPath
            self.flakeRef = flakeRef
        }
    }

    private static func resolveSessionExecutable() -> SessionExe? {
        let env = ProcessInfo.processInfo.environment
        if let direct = env["WAWONA_MICROVM_SESSION"], !direct.isEmpty,
           FileManager.default.isExecutableFile(atPath: direct) {
            return SessionExe(path: direct)
        }
        if let pathExe = which("wawona-microvm-session") {
            return SessionExe(path: pathExe)
        }
        let flake = env["WAWONA_FLAKE"]
            ?? defaultFlakePath()
        let nix = which("nix") ?? "/nix/var/nix/profiles/default/bin/nix"
        if FileManager.default.isExecutableFile(atPath: nix),
           let flake, !flake.isEmpty {
            return SessionExe(nixPath: nix, flakeRef: flake)
        }
        return nil
    }

    private static func defaultFlakePath() -> String? {
        let candidates = [
            NSString(string: "~/Wawona/Wawona").expandingTildeInPath,
            NSString(string: "~/src/Wawona/Wawona").expandingTildeInPath,
        ]
        let fm = FileManager.default
        for root in candidates {
            if fm.fileExists(atPath: (root as NSString).appendingPathComponent("flake.nix")) {
                return root
            }
        }
        return nil
    }

    private static func which(_ name: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
    #endif
}
