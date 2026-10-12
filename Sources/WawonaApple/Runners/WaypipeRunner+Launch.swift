import Foundation
#if canImport(AppKit)
import AppKit
#endif

@_silgen_name("wawona_wasm_run")
func wawona_wasm_run(
    _ argc: Int32,
    _ argv: UnsafePointer<UnsafePointer<CChar>?>?
) -> Int32

extension WWNWaypipeRunner {
    /// Feed the Start Terminal sheet (`WWNIosGuestConsole` / macOS guest console).
    static func appendClientLaunchLog(_ line: String) {
        NotificationCenter.default.post(
            name: Notification.Name("WWNClientLaunchLogNotification"),
            object: nil,
            userInfo: ["line": line]
        )
    }

    /// Nested weston / niri / toy clients are optional-software. Fail closed
    /// with an install hint when the binary is not already on disk (deb/apt).
    static func optionalSoftwareMissingMessage(for clientId: String) -> String {
        "\(clientId) is not bundled. Install from repo.wawona.io (wpm or apt), then Start again."
    }

    func launchInProcessWeston(drm: Bool) {
        _ = drm
        westonRunning = false
        let msg = Self.optionalSoftwareMissingMessage(for: "weston")
        delegate?.runnerDidReceiveError?(msg)
        Self.appendClientLaunchLog("error: \(msg)\n")
        NotificationCenter.default.post(
            name: Notification.Name("WWNNativeClientLaunchFailedNotification"),
            object: self,
            userInfo: ["clientId": "weston", "reason": msg]
        )
    }

    @discardableResult
    func launchBundledExecutable(names: [String], clientKey: String) -> Bool {
        #if os(macOS)
        guard let path = resolveBundledExecutable(names: names) else {
            let msg = Self.optionalSoftwareMissingMessage(
                for: names.first ?? clientKey
            )
            delegate?.runnerDidReceiveError?(msg)
            Self.appendClientLaunchLog("error: \(msg)\n")
            return false
        }
        stopClientProcess(key: clientKey)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = []
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "WWN_MODEB_TTY")
        env.removeValue(forKey: "WWN_MODEB_INSERT")
        if env["NIRI_BACKEND"] == "tty" { env.removeValue(forKey: "NIRI_BACKEND") }
        task.environment = env
        task.terminationHandler = { [weak self] (_: Process) in
            DispatchQueue.main.async {
                self?.lock.lock()
                self?.clientTasks.removeValue(forKey: clientKey)
                self?.lock.unlock()
            }
        }
        do {
            try task.run()
            lock.lock()
            clientTasks[clientKey] = task
            lock.unlock()
            return true
        } catch {
            delegate?.runnerDidReceiveError?(error.localizedDescription)
            return false
        }
        #else
        // Apple-mobile Mode A: no in-process weston/foot archives. Only an
        // already-installed optional binary path (rare) or fail closed.
        let msg = Self.optionalSoftwareMissingMessage(
            for: names.first ?? clientKey
        )
        delegate?.runnerDidReceiveError?(msg)
        Self.appendClientLaunchLog("error: \(msg)\n")
        _ = clientKey
        return false
        #endif
    }

    func stopClientProcess(key: String) {
        #if os(macOS)
        lock.lock()
        let task = clientTasks.removeValue(forKey: key)
        lock.unlock()
        task?.terminate()
        #else
        _ = key
        #endif
    }

    func resolveBundledExecutable(names: [String]) -> String? {
        let fm = FileManager.default
        let macOS = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
        let resBin = Bundle.main.resourceURL?.appendingPathComponent("bin")
        for name in names {
            for root in [macOS, resBin].compactMap({ $0 }) {
                let path = root.appendingPathComponent(name).path
                if fm.isExecutableFile(atPath: path) { return path }
            }
            if let p = Bundle.main.path(forAuxiliaryExecutable: name),
               fm.isExecutableFile(atPath: p)
            {
                return p
            }
            // Absolute path from InstalledOptionalSoftware / custom.
            if name.hasPrefix("/"), fm.isExecutableFile(atPath: name) {
                return name
            }
        }
        return nil
    }
}
