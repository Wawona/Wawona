import Foundation
#if canImport(AppKit)
import AppKit
#endif

@_silgen_name("weston_compositor_main")
func weston_compositor_main(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32
@_silgen_name("wwn_weston_compositor_shutdown_requested")
var wwn_weston_compositor_shutdown_requested: Int32
@_silgen_name("wawona_wasm_run")
func wawona_wasm_run(
    _ argc: Int32,
    _ argv: UnsafePointer<UnsafePointer<CChar>?>?
) -> Int32
@_silgen_name("weston_simple_shm_main")
func weston_simple_shm_main(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

extension WWNWaypipeRunner {
    func launchInProcessWeston(drm: Bool) {
        if westonRunning {
            delegate?.runnerDidReceiveError?("weston already running.")
            return
        }
        westonRunning = true
        wwn_weston_compositor_shutdown_requested = 0
        let useDrm = drm || WWNHostSessionUsesOwnDisplayDRM()
            || (WWNResolveCompositorBackend(nil) as String) == "drm"
        // Clients inherit process env; must set before weston spawns
        // desktop-shell / keyboard in-process.
        #if os(macOS)
        WWNBundleShareEnvironment.apply()
        #else
        WWNRootfsProvider.applyShellEnvironment()
        #endif
        DispatchQueue.global(qos: .userInitiated).async {
            var name = strdup("weston")
            var backend = strdup(useDrm ? "--backend=drm" : "--backend=wayland")
            defer { free(name); free(backend) }
            var argv: [UnsafeMutablePointer<CChar>?] = [name, backend, nil]
            let rc = argv.withUnsafeMutableBufferPointer { buf in
                weston_compositor_main(2, buf.baseAddress)
            }
            DispatchQueue.main.async {
                self.westonRunning = false
                if rc != 0 {
                    self.delegate?.runnerDidReceiveError?("weston_compositor_main exited \(rc)")
                    NotificationCenter.default.post(
                        name: Notification.Name("WWNNativeClientLaunchFailedNotification"),
                        object: self,
                        userInfo: ["clientId": "weston", "reason": "exit \(rc)"]
                    )
                }
            }
        }
    }
    @discardableResult
    func launchBundledExecutable(names: [String], clientKey: String) -> Bool {
        #if os(macOS)
        guard let path = resolveBundledExecutable(names: names) else {
            delegate?.runnerDidReceiveError?("Bundled client missing: \(names.joined(separator: ","))")
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
        _ = clientKey
        delegate?.runnerDidReceiveError?(
            "macOS-only client: \(names.joined(separator: ","))"
        )
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
            if let p = Bundle.main.path(forAuxiliaryExecutable: name), fm.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }
}
